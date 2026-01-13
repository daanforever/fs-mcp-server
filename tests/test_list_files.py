#!/usr/bin/env python3
"""Tests for list_files tool"""

import os
import shutil
import sys
import json
from test_helper import send_mcp_request, test_case, print_test_results

TEST_DIR = "tmp/test_list_files_dir"

# Cleanup and setup
os.makedirs("tmp", exist_ok=True)
if os.path.exists(TEST_DIR):
    shutil.rmtree(TEST_DIR)
os.makedirs(TEST_DIR, exist_ok=True)

print("=== Tests for list_files ===")
print()

# Setup test files and directories
print("Setting up test files and directories...")
os.makedirs(f"{TEST_DIR}/subdir1", exist_ok=True)
os.makedirs(f"{TEST_DIR}/subdir2", exist_ok=True)
os.makedirs(f"{TEST_DIR}/subdir1/nested", exist_ok=True)
os.makedirs(f"{TEST_DIR}/.hidden_dir", exist_ok=True)

# Create test files
with open(f"{TEST_DIR}/file1.txt", "w") as f:
    f.write("test content 1")
with open(f"{TEST_DIR}/file2.txt", "w") as f:
    f.write("test content 2")
with open(f"{TEST_DIR}/file3.rb", "w") as f:
    f.write("ruby code")
with open(f"{TEST_DIR}/.hidden_file", "w") as f:
    f.write("hidden content")
with open(f"{TEST_DIR}/subdir1/file4.txt", "w") as f:
    f.write("nested file")
with open(f"{TEST_DIR}/subdir1/file5.rb", "w") as f:
    f.write("nested ruby")
with open(f"{TEST_DIR}/subdir1/nested/file6.txt", "w") as f:
    f.write("deep nested")
with open(f"{TEST_DIR}/subdir2/file7.txt", "w") as f:
    f.write("another nested")
with open(f"{TEST_DIR}/.hidden_dir/secret.txt", "w") as f:
    f.write("secret")

print()

# Helper function to extract files from response
def extract_files(response):
    """Extract files array from response"""
    if not response or "result" not in response:
        return None
    if "content" not in response["result"]:
        return None
    if not response["result"]["content"] or len(response["result"]["content"]) == 0:
        return None
    
    text = response["result"]["content"][0].get("text", "")
    if not text:
        return None
    
    try:
        data = json.loads(text)
        return data.get("files", [])
    except json.JSONDecodeError:
        return None

# Helper function to get file names from response
def get_file_names(response):
    """Get list of file names from response"""
    files = extract_files(response)
    if files is None:
        return None
    return sorted([f["name"] for f in files])

# Helper function to check if response has error
def has_error(response):
    """Check if response has an error"""
    if response is None:
        return False
    # Check for standard error field
    if "error" in response:
        return True
    # Check for isError flag in result (MCP SDK format)
    if "result" in response and response["result"].get("isError", False):
        return True
    return False

# 1. Basic listing (non-recursive, no filters)
def test_1():
    request = {
        "jsonrpc": "2.0",
        "id": 2,
        "method": "tools/call",
        "params": {
            "name": "list_files",
            "arguments": {"path": TEST_DIR}
        }
    }
    response = send_mcp_request(request)
    files = get_file_names(response)
    # Should include file1.txt, file2.txt, file3.rb, subdir1, subdir2 (but not .hidden_file or .hidden_dir)
    expected = ["file1.txt", "file2.txt", "file3.rb", "subdir1", "subdir2"]
    return files == expected

test_case("1. Basic listing (non-recursive, no filters)", test_1, lambda r: r)

# 2. Path is a file (should return single file entry)
def test_2():
    request = {
        "jsonrpc": "2.0",
        "id": 2,
        "method": "tools/call",
        "params": {
            "name": "list_files",
            "arguments": {"path": f"{TEST_DIR}/file1.txt"}
        }
    }
    response = send_mcp_request(request)
    files = extract_files(response)
    if files is None or len(files) != 1:
        return False
    file = files[0]
    return (file["name"] == "file1.txt" and 
            file["type"] == "file" and 
            "size" in file and 
            "modified" in file)

test_case("2. Path is a file (single file entry)", test_2, lambda r: r)

# 3. Recursive listing
def test_3():
    request = {
        "jsonrpc": "2.0",
        "id": 2,
        "method": "tools/call",
        "params": {
            "name": "list_files",
            "arguments": {"path": TEST_DIR, "recursive": True}
        }
    }
    response = send_mcp_request(request)
    files = get_file_names(response)
    # Should include all files recursively (but not hidden)
    expected = ["file1.txt", "file2.txt", "file3.rb", "file4.txt", "file5.rb", 
                "file6.txt", "file7.txt", "nested", "subdir1", "subdir2"]
    return set(files) == set(expected)

