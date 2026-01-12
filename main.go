package main

import (
	"bytes"
	"context"
	"flag"
	"fmt"
	"log/slog"
	"os"
	"os/exec"
	"os/signal"
	"path/filepath"
	"strings"
	"sync"
	"syscall"
	"time"

	"github.com/modelcontextprotocol/go-sdk/mcp"
)

type EditFileRequest struct {
	Filename  string  `json:"filename"`
	Content   *string `json:"content,omitempty"`
	OldString *string `json:"old_string,omitempty"`
	NewString *string `json:"new_string,omitempty"`
	// Backward compatibility
	OldText *string `json:"old_text,omitempty"`
	NewText *string `json:"new_text,omitempty"`
}

type ReadFileRequest struct {
	Filename string `json:"filename"`
}

type ExecRequest struct {
	Command string  `json:"command"`
	Timeout *int    `json:"timeout,omitempty"` // Default: 300 seconds
	WorkDir *string `json:"work_dir,omitempty"` // Working directory for command execution (default: current working directory)
}

type commandTracker struct {
	mu       sync.Mutex
	commands map[*exec.Cmd]context.CancelFunc
}

var activeCommands = &commandTracker{
	commands: make(map[*exec.Cmd]context.CancelFunc),
}

var (
	debugMode bool
	logger    *slog.Logger
)

func main() {
	// Parse command line flags
	flag.BoolVar(&debugMode, "debug", false, "Enable debug logging to mcp.log")
	flag.Parse()

	// Initialize debug logging if enabled
	if debugMode {
		logFile, err := os.OpenFile("mcp.log", os.O_CREATE|os.O_WRONLY|os.O_APPEND, 0644)
		if err != nil {
			fmt.Fprintf(os.Stderr, "Failed to open log file: %v\n", err)
			os.Exit(1)
		}
		defer logFile.Close()
		logger = slog.New(slog.NewTextHandler(logFile, &slog.HandlerOptions{
			Level: slog.LevelDebug,
		}))
		logger.Info("=== MCP Server started in debug mode ===")
	}

	// Create root context for graceful shutdown
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	// Set up signal handling
	sigChan := make(chan os.Signal, 1)
	signal.Notify(sigChan, syscall.SIGTERM, syscall.SIGINT)

	go func() {
		<-sigChan
		cancel()
		cleanupCommands()
	}()

	// Create MCP server
	server := mcp.NewServer(&mcp.Implementation{
		Name:    "file-edit-server",
		Version: "1.0.0",
	}, &mcp.ServerOptions{
		Logger: logger,
	})

	// Register tools
	mcp.AddTool(server, &mcp.Tool{
		Name:        "edit_file",
		Description: "Edit or create a file. Supports three modes: 1) Full write with 'content', 2) Text replacement with 'old_string' and 'new_string', 3) Append with 'new_string' only",
	}, handleEditFile)

	mcp.AddTool(server, &mcp.Tool{
		Name:        "read_file",
		Description: "Read content of a file",
	}, handleReadFile)

	mcp.AddTool(server, &mcp.Tool{
		Name:        "view",
		Description: "Read content of a file (alias for read_file)",
	}, handleReadFile) // Same handler

	mcp.AddTool(server, &mcp.Tool{
		Name:        "exec",
		Description: "Execute a shell command in a specified or current working directory",
	}, handleExec)

	// Run server (blocks until context cancelled)
	if err := server.Run(ctx, &mcp.StdioTransport{}); err != nil {
		if logger != nil {
			logger.Error("Server error", "error", err)
		}
		os.Exit(1)
	}
}

