# Migration Plan: Migrate to Official MCP Go SDK

## Overview

This plan describes the migration of the MCP file edit server from a manual JSON-RPC implementation to the official `github.com/modelcontextprotocol/go-sdk` library. This migration will automatically resolve the tool result formatting issue and provide a more maintainable, type-safe implementation.

## Problem Statement

The current implementation manually handles JSON-RPC protocol and tool result formatting. According to MCP specification, tool call results must contain a `content` field which is an array of objects with `type` and `text` fields. The current implementation returns custom structures like `{"status": "success", "message": "...", "bytes_written": 49}` instead of the required `{"content": [{"type": "text", "text": "..."}]}` format.

## Benefits of Migration

- Automatic formatting of tool results in correct MCP format (to be validated in Step 0)
- Reduced boilerplate code for JSON-RPC protocol handling
- Type-safe APIs with Go interfaces (to be confirmed in Step 0)
- Built-in middleware support for logging and other cross-cutting concerns (to be confirmed in Step 0)
- Official support and regular updates
- Better error handling with automatic conversion to MCP error format (to be validated in Step 0)
- Automatic schema generation from Go structs (to be confirmed in Step 0)

## Current Architecture

The server currently implements:
- Manual JSON-RPC request/response handling with custom `MCPRequest`, `MCPResponse`, and `MCPError` structures
- Custom request routing in `handleRequest` function
- Manual tool registration and invocation
- Custom debug logging to file
- Signal handling for graceful shutdown
- Command tracking for exec tool with cleanup on shutdown

## Target Architecture

After migration, the server will use:
- Official MCP SDK server instance created with `mcp.NewServer` (exact API to be confirmed in Step 0)
- Automatic tool registration with `mcp.AddTool` or equivalent (exact API to be confirmed in Step 0)
- Standard tool handlers using `ToolHandlerFor` interface or equivalent pattern (exact signature to be confirmed in Step 0)
- Built-in transport layer (`StdioTransport` or equivalent) for JSON-RPC communication (exact API to be confirmed in Step 0)
- Automatic result formatting through `mcp.CallToolResult` and `mcp.TextContent` or equivalent (exact types to be confirmed in Step 0)
- Standard error handling through Go error interface with context preservation

## Migration Steps

### Step 0: Validate SDK and Create Proof-of-Concept

Before full migration, validate SDK capabilities and create a minimal proof-of-concept:

1. **Research SDK Version**: Identify the latest stable version of `github.com/modelcontextprotocol/go-sdk` (check releases, tags, or latest commit). Document the specific version to use (e.g., `v1.0.0` or commit hash).

2. **Verify SDK Capabilities**: Confirm the SDK provides:
   - `ToolHandlerFor` interface or equivalent handler pattern
   - `StdioTransport` for stdio communication
   - Automatic schema generation from structs
   - Middleware or logging hooks
   - Error wrapping with data preservation

3. **Test Argument Format Compatibility**: Create a test to verify the SDK handles arguments as both JSON object and JSON string (current implementation supports both). If SDK only supports one format, document the limitation and plan for client compatibility.

4. **Create Proof-of-Concept**: Migrate a single simple tool (e.g., `read_file`) to validate:
   - SDK integration works correctly
   - Tool result formatting matches MCP specification
   - Error handling preserves necessary context
   - Debug logging can be integrated
   - No regressions in functionality

5. **Document Findings**: Record any limitations, workarounds, or required changes discovered during validation.

### Step 1: Add Dependency

Add the official MCP Go SDK to the project dependencies with a specific version. Update `go.mod` file to include `github.com/modelcontextprotocol/go-sdk` with the version identified in Step 0. Use `go get` with the specific version tag or commit hash to ensure reproducible builds.

### Step 2: Remove Manual Protocol Structures

Remove the following custom structures that manually implement JSON-RPC protocol:
- `MCPRequest` struct - replaced by SDK's internal request handling
- `MCPResponse` struct - replaced by SDK's internal response handling  
- `MCPError` struct - replaced by SDK's automatic error conversion

These structures are located at the beginning of `main.go` and are no longer needed as the SDK handles all protocol-level communication.

### Step 3: Remove Manual Request Handling

Remove the following functions that manually handle JSON-RPC protocol:
- `handleRequest` function - replaced by SDK's automatic routing
- `logRequest` function - will be replaced by SDK middleware or custom logging integration
- `logResponse` function - will be replaced by SDK middleware or custom logging integration

The main request processing loop that reads from stdin, decodes JSON, routes requests, and encodes responses will be replaced by SDK's `server.Run()` method.

### Step 4: Rewrite Main Function

Replace the entire main function implementation. The new main function will:
- Initialize debug logging if enabled (preserve existing debug mode functionality)
- Set up signal handling for graceful shutdown (preserve existing signal handling)
- Create MCP server instance using `mcp.NewServer` with server name and version
- Register all tools using `mcp.AddTool` function
- Run the server using `server.Run()` with context and `StdioTransport`
- Integrate cleanup functions with server shutdown

The signal handling and context cancellation will be integrated with the SDK's server lifecycle.

### Step 5: Rewrite Tool Handlers

Convert all tool handler functions to use the `ToolHandlerFor` interface pattern. Each handler will have the signature:
- Context parameter for cancellation and timeout support
- `*mcp.CallToolRequest` parameter for request metadata
- Input struct parameter (automatically unmarshaled from request arguments)
- Return values: `*mcp.CallToolResult`, `interface{}`, and `error`

#### Edit File Handler

