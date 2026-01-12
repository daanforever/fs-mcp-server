#!/bin/bash

# Notification handling test according to JSON-RPC 2.0
# Notifications (messages without "id" field) should be ignored without response

SERVER="./mcp-file-edit"
TEMP_OUTPUT="/tmp/mcp_test_output.json"

echo "=== Notification handling tests ==="
echo ""

# Test 1: Check that notification is ignored
echo -n "1. Notification is ignored (no response): "
(
    echo '{"jsonrpc":"2.0","method":"notifications/initialized"}'
) | $SERVER > "$TEMP_OUTPUT" 2>&1

if [ ! -s "$TEMP_OUTPUT" ]; then
    echo "PASS"
else
    echo "FAIL - received response to notification:"
    cat "$TEMP_OUTPUT"
fi

# Test 2: Request with id gets response
echo -n "2. Request with id gets response: "
(
    echo '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"test","version":"1.0.0"}}}'
) | $SERVER > "$TEMP_OUTPUT" 2>&1

if grep -q '"id":1' "$TEMP_OUTPUT" && grep -q '"result"' "$TEMP_OUTPUT"; then
    echo "PASS"
else
    echo "FAIL - no response to request:"
    cat "$TEMP_OUTPUT"
fi

# Test 3: Sequence initialize -> notification -> tools/list
echo -n "3. Request sequence (initialize -> notification -> tools/list): "
(
    echo '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"crush","version":"0.31.0"}}}'
    echo '{"jsonrpc":"2.0","method":"notifications/initialized"}'
    echo '{"jsonrpc":"2.0","id":2,"method":"tools/list"}'
) | $SERVER > "$TEMP_OUTPUT" 2>&1

# Should be exactly 2 responses (for id:1 and id:2), no errors
response_count=$(grep -c '"id"' "$TEMP_OUTPUT" 2>/dev/null | head -1 || echo "0")
error_count=$(grep -c '"error"' "$TEMP_OUTPUT" 2>/dev/null | head -1 || echo "0")

# Remove possible spaces and line breaks
response_count=$(echo "$response_count" | tr -d '[:space:]')
error_count=$(echo "$error_count" | tr -d '[:space:]')

if [ "$response_count" = "2" ] && [ "$error_count" = "0" ]; then
    echo "PASS"
else
    echo "FAIL - expected 2 responses without errors, got responses: $response_count, errors: $error_count"
    echo "Output:"
    cat "$TEMP_OUTPUT"
fi

# Test 4: Multiple notifications in a row
echo -n "4. Multiple notifications are ignored: "
(
    echo '{"jsonrpc":"2.0","method":"notifications/initialized"}'
    echo '{"jsonrpc":"2.0","method":"notifications/custom"}'
    echo '{"jsonrpc":"2.0","method":"notifications/another"}'
) | $SERVER > "$TEMP_OUTPUT" 2>&1

if [ ! -s "$TEMP_OUTPUT" ]; then
    echo "PASS"
else
    echo "FAIL - received responses to notifications:"
    cat "$TEMP_OUTPUT"
fi

# Test 5: Mixed sequence
echo -n "5. Mixed sequence (requests and notifications): "
(
    echo '{"jsonrpc":"2.0","id":1,"method":"tools/list"}'
    echo '{"jsonrpc":"2.0","method":"notifications/initialized"}'
    echo '{"jsonrpc":"2.0","id":2,"method":"tools/list"}'
    echo '{"jsonrpc":"2.0","method":"notifications/custom"}'
    echo '{"jsonrpc":"2.0","id":3,"method":"tools/list"}'
) | $SERVER > "$TEMP_OUTPUT" 2>&1

response_count=$(grep -c '"id"' "$TEMP_OUTPUT" 2>/dev/null | head -1 || echo "0")
error_count=$(grep -c '"error"' "$TEMP_OUTPUT" 2>/dev/null | head -1 || echo "0")

# Remove possible spaces and line breaks
response_count=$(echo "$response_count" | tr -d '[:space:]')
error_count=$(echo "$error_count" | tr -d '[:space:]')

if [ "$response_count" = "3" ] && [ "$error_count" = "0" ]; then
    echo "PASS"
else
    echo "FAIL - expected 3 responses without errors, got responses: $response_count, errors: $error_count"
    echo "Output:"
    cat "$TEMP_OUTPUT"
fi

# Test 6: Notification with id: null (should also be ignored)
echo -n "6. Notification with id: null is ignored: "
(
    echo '{"jsonrpc":"2.0","id":null,"method":"notifications/initialized"}'
) | $SERVER > "$TEMP_OUTPUT" 2>&1

if [ ! -s "$TEMP_OUTPUT" ]; then
    echo "PASS"
else
    echo "FAIL - received response to notification with id:null:"
    cat "$TEMP_OUTPUT"
fi

# Test 7: Detailed format check (jsonrpc, id, result)
echo -n "7. Response format is correct (jsonrpc, id, result): "
(
    echo '{"jsonrpc":"2.0","id":100,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"test","version":"1.0.0"}}}'
) | $SERVER > "$TEMP_OUTPUT" 2>&1

if grep -q '"jsonrpc":"2.0"' "$TEMP_OUTPUT" && \
   grep -q '"id":100' "$TEMP_OUTPUT" && \
   grep -q '"result"' "$TEMP_OUTPUT" && \
   ! grep -q '"error"' "$TEMP_OUTPUT"; then
    echo "PASS"
else
    echo "FAIL - incorrect response format:"
    cat "$TEMP_OUTPUT"
fi

echo ""
rm -f "$TEMP_OUTPUT"
echo "Tests completed."
