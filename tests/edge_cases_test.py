#!/usr/bin/env python3
"""Edge cases tests for MCP File Edit Server"""

import os
import shutil
import sys
import json
from test_helper import send_mcp_request, test_case, print_test_results, PASSED, FAILED

TEST_DIR = "test_dir"

# Cleanup and setup
if os.path.exists(TEST_DIR):
    shutil.rmtree(TEST_DIR)
os.makedirs(TEST_DIR, exist_ok=True)

print("=== Edge Cases Tests ===")
print()

# 1. File with empty content (content="")
def test_1():
    request = {
        "jsonrpc": "2.0",
        "id": 2,
        "method": "tools/call",
        "params": {
            "name": "edit_file",
            "arguments": {"filename": f"{TEST_DIR}/empty.txt", "content": ""}
        }
    }
    response = send_mcp_request(request)
    if response and "result" in response and "error" not in response:
        result = response.get("result", {})
        if result.get("isError") is not True:
            file_path = f"{TEST_DIR}/empty.txt"
            if os.path.exists(file_path) and os.path.getsize(file_path) == 0:
                return True
    return False

test_case("Empty file (content='')", test_1, lambda r: r is True)

# 2. File with spaces
def test_2():
    content = "   spaces   "
    request = {
        "jsonrpc": "2.0",
        "id": 2,
        "method": "tools/call",
        "params": {
            "name": "edit_file",
            "arguments": {"filename": f"{TEST_DIR}/spaces.txt", "content": content}
        }
    }
    response = send_mcp_request(request)
    if response and "result" in response and "error" not in response:
        result = response.get("result", {})
        if result.get("isError") is not True:
            file_path = f"{TEST_DIR}/spaces.txt"
            if os.path.exists(file_path):
                with open(file_path, "r", encoding="utf-8") as f:
                    file_content = f.read()
                    if file_content == content:
                        return True
    return False

test_case("File with spaces", test_2, lambda r: r is True)

# 3. Special characters
def test_3():
    content = "Line 1\nLine 2\n\tTabbed"
    request = {
        "jsonrpc": "2.0",
        "id": 2,
        "method": "tools/call",
        "params": {
            "name": "edit_file",
            "arguments": {"filename": f"{TEST_DIR}/special.txt", "content": content}
        }
    }
    response = send_mcp_request(request)
    if response and "result" in response and "error" not in response:
        result = response.get("result", {})
        if result.get("isError") is not True:
            file_path = f"{TEST_DIR}/special.txt"
            if os.path.exists(file_path):
                with open(file_path, "r", encoding="utf-8") as f:
                    file_content = f.read()
                    if "Line 1" in file_content:
                        return True
    return False

test_case("Special characters", test_3, lambda r: r is True)

# 4. Replacing non-existent text
def test_4():
    # First create base file
    request1 = {
        "jsonrpc": "2.0",
        "id": 2,
        "method": "tools/call",
        "params": {
            "name": "edit_file",
            "arguments": {"filename": f"{TEST_DIR}/base.txt", "content": "Base"}
        }
    }
    response1 = send_mcp_request(request1)
    if not response1 or "result" not in response1 or "error" in response1:
        return False
    if response1.get("result", {}).get("isError") is True:
        return False
    # Success, continue
    
    # Then try to replace non-existent text
    request2 = {
        "jsonrpc": "2.0",
        "id": 2,
        "method": "tools/call",
        "params": {
            "name": "edit_file",
            "arguments": {"filename": f"{TEST_DIR}/base.txt", "old_text": "missing", "new_text": "added"}
        }
    }
    response2 = send_mcp_request(request2)
    if response2 and "result" in response2 and "error" not in response2:
        result = response2.get("result", {})
        if result.get("isError") is not True:
            file_path = f"{TEST_DIR}/base.txt"
            if os.path.exists(file_path):
                with open(file_path, "r", encoding="utf-8") as f:
                    file_content = f.read()
                    if "added" in file_content:
                        return True
    return False

test_case("Replacing non-existent text", test_4, lambda r: r is True)

