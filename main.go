package main

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"os/exec"
	"os/signal"
	"path/filepath"
	"strings"
	"sync"
	"syscall"
	"time"
)

type MCPRequest struct {
	JSONRPC string          `json:"jsonrpc"`
	ID      interface{}     `json:"id"`
	Method  string          `json:"method"`
	Params  json.RawMessage `json:"params"`
}

type MCPResponse struct {
	JSONRPC string      `json:"jsonrpc"`
	ID      interface{} `json:"id"`
	Result  interface{} `json:"result,omitempty"`
	Error   *MCPError   `json:"error,omitempty"`
}

type MCPError struct {
	Code    int    `json:"code"`
	Message string `json:"message"`
	Data    interface{} `json:"data,omitempty"`
}

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
	Timeout *int    `json:"timeout,omitempty"` // Timeout in seconds, default: 300 (5 minutes)
	WorkDir *string `json:"work_dir,omitempty"` // Working directory for command execution (default: current working directory)
}

type commandTracker struct {
	mu       sync.Mutex
	commands map[*exec.Cmd]context.CancelFunc
}

var activeCommands = &commandTracker{
	commands: make(map[*exec.Cmd]context.CancelFunc),
}

func main() {
	// Create root context for graceful shutdown
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	
	// Set up signal handling
	sigChan := make(chan os.Signal, 1)
	signal.Notify(sigChan, syscall.SIGTERM, syscall.SIGINT)
	
	// Handle signals in a goroutine
	go func() {
		<-sigChan
		cancel()
		cleanupCommands()
	}()
	
	decoder := json.NewDecoder(os.Stdin)
	encoder := json.NewEncoder(os.Stdout)
	
	for {
		// Check if context is cancelled
		select {
		case <-ctx.Done():
			cleanupCommands()
			return
		default:
		}
		
		var req MCPRequest
		if err := decoder.Decode(&req); err != nil {
			if errors.Is(err, io.EOF) {
				cleanupCommands()
				return
			}
			// Отправляем ошибку парсинга, если есть ID
			if req.ID != nil {
				resp := MCPResponse{
					JSONRPC: "2.0",
					ID:      req.ID,
					Error: &MCPError{
						Code:    -32700,
						Message: fmt.Sprintf("Parse error: %v", err),
					},
				}
				encoder.Encode(resp)
			}
			continue
		}
		
		// Если ID отсутствует или равен null - это уведомление (notification)
		// Согласно JSON-RPC 2.0, на уведомления НЕ нужно отправлять ответ
		if req.ID == nil {
			continue
		}
		
		resp := handleRequest(req)
		if err := encoder.Encode(resp); err != nil {
			// Если не удалось отправить ответ, выходим
			cleanupCommands()
			return
		}
	}
}

