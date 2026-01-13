# AGENTS.md - MCP File Edit Server

## Project Overview

**Type**: MCP (Model Context Protocol) server for file editing operations
**Language**: Go 1.24
**Purpose**: Provides file editing capabilities via MCP protocol for AI agents

## Project Structure

```
/
├── src/                 # Go source files
│   ├── main.go          # Main server implementation
│   ├── types.go         # Type definitions
│   ├── config.go        # Global configuration
│   ├── edit_file.go     # Edit file handler
│   ├── read_file.go     # Read file handler
│   ├── exec.go          # Exec handler
│   └── write_file.go    # Write file handler
├── go.mod               # Go module definition
├── README.md            # User documentation (see Documentation section)
├── AGENTS.md            # This file - AI agent guidelines
├── tests/               # Test scripts and documentation
│   ├── TESTS.md         # Test documentation and Python conversion guide (see Documentation section)
│   ├── test_example.sh  # Example test scripts
│   └── ...              # Additional test scripts
└── .continue/           # MCP server configuration
```

**Architecture**: Simple single-file server with JSON-based MCP protocol

## Essential Commands

### Build
```bash
go mod tidy
go build -o mcp-file-edit ./src
```

### Run
```bash
./mcp-file-edit
```

### Test
```bash
# Run test scripts
./tests/test_example.sh
./tests/test_edge_cases.sh
```

## Protocol & API

### MCP Protocol
- **Protocol Version**: 2024-11-05
- **Transport**: JSON over stdin/stdout
- **Server Name**: file-edit-server
- **Version**: 1.0.0

### Available Tools

#### 1. edit_file
**Description**: Edit or create a file with partial or full replacement

**Parameters**:
- `filename` (string, required): Path to the file
- `content` (string, optional): Full content to write (overrides partial replacement)
- `old_text` (string, optional): Text to be replaced
- `new_text` (string, optional): New text to insert (empty to remove old_text)

**Modes** (priority order):
1. **Full write** (`content`): Writes entire file content
2. **Partial replacement** (`old_text` + `new_text`): Replaces text occurrences
3. **Deletion** (`old_text` without `new_text`): Removes specified text
4. **Append** (only `new_text`): Adds text to end of file
5. **Full replacement** (`old_text: "*"` + `new_text`): Replaces entire content

#### 2. read_file
**Description**: Read content of a file

**Parameters**:
- `filename` (string, required): Path to the file

**Returns**: Object with `content` field containing file content as string

**Note**: The `arguments` parameter can be passed either as a JSON object or as a JSON string (for compatibility with different MCP clients)

## Error Handling

### Error Codes
- `-32600`: Invalid request (malformed JSON)
- `-32601`: Method not found
- `-32602`: Invalid arguments
- `-32000`: File operation errors (read/write failures)

### Error Response Format
```json
{
  "error": {
    "code": -32600,
    "message": "Invalid request"
  }
}
```

## Key Implementation Details

### File Operations
- **Directory Creation**: Automatically creates parent directories with `os.MkdirAll(dir, 0755)`
- **File Permissions**: Files created with `0644` permissions
- **Text Replacement**: Uses `strings.ReplaceAll()` for multiple occurrences
- **UTF-8 Support**: Full Unicode support for file content

### Special Behaviors
- **Non-existent files**: `old_text` operations create new file if it doesn't exist
- **Missing old_text**: If `old_text` not found, `new_text` is appended to file
- **Empty content**: Creates empty file (0 bytes)
- **Wildcard replacement**: `old_text: "*"` replaces entire file content

### Edge Cases Handled
- Empty files and strings
- Special characters and UTF-8
- Nested directories (automatic creation)
- Non-existent files
- Multiple text occurrences
- Various editing modes

## Documentation

### README.md
**Purpose**: User-facing documentation for the MCP File Edit Server

**Contents**:
- **Features Overview**: Lists all available tools (edit_file, read_file, view, exec)
- **API Reference**: Detailed parameter documentation for each tool:
  - `edit_file`: Parameters including `filename`, `content`, `old_string`/`old_text`, `new_string`/`new_text` with backward compatibility notes
  - `read_file`: Parameters including `filename`, `start_line`, `end_line`, `encoding`, `line_numbers`, `skip_empty`, `max_lines`, `pattern`
  - `view`: Alias for `read_file` with identical functionality
  - `exec`: Parameters including `command`, `work_dir`, `timeout` with return value structure
- **Operating Modes**: Detailed explanation of edit_file modes (full write, partial replacement, deletion, append, full replacement)
- **Installation Instructions**: Build commands and setup steps
- **Testing Guide**: Instructions for running tests, including reference to `tests/TESTS.md`
- **Usage Examples**: Comprehensive command-line examples for all tools and features

**Target Audience**: End users, developers integrating the server, and anyone using the MCP tools

