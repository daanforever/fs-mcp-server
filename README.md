# MCP File Edit Server

A simple Go-based MCP (Model Context Protocol) server for file editing.

## Features

- **edit_file** - create/edit files with partial or full replacement
- **read_file** - read file contents
- **view** - read file contents (alias for read_file)
- **exec** - execute shell commands with timeout and working directory support

## edit_file Parameters

| Parameter | Description |
|-----------|-------------|
| `filename` | Path to the file (required) |
| `content` | Full file content (takes priority over old_string/old_text) |
| `old_string` | Text to replace (takes priority over old_text) |
| `new_string` | New text (if empty - removes old_string) |
| `old_text` | Text to replace (deprecated, use old_string) |
| `new_text` | New text (deprecated, use new_string) |

**Note**: Both `old_string`/`new_string` and `old_text`/`new_text` are supported for backward compatibility. `old_string`/`new_string` take priority.

### Operating Modes:

1. **Full write** (`content`): Writes the entire file
2. **Partial replacement** (`old_string`/`old_text` + `new_string`/`new_text`): Replaces text
3. **Deletion** (`old_string`/`old_text` without `new_string`/`new_text`): Removes specified text
4. **Append** (only `new_string`/`new_text`): Adds to the end of the file
5. **Full replacement** (`old_string`/`old_text: "*"` + `new_string`/`new_text`): Replaces entire content

## read_file Parameters

| Parameter | Description |
|-----------|-------------|
| `filename` | Path to the file (required) |

**Return Value**: Object with `content` field containing an array of objects in the format `[{"type": "text", "text": "file content"}]` for MCP protocol compatibility.

## view Parameters

| Parameter | Description |
|-----------|-------------|
| `filename` | Path to the file (required) |

**Note**: `view` is an alias for `read_file` and has identical functionality. Returns the same data format.

## exec Parameters

| Parameter | Description |
|-----------|-------------|
| `command` | Shell command to execute (required) |
| `work_dir` | Working directory for command execution (optional, defaults to current directory) |
| `timeout` | Timeout in seconds (optional, default: 300 seconds / 5 minutes) |

**Return Value**: Object with fields:
- `stdout` - command's standard output
- `stderr` - standard error stream
- `exit_code` - command's exit code (0 on success)
- `status` - execution status ("success" or "failed")
- `timeout` - boolean indicating if timeout was exceeded

**Note**: Commands are executed via `bash -c`. All active commands are automatically terminated when the server shuts down (SIGTERM, then SIGKILL if necessary).

## Installation

```bash
go mod tidy
go build -o mcp-file-edit main.go
```

## Usage Examples

### Full Write
```bash
echo '{"method": "tools/call", "params": {"name": "edit_file", "arguments": {"filename": "test.txt", "content": "Hello World!"}}}' | ./mcp-file-edit
```

### Partial Replacement
```bash
echo '{"method": "tools/call", "params": {"name": "edit_file", "arguments": {"filename": "test.txt", "old_text": "old", "new_text": "new"}}}' | ./mcp-file-edit
```

### Text Deletion
```bash
echo '{"method": "tools/call", "params": {"name": "edit_file", "arguments": {"filename": "test.txt", "old_text": "remove this"}}}' | ./mcp-file-edit
```

### Append to End
```bash
echo '{"method": "tools/call", "params": {"name": "edit_file", "arguments": {"filename": "test.txt", "new_text": "new line"}}}' | ./mcp-file-edit
```

### Read File
```bash
echo '{"method": "tools/call", "params": {"name": "read_file", "arguments": {"filename": "test.txt"}}}' | ./mcp-file-edit
```

### Read File (view - alias for read_file)
```bash
echo '{"method": "tools/call", "params": {"name": "view", "arguments": {"filename": "test.txt"}}}' | ./mcp-file-edit
```

### Execute Command
```bash
echo '{"method": "tools/call", "params": {"name": "exec", "arguments": {"command": "ls -la", "work_dir": "/tmp", "timeout": 60}}}' | ./mcp-file-edit
```