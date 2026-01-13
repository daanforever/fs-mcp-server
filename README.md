# MCP File Edit Server

A simple Go-based MCP (Model Context Protocol) server for file editing operations.

## Features

- **edit_file** - Create/edit files with partial or full replacement
- **read_file** - Read file contents
- **view** - Read file contents (alias for read_file)
- **exec** - Execute shell commands with timeout and working directory support

## edit_file Parameters

| Parameter | Description |
|-----------|-------------|
| `filename` | Path to the file (required) |
| `content` | Full file content (takes priority over old_string/old_text) |
| `old_string` | Text to replace (takes priority over old_text) |
| `new_string` | New text (empty to remove old_string) |
| `old_text` | Text to replace (deprecated, use old_string) |
| `new_text` | New text (deprecated, use new_string) |

**Note**: Both `old_string`/`new_string` and `old_text`/`new_text` are supported for backward compatibility. `old_string`/`new_string` take priority.

### Operating Modes:

1. **Full write** (`content`): Writes entire file content
2. **Partial replacement** (`old_string`/`old_text` + `new_string`/`new_text`): Replaces text
3. **Deletion** (`old_string`/`old_text` without `new_string`/`new_text`): Removes specified text
4. **Append** (only `new_string`/`new_text`): Adds to end of file
5. **Full replacement** (`old_string`/`old_text: "*"` + `new_string`/`new_text`): Replaces entire content

## read_file Parameters

| Parameter | Description |
|-----------|-------------|
| `filename` | Path to the file (required) |
| `start_line` | Starting line number (1-based, optional) |
| `end_line` | Ending line number (1-based, inclusive, optional) |
| `encoding` | File encoding (optional, default: "utf-8"). Supported: utf-8, utf-16, utf-16be, utf-16le, windows-1251, iso-8859-1, iso-8859-15, windows-1252 |
| `line_numbers` | Add line numbers to output (optional, default: false) |
| `skip_empty` | Skip empty lines (optional, default: false) |
| `max_lines` | Maximum number of lines to return (optional) |
| `pattern` | Regex pattern to filter matching lines (optional) |

**Return Value**: Object with `content` field containing an array of objects in format `[{"type": "text", "text": "file content"}]` for MCP protocol compatibility.

**Note**: All parameters except `filename` are optional. If no optional parameters are provided, the entire file is returned as-is, maintaining backward compatibility.

## view Parameters

| Parameter | Description |
|-----------|-------------|
| `filename` | Path to the file (required) |

**Note**: `view` is an alias for `read_file` with identical functionality. Returns the same data format.

## exec Parameters

| Parameter | Description |
|-----------|-------------|
| `command` | Shell command to execute (required) |
| `work_dir` | Working directory for command execution (optional, default: current directory) |
| `timeout` | Timeout in seconds (optional, default: 300 seconds / 5 minutes) |

**Return Value**: Object with fields:
- `stdout` - command standard output
- `stderr` - standard error stream
- `exit_code` - command exit code (0 on success)
- `status` - execution status ("success" or "failed")
- `timeout` - boolean indicating if timeout was exceeded

**Note**: Commands are executed via `bash -c`. All active commands are automatically terminated when the server stops (SIGTERM, then SIGKILL if needed).

## Installation

```bash
go mod tidy
go build -o mcp-file-edit ./src
```

## Usage Examples

### Full write
```bash
echo '{"method": "tools/call", "params": {"name": "edit_file", "arguments": {"filename": "test.txt", "content": "Hello World!"}}}' | ./mcp-file-edit
```

### Partial replacement
```bash
echo '{"method": "tools/call", "params": {"name": "edit_file", "arguments": {"filename": "test.txt", "old_text": "old", "new_text": "new"}}}' | ./mcp-file-edit
```

### Text deletion
```bash
echo '{"method": "tools/call", "params": {"name": "edit_file", "arguments": {"filename": "test.txt", "old_text": "remove this"}}}' | ./mcp-file-edit
```

### Append to file
```bash
echo '{"method": "tools/call", "params": {"name": "edit_file", "arguments": {"filename": "test.txt", "new_text": "new line"}}}' | ./mcp-file-edit
```

### Read file
```bash
echo '{"method": "tools/call", "params": {"name": "read_file", "arguments": {"filename": "test.txt"}}}' | ./mcp-file-edit
```

### Read file with line range
```bash
echo '{"method": "tools/call", "params": {"name": "read_file", "arguments": {"filename": "test.txt", "start_line": 5, "end_line": 10}}}' | ./mcp-file-edit
```

### Read file with line numbers
```bash
echo '{"method": "tools/call", "params": {"name": "read_file", "arguments": {"filename": "test.txt", "line_numbers": true}}}' | ./mcp-file-edit
```

### Read file with regex filter
```bash
echo '{"method": "tools/call", "params": {"name": "read_file", "arguments": {"filename": "test.txt", "pattern": "error|warning"}}}' | ./mcp-file-edit
```

### Read file with encoding
```bash
echo '{"method": "tools/call", "params": {"name": "read_file", "arguments": {"filename": "test.txt", "encoding": "windows-1251"}}}' | ./mcp-file-edit
```

### Read file with multiple filters
```bash
echo '{"method": "tools/call", "params": {"name": "read_file", "arguments": {"filename": "test.txt", "start_line": 1, "end_line": 100, "skip_empty": true, "max_lines": 50, "line_numbers": true}}}' | ./mcp-file-edit
```

### Read file (view - alias for read_file)
```bash
echo '{"method": "tools/call", "params": {"name": "view", "arguments": {"filename": "test.txt"}}}' | ./mcp-file-edit
```

### Execute command
```bash
echo '{"method": "tools/call", "params": {"name": "exec", "arguments": {"command": "ls -la", "work_dir": "/tmp", "timeout": 60}}}' | ./mcp-file-edit
```