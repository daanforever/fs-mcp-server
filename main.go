package main

import (
	"bytes"
	"context"
	"encoding/json"
	"flag"
	"fmt"
	"log/slog"
	"os"
	"os/exec"
	"os/signal"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"
	"sync"
	"syscall"
	"time"
	"unicode/utf8"

	"github.com/modelcontextprotocol/go-sdk/mcp"
	"golang.org/x/text/encoding"
	"golang.org/x/text/encoding/charmap"
	"golang.org/x/text/encoding/unicode"
	"golang.org/x/text/transform"
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
	Filename    string  `json:"filename"`
	StartLine   *int    `json:"start_line,omitempty"`
	EndLine     *int    `json:"end_line,omitempty"`
	Encoding    *string `json:"encoding,omitempty"`
	LineNumbers *bool   `json:"line_numbers,omitempty"`
	SkipEmpty   *bool   `json:"skip_empty,omitempty"`
	MaxLines    *int    `json:"max_lines,omitempty"`
	Pattern     *string `json:"pattern,omitempty"`
}

type ExecRequest struct {
	Command string  `json:"command"`
	Timeout *int    `json:"timeout,omitempty"` // Default: 300 seconds
	WorkDir *string `json:"work_dir,omitempty"` // Working directory for command execution (default: current working directory)
}

type WriteFileRequest struct {
	Filename string `json:"filename"`
	Content  string `json:"content"`
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
		defer func() {
			logFile.Sync()
			logFile.Close()
		}()
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
		Description: "Read content of a file with optional parameters: start_line, end_line, encoding, line_numbers, skip_empty, max_lines, pattern (regex filter)",
	}, handleReadFile)

	mcp.AddTool(server, &mcp.Tool{
		Name:        "view",
		Description: "Read content of a file (alias for read_file)",
	}, handleReadFile) // Same handler

	mcp.AddTool(server, &mcp.Tool{
		Name:        "exec",
		Description: "Execute a shell command in a specified or current working directory",
	}, handleExec)

	mcp.AddTool(server, &mcp.Tool{
		Name:        "write_file",
		Description: "Write content to a file. Creates the file if it doesn't exist, overwrites if it does.",
	}, handleWriteFile)

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
	// Log full request if debug mode
	if logger != nil {
		reqJSON, _ := json.MarshalIndent(req, "", "  ")
		logger.Debug("edit_file REQUEST", "request", string(reqJSON))
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

	message := fmt.Sprintf("File %s updated successfully. Bytes written: %d", input.Filename, len(content))
	result := &mcp.CallToolResult{
		Content: []mcp.Content{
			&mcp.TextContent{Text: message},
		},
	}

	// Log full response if debug mode
	if logger != nil {
		logger.Debug("edit_file completed", "filename", input.Filename, "bytes_written", len(content))
		resultJSON, _ := json.MarshalIndent(result, "", "  ")
		logger.Debug("edit_file RESPONSE", "response", string(resultJSON))
	}

	return result, nil, nil
}

// getEncoding returns the encoding.Encoding for the given encoding name
func getEncoding(encName string) (encoding.Encoding, error) {
	switch strings.ToLower(encName) {
	case "utf-8", "utf8":
		return encoding.Nop, nil
	case "utf-16", "utf16":
		return unicode.UTF16(unicode.LittleEndian, unicode.UseBOM), nil
	case "utf-16be", "utf16be":
		return unicode.UTF16(unicode.BigEndian, unicode.IgnoreBOM), nil
	case "utf-16le", "utf16le":
		return unicode.UTF16(unicode.LittleEndian, unicode.IgnoreBOM), nil
	case "windows-1251", "windows1251", "cp1251":
		return charmap.Windows1251, nil
	case "iso-8859-1", "iso8859-1", "latin1":
		return charmap.ISO8859_1, nil
	case "iso-8859-15", "iso8859-15", "latin9":
		return charmap.ISO8859_15, nil
	case "windows-1252", "windows1252", "cp1252":
		return charmap.Windows1252, nil
	default:
		return nil, fmt.Errorf("unsupported encoding: %s. Supported encodings: utf-8, utf-16, utf-16be, utf-16le, windows-1251, iso-8859-1, iso-8859-15, windows-1252", encName)
	}
}

