package main

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strings"
)

type MCPRequest struct {
	Method  string          `json:"method"`
	Params  json.RawMessage `json:"params"`
}

type MCPResponse struct {
	Result interface{} `json:"result,omitempty"`
	Error  *MCPError   `json:"error,omitempty"`
}

type MCPError struct {
	Code    int    `json:"code"`
	Message string `json:"message"`
}

type EditFileRequest struct {
	Filename string  `json:"filename"`
	Content  *string `json:"content,omitempty"`
	OldText  *string `json:"old_text,omitempty"`
	NewText  *string `json:"new_text,omitempty"`
}

type ReadFileRequest struct {
	Filename string `json:"filename"`
}

func main() {
	decoder := json.NewDecoder(os.Stdin)
	for {
		var req MCPRequest
		if err := decoder.Decode(&req); err != nil {
			if err.Error() == "EOF" {
				return
			}
			continue
		}
		resp := handleRequest(req)
		encoder := json.NewEncoder(os.Stdout)
		encoder.Encode(resp)
	}
}

func handleRequest(req MCPRequest) MCPResponse {
	switch req.Method {
	case "initialize":
		return MCPResponse{
			Result: map[string]interface{}{
				"protocolVersion": "2024-11-05",
				"serverInfo": map[string]interface{}{
					"name":    "file-edit-server",
					"version": "1.0.0",
				},
				"capabilities": map[string]interface{}{
					"tools": []map[string]interface{}{
						{
							"name":        "edit_file",
							"description": "Edit or create a file with partial or full replacement",
							"inputSchema": map[string]interface{}{
								"type": "object",
								"properties": map[string]interface{}{
									"filename": map[string]interface{}{
										"type":        "string",
										"description": "Path to the file",
									},
									"content": map[string]interface{}{
										"type":        "string",
										"description": "Full content to write (overrides partial replacement)",
									},
									"old_text": map[string]interface{}{
										"type":        "string",
										"description": "Text to be replaced",
									},
									"new_text": map[string]interface{}{
										"type":        "string",
										"description": "New text to insert (empty to remove old_text)",
									},
								},
								"required": []string{"filename"},
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
				},
			},
		}
	
	case "tools/call":
		var toolCall struct {
			Name      string          `json:"name"`
			Arguments json.RawMessage `json:"arguments"`
		}
		if err := json.Unmarshal(req.Params, &toolCall); err != nil {
			return MCPResponse{
				Error: &MCPError{Code: -32600, Message: "Invalid request"},
			}
		}
		
		switch toolCall.Name {
		case "edit_file":
			var args EditFileRequest
			if err := json.Unmarshal(toolCall.Arguments, &args); err != nil {
				return MCPResponse{
					Error: &MCPError{Code: -32602, Message: "Invalid arguments"},
				}
			}
			return editFile(args)
			
		case "read_file":
			var args ReadFileRequest
			if err := json.Unmarshal(toolCall.Arguments, &args); err != nil {
				return MCPResponse{
					Error: &MCPError{Code: -32602, Message: "Invalid arguments"},
				}
			}
			return readFile(args)
			
		default:
			return MCPResponse{
				Error: &MCPError{Code: -32601, Message: "Method not found"},
			}
		}
		
	default:
		return MCPResponse{
			Error: &MCPError{Code: -32601, Message: "Method not found"},
		}
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
	
	// Определяем какие параметры переданы
	hasContent := args.Content != nil
	hasOldText := args.OldText != nil
	hasNewText := args.NewText != nil
	
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
		oldText := *args.OldText
		newText := ""
		if hasNewText {
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
		newText := *args.NewText
		if fileContent != "" && !strings.HasSuffix(fileContent, "\n") {
			fileContent += "\n"
		}
		fileContent += newText
		content = []byte(fileContent)
	} else {
		return MCPResponse{
			Error: &MCPError{Code: -32602, Message: "Either content, old_text/new_text, or new_text must be provided"},
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
	
	return MCPResponse{
		Result: map[string]interface{}{
			"content": string(content),
			"status":  "success",
		},
	}
}