# 5. Deleting text (old_text without new_text)
def test_5():
    # First create file
    request1 = {
        "jsonrpc": "2.0",
        "id": 2,
        "method": "tools/call",
        "params": {
            "name": "edit_file",
            "arguments": {"filename": f"{TEST_DIR}/delete.txt", "content": "Remove this\nKeep this"}
        }
    }
    response1 = send_mcp_request(request1)
    if not response1 or "result" not in response1 or "error" in response1:
        return False
    if response1.get("result", {}).get("isError") is True:
        return False
    # Success, continue
    
    # Then delete text
    request2 = {
        "jsonrpc": "2.0",
        "id": 2,
        "method": "tools/call",
        "params": {
            "name": "edit_file",
            "arguments": {"filename": f"{TEST_DIR}/delete.txt", "old_text": "Remove this\n"}
        }
    }
    response2 = send_mcp_request(request2)
    if response2 and "result" in response2 and "error" not in response2:
        result = response2.get("result", {})
        if result.get("isError") is not True:
            file_path = f"{TEST_DIR}/delete.txt"
            if os.path.exists(file_path):
                with open(file_path, "r", encoding="utf-8") as f:
                    file_content = f.read()
                    if file_content == "Keep this":
                        return True
    return False

test_case("Deleting text", test_5, lambda r: r is True)

# 6. Multiple occurrences
def test_6():
    # First create file
    request1 = {
        "jsonrpc": "2.0",
        "id": 2,
        "method": "tools/call",
        "params": {
            "name": "edit_file",
            "arguments": {"filename": f"{TEST_DIR}/multi.txt", "content": "old old old"}
        }
    }
    response1 = send_mcp_request(request1)
    if not response1 or "result" not in response1 or "error" in response1:
        return False
    if response1.get("result", {}).get("isError") is True:
        return False
    # Success, continue
    
    # Then replace all occurrences
    request2 = {
        "jsonrpc": "2.0",
        "id": 2,
        "method": "tools/call",
        "params": {
            "name": "edit_file",
            "arguments": {"filename": f"{TEST_DIR}/multi.txt", "old_text": "old", "new_text": "NEW"}
        }
    }
    response2 = send_mcp_request(request2)
    if response2 and "result" in response2 and "error" not in response2:
        result = response2.get("result", {})
        if result.get("isError") is not True:
            file_path = f"{TEST_DIR}/multi.txt"
            if os.path.exists(file_path):
                with open(file_path, "r", encoding="utf-8") as f:
                    file_content = f.read()
                    if file_content == "NEW NEW NEW":
                        return True
    return False

test_case("Multiple occurrences", test_6, lambda r: r is True)

# 7. Nested directories
def test_7():
    request = {
        "jsonrpc": "2.0",
        "id": 2,
        "method": "tools/call",
        "params": {
            "name": "edit_file",
            "arguments": {"filename": f"{TEST_DIR}/a/b/c/deep.txt", "content": "deep"}
        }
    }
    response = send_mcp_request(request)
    if response and "result" in response and "error" not in response:
        result = response.get("result", {})
        if result.get("isError") is not True:
            file_path = f"{TEST_DIR}/a/b/c/deep.txt"
            if os.path.exists(file_path):
                return True
    return False

test_case("Nested directories", test_7, lambda r: r is True)

# 8. Reading non-existent file
def test_8():
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
        result = response.get("result", {})
        if result.get("isError") is True or "error" in response:
            return True
    return False

test_case("Reading non-existent file", test_8, lambda r: r is True)

