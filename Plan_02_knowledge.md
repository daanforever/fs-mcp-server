# Plan 02: Migration Knowledge Base

This document consolidates all essential information for migrating the MCP file edit server to the official Go SDK.

## Migration Status

- **Step 0**: ✅ Completed - SDK validation and proof-of-concept
- **Step 1**: ✅ Completed - Dependency added to `go.mod`
- **Step 2**: ✅ Completed - Manual protocol structures removed
- **Step 3**: ⏳ Pending - Remove manual request handling functions
- **Steps 4-10**: ⏳ Pending

**Current State**: Code will not compile until Step 3 is completed (functions still reference removed structs). This is expected during migration.

## Quick Reference

### SDK Version
- **Version**: `v1.1.0`
- **Import**: `github.com/modelcontextprotocol/go-sdk/mcp`
- **Status**: ✅ Already added to `go.mod` in Step 0

### Key SDK APIs

```go
import "github.com/modelcontextprotocol/go-sdk/mcp"

// Server creation
server := mcp.NewServer(&mcp.Implementation{
    Name:    "file-edit-server",
    Version: "1.0.0",
}, &mcp.ServerOptions{
    Logger: logger, // optional *slog.Logger
})

// Tool registration
mcp.AddTool(server, &mcp.Tool{
    Name:        "tool_name",
    Description: "Tool description",
}, handlerFunction)

// Run server
server.Run(ctx, &mcp.StdioTransport{})
```

## Tool Handler Pattern

### Handler Signature
```go
func handlerName(ctx context.Context, req *mcp.CallToolRequest, input InputStruct) (
    *mcp.CallToolResult,
    interface{},  // Usually nil, can be used for structured output
    error,
)
```

### Return Value Pattern
```go
// Success case
return &mcp.CallToolResult{
    Content: []mcp.Content{
        &mcp.TextContent{Text: "message here"},
    },
}, nil, nil

// Error case
return nil, nil, fmt.Errorf("error message with context: %v", err)
```

**Critical**: `mcp.TextContent` must be a pointer (`&mcp.TextContent{...}`) because it implements `mcp.Content` interface with pointer receiver.

## Current Implementation Details to Preserve

### Request Structures (Keep These)
```go
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

type ExecRequest struct {
    Command string  `json:"command"`
    Timeout *int    `json:"timeout,omitempty"` // Default: 300 seconds
    WorkDir *string `json:"work_dir,omitempty"`
}
```

### Command Tracking (Preserve)
```go
type commandTracker struct {
    mu       sync.Mutex
    commands map[*exec.Cmd]context.CancelFunc
}

var activeCommands = &commandTracker{
    commands: make(map[*exec.Cmd]context.CancelFunc),
}
```

### Debug Logging (Convert to slog)
Current implementation uses `log` package. Convert to `slog`:
```go
import (
    "log/slog"
    "os"
)

var logger *slog.Logger
if debugMode {
    logFile, err := os.OpenFile("mcp.log", os.O_CREATE|os.O_WRONLY|os.O_APPEND, 0644)
    if err != nil {
        // handle error
    }
    logger = slog.New(slog.NewTextHandler(logFile, &slog.HandlerOptions{
        Level: slog.LevelDebug,
    }))
}
```

## Conversion Patterns

### Pattern 1: Converting Tool Handlers

**Before (Current)**:
```go
func readFile(args ReadFileRequest, rawArguments json.RawMessage, receivedArgs map[string]interface{}) MCPResponse {
    content, err := os.ReadFile(args.Filename)
    if err != nil {
        return MCPResponse{
            Error: &MCPError{
                Code:    -32000,
                Message: fmt.Sprintf("Failed to read file: %v", err),
                Data: map[string]interface{}{
                    "received_arguments": receivedArgs,
                },
            },
        }
    }
    
    return MCPResponse{
        Result: map[string]interface{}{
            "content": []map[string]interface{}{
                {
                    "type": "text",
                    "text": string(content),
                },
            },
        },
    }
}
```

**After (SDK)**:
```go
func handleReadFile(ctx context.Context, req *mcp.CallToolRequest, input ReadFileRequest) (
    *mcp.CallToolResult,
    interface{},
    error,
) {
    content, err := os.ReadFile(input.Filename)
    if err != nil {
        return nil, nil, fmt.Errorf("failed to read file %q: %v", input.Filename, err)
    }
    
    return &mcp.CallToolResult{
        Content: []mcp.Content{
            &mcp.TextContent{Text: string(content)},
        },
    }, nil, nil
}
```

