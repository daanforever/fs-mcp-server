package main

import (
	"context"
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