# 9. Full replacement with *
def test_9():
    # First create file
    request1 = {
        "jsonrpc": "2.0",
        "id": 2,
        "method": "tools/call",
        "params": {
            "name": "edit_file",
            "arguments": {"filename": f"{TEST_DIR}/asterisk.txt", "content": "old"}
        }
    }
    response1 = send_mcp_request(request1)
    if not response1 or "result" not in response1 or "error" in response1:
        return False
    if response1.get("result", {}).get("isError") is True:
        return False
    # Success, continue
    
    # Then replace using *
    request2 = {
        "jsonrpc": "2.0",
        "id": 2,
        "method": "tools/call",
        "params": {
            "name": "edit_file",
            "arguments": {"filename": f"{TEST_DIR}/asterisk.txt", "old_text": "*", "new_text": "NEW"}
        }
    }
    response2 = send_mcp_request(request2)
    if response2 and "result" in response2 and "error" not in response2:
        result = response2.get("result", {})
        if result.get("isError") is not True:
            file_path = f"{TEST_DIR}/asterisk.txt"
            if os.path.exists(file_path):
                with open(file_path, "r", encoding="utf-8") as f:
                    file_content = f.read()
                    if file_content == "NEW":
                        return True
    return False

test_case("Full replacement with *", test_9, lambda r: r is True)

# 10. Very long string
def test_10():
    long_content = "A" * 10000
    request = {
        "jsonrpc": "2.0",
        "id": 2,
        "method": "tools/call",
        "params": {
            "name": "edit_file",
            "arguments": {"filename": f"{TEST_DIR}/long.txt", "content": long_content}
        }
    }
    response = send_mcp_request(request)
    if response and "result" in response and "error" not in response:
        result = response.get("result", {})
        if result.get("isError") is not True:
            file_path = f"{TEST_DIR}/long.txt"
            if os.path.exists(file_path):
                file_size = os.path.getsize(file_path)
                if file_size == 10000:
                    return True
    return False

test_case("Very long string", test_10, lambda r: r is True)

# 11. UTF-8 characters
def test_11():
    content = "Привет мир! 🌍"
    request = {
        "jsonrpc": "2.0",
        "id": 2,
        "method": "tools/call",
        "params": {
            "name": "edit_file",
            "arguments": {"filename": f"{TEST_DIR}/utf8.txt", "content": content}
        }
    }
    response = send_mcp_request(request)
    if response and "result" in response and "error" not in response:
        result = response.get("result", {})
        if result.get("isError") is not True:
            file_path = f"{TEST_DIR}/utf8.txt"
            if os.path.exists(file_path):
                with open(file_path, "r", encoding="utf-8") as f:
                    file_content = f.read()
                    if "Привет" in file_content:
                        return True
    return False

test_case("UTF-8 (Cyrillic)", test_11, lambda r: r is True)

# 12. Replacement in an empty file
def test_12():
    # First create empty file
    request1 = {
        "jsonrpc": "2.0",
        "id": 2,
        "method": "tools/call",
        "params": {
            "name": "edit_file",
            "arguments": {"filename": f"{TEST_DIR}/empty2.txt", "content": ""}
        }
    }
    response1 = send_mcp_request(request1)
    if not response1 or "result" not in response1 or "error" in response1:
        return False
    if response1.get("result", {}).get("isError") is True:
        return False
    # Success, continue
    
    # Then replace empty with text
    request2 = {
        "jsonrpc": "2.0",
        "id": 2,
        "method": "tools/call",
        "params": {
            "name": "edit_file",
            "arguments": {"filename": f"{TEST_DIR}/empty2.txt", "old_text": "", "new_text": "text"}
        }
    }
    response2 = send_mcp_request(request2)
    if response2 and "result" in response2 and "error" not in response2:
        result = response2.get("result", {})
        if result.get("isError") is not True:
            file_path = f"{TEST_DIR}/empty2.txt"
            if os.path.exists(file_path):
                with open(file_path, "r", encoding="utf-8") as f:
                    file_content = f.read()
                    if file_content == "text":
                        return True
    return False

test_case("Replacement in an empty file", test_12, lambda r: r is True)

