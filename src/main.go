package main

import (
	"context"
	"encoding/json"
	"flag"
	"fmt"
	"log/slog"
	"os"
	"os/signal"
	"syscall"

	"github.com/modelcontextprotocol/go-sdk/mcp"
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

	// Register tools with JSON Schema descriptions for parameters

	// edit_file tool
	editFileSchema := map[string]interface{}{
		"type": "object",
		"properties": map[string]interface{}{
			"filename": map[string]interface{}{
				"type":        "string",
				"description": "Path to the file to edit",
			},
			"content": map[string]interface{}{
				"type":        "string",
				"description": "Full content to write (overrides partial replacement)",
			},
			"old_string": map[string]interface{}{
				"type":        "string",
				"description": "Text to be replaced (use with new_string)",
			},
			"new_string": map[string]interface{}{
				"type":        "string",
				"description": "New text to insert (use with old_string for replacement, or alone for append)",
			},
			"old_text": map[string]interface{}{
				"type":        "string",
				"description": "[Deprecated] Use old_string instead",
			},
			"new_text": map[string]interface{}{
				"type":        "string",
				"description": "[Deprecated] Use new_string instead",
			},
		},
		"required": []string{"filename"},
	}
	editFileSchemaJSON, _ := json.Marshal(editFileSchema)
	mcp.AddTool(server, &mcp.Tool{
		Name:        "edit_file",
		Description: "Edit a file. Supports two modes: 1) Text replacement with 'old_string' and 'new_string', 2) Append with 'new_string' only",
		InputSchema: json.RawMessage(editFileSchemaJSON),
	}, handleEditFile)

	// read_file tool
	readFileSchema := map[string]interface{}{
		"type": "object",
		"properties": map[string]interface{}{
			"filename": map[string]interface{}{
				"type":        "string",
				"description": "Path to the file to read",
			},
			"start_line": map[string]interface{}{
				"type":        "integer",
				"description": "Starting line number (1-based, inclusive)",
			},
			"end_line": map[string]interface{}{
				"type":        "integer",
				"description": "Ending line number (1-based, inclusive)",
			},
			"encoding": map[string]interface{}{
				"type":        "string",
				"description": "File encoding (utf-8, utf-16, utf-16le, utf-16be, windows-1251, iso-8859-1, etc.)",
			},
			"line_numbers": map[string]interface{}{
				"type":        "boolean",
				"description": "Include line numbers in output",
			},
			"skip_empty": map[string]interface{}{
				"type":        "boolean",
				"description": "Skip empty lines in output",
			},
			"max_lines": map[string]interface{}{
				"type":        "integer",
				"description": "Maximum number of lines to read",
			},
			"pattern": map[string]interface{}{
				"type":        "string",
				"description": "Regex pattern to filter lines",
			},
		},
		"required": []string{"filename"},
	}
	readFileSchemaJSON, _ := json.Marshal(readFileSchema)
	mcp.AddTool(server, &mcp.Tool{
		Name:        "read_file",
		Description: "Read content of a file with optional parameters for pagination, encoding, and filtering",
		InputSchema: json.RawMessage(readFileSchemaJSON),
	}, handleReadFile)

	// view tool (alias for read_file)
	mcp.AddTool(server, &mcp.Tool{
		Name:        "view",
		Description: "Read content of a file (alias for read_file)",
		InputSchema: json.RawMessage(readFileSchemaJSON),
	}, handleReadFile)

	// exec tool
	execSchema := map[string]interface{}{
		"type": "object",
		"properties": map[string]interface{}{
			"command": map[string]interface{}{
				"type":        "string",
				"description": "Shell command to execute",
			},
			"work_dir": map[string]interface{}{
				"type":        "string",
				"description": "Working directory for command execution (default: current directory)",
			},
			"timeout": map[string]interface{}{
				"type":        "integer",
				"description": "Timeout in seconds (default: 300)",
			},
		},
		"required": []string{"command"},
	}
	execSchemaJSON, _ := json.Marshal(execSchema)
	mcp.AddTool(server, &mcp.Tool{
		Name:        "exec",
		Description: "Execute a shell command in a specified or current working directory",
		InputSchema: json.RawMessage(execSchemaJSON),
	}, handleExec)

	// write_file tool
	writeFileSchema := map[string]interface{}{
		"type": "object",
		"properties": map[string]interface{}{
			"filename": map[string]interface{}{
				"type":        "string",
				"description": "Path to the file to write",
			},
			"content": map[string]interface{}{
				"type":        "string",
				"description": "Content to write to the file",
			},
		},
		"required": []string{"filename", "content"},
	}
	writeFileSchemaJSON, _ := json.Marshal(writeFileSchema)
	mcp.AddTool(server, &mcp.Tool{
		Name:        "write_file",
		Description: "Write content to a file. Creates the file if it doesn't exist, overwrites if it does.",
		InputSchema: json.RawMessage(writeFileSchemaJSON),
	}, handleWriteFile)

	// list_files tool
	listFilesSchema := map[string]interface{}{
		"type": "object",
		"properties": map[string]interface{}{
			"path": map[string]interface{}{
				"type":        "string",
				"description": "Directory path to list",
			},
			"pattern": map[string]interface{}{
				"type":        "string",
				"description": "Glob pattern to filter files (e.g., '*.go', '**/*.txt')",
			},
			"recursive": map[string]interface{}{
				"type":        "boolean",
				"description": "List files recursively",
			},
			"show_hidden": map[string]interface{}{
				"type":        "boolean",
				"description": "Include hidden files (starting with .)",
			},
			"max_depth": map[string]interface{}{
				"type":        "integer",
				"description": "Maximum recursion depth (when recursive is true)",
			},
		},
		"required": []string{"path"},
	}
	listFilesSchemaJSON, _ := json.Marshal(listFilesSchema)
	mcp.AddTool(server, &mcp.Tool{
		Name:        "list_files",
		Description: "List files and directories in a specified path with optional filtering",
		InputSchema: json.RawMessage(listFilesSchemaJSON),
	}, handleListFiles)

	// Run server (blocks until context cancelled)
	if err := server.Run(ctx, &mcp.StdioTransport{}); err != nil {
		if logger != nil {
			logger.Error("Server error", "error", err)
		}
		os.Exit(1)
	}
}