// decodeContent decodes file content using the specified encoding
func decodeContent(data []byte, encName string) (string, error) {
	if encName == "" || strings.ToLower(encName) == "utf-8" || strings.ToLower(encName) == "utf8" {
		// Check if it's valid UTF-8
		if utf8.Valid(data) {
			return string(data), nil
		}
		// If not valid UTF-8 but encoding is utf-8, return as-is (might be binary)
		return string(data), nil
	}

	enc, err := getEncoding(encName)
	if err != nil {
		return "", err
	}

	decoder := enc.NewDecoder()
	decoded, _, err := transform.Bytes(decoder, data)
	if err != nil {
		return "", fmt.Errorf("failed to decode content with encoding %s: %v", encName, err)
	}

	return string(decoded), nil
}

// splitLines splits content into lines while preserving line ending information
func splitLines(content string) []string {
	// Normalize line endings and split
	content = strings.ReplaceAll(content, "\r\n", "\n")
	content = strings.ReplaceAll(content, "\r", "\n")
	lines := strings.Split(content, "\n")
	
	// If the last line is empty and content doesn't end with newline, don't include it
	// But we'll keep it for now to preserve behavior
	return lines
}

func handleReadFile(ctx context.Context, req *mcp.CallToolRequest, input ReadFileRequest) (
	*mcp.CallToolResult,
	interface{},
	error,
) {
	// Log full request if debug mode
	if logger != nil {
		reqJSON, _ := json.MarshalIndent(req, "", "  ")
		logger.Debug("read_file REQUEST", "request", string(reqJSON))
		logger.Debug("read_file called", "filename", input.Filename)
	}

	// Parameter validation
	if input.StartLine != nil && *input.StartLine < 1 {
		return nil, nil, fmt.Errorf("invalid start_line: must be >= 1, got %d", *input.StartLine)
	}
	if input.EndLine != nil && input.StartLine != nil && *input.EndLine < *input.StartLine {
		return nil, nil, fmt.Errorf("invalid line range: end_line (%d) must be >= start_line (%d)", *input.EndLine, *input.StartLine)
	}
	if input.MaxLines != nil && *input.MaxLines < 1 {
		return nil, nil, fmt.Errorf("invalid max_lines: must be > 0, got %d", *input.MaxLines)
	}

	// Validate regex pattern if provided
	var patternRegex *regexp.Regexp
	if input.Pattern != nil {
		var err error
		patternRegex, err = regexp.Compile(*input.Pattern)
		if err != nil {
			return nil, nil, fmt.Errorf("invalid regex pattern %q: %v", *input.Pattern, err)
		}
	}

	// Read file
	content, err := os.ReadFile(input.Filename)
	if err != nil {
		return nil, nil, fmt.Errorf("failed to read file %q: %v", input.Filename, err)
	}

	// Determine encoding (default to utf-8)
	encName := "utf-8"
	if input.Encoding != nil {
		encName = *input.Encoding
	}

	// Decode content
	decodedContent, err := decodeContent(content, encName)
	if err != nil {
		return nil, nil, err
	}

	// Split into lines
	allLines := splitLines(decodedContent)
	if len(allLines) == 0 {
		// Empty file
		result := &mcp.CallToolResult{
			Content: []mcp.Content{
				&mcp.TextContent{Text: ""},
			},
		}
		if logger != nil {
			logger.Debug("read_file completed", "filename", input.Filename, "size", 0)
		}
		return result, nil, nil
	}

	// Apply start_line/end_line filter (1-based to 0-based conversion)
	startIdx := 0
	endIdx := len(allLines)
	if input.StartLine != nil {
		startIdx = *input.StartLine - 1
		if startIdx < 0 {
			startIdx = 0
		}
		if startIdx >= len(allLines) {
			// Start line is beyond file length
			result := &mcp.CallToolResult{
				Content: []mcp.Content{
					&mcp.TextContent{Text: ""},
				},
			}
			if logger != nil {
				logger.Debug("read_file completed", "filename", input.Filename, "lines", 0)
			}
			return result, nil, nil
		}
	}
	if input.EndLine != nil {
		endIdx = *input.EndLine
		if endIdx > len(allLines) {
			endIdx = len(allLines)
		}
		if endIdx <= startIdx {
			// Invalid range
			result := &mcp.CallToolResult{
				Content: []mcp.Content{
					&mcp.TextContent{Text: ""},
				},
			}
			if logger != nil {
				logger.Debug("read_file completed", "filename", input.Filename, "lines", 0)
			}
			return result, nil, nil
		}
	}

	// Get lines in range
	filteredLines := allLines[startIdx:endIdx]
	originalLineNumbers := make([]int, len(filteredLines))
	for i := range filteredLines {
		originalLineNumbers[i] = startIdx + i + 1 // 1-based line numbers
	}

	// Apply pattern filter
	if patternRegex != nil {
		newFilteredLines := make([]string, 0, len(filteredLines))
		newLineNumbers := make([]int, 0, len(originalLineNumbers))
		for i, line := range filteredLines {
			if patternRegex.MatchString(line) {
				newFilteredLines = append(newFilteredLines, line)
				newLineNumbers = append(newLineNumbers, originalLineNumbers[i])
			}
		}
		filteredLines = newFilteredLines
		originalLineNumbers = newLineNumbers
	}

	// Apply skip_empty filter
	if input.SkipEmpty != nil && *input.SkipEmpty {
		newFilteredLines := make([]string, 0, len(filteredLines))
		newLineNumbers := make([]int, 0, len(originalLineNumbers))
		for i, line := range filteredLines {
			if strings.TrimSpace(line) != "" {
				newFilteredLines = append(newFilteredLines, line)
				newLineNumbers = append(newLineNumbers, originalLineNumbers[i])
			}
		}
		filteredLines = newFilteredLines
		originalLineNumbers = newLineNumbers
	}

	// Apply max_lines limit
	if input.MaxLines != nil && len(filteredLines) > *input.MaxLines {
		filteredLines = filteredLines[:*input.MaxLines]
		originalLineNumbers = originalLineNumbers[:*input.MaxLines]
	}

	// Add line numbers if requested
	if input.LineNumbers != nil && *input.LineNumbers {
		// Calculate padding width based on the highest line number
		maxLineNum := 0
		for _, num := range originalLineNumbers {
			if num > maxLineNum {
				maxLineNum = num
			}
		}
		paddingWidth := len(strconv.Itoa(maxLineNum))

		for i := range filteredLines {
			lineNumStr := strconv.Itoa(originalLineNumbers[i])
			// Pad with spaces
			for len(lineNumStr) < paddingWidth {
				lineNumStr = " " + lineNumStr
			}
			filteredLines[i] = lineNumStr + ": " + filteredLines[i]
		}
	}

	// Join lines back together
	resultText := strings.Join(filteredLines, "\n")
	// If original content ended with newline and we have lines, add trailing newline
	if len(allLines) > 0 && len(filteredLines) > 0 {
		// Check if last line of original was empty (meaning file ended with newline)
		// This is a heuristic - if the last line in allLines is empty, file likely ended with newline
		if len(allLines) > 1 && allLines[len(allLines)-1] == "" {
			resultText += "\n"
		}
	}

	result := &mcp.CallToolResult{
		Content: []mcp.Content{
			&mcp.TextContent{Text: resultText},
		},
	}

	// Log full response if debug mode
	if logger != nil {
		logger.Debug("read_file completed", "filename", input.Filename, "size", len(resultText), "lines", len(filteredLines))
		resultJSON, _ := json.MarshalIndent(result, "", "  ")
		logger.Debug("read_file RESPONSE", "response", string(resultJSON))
	}

	return result, nil, nil
}

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