**Key Information**:
- Parameter priority and backward compatibility (`old_string`/`new_string` vs `old_text`/`new_text`)
- Response format details (MCP protocol compatibility with content array format)
- Encoding support (utf-8, utf-16 variants, windows-1251, iso-8859-1, iso-8859-15, windows-1252)
- Command execution details (bash -c, timeout handling, process termination)

### tests/TESTS.md
**Purpose**: Comprehensive testing documentation and Python test conversion guide

**Contents**:
- **Python Test Conversion Guide**: Complete guide for creating and converting tests to Python
- **Test Structure & Templates**: Basic templates and patterns for writing tests
- **Helper Functions Documentation**:
  - `send_mcp_request()`: Sends MCP requests with automatic initialization
  - `test_case()`: Runs test cases and tracks results
  - `print_test_results()`: Prints test summary and returns exit code
- **Common Test Patterns**: Examples for:
  - Reading file content (with safe dictionary access)
  - Writing/editing files
  - Error handling tests
  - Comparing tool responses
  - Testing JSON string arguments
- **File Operations**: Patterns for creating test files, reading files, and cleanup
- **Response Structure**: Detailed explanation of MCP response formats (success and error responses)
- **Conversion Checklist**: Step-by-step guide for converting shell tests to Python
- **Differences from Shell Tests**: Comparison of shell vs Python testing approaches
- **Best Practices**: Safety guidelines, error handling, and testing recommendations
- **Example Test File**: Complete working example demonstrating all patterns
- **Running Tests**: Instructions for individual and batch test execution
- **Troubleshooting**: Common issues and solutions

**Target Audience**: Test developers, contributors adding new tests, developers converting shell tests to Python

**Key Information**:
- Always use `id: 2` or higher to avoid conflicts with initialize request
- Safe dictionary access patterns to avoid KeyError exceptions
- Response structure: `response["result"]["content"][0]["text"]` with proper checks
- Error checking: `isError` flag or `error` key in response
- Python is preferred over shell scripts for better maintainability and cross-platform compatibility

## Testing Strategy

### Test Files
- `tests/test_example.sh`: Basic functionality tests
- `tests/test_edge_cases.sh`: Comprehensive edge case testing
- `tests/TESTS.md`: Comprehensive test documentation and Python conversion guide (see Documentation section above)

### Test Coverage
15+ edge cases tested including:
- Empty files and content
- Text replacement and deletion
- Multiple occurrences
- Nested directory creation
- UTF-8 character support
- File append operations
- Priority handling of parameters

## Code Style & Conventions

### Naming
- **Structs**: PascalCase (e.g., `MCPRequest`, `EditFileRequest`)
- **Functions**: camelCase (e.g., `handleRequest`, `editFile`)
- **Variables**: camelCase (e.g., `fileContent`, `oldText`)
- **Constants**: Not used (all values are dynamic)

### Error Handling
- Uses custom `MCPError` struct with `Code` and `Message` fields
- Error codes follow MCP protocol standards
- Descriptive error messages with context

### JSON Processing
- Uses `encoding/json` package
- `json.RawMessage` for flexible parameter handling
- Explicit JSON tagging for struct fields

### File Operations
- Uses `os` package for file I/O
- `filepath` package for path manipulation
- `strings` package for text operations

## Development Workflow

### Typical Request Flow
1. JSON request received via stdin
2. Decode request using `json.NewDecoder`
3. Route to appropriate handler based on `method` field
4. Process tool call (edit_file/read_file)
5. Return JSON response via stdout

### Adding New Tools
1. Add tool definition in `initialize` method
2. Add handler in `tools/call` switch statement
3. Implement function following existing patterns
4. Update README.md with usage examples

## Gotchas & Pitfalls

### Parameter Priority
- `content` parameter takes priority over `old_text`/`new_text`
- If both are provided, `content` is used and other parameters ignored

### Text Replacement Logic
- If `old_text` not found and `new_text` provided, text is appended
- If `old_text` not found and no `new_text`, operation fails silently
- Wildcard `*` in `old_text` replaces entire file content

### File Creation
- Directories are automatically created for nested paths
- Files are created with 0644 permissions
- Empty content creates 0-byte files

### Error Conditions
- Returns error for invalid JSON or missing required fields
- File operation errors include detailed messages
- Method not found returns standard MCP error code

## Performance Considerations

- **Memory**: Reads entire file content into memory for operations
- **Concurrency**: Single-threaded, processes requests sequentially
- **I/O**: File operations are blocking
- **Scalability**: Designed for single-file operations, not bulk processing

## Security Notes

- No authentication/authorization implemented
- File operations limited to server's filesystem permissions
- No validation of file paths (potential directory traversal risk)
- Runs with current user's permissions

## Future Enhancement Areas

- Add file existence validation
- Implement path sanitization
- Add bulk file operations
- Support for binary files
- File locking mechanism
- Transaction support for multiple operations