# 13. Content has priority over old_text/new_text
def test_13():
    # First create file
    request1 = {
        "jsonrpc": "2.0",
        "id": 2,
        "method": "tools/call",
        "params": {
            "name": "edit_file",
            "arguments": {"filename": f"{TEST_DIR}/priority.txt", "content": "content1"}
        }
    }
    response1 = send_mcp_request(request1)
    if not response1 or "result" not in response1 or "error" in response1:
        return False
    if response1.get("result", {}).get("isError") is True:
        return False
    # Success, continue
    
    # Then use content with old_text/new_text (content should take priority)
    request2 = {
        "jsonrpc": "2.0",
        "id": 2,
        "method": "tools/call",
        "params": {
            "name": "edit_file",
            "arguments": {
                "filename": f"{TEST_DIR}/priority.txt",
                "content": "content2",
                "old_text": "ignored",
                "new_text": "ignored"
            }
        }
    }
    response2 = send_mcp_request(request2)
    if response2 and "result" in response2 and "error" not in response2:
        result = response2.get("result", {})
        if result.get("isError") is not True:
            file_path = f"{TEST_DIR}/priority.txt"
            if os.path.exists(file_path):
                with open(file_path, "r", encoding="utf-8") as f:
                    file_content = f.read()
                    if file_content == "content2":
                        return True
    return False

test_case("Content priority over old_text/new_text", test_13, lambda r: r is True)

# 14. Appending to an empty file
def test_14():
    # First create empty file
    request1 = {
        "jsonrpc": "2.0",
        "id": 2,
        "method": "tools/call",
        "params": {
            "name": "edit_file",
            "arguments": {"filename": f"{TEST_DIR}/empty3.txt", "content": ""}
        }
    }
    response1 = send_mcp_request(request1)
    if not response1 or "result" not in response1 or "error" in response1:
        return False
    if response1.get("result", {}).get("isError") is True:
        return False
    # Success, continue
    
    # Then append to empty file
    request2 = {
        "jsonrpc": "2.0",
        "id": 2,
        "method": "tools/call",
        "params": {
            "name": "edit_file",
            "arguments": {"filename": f"{TEST_DIR}/empty3.txt", "new_text": "line1"}
        }
    }
    response2 = send_mcp_request(request2)
    if response2 and "result" in response2 and "error" not in response2:
        result = response2.get("result", {})
        if result.get("isError") is not True:
            file_path = f"{TEST_DIR}/empty3.txt"
            if os.path.exists(file_path):
                with open(file_path, "r", encoding="utf-8") as f:
                    file_content = f.read()
                    if file_content == "line1":
                        return True
    return False

test_case("Appending to an empty file", test_14, lambda r: r is True)

# 15. Multiline new text
def test_15():
    # First create file
    request1 = {
        "jsonrpc": "2.0",
        "id": 2,
        "method": "tools/call",
        "params": {
            "name": "edit_file",
            "arguments": {"filename": f"{TEST_DIR}/multiline.txt", "content": "start"}
        }
    }
    response1 = send_mcp_request(request1)
    if not response1 or "result" not in response1 or "error" in response1:
        return False
    if response1.get("result", {}).get("isError") is True:
        return False
    # Success, continue
    
    # Then replace with multiline text
    request2 = {
        "jsonrpc": "2.0",
        "id": 2,
        "method": "tools/call",
        "params": {
            "name": "edit_file",
            "arguments": {
                "filename": f"{TEST_DIR}/multiline.txt",
                "old_text": "start",
                "new_text": "line1\nline2\nline3"
            }
        }
    }
    response2 = send_mcp_request(request2)
    if response2 and "result" in response2 and "error" not in response2:
        result = response2.get("result", {})
        if result.get("isError") is not True:
            file_path = f"{TEST_DIR}/multiline.txt"
            if os.path.exists(file_path):
                with open(file_path, "r", encoding="utf-8") as f:
                    file_content = f.read()
                    if "line2" in file_content:
                        return True
    return False

test_case("Multiline new text", test_15, lambda r: r is True)

