#!/bin/bash

# Test script for proof-of-concept SDK implementation with proper MCP protocol flow

set -e

echo "=== Testing POC Server with Proper MCP Protocol Flow ==="
echo ""

# Create a test file
TEST_FILE="test_poc_file.txt"
echo "Hello, World! This is a test file." > "$TEST_FILE"

# Create a named pipe for communication
FIFO_IN="/tmp/poc_in_$$"
FIFO_OUT="/tmp/poc_out_$$"
mkfifo "$FIFO_IN" "$FIFO_OUT"

# Start server in background
./poc_server < "$FIFO_IN" > "$FIFO_OUT" 2>&1 &
POC_PID=$!

# Function to send request and get response
send_request() {
    local request="$1"
    echo "$request" > "$FIFO_IN"
    sleep 0.5
    if [ -s "$FIFO_OUT" ]; then
        head -1 "$FIFO_OUT"
    fi
}

# Test 1: Initialize request
echo "Test 1: Initialize request"
RESPONSE=$(send_request '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"test-client","version":"1.0.0"}}}')
echo "Response: $RESPONSE"
echo ""

# Test 2: Send initialized notification (required by MCP protocol)
echo "Test 2: Send initialized notification"
echo '{"jsonrpc":"2.0","method":"notifications/initialized","params":{}}' > "$FIFO_IN"
sleep 0.5
echo "Notification sent"
echo ""

# Test 3: Tools list request
echo "Test 3: Tools list request"
RESPONSE=$(send_request '{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}')
echo "Response: $RESPONSE"
echo ""

# Test 4: Read file with JSON object arguments
echo "Test 4: Read file with JSON object arguments"
RESPONSE=$(send_request "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"tools/call\",\"params\":{\"name\":\"read_file\",\"arguments\":{\"filename\":\"$TEST_FILE\"}}}")
echo "Response: $RESPONSE"
echo "Checking for content field..."
if echo "$RESPONSE" | grep -q '"content"'; then
    echo "✓ Content field found"
    if echo "$RESPONSE" | grep -q '"type".*"text"'; then
        echo "✓ Text content type found"
    fi
else
    echo "✗ Content field NOT found"
fi
echo ""

# Test 5: Read file with JSON string arguments (compatibility test)
echo "Test 5: Read file with JSON string arguments (compatibility test)"
RESPONSE=$(send_request "{\"jsonrpc\":\"2.0\",\"id\":4,\"method\":\"tools/call\",\"params\":{\"name\":\"read_file\",\"arguments\":\"{\\\"filename\\\":\\\"$TEST_FILE\\\"}\"}}")
echo "Response: $RESPONSE"
echo "Checking for content field..."
if echo "$RESPONSE" | grep -q '"content"'; then
    echo "✓ Content field found"
else
    echo "✗ Content field NOT found"
fi
echo "Checking for error..."
if echo "$RESPONSE" | grep -q '"error"'; then
    echo "⚠ Error found (may indicate JSON string arguments not supported)"
else
    echo "✓ No error (JSON string arguments supported)"
fi
echo ""

# Cleanup
kill $POC_PID 2>/dev/null || true
wait $POC_PID 2>/dev/null || true
rm -f "$TEST_FILE" "$FIFO_IN" "$FIFO_OUT"

echo "=== Tests Complete ==="
