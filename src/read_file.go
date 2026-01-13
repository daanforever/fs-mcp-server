package main

import (
	"context"
	"encoding/json"
	"fmt"
	"os"
	"regexp"
	"strconv"
	"strings"
	"unicode/utf8"

	"github.com/modelcontextprotocol/go-sdk/mcp"
	"golang.org/x/text/encoding"
	"golang.org/x/text/encoding/charmap"
	"golang.org/x/text/encoding/unicode"
	"golang.org/x/text/transform"
)

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
