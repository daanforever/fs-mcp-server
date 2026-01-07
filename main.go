package main

import (
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"
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

func main() {
	decoder := json.NewDecoder(os.Stdin)
	encoder := json.NewEncoder(os.Stdout)
	
	for {
		var req MCPRequest
		if err := decoder.Decode(&req); err != nil {
			if errors.Is(err, io.EOF) {
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
		
		resp := handleRequest(req)
		if err := encoder.Encode(resp); err != nil {
			// Если не удалось отправить ответ, выходим
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
			var args EditFileRequest
			if err := json.Unmarshal(arguments, &args); err != nil {
				resp.Error = &MCPError{Code: -32602, Message: fmt.Sprintf("Invalid arguments: %v", err)}
				return resp
			}
			result := editFile(args)
			resp.Result = result.Result
			resp.Error = result.Error
			return resp
			
		case "read_file":
			var args ReadFileRequest
			if err := json.Unmarshal(arguments, &args); err != nil {
				resp.Error = &MCPError{Code: -32602, Message: fmt.Sprintf("Invalid arguments: %v", err)}
				return resp
			}
			result := readFile(args)
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

func editFile(args EditFileRequest) MCPResponse {
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
		content = []byte(*args.Content)
	} else if hasOldText {
		// Режим замены текста
		content, err = os.ReadFile(args.Filename)
		if err != nil && !os.IsNotExist(err) {
			return MCPResponse{
				Error: &MCPError{Code: -32000, Message: fmt.Sprintf("Failed to read file: %v", err)},
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
				Error: &MCPError{Code: -32000, Message: fmt.Sprintf("Failed to read file: %v", err)},
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
			},
		}
	}
	
	err = os.WriteFile(args.Filename, content, 0644)
	if err != nil {
		return MCPResponse{
			Error: &MCPError{Code: -32000, Message: fmt.Sprintf("Failed to write file: %v", err)},
		}
	}
	
	return MCPResponse{
		Result: map[string]interface{}{
			"status":  "success",
			"message": fmt.Sprintf("File %s updated successfully", args.Filename),
		},
	}
}

func readFile(args ReadFileRequest) MCPResponse {
	content, err := os.ReadFile(args.Filename)
	if err != nil {
		return MCPResponse{
			Error: &MCPError{Code: -32000, Message: fmt.Sprintf("Failed to read file: %v", err)},
		}
	}
	
	// Возвращаем объект с полем content для совместимости с различными клиентами
	return MCPResponse{
		Result: map[string]interface{}{
			"content": string(content),
		},
	}
}
