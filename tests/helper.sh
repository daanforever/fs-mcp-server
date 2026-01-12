#!/bin/bash

# Common helper functions for MCP File Edit Server tests
# Source this file in test scripts: source "$(dirname "$0")/helper.sh"

# Default server path (can be overridden)
SERVER="${SERVER:-./mcp-file-edit}"

# Test counters (initialize if not set)
PASSED="${PASSED:-0}"
FAILED="${FAILED:-0}"

# Send MCP request with proper initialization
# Usage: send_mcp_request '{"jsonrpc":"2.0","id":1,"method":"tools/call",...}'
send_mcp_request() {
    local request="$1"
    local timeout="${2:-5}"  # Default timeout 5 seconds
    
    (
        echo '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"test","version":"1.0.0"}}}'
        sleep 0.1
        echo '{"jsonrpc":"2.0","method":"notifications/initialized","params":{}}'
        sleep 0.1
        echo "$request"
        sleep 1.0
    ) | timeout "$timeout" "$SERVER" 2>/dev/null | grep -v '"id":1' | tail -1
}

# Run a test case and track results
# Usage: test_case "Test name" "command_to_run" '[ "$result" == "expected" ]'
test_case() {
    local name="$1"
    local test_cmd="$2"
    local expected="$3"
    
    echo -n "  $name: "
    set +e
    result=$(eval "$test_cmd" 2>/dev/null)
    cmd_exit=$?
    set -e
    
    if [ $cmd_exit -ne 0 ] && [ $cmd_exit -ne 124 ]; then
        echo "FAIL (command error: $cmd_exit)"
        echo "    Result: $result"
        ((FAILED++))
        return
    fi
    
    if eval "$expected"; then
        echo "PASS"
        ((PASSED++))
    else
        echo "FAIL"
        echo "    Result: $result"
        ((FAILED++))
    fi
}

# Parse exec response - extract stdout
# Usage: parse_exec_stdout "$response"
parse_exec_stdout() {
    local response="$1"
    local text=$(echo "$response" | jq -r '.result.content[0].text')
    if echo "$text" | grep -q "^STDOUT:"; then
        echo "$text" | sed -n '/^STDOUT:$/,/^STDERR:\|^$/p' | sed '1d' | sed '/^STDERR:/d' | sed '/^$/d' | tr -d '\n'
    else
        echo ""
    fi
}

# Parse exec response - extract stderr
# Usage: parse_exec_stderr "$response"
parse_exec_stderr() {
    local response="$1"
    local text=$(echo "$response" | jq -r '.result.content[0].text')
    if echo "$text" | grep -q "^STDERR:"; then
        echo "$text" | sed -n '/^STDERR:$/,/^$/p' | sed '1d' | sed '/^$/d' | tr -d '\n'
    else
        echo ""
    fi
}

# Parse exec response - extract exit code
# Usage: parse_exec_exit_code "$response"
parse_exec_exit_code() {
    local response="$1"
    echo "$response" | jq -r '.result.content[0].text' | grep -oP 'Exit code: \K\d+'
}

# Parse exec response - extract status
# Usage: parse_exec_status "$response"
parse_exec_status() {
    local response="$1"
    echo "$response" | jq -r '.result.content[0].text' | grep -oP 'Status: \K\w+'
}

# Parse exec response - check if timed out
# Usage: parse_exec_timeout "$response"
parse_exec_timeout() {
    local response="$1"
    echo "$response" | jq -r '.result.content[0].text' | grep -q "timed out" && echo "true" || echo "false"
}

# Check if error response contains received_arguments
# Usage: check_error_has_arguments "test_name" "$response" "expected_arg"
check_error_has_arguments() {
    local test_name="$1"
    local response="$2"
    local expected_arg="$3"
    
    echo "Тест: $test_name"
    
    # Check for error.data.received_arguments field
    if echo "$response" | jq -e '.error.data.received_arguments' > /dev/null 2>&1; then
        # If expected arg is specified, check for it
        if [ -n "$expected_arg" ]; then
            if echo "$response" | jq -e ".error.data.received_arguments.$expected_arg" > /dev/null 2>&1; then
                echo "  ✓ PASS: Ошибка содержит received_arguments с $expected_arg"
                ((PASSED++))
            else
                echo "  ✗ FAIL: Ошибка не содержит $expected_arg в received_arguments"
                echo "  Ответ: $response"
                ((FAILED++))
            fi
        else
            echo "  ✓ PASS: Ошибка содержит received_arguments"
            ((PASSED++))
        fi
    else
        echo "  ✗ FAIL: Ошибка не содержит поле data.received_arguments"
        echo "  Ответ: $response"
        ((FAILED++))
    fi
    echo ""
}

# Simple test runner (for edge cases)
# Usage: run_test "Test name" '{"method":"tools/call",...}' '[[ "$result" == *"success"* ]]'
run_test() {
    local name="$1"
    local request="$2"
    local expected_check="$3"
    
    echo -n "Test: $name ... "
    result=$(echo "$request" | "$SERVER" 2>/dev/null)
    
    if eval "$expected_check"; then
        echo -e "\033[0;32mPASS\033[0m"
        ((PASSED++))
    else
        echo -e "\033[0;31mFAIL\033[0m"
        echo "  Request: $request"
        echo "  Result: $result"
        ((FAILED++))
    fi
}

# Print test results summary
# Usage: print_test_results
print_test_results() {
    echo ""
    echo "=== Результаты ==="
    echo "Пройдено: $PASSED"
    echo "Провалено: $FAILED"
    echo ""
    
    if [ $FAILED -eq 0 ]; then
        echo "Все тесты пройдены успешно!"
        return 0
    else
        echo "Некоторые тесты провалились."
        return 1
    fi
}