### Pattern 2: Error Handling Conversion

**Before**:
```go
return MCPResponse{
    Error: &MCPError{
        Code:    -32602,
        Message: fmt.Sprintf("Invalid arguments: %v", err),
        Data: map[string]interface{}{
            "received_arguments": receivedArgs,
        },
    },
}
```

**After**:
```go
// Include context directly in error message
return nil, nil, fmt.Errorf("invalid arguments: %v. Received: filename=%q", err, input.Filename)
```

### Pattern 3: Success Response Conversion

**Before (edit_file)**:
```go
return MCPResponse{
    Result: map[string]interface{}{
        "status":  "success",
        "message": fmt.Sprintf("File %s updated successfully", args.Filename),
        "bytes_written": len(content),
    },
}
```

**After**:
```go
message := fmt.Sprintf("File %s updated successfully. Bytes written: %d", input.Filename, len(content))
return &mcp.CallToolResult{
    Content: []mcp.Content{
        &mcp.TextContent{Text: message},
    },
}, nil, nil
```

### Pattern 4: Exec Command Response Conversion

**Before**:
```go
return MCPResponse{
    Result: map[string]interface{}{
        "stdout":    stdoutBuf.String(),
        "stderr":    stderrBuf.String(),
        "exit_code": exitCode,
        "status":    status,
        "timeout":   timedOut,
    },
}
```

**After**:
```go
var message strings.Builder
fmt.Fprintf(&message, "Exit code: %d\n", exitCode)
fmt.Fprintf(&message, "Status: %s\n", status)
if timedOut {
    fmt.Fprintf(&message, "Command timed out after %d seconds\n", timeout)
}
if stdoutBuf.Len() > 0 {
    fmt.Fprintf(&message, "STDOUT:\n%s\n", stdoutBuf.String())
}
if stderrBuf.Len() > 0 {
    fmt.Fprintf(&message, "STDERR:\n%s\n", stderrBuf.String())
}

return &mcp.CallToolResult{
    Content: []mcp.Content{
        &mcp.TextContent{Text: message.String()},
    },
}, nil, nil
```

## Structures to Remove

### Step 2: Removed ✅
- `MCPRequest` struct - **REMOVED**
- `MCPResponse` struct - **REMOVED**
- `MCPError` struct - **REMOVED**

### Step 3: To be removed
- `handleRequest` function (lines 170-419)
- `logRequest` function (lines 744-762)
- `logResponse` function (lines 764-780)

## Main Function Conversion

### Current Main Function Structure
1. Parse flags (`-debug`)
2. Initialize debug logging
3. Create context for graceful shutdown
4. Set up signal handling
5. Main loop: read from stdin, decode JSON, route requests, encode responses

### New Main Function Structure
```go
func main() {
    // Parse flags
    flag.BoolVar(&debugMode, "debug", false, "Enable debug logging to mcp.log")
    flag.Parse()
    
    // Initialize debug logging (convert to slog)
    var logger *slog.Logger
    if debugMode {
        logFile, err := os.OpenFile("mcp.log", os.O_CREATE|os.O_WRONLY|os.O_APPEND, 0644)
        if err != nil {
            fmt.Fprintf(os.Stderr, "Failed to open log file: %v\n", err)
            os.Exit(1)
        }
        defer logFile.Close()
        logger = slog.New(slog.NewTextHandler(logFile, &slog.HandlerOptions{
            Level: slog.LevelDebug,
        }))
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
        Description: "Read content of a file",
    }, handleReadFile)
    
    mcp.AddTool(server, &mcp.Tool{
        Name:        "view",
        Description: "Read content of a file (alias for read_file)",
    }, handleReadFile) // Same handler
    
    mcp.AddTool(server, &mcp.Tool{
        Name:        "exec",
        Description: "Execute a shell command in a specified or current working directory",
    }, handleExec)
    
    // Run server (blocks until context cancelled)
    if err := server.Run(ctx, &mcp.StdioTransport{}); err != nil {
        if logger != nil {
            logger.Error("Server error", "error", err)
        }
        os.Exit(1)
    }
}
```

## Edit File Handler Logic (Preserve)

The `editFile` function has complex logic that must be preserved:

1. **Directory Creation**: `os.MkdirAll(dir, 0755)` for parent directories
2. **Priority Order**:
   - `content` parameter → Full write mode
   - `old_string`/`old_text` + `new_string`/`new_text` → Replacement mode
   - `new_string`/`new_text` only → Append mode