func handleWriteFile(ctx context.Context, req *mcp.CallToolRequest, input WriteFileRequest) (
	*mcp.CallToolResult,
	interface{},
	error,
) {
	// Log full request if debug mode
	if logger != nil {
		reqJSON, _ := json.MarshalIndent(req, "", "  ")
		logger.Debug("write_file REQUEST", "request", string(reqJSON))
		logger.Debug("write_file called", "filename", input.Filename)
	}

	// Create directories if needed
	dir := filepath.Dir(input.Filename)
	if dir != "." && dir != "" {
		if err := os.MkdirAll(dir, 0755); err != nil {
			return nil, nil, fmt.Errorf("failed to create directory %q: %v", dir, err)
		}
	}

	// Write file with atomic operation
	content := []byte(input.Content)
	err := os.WriteFile(input.Filename, content, 0644)
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

	message := fmt.Sprintf("File %s written successfully. Bytes written: %d", input.Filename, len(content))
	result := &mcp.CallToolResult{
		Content: []mcp.Content{
			&mcp.TextContent{Text: message},
		},
	}

	// Log full response if debug mode
	if logger != nil {
		logger.Debug("write_file completed", "filename", input.Filename, "bytes_written", len(content))
		resultJSON, _ := json.MarshalIndent(result, "", "  ")
		logger.Debug("write_file RESPONSE", "response", string(resultJSON))
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