test_case("3. Recursive listing", test_3, lambda r: r)

# 4. MaxDepth limiting - depth 1 (current directory only)
def test_4():
    request = {
        "jsonrpc": "2.0",
        "id": 2,
        "method": "tools/call",
        "params": {
            "name": "list_files",
            "arguments": {"path": TEST_DIR, "recursive": True, "max_depth": 1}
        }
    }
    response = send_mcp_request(request)
    files = get_file_names(response)
    # Should only include immediate children (same as non-recursive)
    expected = ["file1.txt", "file2.txt", "file3.rb", "subdir1", "subdir2"]
    return files == expected

test_case("4. MaxDepth=1 (current directory only)", test_4, lambda r: r)

# 5. MaxDepth limiting - depth 2 (one level deep)
def test_5():
    request = {
        "jsonrpc": "2.0",
        "id": 2,
        "method": "tools/call",
        "params": {
            "name": "list_files",
            "arguments": {"path": TEST_DIR, "recursive": True, "max_depth": 2}
        }
    }
    response = send_mcp_request(request)
    files = get_file_names(response)
    # Should include immediate children and one level deep (but not nested/file6.txt)
    expected = ["file1.txt", "file2.txt", "file3.rb", "file4.txt", "file5.rb", 
                "file7.txt", "nested", "subdir1", "subdir2"]
    return set(files) == set(expected)

test_case("5. MaxDepth=2 (one level deep)", test_5, lambda r: r)

# 6. Pattern filtering - *.txt
def test_6():
    request = {
        "jsonrpc": "2.0",
        "id": 2,
        "method": "tools/call",
        "params": {
            "name": "list_files",
            "arguments": {"path": TEST_DIR, "pattern": "*.txt"}
        }
    }
    response = send_mcp_request(request)
    files = get_file_names(response)
    # Should only include .txt files in current directory
    expected = ["file1.txt", "file2.txt"]
    return files == expected

test_case("6. Pattern filtering (*.txt)", test_6, lambda r: r)

# 7. Pattern filtering with recursive
def test_7():
    request = {
        "jsonrpc": "2.0",
        "id": 2,
        "method": "tools/call",
        "params": {
            "name": "list_files",
            "arguments": {"path": TEST_DIR, "recursive": True, "pattern": "*.txt"}
        }
    }
    response = send_mcp_request(request)
    files = get_file_names(response)
    # Should include all .txt files recursively
    expected = ["file1.txt", "file2.txt", "file4.txt", "file6.txt", "file7.txt"]
    return set(files) == set(expected)

test_case("7. Pattern filtering (*.txt) with recursive", test_7, lambda r: r)

# 8. Pattern filtering - file*
def test_8():
    request = {
        "jsonrpc": "2.0",
        "id": 2,
        "method": "tools/call",
        "params": {
            "name": "list_files",
            "arguments": {"path": TEST_DIR, "pattern": "file*"}
        }
    }
    response = send_mcp_request(request)
    files = get_file_names(response)
    # Should include all files starting with "file"
    expected = ["file1.txt", "file2.txt", "file3.rb"]
    return files == expected

test_case("8. Pattern filtering (file*)", test_8, lambda r: r)

# 9. Show hidden files
def test_9():
    request = {
        "jsonrpc": "2.0",
        "id": 2,
        "method": "tools/call",
        "params": {
            "name": "list_files",
            "arguments": {"path": TEST_DIR, "show_hidden": True}
        }
    }
    response = send_mcp_request(request)
    files = get_file_names(response)
    # Should include .hidden_file and .hidden_dir
    expected = [".hidden_dir", ".hidden_file", "file1.txt", "file2.txt", "file3.rb", "subdir1", "subdir2"]
    return files == expected

test_case("9. Show hidden files", test_9, lambda r: r)

# 10. Show hidden files with recursive
def test_10():
    request = {
        "jsonrpc": "2.0",
        "id": 2,
        "method": "tools/call",
        "params": {
            "name": "list_files",
            "arguments": {"path": TEST_DIR, "recursive": True, "show_hidden": True}
        }
    }
    response = send_mcp_request(request)
    files = get_file_names(response)
    # Should include .hidden_dir and secret.txt inside it
    expected = [".hidden_dir", ".hidden_file", "file1.txt", "file2.txt", "file3.rb", 
                "file4.txt", "file5.rb", "file6.txt", "file7.txt", "nested", 
                "secret.txt", "subdir1", "subdir2"]
    return set(files) == set(expected)

test_case("10. Show hidden files with recursive", test_10, lambda r: r)

