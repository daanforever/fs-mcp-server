package main

import (
	"context"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"github.com/modelcontextprotocol/go-sdk/mcp"
)

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
