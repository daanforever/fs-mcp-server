package main

import (
	"context"
	"flag"
	"fmt"
	"log"
	"os"
	"os/signal"
	"syscall"

	"github.com/modelcontextprotocol/go-sdk/mcp"
)

var (
	debugMode bool
	logFile   *os.File
)

// ReadFileRequest matches the existing structure
type ReadFileRequest struct {
	Filename string `json:"filename"`
}

// Proof-of-concept: read_file tool handler using SDK
func handleReadFile(ctx context.Context, req *mcp.CallToolRequest, input ReadFileRequest) (
	*mcp.CallToolResult,
	interface{},
	error,
) {
	// Read file content
	content, err := os.ReadFile(input.Filename)
	if err != nil {
		return nil, nil, fmt.Errorf("failed to read file: %v", err)
	}

	// Return result in proper MCP format with Content array
	result := &mcp.CallToolResult{
		Content: []mcp.Content{
			&mcp.TextContent{
				Text: string(content),
			},
		},
	}

	return result, nil, nil
}

func main() {
	// Parse command line flags
	flag.BoolVar(&debugMode, "debug", false, "Enable debug logging to mcp.log")
	flag.Parse()

	// Initialize debug logging if enabled
	if debugMode {
		var err error
		logFile, err = os.OpenFile("mcp.log", os.O_CREATE|os.O_WRONLY|os.O_APPEND, 0644)
		if err != nil {
			fmt.Fprintf(os.Stderr, "Failed to open log file: %v\n", err)
			os.Exit(1)
		}
		defer logFile.Close()
		log.SetOutput(logFile)
		log.SetFlags(log.Ldate | log.Ltime | log.Lmicroseconds)
		log.Println("=== MCP Server started in debug mode (POC) ===")
	}

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
		if debugMode && logFile != nil {
			log.Println("=== MCP Server shutting down (POC) ===")
		}
	}()

	// Create MCP server instance
	server := mcp.NewServer(&mcp.Implementation{
		Name:    "file-edit-server",
		Version: "1.0.0",
	}, nil)

	// Register read_file tool
	mcp.AddTool(server, &mcp.Tool{
		Name:        "read_file",
		Description: "Read content of a file",
	}, handleReadFile)

	// Run the server over standard input/output
	if err := server.Run(ctx, &mcp.StdioTransport{}); err != nil {
		if debugMode && logFile != nil {
			log.Printf("Server error: %v\n", err)
		}
		log.Fatal(err)
	}
}