# 11. Empty directory
def test_11():
    empty_dir = f"{TEST_DIR}/empty_subdir"
    os.makedirs(empty_dir, exist_ok=True)
    request = {
        "jsonrpc": "2.0",
        "id": 2,
        "method": "tools/call",
        "params": {
            "name": "list_files",
            "arguments": {"path": empty_dir}
        }
    }
    response = send_mcp_request(request)
    files = extract_files(response)
    return files is not None and len(files) == 0

test_case("11. Empty directory", test_11, lambda r: r)

# 12. Non-existent path (error case)
def test_12():
    request = {
        "jsonrpc": "2.0",
        "id": 2,
        "method": "tools/call",
        "params": {
            "name": "list_files",
            "arguments": {"path": f"{TEST_DIR}/nonexistent"}
        }
    }
    response = send_mcp_request(request)
    return has_error(response)

test_case("12. Non-existent path (error)", test_12, lambda r: r)

# 13. Combined filters (pattern + recursive + show_hidden + max_depth)
def test_13():
    request = {
        "jsonrpc": "2.0",
        "id": 2,
        "method": "tools/call",
        "params": {
            "name": "list_files",
            "arguments": {
                "path": TEST_DIR,
                "recursive": True,
                "pattern": "*.txt",
                "show_hidden": True,
                "max_depth": 2
            }
        }
    }
    response = send_mcp_request(request)
    files = get_file_names(response)
    # Should include .txt files up to depth 2, including hidden .txt files
    # Note: .hidden_file doesn't match *.txt pattern, so it's excluded
    # secret.txt is at depth 2 inside .hidden_dir and matches the pattern
    expected = ["file1.txt", "file2.txt", "file4.txt", "file7.txt", "secret.txt"]
    return set(files) == set(expected)

test_case("13. Combined filters (pattern + recursive + show_hidden + max_depth)", test_13, lambda r: r)

# 14. Verify response structure
def test_14():
    request = {
        "jsonrpc": "2.0",
        "id": 2,
        "method": "tools/call",
        "params": {
            "name": "list_files",
            "arguments": {"path": f"{TEST_DIR}/file1.txt"}
        }
    }
    response = send_mcp_request(request)
    files = extract_files(response)
    if files is None or len(files) != 1:
        return False
    file = files[0]
    # Check required fields
    required = ["name", "type", "modified"]
    for field in required:
        if field not in file:
            return False
    # Check type is valid
    if file["type"] not in ["file", "directory"]:
        return False
    # Check size is present for files
    if file["type"] == "file" and "size" not in file:
        return False
    return True

test_case("14. Verify response structure", test_14, lambda r: r)

# 15. Verify file sizes and modification dates
def test_15():
    request = {
        "jsonrpc": "2.0",
        "id": 2,
        "method": "tools/call",
        "params": {
            "name": "list_files",
            "arguments": {"path": f"{TEST_DIR}/file1.txt"}
        }
    }
    response = send_mcp_request(request)
    files = extract_files(response)
    if files is None or len(files) != 1:
        return False
    file = files[0]
    # Check size is correct (file1.txt has "test content 1" = 14 bytes)
    if file["size"] != 14:
        return False
    # Check modified is a valid ISO 8601 date string
    if not file["modified"] or len(file["modified"]) < 10:
        return False
    # Should be in RFC3339 format (e.g., "2024-01-01T00:00:00Z")
    if "T" not in file["modified"]:
        return False
    return True

test_case("15. Verify file sizes and modification dates", test_15, lambda r: r)

# 16. Invalid max_depth (should error)
def test_16():
    request = {
        "jsonrpc": "2.0",
        "id": 2,
        "method": "tools/call",
        "params": {
            "name": "list_files",
            "arguments": {"path": TEST_DIR, "max_depth": 0}
        }
    }
    response = send_mcp_request(request)
    return has_error(response)

test_case("16. Invalid max_depth=0 (error)", test_16, lambda r: r)

# 17. max_depth without recursive (should be ignored, works normally)
def test_17():
    request = {
        "jsonrpc": "2.0",
        "id": 2,
        "method": "tools/call",
        "params": {
            "name": "list_files",
            "arguments": {"path": TEST_DIR, "max_depth": 1}
        }
    }
    response = send_mcp_request(request)
    files = get_file_names(response)
    # Should work as non-recursive (max_depth ignored when recursive is false)
    expected = ["file1.txt", "file2.txt", "file3.rb", "subdir1", "subdir2"]
    if files is None:
        return False
    return files == expected

test_case("17. max_depth without recursive (ignored)", test_17, lambda r: r)

print()
print("=== Test Summary ===")
print()

# Cleanup
shutil.rmtree(TEST_DIR, ignore_errors=True)

# Print results and exit
sys.exit(print_test_results())