3. **Special Cases**:
   - `old_text == "*"` → Replace entire file content
   - If `old_text` not found and `new_text` provided → Append to file
   - Empty content creates 0-byte file
4. **File Operations**:
   - Write with `os.WriteFile(filename, content, 0644)`
   - Verify write by checking file size
5. **Backward Compatibility**: Support both `old_string`/`new_string` and `old_text`/`new_text`

## Exec Handler Logic (Preserve)

The `execCommand` function has important logic:

1. **Timeout**: Default 300 seconds (5 minutes), configurable
2. **Working Directory**: Validates directory exists and is a directory
3. **Command Execution**: Uses `exec.CommandContext` with timeout context
4. **Command Tracking**: Registers command with `activeCommands` tracker
5. **Cleanup**: Unregisters command when done (defer)
6. **Output Capture**: Captures both stdout and stderr
7. **Exit Code**: Extracts exit code from `exec.ExitError`
8. **Timeout Detection**: Checks `context.DeadlineExceeded`

## Important Limitations

### 1. Argument Format Compatibility
- **Issue**: SDK only supports JSON object format for arguments
- **Current**: Supports both JSON object and JSON string
- **Impact**: Breaking change for clients using JSON string format
- **Action**: Document breaking change, test with existing clients

### 2. Error Context Preservation
- **Issue**: SDK doesn't preserve custom error data fields
- **Current**: Uses `MCPError.Data` to include `received_arguments`
- **Solution**: Include context directly in error messages
- **Example**: `fmt.Errorf("Invalid arguments: %v. Received: filename=%q", err, input.Filename)`

### 3. Debug Logging
- **Issue**: SDK logger logs protocol-level activity, not individual tool calls
- **Solution**: Add logging at beginning/end of each handler for detailed tool call logging
- **Alternative**: Use `ServerOptions.Logger` for protocol-level logging

### 4. No Middleware System
- **Issue**: SDK doesn't have built-in middleware
- **Solution**: Add logging calls directly in handlers
- **Pattern**: Log at handler start and end

## Schema Generation

SDK automatically generates schemas from struct tags. Add `jsonschema` tags for better documentation:

```go
type EditFileRequest struct {
    Filename  string  `json:"filename" jsonschema:"required,description=Path to the file to edit or create"`
    Content   *string `json:"content,omitempty" jsonschema:"description=Full file content. When provided, writes the entire file (overrides other parameters)"`
    OldString *string `json:"old_string,omitempty" jsonschema:"description=Text to be replaced in the file. Must be used together with 'new_string' for replacement, or alone to remove text"`
    NewString *string `json:"new_string,omitempty" jsonschema:"description=New text to insert. Used with 'old_string' for replacement, or alone to append to file"`
    // Backward compatibility
    OldText *string `json:"old_text,omitempty" jsonschema:"description=Deprecated: Use old_string instead"`
    NewText *string `json:"new_text,omitempty" jsonschema:"description=Deprecated: Use new_string instead"`
}
```

## Testing Checklist

### Pre-Migration (Step 0) ✅
- [x] SDK installation and compilation
- [x] Basic tool handler pattern
- [ ] Argument format compatibility (runtime testing needed)
- [ ] Error handling with context (testing needed)
- [ ] Debug logging integration (testing needed)

### Post-Migration
- [ ] Run all existing test scripts
- [ ] Test each tool individually (edit_file, read_file, view, exec)
- [ ] Verify error handling with invalid inputs
- [ ] Test graceful shutdown
- [ ] Verify debug logging output
- [ ] Test edge cases (empty files, special characters, timeouts)
- [ ] Test with existing clients to ensure compatibility

## File Locations

- **Proof-of-Concept**: `poc/poc_main.go` - Reference implementation
- **Findings**: `STEP0_FINDINGS.md` - Detailed Step 0 findings
- **Migration Plan**: `Plan_02.md` - Full migration plan
- **This Document**: `Plan_02_knowledge.md` - Quick reference guide

## Step-by-Step Quick Reference

### Step 1: Add Dependency ✅
- **Status**: Completed in Step 0
- `go.mod` contains `github.com/modelcontextprotocol/go-sdk v1.1.0`
- Dependency verified and ready for use

### Step 2: Remove Manual Protocol Structures ✅
- **Status**: Completed
- Removed `MCPRequest`, `MCPResponse`, `MCPError` structs from `main.go`
- **Note**: Code will not compile until Step 3 removes functions that reference these structs
- **Location**: Previously at lines 22-40 in `main.go`, now removed
- **Impact**: These structures are replaced by SDK's internal protocol handling