Convert `editFile` function to `handleEditFile` handler:
- Keep all existing file editing logic (directory creation, content handling, text replacement, append operations)
- Replace return value from `MCPResponse` to `*mcp.CallToolResult` with `Content` field containing array of `mcp.TextContent`
- Format success message as text content: "File {filename} updated successfully. Bytes written: {count}"
- Return errors as standard Go errors (SDK will convert to MCP error format)
- Remove manual error structure creation

#### Read File Handler

Convert `readFile` function to `handleReadFile` handler:
- Keep existing file reading logic
- Return file content as `mcp.TextContent` in `mcp.CallToolResult.Content` array
- Return errors as standard Go errors
- This handler will be used for both `read_file` and `view` tools (same implementation)

#### Exec Handler

Convert `execCommand` function to `handleExec` handler:
- Keep all existing command execution logic (timeout, work directory, stdout/stderr capture, exit code)
- Format output as single text message containing:
  - Exit code information
  - Status (success/failed)
  - Timeout indication if applicable
  - STDOUT content if present
  - STDERR content if present
- Return formatted message as `mcp.TextContent` in `mcp.CallToolResult.Content` array
- Return errors as standard Go errors

### Step 6: Update Request Structures

Keep existing request structures (`EditFileRequest`, `ReadFileRequest`, `ExecRequest`) but add JSON schema tags for automatic schema generation:
- Add `jsonschema` tags to struct fields for better documentation
- Ensure backward compatibility with existing field names (`old_text`/`new_text` aliases)
- These structures will be used as input parameters for `ToolHandlerFor` handlers

### Step 7: Update Error Handling

Replace all manual `MCPError` structure creation with standard Go error returns:
- Use `fmt.Errorf()` or custom error types
- SDK automatically converts Go errors to proper MCP error format
- Remove all `MCPResponse` error returns
- Keep error messages descriptive and informative
- **Preserve Error Context**: If the SDK supports error wrapping with data fields, use SDK's error wrapping features to preserve error details (like received arguments) that were previously in the `Data` field. If SDK doesn't support this, include critical context directly in error messages.

### Step 8: Integrate Debug Logging

Preserve existing debug logging functionality:
- Keep debug mode flag and log file initialization
- **Integration Approach**: Based on Step 0 validation, choose one of the following approaches (in priority order):
  1. Use SDK middleware if available and provides request/response hooks
  2. Add logging calls at the beginning and end of each tool handler (log request details and results)
  3. Create custom transport wrapper that intercepts requests/responses before passing to SDK
  4. Use SDK's built-in logging if available and configurable
- Maintain existing log format and file output
- Ensure logging captures request method, parameters, response results, and errors

### Step 9: Preserve Command Tracking

Keep existing command tracking functionality for exec tool:
- Preserve `commandTracker` struct and `activeCommands` global variable
- Integrate `cleanupCommands` function with server shutdown
- Ensure commands are properly tracked and cleaned up on server termination
- Maintain thread-safe command registration and unregistration

### Step 10: Update Tool Definitions

Tool definitions will be simplified:
- Remove manual schema definitions from `tools/list` handler
- SDK automatically generates schemas from handler input structs
- Keep tool names, descriptions, and parameter documentation
- Tool registration happens via `mcp.AddTool` with tool metadata

## Files to Modify

- `go.mod` - Add dependency on `github.com/modelcontextprotocol/go-sdk` with specific version (determined in Step 0)
- `main.go` - Complete refactoring of main function, tool handlers, and protocol handling

## Potential Challenges

### Argument Format Compatibility

**Status**: To be validated in Step 0.

The current code supports arguments as both JSON object and JSON string (for compatibility). If SDK validation in Step 0 reveals the SDK only supports one format:
- Document the limitation clearly
- If SDK only supports JSON object: Update client documentation and note breaking change
- If SDK only supports JSON string: May need custom argument parsing wrapper
- Test with existing clients to ensure compatibility

### Debug Logging Integration

**Status**: Approach to be determined in Step 0, implementation defined in Step 8.

The integration approach will be selected based on SDK capabilities discovered during validation. The chosen approach will be documented and implemented consistently across all handlers.

### Error Format Details

**Status**: Solution defined in Step 7.

During Step 0 validation, determine if SDK supports error wrapping with data fields. If supported, use SDK's error wrapping features. If not supported, include critical context (like received arguments) directly in error messages to maintain debugging capability.

### Testing Compatibility

Existing test scripts may need updates if:
- Response format changes (even if correct)
- Error message format changes
- Request/response timing changes

## Testing Strategy

### Pre-Migration Testing (Step 0)
1. Validate SDK installation and basic functionality
2. Test proof-of-concept tool with various inputs
3. Verify argument format compatibility
4. Test error handling and context preservation
5. Validate debug logging integration approach

### Post-Migration Testing
1. Run all existing test scripts to verify functionality
2. Test each tool individually (edit_file, read_file, view, exec)
3. Verify error handling with invalid inputs
4. Test graceful shutdown and command cleanup
5. Verify debug logging output
6. Test edge cases (empty files, special characters, timeouts)
7. Test with existing clients to ensure compatibility

## Rollback Plan

If migration encounters issues:
1. Keep current implementation in git branch
2. Create migration branch for SDK implementation
3. Test thoroughly before merging
4. Can revert to manual implementation if needed

## Success Criteria

Migration is successful when:
- All tools work correctly with proper MCP result formatting
- All existing tests pass
- Debug logging functions correctly
- Graceful shutdown works properly
- Command tracking and cleanup works for exec tool
- No regressions in functionality
- Code is cleaner and more maintainable

## Post-Migration Benefits

After successful migration:
- Automatic compliance with MCP specification
- Reduced code complexity and maintenance burden
- Better type safety and compile-time checks
- Access to SDK updates and improvements
- Easier to add new tools in the future
- Better integration with MCP ecosystem