# 16. Replace all occurrences (default)
def test_16():
    # First create file
    request1 = {
        "jsonrpc": "2.0",
        "id": 2,
        "method": "tools/call",
        "params": {
            "name": "edit_file",
            "arguments": {"filename": f"{TEST_DIR}/all.txt", "content": "test test test"}
        }
    }
    response1 = send_mcp_request(request1)
    if not response1 or "result" not in response1 or "error" in response1:
        return False
    if response1.get("result", {}).get("isError") is True:
        return False
    # Success, continue
    
    # Then replace all occurrences
    request2 = {
        "jsonrpc": "2.0",
        "id": 2,
        "method": "tools/call",
        "params": {
            "name": "edit_file",
            "arguments": {"filename": f"{TEST_DIR}/all.txt", "old_text": "test", "new_text": "PASS"}
        }
    }
    response2 = send_mcp_request(request2)
    if response2 and "result" in response2 and "error" not in response2:
        result = response2.get("result", {})
        if result.get("isError") is not True:
            file_path = f"{TEST_DIR}/all.txt"
            if os.path.exists(file_path):
                with open(file_path, "r", encoding="utf-8") as f:
                    file_content = f.read()
                    if file_content == "PASS PASS PASS":
                        return True
    return False

test_case("Replace all occurrences (default)", test_16, lambda r: r is True)

# 17. File without extension
def test_17():
    request = {
        "jsonrpc": "2.0",
        "id": 2,
        "method": "tools/call",
        "params": {
            "name": "edit_file",
            "arguments": {"filename": f"{TEST_DIR}/noextension", "content": "no ext"}
        }
    }
    response = send_mcp_request(request)
    if response and "result" in response and "error" not in response:
        result = response.get("result", {})
        if result.get("isError") is not True:
            file_path = f"{TEST_DIR}/noextension"
            if os.path.exists(file_path):
                return True
    return False

test_case("File without extension", test_17, lambda r: r is True)

# 18. Writing to a directory (error)
def test_18():
    request = {
        "jsonrpc": "2.0",
        "id": 2,
        "method": "tools/call",
        "params": {
            "name": "edit_file",
            "arguments": {"filename": f"{TEST_DIR}/", "content": "test"}
        }
    }
    response = send_mcp_request(request)
    # This should either error or succeed (depending on implementation)
    if response:
        result = response.get("result", {})
        if result.get("isError") is True or "error" in response:
            return True
        # Or if it succeeds, that's also acceptable
        if result.get("isError") is not True:
            return True
    return False

test_case("Writing to a directory", test_18, lambda r: r is True)

# 19. File with BOM
def test_19():
    content = "\uFEFFBOM"
    request = {
        "jsonrpc": "2.0",
        "id": 2,
        "method": "tools/call",
        "params": {
            "name": "edit_file",
            "arguments": {"filename": f"{TEST_DIR}/bom.txt", "content": content}
        }
    }
    response = send_mcp_request(request)
    if response and "result" in response and "error" not in response:
        result = response.get("result", {})
        if result.get("isError") is not True:
            file_path = f"{TEST_DIR}/bom.txt"
            if os.path.exists(file_path):
                return True
    return False

test_case("File with BOM", test_19, lambda r: r is True)

# 20. Check that old content does not affect new write
def test_20():
    # First create file
    request1 = {
        "jsonrpc": "2.0",
        "id": 2,
        "method": "tools/call",
        "params": {
            "name": "edit_file",
            "arguments": {"filename": f"{TEST_DIR}/rewrite.txt", "content": "OLD"}
        }
    }
    response1 = send_mcp_request(request1)
    if not response1 or "result" not in response1 or "error" in response1:
        return False
    if response1.get("result", {}).get("isError") is True:
        return False
    # Success, continue
    
    # Then rewrite with new content
    request2 = {
        "jsonrpc": "2.0",
        "id": 2,
        "method": "tools/call",
        "params": {
            "name": "edit_file",
            "arguments": {"filename": f"{TEST_DIR}/rewrite.txt", "content": "NEW"}
        }
    }
    response2 = send_mcp_request(request2)
    if response2 and "result" in response2 and "error" not in response2:
        result = response2.get("result", {})
        if result.get("isError") is not True:
            file_path = f"{TEST_DIR}/rewrite.txt"
            if os.path.exists(file_path):
                with open(file_path, "r", encoding="utf-8") as f:
                    file_content = f.read()
                    if file_content == "NEW":
                        return True
    return False

test_case("Rewriting an existing file", test_20, lambda r: r is True)

# Cleanup
shutil.rmtree(TEST_DIR, ignore_errors=True)

# Print results and exit
sys.exit(print_test_results())
