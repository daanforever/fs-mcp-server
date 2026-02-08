package main

import (
	"context"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"runtime"
	"strings"

	"github.com/modelcontextprotocol/go-sdk/mcp"
)

// detectLineEnding detects the line ending style of the content
func detectLineEnding(content string) string {
	if strings.Contains(content, "\r\n") {
		return "\r\n" // Windows
	}
	return "\n" // Unix/Linux/macOS
}

// normalizeLineEndings converts content to use \n for internal processing
func normalizeLineEndings(content string) string {
	return strings.ReplaceAll(content, "\r\n", "\n")
}

// restoreLineEndings converts \n back to the original line ending style
func restoreLineEndings(content string, lineEnding string) string {
	if lineEnding == "\r\n" {
		// Replace \n with \r\n, but be careful not to double-convert
		// First, normalize any existing \r\n to \n, then convert all \n to \r\n
		content = strings.ReplaceAll(content, "\r\n", "\n")
		return strings.ReplaceAll(content, "\n", "\r\n")
	}
	return content
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
		logger.Debug("edit_file called", "filename", input.Filename, "os", runtime.GOOS)
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
		
		// On Windows, normalize line endings to CRLF for full writes if not explicitly provided
		contentStr := *input.Content
		if runtime.GOOS == "windows" && !strings.Contains(contentStr, "\r\n") {
			// If content has LF but no CRLF, and we're on Windows, convert to CRLF
			contentStr = strings.ReplaceAll(contentStr, "\n", "\r\n")
		}
		content = []byte(contentStr)
	} else if hasOldText {
		// Text replacement mode
		originalContent, err := os.ReadFile(input.Filename)
		if err != nil && !os.IsNotExist(err) {
			return nil, nil, fmt.Errorf("failed to read file %q: %v", input.Filename, err)
		}

		fileContent := string(originalContent)
		
		// Detect the line ending style of the existing file
		lineEnding := detectLineEnding(fileContent)
		
		// Normalize file content to \n for processing
		normalizedFileContent := normalizeLineEndings(fileContent)
		
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

		// Normalize input text to \n for matching (in case they came with different line endings)
		normalizedOldText := normalizeLineEndings(oldText)
		normalizedNewText := normalizeLineEndings(newText)

		if normalizedOldText == "*" {
			normalizedFileContent = normalizedNewText
		} else if strings.Contains(normalizedFileContent, normalizedOldText) {
			normalizedFileContent = strings.ReplaceAll(normalizedFileContent, normalizedOldText, normalizedNewText)
		} else if normalizedNewText != "" {
			if normalizedFileContent != "" && !strings.HasSuffix(normalizedFileContent, "\n") {
				normalizedFileContent += "\n"
			}
			normalizedFileContent += normalizedNewText
		}

		// Restore original line ending style before writing
		finalContent := restoreLineEndings(normalizedFileContent, lineEnding)
		content = []byte(finalContent)
	} else if hasNewText {
		// Append mode
		current, err := os.ReadFile(input.Filename)
		if err != nil && !os.IsNotExist(err) {
			return nil, nil, fmt.Errorf("failed to read file %q: %v", input.Filename, err)
		}
		fileContent := string(current)
		
		// Detect the line ending style of the existing file
		lineEnding := detectLineEnding(fileContent)
		
		// Normalize to \n for processing
		normalizedFileContent := normalizeLineEndings(fileContent)
		
		var newText string
		if input.NewString != nil {
			newText = *input.NewString
		} else if input.NewText != nil {
			newText = *input.NewText
		}
		
		// Normalize new text to \n
		normalizedNewText := normalizeLineEndings(newText)

		if normalizedFileContent != "" && !strings.HasSuffix(normalizedFileContent, "\n") {
			normalizedFileContent += "\n"
		}
		normalizedFileContent += normalizedNewText
		
		// Restore original line ending style
		finalContent := restoreLineEndings(normalizedFileContent, lineEnding)
		content = []byte(finalContent)
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
		logger.Debug("edit_file completed", "filename", input.Filename, "bytes_written", len(content), "os", runtime.GOOS)
		resultJSON, _ := json.MarshalIndent(result, "", "  ")
		logger.Debug("edit_file RESPONSE", "response", string(resultJSON))
	}

	return result, nil, nil
}
