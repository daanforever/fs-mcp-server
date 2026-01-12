#!/usr/bin/env python3
"""Test script for POC server using proper MCP protocol"""

import json
import subprocess
import sys
import time
import os

# Create test file
test_file = "test_poc_file.txt"
with open(test_file, "w") as f:
    f.write("Hello, World! This is a test file.\n")

# Start server
proc = subprocess.Popen(
    ["./poc_server"],
    stdin=subprocess.PIPE,
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE,
    text=True,
    bufsize=1
)

def send_request(req):
    """Send a request and read response"""
    req_json = json.dumps(req) + "\n"
    proc.stdin.write(req_json)
    proc.stdin.flush()
    time.sleep(0.2)
    response_line = proc.stdout.readline()
    if response_line:
        return json.loads(response_line.strip())
    return None

try:
    print("=== Testing POC Server ===\n")
    
    # Test 1: Initialize
    print("Test 1: Initialize request")
    init_req = {
        "jsonrpc": "2.0",
        "id": 1,
        "method": "initialize",
        "params": {
            "protocolVersion": "2024-11-05",
            "capabilities": {},
            "clientInfo": {"name": "test-client", "version": "1.0.0"}
        }
    }
    init_resp = send_request(init_req)
    print(f"Response: {json.dumps(init_resp, indent=2)}")
    print()
    
    # Test 2: Send initialized notification
    print("Test 2: Send initialized notification")
    notif = {
        "jsonrpc": "2.0",
        "method": "notifications/initialized",
        "params": {}
    }
    send_request(notif)
    print("Notification sent")
    print()
    
    # Test 3: Tools list
    print("Test 3: Tools list request")
    tools_req = {
        "jsonrpc": "2.0",
        "id": 2,
        "method": "tools/list",
        "params": {}
    }
    tools_resp = send_request(tools_req)
    print(f"Response: {json.dumps(tools_resp, indent=2)}")
    print()
    
    # Test 4: Read file with JSON object arguments
    print("Test 4: Read file with JSON object arguments")
    read_req = {
        "jsonrpc": "2.0",
        "id": 3,
        "method": "tools/call",
        "params": {
            "name": "read_file",
            "arguments": {
                "filename": test_file
            }
        }
    }
    read_resp = send_request(read_req)
    print(f"Response: {json.dumps(read_resp, indent=2)}")
    if read_resp and "result" in read_resp:
        if "content" in read_resp["result"]:
            print("✓ Content field found")
            if read_resp["result"]["content"]:
                content_item = read_resp["result"]["content"][0]
                if "type" in content_item and content_item["type"] == "text":
                    print("✓ Text content type found")
                    if "text" in content_item:
                        print(f"✓ Text content: {content_item['text'][:50]}...")
        else:
            print("✗ Content field NOT found")
    elif read_resp and "error" in read_resp:
        print(f"✗ Error: {read_resp['error']}")
    print()
    
    # Test 5: Read file with JSON string arguments
    print("Test 5: Read file with JSON string arguments (compatibility)")
    read_str_req = {
        "jsonrpc": "2.0",
        "id": 4,
        "method": "tools/call",
        "params": {
            "name": "read_file",
            "arguments": json.dumps({"filename": test_file})
        }
    }
    read_str_resp = send_request(read_str_req)
    print(f"Response: {json.dumps(read_str_resp, indent=2)}")
    if read_str_resp and "error" in read_str_resp:
        print("⚠ Error found (JSON string arguments may not be supported)")
    elif read_str_resp and "result" in read_str_resp:
        if "content" in read_str_resp["result"]:
            print("✓ JSON string arguments supported")
        else:
            print("⚠ Response received but no content field")
    print()

finally:
    # Cleanup
    proc.terminate()
    proc.wait()
    if os.path.exists(test_file):
        os.remove(test_file)
    
    print("=== Tests Complete ===")