func handleRequest(req MCPRequest) MCPResponse {
	resp := MCPResponse{
		JSONRPC: "2.0",
		ID:      req.ID,
	}
	
	switch req.Method {
	case "initialize":
		resp.Result = map[string]interface{}{
			"protocolVersion": "2024-11-05",
			"serverInfo": map[string]interface{}{
				"name":    "file-edit-server",
				"version": "1.0.0",
			},
			"capabilities": map[string]interface{}{
				"tools": map[string]interface{}{},
			},
		}
		return resp
	
	case "tools/list":
		resp.Result = map[string]interface{}{
			"tools": []map[string]interface{}{
			{
				"name":        "edit_file",
				"description": "Edit or create a file. Supports three modes: 1) Full write with 'content', 2) Text replacement with 'old_string' and 'new_string', 3) Append with 'new_string' only",
				"inputSchema": map[string]interface{}{
					"type": "object",
					"properties": map[string]interface{}{
						"filename": map[string]interface{}{
							"type":        "string",
							"description": "Path to the file to edit or create",
						},
						"content": map[string]interface{}{
							"type":        "string",
							"description": "Full file content. When provided, writes the entire file (overrides other parameters)",
						},
						"old_string": map[string]interface{}{
							"type":        "string",
							"description": "Text to be replaced in the file. Must be used together with 'new_string' for replacement, or alone to remove text",
						},
						"new_string": map[string]interface{}{
							"type":        "string",
							"description": "New text to insert. Used with 'old_string' for replacement, or alone to append to file",
						},
					},
					"required": []string{"filename"},
					"anyOf": []map[string]interface{}{
						{
							"required": []string{"content"},
						},
						{
							"required": []string{"old_string"},
						},
						{
							"required": []string{"new_string"},
						},
					},
				},
			},
				{
					"name":        "read_file",
					"description": "Read content of a file",
					"inputSchema": map[string]interface{}{
						"type": "object",
						"properties": map[string]interface{}{
							"filename": map[string]interface{}{
								"type":        "string",
								"description": "Path to the file",
							},
						},
						"required": []string{"filename"},
					},
				},
				{
					"name":        "view",
					"description": "Read content of a file (alias for read_file)",
					"inputSchema": map[string]interface{}{
						"type": "object",
						"properties": map[string]interface{}{
							"filename": map[string]interface{}{
								"type":        "string",
								"description": "Path to the file",
							},
						},
						"required": []string{"filename"},
					},
				},
				{
					"name":        "exec",
					"description": "Execute a shell command in a specified or current working directory",
					"inputSchema": map[string]interface{}{
						"type": "object",
						"properties": map[string]interface{}{
							"command": map[string]interface{}{
								"type":        "string",
								"description": "The shell command to execute",
							},
							"timeout": map[string]interface{}{
								"type":        "integer",
								"description": "Timeout in seconds (default: 300, i.e., 5 minutes)",
							},
							"work_dir": map[string]interface{}{
								"type":        "string",
								"description": "Working directory for command execution (default: current working directory)",
							},
						},
						"required": []string{"command"},
					},
				},
			},
		}
		return resp
	
	case "tools/call":
		var toolCall struct {
			Name      string          `json:"name"`
			Arguments json.RawMessage `json:"arguments"`
		}
		if err := json.Unmarshal(req.Params, &toolCall); err != nil {
			resp.Error = &MCPError{Code: -32600, Message: "Invalid request"}
			return resp
		}
		
		// Обрабатываем arguments - может быть строкой JSON или объектом
		arguments := toolCall.Arguments
		if len(arguments) > 0 && arguments[0] == '"' {
			// Если arguments - строка JSON, распарсим её
			var argsStr string
			if err := json.Unmarshal(arguments, &argsStr); err == nil {
				arguments = []byte(argsStr)
			}
		}
		
		switch toolCall.Name {
		case "edit_file":
			// Парсим аргументы для отображения в ошибках (даже если они невалидны)
			var rawArgs map[string]interface{}
			json.Unmarshal(arguments, &rawArgs)
			// Если не удалось распарсить, включаем raw строку
			if rawArgs == nil {
				rawArgs = make(map[string]interface{})
				rawArgs["_raw"] = string(arguments)
			}
			
			var args EditFileRequest
			if err := json.Unmarshal(arguments, &args); err != nil {
				resp.Error = &MCPError{
					Code:    -32602,
					Message: fmt.Sprintf("Invalid arguments: %v", err),
					Data: map[string]interface{}{
						"received_arguments": rawArgs,
					},
				}
				return resp
			}
			result := editFile(args, arguments, rawArgs)
			resp.Result = result.Result
			resp.Error = result.Error
			return resp
			
		case "read_file":
			// Парсим аргументы для отображения в ошибках (даже если они невалидны)
			var rawArgs map[string]interface{}
			json.Unmarshal(arguments, &rawArgs)
			// Если не удалось распарсить, включаем raw строку
			if rawArgs == nil {
				rawArgs = make(map[string]interface{})
				rawArgs["_raw"] = string(arguments)
			}
			
			var args ReadFileRequest
			if err := json.Unmarshal(arguments, &args); err != nil {
				resp.Error = &MCPError{
					Code:    -32602,
					Message: fmt.Sprintf("Invalid arguments: %v", err),
					Data: map[string]interface{}{
						"received_arguments": rawArgs,
					},
				}
				return resp
			}
			result := readFile(args, arguments, rawArgs)
			resp.Result = result.Result
			resp.Error = result.Error
			return resp
			
		case "view":
			// Alias for read_file - same implementation
			// Парсим аргументы для отображения в ошибках (даже если они невалидны)
			var rawArgs map[string]interface{}
			json.Unmarshal(arguments, &rawArgs)
			// Если не удалось распарсить, включаем raw строку
			if rawArgs == nil {
				rawArgs = make(map[string]interface{})
				rawArgs["_raw"] = string(arguments)
			}
			
			var args ReadFileRequest
			if err := json.Unmarshal(arguments, &args); err != nil {
				resp.Error = &MCPError{
					Code:    -32602,
					Message: fmt.Sprintf("Invalid arguments: %v", err),
					Data: map[string]interface{}{
						"received_arguments": rawArgs,
					},
				}
				return resp
			}
			result := readFile(args, arguments, rawArgs)
			resp.Result = result.Result
			resp.Error = result.Error
			return resp
			
		case "exec":
			// Парсим аргументы для отображения в ошибках (даже если они невалидны)
			var rawArgs map[string]interface{}
			json.Unmarshal(arguments, &rawArgs)
			// Если не удалось распарсить, включаем raw строку
			if rawArgs == nil {
				rawArgs = make(map[string]interface{})
				rawArgs["_raw"] = string(arguments)
			}
			
			var args ExecRequest
			if err := json.Unmarshal(arguments, &args); err != nil {
				resp.Error = &MCPError{
					Code:    -32602,
					Message: fmt.Sprintf("Invalid arguments: %v", err),
					Data: map[string]interface{}{
						"received_arguments": rawArgs,
					},
				}
				return resp
			}
			result := execCommand(args, arguments, rawArgs)
			resp.Result = result.Result
			resp.Error = result.Error
			return resp
			
		default:
			resp.Error = &MCPError{Code: -32601, Message: fmt.Sprintf("Method not found: %s", toolCall.Name)}
			return resp
		}
		
	default:
		resp.Error = &MCPError{Code: -32601, Message: "Method not found"}
		return resp
	}
}

