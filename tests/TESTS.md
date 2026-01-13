# Test Documentation - Python Test Conversion Guide

## Overview

This document provides comprehensive guidance on creating and converting tests to Python for the MCP File Edit Server. Python tests offer better maintainability, cross-platform compatibility, and easier debugging compared to shell scripts.

## Test Structure

### Basic Template

```python
#!/usr/bin/env python3
"""Test description"""

import os
import shutil
import sys
import json  # Only needed if using json.dumps()
from test_helper import send_mcp_request, test_case, print_test_results
# Note: PASSED and FAILED are global variables in test_helper, 
# imported only if you need to access them directly (rarely needed)

TEST_DIR = "tmp/test_dir_name"

# Cleanup and setup
os.makedirs("tmp", exist_ok=True)
if os.path.exists(TEST_DIR):
    shutil.rmtree(TEST_DIR)
os.makedirs(TEST_DIR, exist_ok=True)

print("=== Test Suite Name ===")
print()

# Setup test files
# ... create test files ...

# Define test functions
def test_name():
    request = {
        "jsonrpc": "2.0",
        "id": 2,  # Use id > 1 to avoid conflicts with initialize
        "method": "tools/call",
        "params": {
            "name": "tool_name",
            "arguments": {...}
        }
    }
    response = send_mcp_request(request)
    # Process response and return result
    return result

# Run tests
test_case("Test name", test_name, lambda r: check_condition(r))

# Cleanup
shutil.rmtree(TEST_DIR, ignore_errors=True)

# Print results and exit
sys.exit(print_test_results())
```

## Helper Functions

### `send_mcp_request(request, timeout=5)`

Sends an MCP request to the server with proper initialization.

**Parameters:**
- `request` (dict): JSON-RPC request object
- `timeout` (int): Timeout in seconds (default: 5)

**Returns:**
- Response dictionary or `None` if request failed

**Features:**
- Automatically sends `initialize` and `notifications/initialized` messages
- Handles process lifecycle (start, communicate, cleanup)
- Filters out initialization responses
- Returns the last non-initialize response

**Example:**
```python
request = {
    "jsonrpc": "2.0",
    "id": 2,
    "method": "tools/call",
    "params": {
        "name": "read_file",
        "arguments": {"filename": "test.txt"}
    }
}
response = send_mcp_request(request)
```

### `test_case(name, test_func, check_func)`

Runs a test case and tracks results.

**Parameters:**
- `name` (str): Test case name/description
- `test_cmd` (callable): Function that returns test result
- `expected_check` (callable): Function that validates the result (returns bool)

**Example:**
```python
def test_read_file():
    # ... test logic ...
    return "Hello, World!"

test_case("Read file test", test_read_file, lambda r: r == "Hello, World!")
```

### `print_test_results()`

Prints test summary and returns exit code.

**Returns:**
- `0` if all tests passed
- `1` if any tests failed

**Usage:**
```python
sys.exit(print_test_results())
```

## Common Test Patterns

### 1. Reading File Content

**Pattern:**
```python
def test_read():
    request = {
        "jsonrpc": "2.0",
        "id": 2,
        "method": "tools/call",
        "params": {
            "name": "read_file",  # or "view"
            "arguments": {"filename": f"{TEST_DIR}/file.txt"}
        }
    }
    response = send_mcp_request(request)
    if response and "result" in response and "content" in response["result"]:
        if response["result"]["content"] and len(response["result"]["content"]) > 0:
            return response["result"]["content"][0].get("text", "")
    return None

test_case("Read file", test_read, lambda r: r == "expected content")
```

**Key Points:**
- **Always check for keys before accessing** to avoid KeyError exceptions
- Check for `"result"` and `"content"` keys
- Verify content array is not empty before accessing `[0]`
- Access content as `response["result"]["content"][0].get("text", "")` (use `.get()` for safety)
- Return `None` on failure, actual value on success
- Use lambda for validation in `test_case()`

### 2. Writing/Editing Files

