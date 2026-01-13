package main

import (
	"context"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/modelcontextprotocol/go-sdk/mcp"
)

type fileEntry struct {
	Name     string  `json:"name"`
	Type     string  `json:"type"`
	Size     *int64  `json:"size,omitempty"`
	Modified string  `json:"modified"`
}

type listFilesResponse struct {
	Files []fileEntry `json:"files"`
}

func handleListFiles(ctx context.Context, req *mcp.CallToolRequest, input ListFilesRequest) (
	*mcp.CallToolResult,
	interface{},
	error,
) {
	// Log full request if debug mode
	if logger != nil {
		reqJSON, _ := json.MarshalIndent(req, "", "  ")
		logger.Debug("list_files REQUEST", "request", string(reqJSON))
		logger.Debug("list_files called", "path", input.Path, "pattern", input.Pattern, "recursive", input.Recursive, "show_hidden", input.ShowHidden, "max_depth", input.MaxDepth)
	}

	// Check if path exists
	info, err := os.Stat(input.Path)
	if err != nil {
		return nil, nil, fmt.Errorf("failed to access path %q: %v", input.Path, err)
	}

	files := []fileEntry{} // Initialize as empty slice, not nil

	// If path is a file, return single file entry
	if !info.IsDir() {
		file := fileEntry{
			Name:     filepath.Base(input.Path),
			Type:     "file",
			Modified: info.ModTime().Format(time.RFC3339),
		}
		size := info.Size()
		file.Size = &size
		files = []fileEntry{file}

		resultJSON, _ := json.Marshal(listFilesResponse{Files: files})
		result := &mcp.CallToolResult{
			Content: []mcp.Content{
				&mcp.TextContent{Text: string(resultJSON)},
			},
		}

		if logger != nil {
			logger.Debug("list_files completed", "path", input.Path, "files_count", 1)
			resultJSON, _ := json.MarshalIndent(result, "", "  ")
			logger.Debug("list_files RESPONSE", "response", string(resultJSON))
		}

		return result, nil, nil
	}

	// Path is a directory - list files
	recursive := false
	if input.Recursive != nil {
		recursive = *input.Recursive
	}

	showHidden := false
	if input.ShowHidden != nil {
		showHidden = *input.ShowHidden
	}

	maxDepth := -1 // -1 means no limit
	if input.MaxDepth != nil {
		// Always validate max_depth if provided
		if *input.MaxDepth < 1 {
			return nil, nil, fmt.Errorf("invalid max_depth: must be >= 1, got %d", *input.MaxDepth)
		}
		// Only use max_depth when recursive is true
		if recursive {
			maxDepth = *input.MaxDepth
		}
	}

	// Determine if we should use pattern matching
	var patternMatch func(string) bool
	if input.Pattern != nil && *input.Pattern != "" {
		pattern := *input.Pattern
		patternMatch = func(name string) bool {
			matched, err := filepath.Match(pattern, name)
			return err == nil && matched
		}
	}

	// Walk directory
	if recursive {
		err = filepath.Walk(input.Path, func(path string, info os.FileInfo, err error) error {
			if err != nil {
				// Skip files/directories we can't access
				return nil
			}

			// Calculate depth relative to base path
			relPath, err := filepath.Rel(input.Path, path)
			if err != nil {
				return nil
			}

			// Count depth (number of separators + 1 for the file itself)
			depth := 1
			if relPath != "." {
				depth = strings.Count(relPath, string(filepath.Separator)) + 1
			}

			// Check max depth
			if maxDepth > 0 && depth > maxDepth {
				if info.IsDir() {
					return filepath.SkipDir
				}
				return nil
			}

			// Get base name
			name := filepath.Base(path)

			// Filter hidden files
			if !showHidden && strings.HasPrefix(name, ".") {
				if info.IsDir() {
					return filepath.SkipDir
				}
				return nil
			}

			// Filter by pattern (only match against base name)
			// Note: We still traverse directories even if they don't match pattern
			// to find matching files inside them
			if patternMatch != nil && !patternMatch(name) {
				if info.IsDir() {
					// Still traverse the directory to find matching files inside
					return nil
				}
				// Skip this file if it doesn't match
				return nil
			}

			// Create entry
			entry := fileEntry{
				Name:     name,
				Type:     "directory",
				Modified: info.ModTime().Format(time.RFC3339),
			}

			if !info.IsDir() {
				entry.Type = "file"
				size := info.Size()
				entry.Size = &size
			}

			// Skip the root directory itself
			if relPath != "." {
				files = append(files, entry)
			}

			return nil
		})
	} else {
		// Non-recursive: only list immediate children
		entries, err := os.ReadDir(input.Path)
		if err != nil {
			return nil, nil, fmt.Errorf("failed to read directory %q: %v", input.Path, err)
		}

		for _, entry := range entries {
			// Filter hidden files
			if !showHidden && strings.HasPrefix(entry.Name(), ".") {
				continue
			}

			// Filter by pattern
			if patternMatch != nil && !patternMatch(entry.Name()) {
				continue
			}

			info, err := entry.Info()
			if err != nil {
				continue
			}

			file := fileEntry{
				Name:     entry.Name(),
				Type:     "directory",
				Modified: info.ModTime().Format(time.RFC3339),
			}

			if !entry.IsDir() {
				file.Type = "file"
				size := info.Size()
				file.Size = &size
			}

			files = append(files, file)
		}
	}

	if err != nil {
		return nil, nil, fmt.Errorf("error walking directory: %v", err)
	}

	// Ensure files is never nil (use empty slice)
	if files == nil {
		files = []fileEntry{}
	}

	resultJSON, _ := json.Marshal(listFilesResponse{Files: files})
	result := &mcp.CallToolResult{
		Content: []mcp.Content{
			&mcp.TextContent{Text: string(resultJSON)},
		},
	}

	// Log full response if debug mode
	if logger != nil {
		logger.Debug("list_files completed", "path", input.Path, "files_count", len(files))
		resultJSON, _ := json.MarshalIndent(result, "", "  ")
		logger.Debug("list_files RESPONSE", "response", string(resultJSON))
	}

	return result, nil, nil
}
