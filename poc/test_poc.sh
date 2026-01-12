#!/bin/bash

# Test script for proof-of-concept SDK implementation

set -e

echo "=== Testing POC Server ==="
echo ""

# Create a test file
TEST_FILE="test_poc_file.txt"
echo "Hello, World! This is a test file." > "$TEST_FILE"

# Test 1: Initialize request
echo "Test 1: Initialize request"
echo '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"test-client","version":"1.0.0"}}}' | ./poc_server > /tmp/poc_init_response.json 2>&1 &
POC_PID=$!
sleep 1
kill $POC_PID 2>/dev/null || true
wait $POC_PID 2>/dev/null || true

if [ -f /tmp/poc_init_response.json ]; then
    echo "Response received:"
    cat /tmp/poc_init_response.json
    echo ""
else
    echo "No response received"
fi

# Test 2: Tools list request
echo ""
echo "Test 2: Tools list request"
echo '{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}' | ./poc_server > /tmp/poc_tools_response.json 2>&1 &
POC_PID=$!
sleep 1
kill $POC_PID 2>/dev/null || true
wait $POC_PID 2>/dev/null || true

if [ -f /tmp/poc_tools_response.json ]; then
    echo "Response received:"
    cat /tmp/poc_tools_response.json
    echo ""
else
    echo "No response received"
fi

# Test 3: Read file with JSON object arguments
echo ""
echo "Test 3: Read file with JSON object arguments"
echo "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"tools/call\",\"params\":{\"name\":\"read_file\",\"arguments\":{\"filename\":\"$TEST_FILE\"}}}" | ./poc_server > /tmp/poc_read_object_response.json 2>&1 &
POC_PID=$!
sleep 1
kill $POC_PID 2>/dev/null || true
wait $POC_PID 2>/dev/null || true

if [ -f /tmp/poc_read_object_response.json ]; then
    echo "Response received:"
    cat /tmp/poc_read_object_response.json
    echo ""
    echo "Checking for content field..."
    if grep -q '"content"' /tmp/poc_read_object_response.json; then
        echo "✓ Content field found"
    else
        echo "✗ Content field NOT found"
    fi
else
    echo "No response received"
fi

# Test 4: Read file with JSON string arguments (compatibility test)
echo ""
echo "Test 4: Read file with JSON string arguments (compatibility test)"
echo "{\"jsonrpc\":\"2.0\",\"id\":4,\"method\":\"tools/call\",\"params\":{\"name\":\"read_file\",\"arguments\":\"{\\\"filename\\\":\\\"$TEST_FILE\\\"}\"}}" | ./poc_server > /tmp/poc_read_string_response.json 2>&1 &
POC_PID=$!
sleep 1
kill $POC_PID 2>/dev/null || true
wait $POC_PID 2>/dev/null || true

if [ -f /tmp/poc_read_string_response.json ]; then
    echo "Response received:"
    cat /tmp/poc_read_string_response.json
    echo ""
    echo "Checking for content field..."
    if grep -q '"content"' /tmp/poc_read_string_response.json; then
        echo "✓ Content field found"
    else
        echo "✗ Content field NOT found"
    fi
    echo "Checking for error..."
    if grep -q '"error"' /tmp/poc_read_string_response.json; then
        echo "⚠ Error found (may indicate JSON string arguments not supported)"
    else
        echo "✓ No error (JSON string arguments supported)"
    fi
else
    echo "No response received"
fi

# Cleanup
rm -f "$TEST_FILE"
rm -f /tmp/poc_*_response.json

echo ""
echo "=== Tests Complete ==="