**Pattern:**
```python
def test_write():
    request = {
        "jsonrpc": "2.0",
        "id": 2,
        "method": "tools/call",
        "params": {
            "name": "edit_file",
            "arguments": {
                "filename": f"{TEST_DIR}/file.txt",
                "content": "file content"
            }
        }
    }
    response = send_mcp_request(request)
    if response and "result" in response and "error" not in response:
        result = response.get("result", {})
        if result.get("isError") is not True:
            # Verify file was created/modified
            if os.path.exists(f"{TEST_DIR}/file.txt"):
                with open(f"{TEST_DIR}/file.txt", "r", encoding="utf-8") as f:
                    return f.read()
    return None

test_case("Write file", test_write, lambda r: r == "file content")
```

### 3. Error Handling Tests

**Pattern:**
```python
def test_error():
    request = {
        "jsonrpc": "2.0",
        "id": 2,
        "method": "tools/call",
        "params": {
            "name": "read_file",
            "arguments": {"filename": f"{TEST_DIR}/nonexistent.txt"}
        }
    }
    response = send_mcp_request(request)
    if response:
        return response.get("result", {}).get("isError") is True or "error" in response
    return False

test_case("Error handling", test_error, lambda r: r is True)
```

**Key Points:**
- Check for `isError` in result or `error` key in response
- Return `True` if error detected, `False` otherwise

### 4. Comparing Tool Responses

**Pattern:**
```python
def test_comparison():
    request1 = {
        "jsonrpc": "2.0",
        "id": 2,
        "method": "tools/call",
        "params": {
            "name": "view",
            "arguments": {"filename": f"{TEST_DIR}/file.txt"}
        }
    }
    request2 = {
        "jsonrpc": "2.0",
        "id": 2,
        "method": "tools/call",
        "params": {
            "name": "read_file",
            "arguments": {"filename": f"{TEST_DIR}/file.txt"}
        }
    }
    response1 = send_mcp_request(request1)
    response2 = send_mcp_request(request2)
    if response1 and response2 and "result" in response1 and "result" in response2:
        result1 = response1["result"]
        result2 = response2["result"]
        if "content" in result1 and "content" in result2:
            content1 = result1["content"]
            content2 = result2["content"]
            if content1 and content2 and len(content1) > 0 and len(content2) > 0:
                text1 = content1[0].get("text", "")
                text2 = content2[0].get("text", "")
                return text1 == text2
    return False

test_case("Compare tools", test_comparison, lambda r: r is True)
```

### 5. Testing JSON String Arguments (Unsupported)

**Pattern:**
```python
import json

def test_string_args():
    request = {
        "jsonrpc": "2.0",
        "id": 2,
        "method": "tools/call",
        "params": {
            "name": "read_file",
            "arguments": json.dumps({"filename": f"{TEST_DIR}/file.txt"})
        }
    }
    response = send_mcp_request(request)
    if response:
        return response.get("result", {}).get("isError") is True or "error" in response
    return False

test_case("String arguments (unsupported)", test_string_args, lambda r: r is True)
```

**Note:** The MCP SDK only supports JSON object format for arguments. JSON string format should return an error.

## File Operations

### Creating Test Files

```python
# Simple file
with open(f"{TEST_DIR}/file.txt", "w", encoding="utf-8") as f:
    f.write("content")

# Empty file
with open(f"{TEST_DIR}/empty.txt", "w", encoding="utf-8") as f:
    pass  # Empty file

# Multiline file
with open(f"{TEST_DIR}/multiline.txt", "w", encoding="utf-8") as f:
    f.write("Line 1\nLine 2\nLine 3")

# UTF-8 file
with open(f"{TEST_DIR}/utf8.txt", "w", encoding="utf-8") as f:
    f.write("Привет 🌍")

# Nested directories
os.makedirs(f"{TEST_DIR}/nested/deep", exist_ok=True)
with open(f"{TEST_DIR}/nested/deep/file.txt", "w", encoding="utf-8") as f:
    f.write("content")
```

### Reading Test Files

```python
# Read file content
if os.path.exists(file_path):
    with open(file_path, "r", encoding="utf-8") as f:
        content = f.read()

# Check file size
if os.path.exists(file_path):
    size = os.path.getsize(file_path)
```

### Cleanup

```python
# Remove test directory
shutil.rmtree(TEST_DIR, ignore_errors=True)
```

## Response Structure

### Successful Response

**JSON representation:**
```json
{
    "jsonrpc": "2.0",
    "id": 2,
    "result": {
        "content": [
            {
                "type": "text",
                "text": "file content"
            }
        ],
        "isError": false
    }
}
```