func editFile(args EditFileRequest, rawArguments json.RawMessage, receivedArgs map[string]interface{}) MCPResponse {
	// Создаем директории если нужно
	dir := filepath.Dir(args.Filename)
	if dir != "." && dir != "" {
		os.MkdirAll(dir, 0755)
	}
	
	var content []byte
	var err error
	
	// Определяем какие параметры переданы (поддержка обоих вариантов имен для обратной совместимости)
	hasContent := args.Content != nil
	// Приоритет: old_string/new_string > old_text/new_text
	hasOldText := args.OldString != nil || args.OldText != nil
	hasNewText := args.NewString != nil || args.NewText != nil
	
	// Приоритет: content > old_text/new_text
	if hasContent {
		// Режим полной записи (включая пустую строку)
		if args.Content == nil {
			return MCPResponse{
				Error: &MCPError{
					Code:    -32602,
					Message: "Invalid arguments: content parameter is nil",
					Data: map[string]interface{}{
						"received_arguments": receivedArgs,
					},
				},
			}
		}
		content = []byte(*args.Content)
	} else if hasOldText {
		// Режим замены текста
		content, err = os.ReadFile(args.Filename)
		if err != nil && !os.IsNotExist(err) {
			return MCPResponse{
				Error: &MCPError{
					Code:    -32000,
					Message: fmt.Sprintf("Failed to read file: %v", err),
					Data: map[string]interface{}{
						"received_arguments": receivedArgs,
					},
				},
			}
		}
		
		fileContent := string(content)
		// Используем old_string/new_string если есть, иначе old_text/new_text
		var oldText string
		if args.OldString != nil {
			oldText = *args.OldString
		} else if args.OldText != nil {
			oldText = *args.OldText
		}
		newText := ""
		if args.NewString != nil {
			newText = *args.NewString
		} else if args.NewText != nil {
			newText = *args.NewText
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
		// Добавление в конец файла
		current, err := os.ReadFile(args.Filename)
		if err != nil && !os.IsNotExist(err) {
			return MCPResponse{
				Error: &MCPError{
					Code:    -32000,
					Message: fmt.Sprintf("Failed to read file: %v", err),
					Data: map[string]interface{}{
						"received_arguments": receivedArgs,
					},
				},
			}
		}
		fileContent := string(current)
		var newText string
		if args.NewString != nil {
			newText = *args.NewString
		} else if args.NewText != nil {
			newText = *args.NewText
		}
		if fileContent != "" && !strings.HasSuffix(fileContent, "\n") {
			fileContent += "\n"
		}
		fileContent += newText
		content = []byte(fileContent)
	} else {
		return MCPResponse{
			Error: &MCPError{
				Code:    -32602,
				Message: "Invalid arguments: must provide either 'content' (for full write), 'old_string' (for replacement/removal), or 'new_string' (for append)",
				Data: map[string]interface{}{
					"received_arguments": receivedArgs,
				},
			},
		}
	}
	
	// Write file with atomic operation for better reliability
	err = os.WriteFile(args.Filename, content, 0644)
	if err != nil {
		return MCPResponse{
			Error: &MCPError{
				Code:    -32000,
				Message: fmt.Sprintf("Failed to write file: %v", err),
				Data: map[string]interface{}{
					"received_arguments": receivedArgs,
					"content_length":     len(content),
				},
			},
		}
	}
	
	// Verify the write was successful by checking file size
	info, err := os.Stat(args.Filename)
	if err != nil {
		return MCPResponse{
			Error: &MCPError{
				Code:    -32000,
				Message: fmt.Sprintf("Failed to verify file write: %v", err),
				Data: map[string]interface{}{
					"received_arguments": receivedArgs,
					"content_length":     len(content),
				},
			},
		}
	}
	
	// Check if written size matches expected size
	if info.Size() != int64(len(content)) {
		return MCPResponse{
			Error: &MCPError{
				Code:    -32000,
				Message: fmt.Sprintf("File size mismatch: expected %d bytes, got %d bytes", len(content), info.Size()),
				Data: map[string]interface{}{
					"received_arguments": receivedArgs,
					"expected_size":      len(content),
					"actual_size":        info.Size(),
				},
			},
		}
	}
	
	return MCPResponse{
		Result: map[string]interface{}{
			"status":  "success",
			"message": fmt.Sprintf("File %s updated successfully", args.Filename),
			"bytes_written": len(content),
		},
	}
}

func readFile(args ReadFileRequest, rawArguments json.RawMessage, receivedArgs map[string]interface{}) MCPResponse {
	content, err := os.ReadFile(args.Filename)
	if err != nil {
		return MCPResponse{
			Error: &MCPError{
				Code:    -32000,
				Message: fmt.Sprintf("Failed to read file: %v", err),
				Data: map[string]interface{}{
					"received_arguments": receivedArgs,
				},
			},
		}
	}
	
	// Возвращаем объект с полем content как массив объектов для совместимости с MCP протоколом
	// Формат: [{"type": "text", "text": "..."}]
	return MCPResponse{
		Result: map[string]interface{}{
			"content": []map[string]interface{}{
				{
					"type": "text",
					"text": string(content),
				},
			},
		},
	}
}

func execCommand(args ExecRequest, rawArguments json.RawMessage, receivedArgs map[string]interface{}) MCPResponse {
	// Determine timeout
	timeout := 300 // Default: 5 minutes
	if args.Timeout != nil {
		timeout = *args.Timeout
	}
	
	// Validate work_dir if provided
	if args.WorkDir != nil {
		info, err := os.Stat(*args.WorkDir)
		if err != nil {
			return MCPResponse{
				Error: &MCPError{
					Code:    -32602,
					Message: fmt.Sprintf("Invalid work_dir: %v", err),
					Data: map[string]interface{}{
						"received_arguments": receivedArgs,
					},
				},
			}
		}
		if !info.IsDir() {
			return MCPResponse{
				Error: &MCPError{
					Code:    -32602,
					Message: fmt.Sprintf("work_dir is not a directory: %s", *args.WorkDir),
					Data: map[string]interface{}{
						"received_arguments": receivedArgs,
					},
				},
			}
		}
	}
	
	// Create context with timeout
	ctx, cancel := context.WithTimeout(context.Background(), time.Duration(timeout)*time.Second)
	defer cancel()
	
	// Create command
	cmd := exec.CommandContext(ctx, "bash", "-c", args.Command)
	
	// Set working directory if provided
	if args.WorkDir != nil {
		cmd.Dir = *args.WorkDir
	}
	
	// Capture stdout and stderr
	var stdoutBuf, stderrBuf bytes.Buffer
	cmd.Stdout = &stdoutBuf
	cmd.Stderr = &stderrBuf
	
	// Start the command
	if err := cmd.Start(); err != nil {
		return MCPResponse{
			Error: &MCPError{
				Code:    -32000,
				Message: fmt.Sprintf("Failed to start command: %v", err),
				Data: map[string]interface{}{
					"received_arguments": receivedArgs,
				},
			},
		}
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
			if ctx.Err() == context.DeadlineExceeded {
				return MCPResponse{
					Error: &MCPError{
						Code:    -32000,
						Message: fmt.Sprintf("Command timed out after %d seconds", timeout),
						Data: map[string]interface{}{
							"received_arguments": receivedArgs,
							"timeout":            timeout,
						},
					},
				}
			}
			return MCPResponse{
				Error: &MCPError{
					Code:    -32000,
					Message: fmt.Sprintf("Command execution error: %v", err),
					Data: map[string]interface{}{
						"received_arguments": receivedArgs,
					},
				},
			}
		}
	}
	
	// Determine status
	status := "success"
	if exitCode != 0 {
		status = "failed"
	}
	
	// Check for timeout
	timedOut := ctx.Err() == context.DeadlineExceeded
	
	return MCPResponse{
		Result: map[string]interface{}{
			"stdout":    stdoutBuf.String(),
			"stderr":    stderrBuf.String(),
			"exit_code": exitCode,
			"status":    status,
			"timeout":   timedOut,
		},
	}
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
}