### Step 3: Remove Manual Request Handling
- Remove `handleRequest`, `logRequest`, `logResponse` functions
- Remove main request processing loop

### Step 4: Rewrite Main Function
- Use pattern from "Main Function Conversion" section above
- Preserve signal handling and cleanup

### Step 5: Rewrite Tool Handlers
- Convert `editFile` → `handleEditFile`
- Convert `readFile` → `handleReadFile` (used for both `read_file` and `view`)
- Convert `execCommand` → `handleExec`
- Use conversion patterns from above

### Step 6: Update Request Structures
- Add `jsonschema` tags to struct fields
- Keep backward compatibility fields (`old_text`/`new_text`)

### Step 7: Update Error Handling
- Replace all `MCPError` returns with standard Go errors
- Include context in error messages

### Step 8: Integrate Debug Logging
- Convert to `slog.Logger`
- Add handler-level logging if needed for detailed tool call logging

### Step 9: Preserve Command Tracking
- Keep `commandTracker` and `activeCommands`
- Integrate `cleanupCommands` with server shutdown

### Step 10: Update Tool Definitions
- Remove manual schema definitions
- SDK auto-generates from struct tags

## Common Pitfalls to Avoid

1. **TextContent Pointer**: Must use `&mcp.TextContent{...}`, not `mcp.TextContent{...}`
2. **Error Return**: Return `nil, nil, error` for errors, not `MCPResponse` with error
3. **Context Usage**: Use `ctx` parameter for cancellation/timeout support
4. **Argument Format**: SDK only supports JSON object, not JSON string
5. **Schema Tags**: Add `jsonschema` tags for better auto-generated schemas
6. **Handler Signature**: Must match exact signature pattern
7. **Content Array**: Always return `Content []mcp.Content` in `CallToolResult`

## Useful Code Snippets

### Handler-Level Logging (if needed)
```go
func handleReadFile(ctx context.Context, req *mcp.CallToolRequest, input ReadFileRequest) (
    *mcp.CallToolResult,
    interface{},
    error,
) {
    // Log request if debug mode
    if logger != nil {
        logger.Debug("read_file called", "filename", input.Filename)
    }
    
    // ... handler logic ...
    
    // Log result if debug mode
    if logger != nil {
        logger.Debug("read_file completed", "filename", input.Filename, "size", len(content))
    }
    
    return result, nil, nil
}
```

### Context-Aware File Operations
```go
// Use context for cancellation support
select {
case <-ctx.Done():
    return nil, nil, ctx.Err()
default:
    // Continue with operation
}
```

### Preserving Edit File Logic
```go
// Priority: content > old_string/new_string > new_string only
hasContent := input.Content != nil
hasOldText := input.OldString != nil || input.OldText != nil
hasNewText := input.NewString != nil || input.NewText != nil

if hasContent {
    // Full write mode
} else if hasOldText {
    // Replacement mode
} else if hasNewText {
    // Append mode
} else {
    return nil, nil, fmt.Errorf("must provide either 'content', 'old_string', or 'new_string'")
}
```

## Migration Order Recommendation

1. **Step 2-3**: Remove old structures and handlers (clean slate)
2. **Step 4**: Rewrite main function with SDK
3. **Step 5**: Convert handlers one at a time (start with `read_file` as simplest)
4. **Step 6**: Add schema tags to request structures
5. **Step 7**: Update error handling throughout
6. **Step 8**: Integrate debug logging
7. **Step 9**: Ensure command tracking works
8. **Step 10**: Verify tool definitions are correct

## Success Indicators

- ✅ Code compiles without errors
- ✅ All tools respond correctly
- ✅ Result format matches MCP spec: `{"content": [{"type": "text", "text": "..."}]}`
- ✅ Error messages are descriptive and include context
- ✅ Debug logging works (if enabled)
- ✅ Graceful shutdown works
- ✅ Command cleanup works for exec tool
- ✅ All existing tests pass

## Additional Resources

- **SDK Documentation**: `go doc github.com/modelcontextprotocol/go-sdk/mcp`
- **Proof-of-Concept**: `poc/poc_main.go` - Working example
- **Step 0 Findings**: `STEP0_FINDINGS.md` - Detailed validation results
- **Migration Plan**: `Plan_02.md` - Complete migration strategy