**In Python code, access as:**
```python
response["result"]["content"][0]["text"]  # "file content"
response["result"].get("isError")  # False (Python boolean)
```

### Error Response

**Format 1 - Error object:**
```json
{
    "jsonrpc": "2.0",
    "id": 2,
    "error": {
        "code": -32000,
        "message": "Error message"
    }
}
```

**Format 2 - Error in result:**
```json
{
    "jsonrpc": "2.0",
    "id": 2,
    "result": {
        "isError": true,
        "content": [...]
    }
}
```

**In Python code, check for errors:**
```python
# Check for error object
if "error" in response:
    error_code = response["error"]["code"]
    
# Check for isError flag
if response.get("result", {}).get("isError") is True:
    # Handle error
```

## Conversion Checklist

When converting a shell test to Python:

- [ ] Replace shell script shebang with Python shebang
- [ ] Import required modules (`os`, `shutil`, `sys`, `test_helper`)
- [ ] Import `json` only if using `json.dumps()` (e.g., for string arguments tests)
- [ ] Replace `TEST_DIR` variable definition
- [ ] Convert file creation from `echo` to `open()` with context manager
- [ ] Replace `mkdir -p` with `os.makedirs(..., exist_ok=True)`
- [ ] Convert `test_case` calls to Python function definitions
- [ ] Replace shell command execution with `send_mcp_request()`
- [ ] Convert `jq` parsing to Python dictionary access
- [ ] Replace shell conditionals with Python `if` statements
- [ ] Convert shell string comparisons to Python string operations
- [ ] Replace `rm -rf` with `shutil.rmtree()`
- [ ] Update `print_test_results` call to use Python function
- [ ] Use `id: 2` instead of `id: 1` to avoid conflicts with initialize
- [ ] Check response structure: `response["result"]["content"][0]["text"]`
- [ ] Handle errors: check for `isError` or `error` key
- [ ] Make script executable: `chmod +x test_file.py`

## Differences from Shell Tests

### 1. Request ID

**Shell:** Often uses `id: 1`  
**Python:** Use `id: 2` or higher to avoid conflicts with initialize request

### 2. Response Parsing

**Shell:** Uses `jq` for JSON parsing
```bash
result=$(echo "$request" | $SERVER | jq -r '.result.content[0].text')
```

**Python:** Direct dictionary access (with safety checks)
```python
response = send_mcp_request(request)
if response and "result" in response and "content" in response["result"]:
    if response["result"]["content"] and len(response["result"]["content"]) > 0:
        text = response["result"]["content"][0].get("text", "")
```

### 3. File Operations

**Shell:**
```bash
echo "content" > file.txt
mkdir -p dir/subdir
rm -rf dir
```

**Python:**
```python
with open("file.txt", "w") as f:
    f.write("content")
os.makedirs("dir/subdir", exist_ok=True)
shutil.rmtree("dir", ignore_errors=True)
```

### 4. String Comparisons

**Shell:**
```bash
[[ "$result" == "expected" ]]
[[ "$result" == *"substring"* ]]
```

**Python:**
```python
r == "expected"
"substring" in r
```

### 5. Error Checking

**Shell:**
```bash
if echo "$request" | $SERVER | jq -e '.error != null'; then
    # error
fi
```

**Python:**
```python
if response.get("result", {}).get("isError") is True or "error" in response:
    # error
```

## Best Practices

1. **Never use unsafe dictionary access** - Always check keys exist before accessing:
   ```python
   # ❌ WRONG - Can raise KeyError
   text = response["result"]["content"][0]["text"]
   
   # ✅ CORRECT - Safe access with checks
   if response and "result" in response and "content" in response["result"]:
       if response["result"]["content"] and len(response["result"]["content"]) > 0:
           text = response["result"]["content"][0].get("text", "")
   ```

2. **Always use `id: 2` or higher** - Avoid conflicts with initialize request (id: 1)

3. **Check response structure** - Always verify keys exist before accessing to avoid KeyError:
   ```python
   if response and "result" in response and "content" in response["result"]:
       if response["result"]["content"] and len(response["result"]["content"]) > 0:
           text = response["result"]["content"][0].get("text", "")
   ```
   **Never use direct access like `response["result"]["content"][0]["text"]` without checks!**