func handleEditFile(ctx context.Context, req *mcp.CallToolRequest, input EditFileRequest) (
	*mcp.CallToolResult,
	interface{},
	error,
) {
	// Log request if debug mode
	if logger != nil {
		logger.Debug("edit_file called", "filename", input.Filename)
	}

	// Create directories if needed
	dir := filepath.Dir(input.Filename)
	if dir != "." && dir != "" {
		if err := os.MkdirAll(dir, 0755); err != nil {
			return nil, nil, fmt.Errorf("failed to create directory %q: %v", dir, err)
		}
	}

	var content []byte
	var err error

	// Determine which parameters are provided (support both naming variants for backward compatibility)
	hasContent := input.Content != nil
	// Priority: old_string/new_string > old_text/new_text
	hasOldText := input.OldString != nil || input.OldText != nil
	hasNewText := input.NewString != nil || input.NewText != nil

	// Priority: content > old_string/new_string > new_string only
	if hasContent {
		// Full write mode (including empty string)
		if input.Content == nil {
			return nil, nil, fmt.Errorf("invalid arguments: content parameter is nil")
		}
		content = []byte(*input.Content)
	} else if hasOldText {
		// Text replacement mode
		content, err = os.ReadFile(input.Filename)
		if err != nil && !os.IsNotExist(err) {
			return nil, nil, fmt.Errorf("failed to read file %q: %v", input.Filename, err)
		}

		fileContent := string(content)
		// Use old_string/new_string if available, otherwise old_text/new_text
		var oldText string
		if input.OldString != nil {
			oldText = *input.OldString
		} else if input.OldText != nil {
			oldText = *input.OldText
		}
		newText := ""
		if input.NewString != nil {
			newText = *input.NewString
		} else if input.NewText != nil {
			newText = *input.NewText
		}

		if oldText == "*" {
			fileContent = newText
		} else if strings.Contains(fileContent, oldText) {
			fileContent = strings.ReplaceAll(fileContent, oldText, newText)
		} else if newText != "" {
			if fileContent != "" && !strings.HasSuffix(fileContent, "\n") {
				fileContent += "\n"
			}
			fileContent += newText
		}

		content = []byte(fileContent)
	} else if hasNewText {
		// Append mode
		current, err := os.ReadFile(input.Filename)
		if err != nil && !os.IsNotExist(err) {
			return nil, nil, fmt.Errorf("failed to read file %q: %v", input.Filename, err)
		}
		fileContent := string(current)
		var newText string
		if input.NewString != nil {
			newText = *input.NewString
		} else if input.NewText != nil {
			newText = *input.NewText
		}
		if fileContent != "" && !strings.HasSuffix(fileContent, "\n") {
			fileContent += "\n"
		}
		fileContent += newText
		content = []byte(fileContent)
	} else {
		return nil, nil, fmt.Errorf("invalid arguments: must provide either 'content' (for full write), 'old_string' (for replacement/removal), or 'new_string' (for append)")
	}

	// Write file with atomic operation for better reliability
	err = os.WriteFile(input.Filename, content, 0644)
	if err != nil {
		return nil, nil, fmt.Errorf("failed to write file %q: %v", input.Filename, err)
	}

	// Verify the write was successful by checking file size
	info, err := os.Stat(input.Filename)
	if err != nil {
		return nil, nil, fmt.Errorf("failed to verify file write for %q: %v", input.Filename, err)
	}

	// Check if written size matches expected size
	if info.Size() != int64(len(content)) {
		return nil, nil, fmt.Errorf("file size mismatch for %q: expected %d bytes, got %d bytes", input.Filename, len(content), info.Size())
	}

	// Log result if debug mode
	if logger != nil {
		logger.Debug("edit_file completed", "filename", input.Filename, "bytes_written", len(content))
	}

	message := fmt.Sprintf("File %s updated successfully. Bytes written: %d", input.Filename, len(content))
	return &mcp.CallToolResult{
		Content: []mcp.Content{
			&mcp.TextContent{Text: message},
		},
	}, nil, nil
}

func handleReadFile(ctx context.Context, req *mcp.CallToolRequest, input ReadFileRequest) (
	*mcp.CallToolResult,
	interface{},
	error,
) {
	// Log request if debug mode
	if logger != nil {
		logger.Debug("read_file called", "filename", input.Filename)
	}

	content, err := os.ReadFile(input.Filename)
	if err != nil {
		return nil, nil, fmt.Errorf("failed to read file %q: %v", input.Filename, err)
	}

	// Log result if debug mode
	if logger != nil {
		logger.Debug("read_file completed", "filename", input.Filename, "size", len(content))
	}

	return &mcp.CallToolResult{
		Content: []mcp.Content{
			&mcp.TextContent{Text: string(content)},
		},
	}, nil, nil
}

func handleExec(ctx context.Context, req *mcp.CallToolRequest, input ExecRequest) (
	*mcp.CallToolResult,
	interface{},
	error,
) {
	// Log request if debug mode
	if logger != nil {
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

	// Log result if debug mode
	if logger != nil {
		logger.Debug("exec completed", "command", input.Command, "exit_code", exitCode, "status", status, "timeout", timedOut)
	}

	return &mcp.CallToolResult{
		Content: []mcp.Content{
			&mcp.TextContent{Text: message.String()},
		},
	}, nil, nil
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
