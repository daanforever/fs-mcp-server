package main

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"strings"
	"syscall"
	"time"

	"github.com/modelcontextprotocol/go-sdk/mcp"
)

func handleExec(ctx context.Context, req *mcp.CallToolRequest, input ExecRequest) (
	*mcp.CallToolResult,
	interface{},
	error,
) {
	// Log full request if debug mode
	if logger != nil {
		reqJSON, _ := json.MarshalIndent(req, "", "  ")
		logger.Debug("exec REQUEST", "request", string(reqJSON))
		logger.Debug("exec called", "command", input.Command, "timeout", input.Timeout, "work_dir", input.WorkDir)
	}

	// Determine timeout
	timeout := 300 // Default: 5 minutes
	if input.Timeout != nil {
		timeout = *input.Timeout
	}

	// Validate work_dir if provided
	if input.WorkDir != nil {
		info, err := os.Stat(*input.WorkDir)
		if err != nil {
			return nil, nil, fmt.Errorf("invalid work_dir %q: %v", *input.WorkDir, err)
		}
		if !info.IsDir() {
			return nil, nil, fmt.Errorf("work_dir is not a directory: %s", *input.WorkDir)
		}
	}

	// Create context with timeout
	cmdCtx, cancel := context.WithTimeout(ctx, time.Duration(timeout)*time.Second)
	defer cancel()

	// Create command
	cmd := exec.CommandContext(cmdCtx, "bash", "-c", input.Command)

	// Set working directory if provided
	if input.WorkDir != nil {
		cmd.Dir = *input.WorkDir
	}

	// Capture stdout and stderr
	var stdoutBuf, stderrBuf bytes.Buffer
	cmd.Stdout = &stdoutBuf
	cmd.Stderr = &stderrBuf

	// Start the command
	if err := cmd.Start(); err != nil {
		return nil, nil, fmt.Errorf("failed to start command: %v", err)
	}

	// Register command with tracker (only after successful start)
	activeCommands.mu.Lock()
	activeCommands.commands[cmd] = cancel
	activeCommands.mu.Unlock()

	// Unregister when done
	defer func() {
		activeCommands.mu.Lock()
		delete(activeCommands.commands, cmd)
		activeCommands.mu.Unlock()
	}()

	// Wait for command to complete
	err := cmd.Wait()

	// Get exit code
	exitCode := 0
	if err != nil {
		if exitError, ok := err.(*exec.ExitError); ok {
			exitCode = exitError.ExitCode()
		} else {
			// Check if it's a timeout
			if cmdCtx.Err() == context.DeadlineExceeded {
				return nil, nil, fmt.Errorf("command timed out after %d seconds", timeout)
			}
			return nil, nil, fmt.Errorf("command execution error: %v", err)
		}
	}

	// Determine status
	status := "success"
	if exitCode != 0 {
		status = "failed"
	}

	// Check for timeout
	timedOut := cmdCtx.Err() == context.DeadlineExceeded

	// Format output message
	var message strings.Builder
	fmt.Fprintf(&message, "Exit code: %d\n", exitCode)
	fmt.Fprintf(&message, "Status: %s\n", status)
	if timedOut {
		fmt.Fprintf(&message, "Command timed out after %d seconds\n", timeout)
	}
	if stdoutBuf.Len() > 0 {
		fmt.Fprintf(&message, "STDOUT:\n%s\n", stdoutBuf.String())
	}
	if stderrBuf.Len() > 0 {
		fmt.Fprintf(&message, "STDERR:\n%s\n", stderrBuf.String())
	}

	result := &mcp.CallToolResult{
		Content: []mcp.Content{
			&mcp.TextContent{Text: message.String()},
		},
	}

	// Log full response if debug mode
	if logger != nil {
		logger.Debug("exec completed", "command", input.Command, "exit_code", exitCode, "status", status, "timeout", timedOut)
		resultJSON, _ := json.MarshalIndent(result, "", "  ")
		logger.Debug("exec RESPONSE", "response", string(resultJSON))
	}

	return result, nil, nil
}

func cleanupCommands() {
	// Copy commands and cancels while holding lock to avoid race condition
	activeCommands.mu.Lock()
	cmds := make([]*exec.Cmd, 0, len(activeCommands.commands))
	cancels := make([]context.CancelFunc, 0, len(activeCommands.commands))
	for cmd, cancel := range activeCommands.commands {
		cmds = append(cmds, cmd)
		cancels = append(cancels, cancel)
	}
	activeCommands.mu.Unlock()

	// Cancel contexts and send SIGTERM
	for i, cmd := range cmds {
		cancels[i]() // Cancel context first
		if cmd.Process != nil && cmd.ProcessState == nil {
			cmd.Process.Signal(syscall.SIGTERM)
		}
	}

	// Wait for processes to terminate (with timeout)
	done := make(chan struct{})
	go func() {
		for _, cmd := range cmds {
			if cmd.Process != nil && cmd.ProcessState == nil {
				cmd.Process.Wait()
			}
		}
		close(done)
	}()

	select {
	case <-done:
	case <-time.After(5 * time.Second):
		// Force kill if still running after 5 seconds
		for _, cmd := range cmds {
			if cmd.Process != nil && cmd.ProcessState == nil {
				cmd.Process.Kill()
			}
		}
	}

	// Log shutdown if debug mode is enabled
	if logger != nil {
		logger.Info("=== MCP Server shutting down ===")
	}
}
