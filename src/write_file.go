package main

import (
	"context"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"

	"github.com/modelcontextprotocol/go-sdk/mcp"
)

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