4. **Return meaningful values** - Return actual data for success, `None` or `False` for failure

5. **Use descriptive test names** - Make test case names clear and specific

6. **Handle encoding** - Always specify `encoding="utf-8"` when reading/writing files

7. **Clean up properly** - Use `shutil.rmtree(..., ignore_errors=True)` for cleanup

8. **Test error cases** - Include tests for missing files, invalid arguments, etc.

9. **Use lambda for validation** - Keep validation logic concise in `test_case()` calls

10. **Create test files explicitly** - Don't rely on server creating files for read tests

11. **Verify file operations** - After write operations, read the file to verify content

## Example: Complete Test File

```python
#!/usr/bin/env python3
"""Example test file"""

import os
import shutil
import sys
from test_helper import send_mcp_request, test_case, print_test_results

TEST_DIR = "tmp/example_test"

# Setup
os.makedirs("tmp", exist_ok=True)
if os.path.exists(TEST_DIR):
    shutil.rmtree(TEST_DIR)
os.makedirs(TEST_DIR, exist_ok=True)

# Create test file
with open(f"{TEST_DIR}/test.txt", "w", encoding="utf-8") as f:
    f.write("Hello, World!")

print("=== Example Tests ===")
print()

# Test 1: Read file
def test_read():
    request = {
        "jsonrpc": "2.0",
        "id": 2,
        "method": "tools/call",
        "params": {
            "name": "read_file",
            "arguments": {"filename": f"{TEST_DIR}/test.txt"}
        }
    }
    response = send_mcp_request(request)
    if response and "result" in response and "content" in response["result"]:
        if response["result"]["content"] and len(response["result"]["content"]) > 0:
            return response["result"]["content"][0].get("text", "")
    return None

test_case("Read file", test_read, lambda r: r == "Hello, World!")

# Test 2: Write file
def test_write():
    request = {
        "jsonrpc": "2.0",
        "id": 2,
        "method": "tools/call",
        "params": {
            "name": "edit_file",
            "arguments": {
                "filename": f"{TEST_DIR}/output.txt",
                "content": "New content"
            }
        }
    }
    response = send_mcp_request(request)
    if response and "result" in response and "error" not in response:
        if response.get("result", {}).get("isError") is not True:
            file_path = f"{TEST_DIR}/output.txt"
            if os.path.exists(file_path):
                with open(file_path, "r", encoding="utf-8") as f:
                    return f.read()
    return None

test_case("Write file", test_write, lambda r: r == "New content")

# Test 3: Error case
def test_error():
    request = {
        "jsonrpc": "2.0",
        "id": 2,
        "method": "tools/call",
        "params": {
            "name": "read_file",
            "arguments": {"filename": f"{TEST_DIR}/nonexistent.txt"}
        }
    }
    response = send_mcp_request(request)
    if response:
        return response.get("result", {}).get("isError") is True or "error" in response
    return False

test_case("Error handling", test_error, lambda r: r is True)

# Cleanup
shutil.rmtree(TEST_DIR, ignore_errors=True)

# Print results
sys.exit(print_test_results())
```

## Running Tests

### Individual Test
```bash
python3 tests/test_view.py
```

### All Tests
```bash
./tests/run_all_tests.sh
```

## Troubleshooting

### Tests Always Fail

1. **Check server binary exists**: Ensure `./mcp-file-edit` is built
2. **Verify response structure**: Print response to see actual structure
3. **Check file paths**: Ensure test files are created in correct location
4. **Verify encoding**: Use `encoding="utf-8"` for all file operations

### Response is None

1. **Check timeout**: Increase timeout in `send_mcp_request(request, timeout=10)`
2. **Verify server starts**: Check if server process starts correctly
3. **Check request format**: Ensure JSON-RPC request is properly formatted
4. **Check server binary**: Ensure `./mcp-file-edit` exists and is executable
5. **Check working directory**: Run tests from project root directory

### Import Errors

1. **Check Python version**: Requires Python 3.6+
2. **Verify test_helper.py exists**: Ensure helper module is in same directory
3. **Check imports**: All required modules should be available

## Additional Resources

- See `test_read_file.py` for read_file tool tests
- See `test_view.py` for view tool tests (converted from shell)
- See `edge_cases_test.py` for comprehensive edge case testing
- See `test_helper.py` for helper function implementations
