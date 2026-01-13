#!/bin/bash

# Tests for the exec function
# Checks command execution, timeouts, working directories, error handling

# Source helper functions
source "$(dirname "$0")/helper.sh"

TEST_DIR="tmp/test_exec_dir"
mkdir -p tmp
rm -rf $TEST_DIR
mkdir -p $TEST_DIR

PASSED=0
FAILED=0

# Override send_mcp_request to use longer timeout for exec tests
send_mcp_request() {
    local request="$1"
    local timeout="${2:-10}"  # Default timeout 10 seconds for exec tests
    
    (
        echo '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"test","version":"1.0.0"}}}'
        echo '{"jsonrpc":"2.0","method":"notifications/initialized","params":{}}'
        echo "$request"
        sleep 0.1
    ) | timeout "$timeout" "$SERVER" 2>/dev/null | tail -1
}

echo "=== Exec tool tests ==="
echo ""

echo "1. Basic command execution tests:"
echo ""

# 1.1 Simple command (echo)
test_case "1.1 Simple command (echo)" \
    "response=\$(send_mcp_request '{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"exec\",\"arguments\":{\"command\":\"echo hello\"}}}') && parse_exec_stdout \"\$response\"" \
    '[ "$result" = "hello" ]'

# 1.2 Command with stdout output
test_case "1.2 Stdout output" \
    "response=\$(send_mcp_request '{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"exec\",\"arguments\":{\"command\":\"echo -n test123\"}}}') && parse_exec_stdout \"\$response\"" \
    '[ "$result" == "test123" ]'

# 1.3 Command with stderr output
test_case "1.3 Stderr output" \
    "response=\$(send_mcp_request '{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"exec\",\"arguments\":{\"command\":\"echo error >&2\"}}}') && parse_exec_stderr \"\$response\"" \
    '[ "$result" == "error" ]'

# 1.4 Command with output to both streams
test_case "1.4 Stdout and stderr output" \
    "response=\$(send_mcp_request '{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"exec\",\"arguments\":{\"command\":\"echo out && echo err >&2\"}}}') && stdout=\$(parse_exec_stdout \"\$response\") && stderr=\$(parse_exec_stderr \"\$response\") && [ \"\$stdout\" == \"out\" ] && [ \"\$stderr\" == \"err\" ]" \
    '[ $? -eq 0 ]'

# 1.5 Exit code check (successful command)
test_case "1.5 Exit code of successful command" \
    "response=\$(send_mcp_request '{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"exec\",\"arguments\":{\"command\":\"true\"}}}') && parse_exec_exit_code \"\$response\"" \
    '[ "$result" == "0" ]'

# 1.6 Exit code check (failed command)
test_case "1.6 Exit code of failed command" \
    "response=\$(send_mcp_request '{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"exec\",\"arguments\":{\"command\":\"false\"}}}') && parse_exec_exit_code \"\$response\"" \
    '[ "$result" == "1" ]'

# 1.7 Status check (success)
test_case "1.7 Status of successful command" \
    "response=\$(send_mcp_request '{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"exec\",\"arguments\":{\"command\":\"true\"}}}') && parse_exec_status \"\$response\"" \
    '[ "$result" == "success" ]'

# 1.8 Status check (failed)
test_case "1.8 Status of failed command" \
    "response=\$(send_mcp_request '{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"exec\",\"arguments\":{\"command\":\"false\"}}}') && parse_exec_status \"\$response\"" \
    '[ "$result" == "failed" ]'

echo ""
echo "2. Working directory (work_dir) tests:"
echo ""

# 2.1 Execute command in the specified directory
test_case "2.1 Execute in specified directory" \
    "response=\$(send_mcp_request '{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"exec\",\"arguments\":{\"command\":\"pwd\",\"work_dir\":\"$TEST_DIR\"}}}') && result=\$(parse_exec_stdout \"\$response\" | xargs realpath) && [ \"\$result\" == \"\$(realpath $TEST_DIR)\" ]" \
    '[ $? -eq 0 ]'

# 2.2 Execute command without specifying work_dir (current directory)
test_case "2.2 Execute without work_dir" \
    "cwd=\$(pwd) && response=\$(send_mcp_request '{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"exec\",\"arguments\":{\"command\":\"pwd\"}}}') && result=\$(parse_exec_stdout \"\$response\" | xargs realpath) && [ \"\$result\" == \"\$(realpath \$cwd)\" ]" \
    '[ $? -eq 0 ]'

# 2.3 Create a file in the specified directory
test_case "2.3 Create file in work_dir" \
    "send_mcp_request '{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"exec\",\"arguments\":{\"command\":\"echo test > file.txt\",\"work_dir\":\"$TEST_DIR\"}}}' > /dev/null && [ -f $TEST_DIR/file.txt ] && [ \"\$(cat $TEST_DIR/file.txt)\" == \"test\" ]" \
    '[ $? -eq 0 ]'

# 2.4 Error: non-existent directory
test_case "2.4 Error: non-existent directory" \
    "send_mcp_request '{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"exec\",\"arguments\":{\"command\":\"pwd\",\"work_dir\":\"$TEST_DIR/nonexistent\"}}}' | jq -e '.result.isError == true or .error != null'" \
    '[ $? -eq 0 ]'

# 2.5 Error: work_dir is a file, not a directory
test_case "2.5 Error: work_dir is a file" \
    "echo test > $TEST_DIR/notadir && send_mcp_request '{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"exec\",\"arguments\":{\"command\":\"pwd\",\"work_dir\":\"$TEST_DIR/notadir\"}}}' | jq -e '.result.isError == true or .error != null'" \
    '[ $? -eq 0 ]'

echo ""
echo "3. Timeout tests:"
echo ""

# 3.1 Command completes before timeout
test_case "3.1 Command completes before timeout" \
    "response=\$(send_mcp_request '{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"exec\",\"arguments\":{\"command\":\"echo done\",\"timeout\":5}}}') && parse_exec_timeout \"\$response\" | grep -q false && parse_exec_stdout \"\$response\" | grep -q 'done'" \
    '[ $? -eq 0 ]'

# 3.2 Command exceeds timeout
test_case "3.2 Command exceeds timeout" \
    "send_mcp_request '{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"exec\",\"arguments\":{\"command\":\"sleep 2\",\"timeout\":1}}}' | jq -e '(.result.isError == true or .error != null) and ((.result.content[0].text // .error.message // \"\") | contains(\"timed out\"))'" \
    '[ $? -eq 0 ]'

# 3.3 Default timeout (300 seconds) - quick command should complete
test_case "3.3 Default timeout (quick command)" \
    "response=\$(send_mcp_request '{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"exec\",\"arguments\":{\"command\":\"echo quick\"}}}') && echo \"\$response\" | jq -e '.result != null' && parse_exec_timeout \"\$response\" | grep -q false" \
    '[ $? -eq 0 ]'

# 3.4 Very short timeout for a quick command
test_case "3.4 Very short timeout (command finishes)" \
    "response=\$(send_mcp_request '{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"exec\",\"arguments\":{\"command\":\"echo fast\",\"timeout\":1}}}') && echo \"\$response\" | jq -e '.result != null' && parse_exec_timeout \"\$response\" | grep -q false" \
    '[ $? -eq 0 ]'

echo ""
echo "4. Error handling tests:"
echo ""

# 4.1 Command not found
test_case "4.1 Command not found" \
    "send_mcp_request '{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"exec\",\"arguments\":{\"command\":\"nonexistent_command_xyz123\"}}}' | jq -e '.result.isError == true or .error != null'" \
    '[ $? -eq 0 ]'

# 4.2 Missing mandatory 'command' parameter
test_case "4.2 Missing 'command' parameter" \
    "send_mcp_request '{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"exec\",\"arguments\":{}}}' | jq -e '.result.isError == true or .error != null'" \
    '[ $? -eq 0 ]'

# 4.3 Invalid JSON in arguments
test_case "4.3 Invalid JSON in arguments" \
    "send_mcp_request '{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"exec\",\"arguments\":\"{invalid}\"}}' | jq -e '.result.isError == true or .error != null'" \
    '[ $? -eq 0 ]'

# 4.4 Command with syntax error
test_case "4.4 Command with syntax error" \
    "response=\$(send_mcp_request '{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"exec\",\"arguments\":{\"command\":\"if [\"}}}') && echo \"\$response\" | jq -e '.result != null' && [ \"\$(parse_exec_exit_code \"\$response\")\" != \"0\" ]" \
    '[ $? -eq 0 ]'

echo ""
echo "5. Edge case tests:"
echo ""

# 5.1 Empty command
test_case "5.1 Empty command" \
    "response=\$(send_mcp_request '{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"exec\",\"arguments\":{\"command\":\"\"}}}') && echo \"\$response\" | jq -e '.result != null' && [ \"\$(parse_exec_exit_code \"\$response\")\" == \"0\" ]" \
    '[ $? -eq 0 ]'

# 5.2 Command with spaces
test_case "5.2 Command with spaces" \
    "response=\$(send_mcp_request '{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"exec\",\"arguments\":{\"command\":\"echo   multiple   spaces\"}}}') && parse_exec_stdout \"\$response\"" \
    '[ "$result" == "multiple spaces" ]'

# 5.3 Command with newlines
test_case "5.3 Command with newlines" \
    "response=\$(send_mcp_request '{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"exec\",\"arguments\":{\"command\":\"printf \\\"line1\\\\nline2\\\"\"}}}') && stdout=\$(parse_exec_stdout \"\$response\") && [[ \"\$stdout\" == *\"line1\"* ]] && [[ \"\$stdout\" == *\"line2\"* ]]" \
    '[ $? -eq 0 ]'

# 5.4 Command with special characters
test_case "5.4 Command with special characters" \
    "send_mcp_request '{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"exec\",\"arguments\":{\"command\":\"echo test123\"}}}' | jq -e '.result != null'" \
    '[ $? -eq 0 ]'

# 5.5 Command with UTF-8 characters
test_case "5.5 Command with UTF-8 characters" \
    "response=\$(send_mcp_request '{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"exec\",\"arguments\":{\"command\":\"echo Привет 🌍\"}}}') && stdout=\$(parse_exec_stdout \"\$response\") && [[ \"\$stdout\" == *\"Привет\"* ]]" \
    '[ $? -eq 0 ]'

# 5.6 Long command
test_case "5.6 Long command" \
    "long_cmd=\"echo \$(seq 1 100 | tr '\n' ' ')\" && response=\$(send_mcp_request \"{\\\"jsonrpc\\\":\\\"2.0\\\",\\\"id\\\":2,\\\"method\\\":\\\"tools/call\\\",\\\"params\\\":{\\\"name\\\":\\\"exec\\\",\\\"arguments\\\":{\\\"command\\\":\\\"\$long_cmd\\\"}}}\") && echo \"\$response\" | jq -e '.result != null'" \
    '[ $? -eq 0 ]'

# 5.7 Command with environment variables
test_case "5.7 Command with environment variables" \
    "response=\$(send_mcp_request '{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"exec\",\"arguments\":{\"command\":\"echo \$HOME\"}}}') && stdout=\$(parse_exec_stdout \"\$response\") && [ -n \"\$stdout\" ]" \
    '[ $? -eq 0 ]'

# 5.8 Command with output redirection
test_case "5.8 Command with output redirection" \
    "send_mcp_request '{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"exec\",\"arguments\":{\"command\":\"echo redirect > '$TEST_DIR'/redirect.txt\"}}}' > /dev/null && [ -f $TEST_DIR/redirect.txt ] && [ \"\$(cat $TEST_DIR/redirect.txt)\" == \"redirect\" ]" \
    '[ $? -eq 0 ]'

# 5.9 Command with pipe
test_case "5.9 Command with pipe" \
    "response=\$(send_mcp_request '{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"exec\",\"arguments\":{\"command\":\"echo hello | tr a-z A-Z\"}}}') && parse_exec_stdout \"\$response\"" \
    '[ "$result" == "HELLO" ]'

# 5.10 Command with multiple commands (&&)
test_case "5.10 Command with &&" \
    "response=\$(send_mcp_request '{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"exec\",\"arguments\":{\"command\":\"echo first && echo second\"}}}') && stdout=\$(parse_exec_stdout \"\$response\") && [[ \"\$stdout\" == *\"first\"* ]] && [[ \"\$stdout\" == *\"second\"* ]]" \
    '[ $? -eq 0 ]'

# 5.11 Command with multiple commands (||)
test_case "5.11 Command with ||" \
    "response=\$(send_mcp_request '{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"exec\",\"arguments\":{\"command\":\"false || echo fallback\"}}}') && stdout=\$(parse_exec_stdout \"\$response\") && [ \"\$stdout\" == \"fallback\" ]" \
    '[ $? -eq 0 ]'

# 5.12 Command with exit code > 1
test_case "5.12 Exit code > 1" \
    "response=\$(send_mcp_request '{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"exec\",\"arguments\":{\"command\":\"exit 42\"}}}') && parse_exec_exit_code \"\$response\"" \
    '[ "$result" == "42" ]'

# 5.13 Command with negative timeout (should default or be handled as error)
test_case "5.13 Negative timeout" \
    "response=\$(send_mcp_request '{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"exec\",\"arguments\":{\"command\":\"echo test\",\"timeout\":-1}}}') && echo \"\$response\" | jq -e '.result != null or .error != null'" \
    '[ $? -eq 0 ]'

# 5.14 Command with zero timeout
test_case "5.14 Zero timeout" \
    "response=\$(send_mcp_request '{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"exec\",\"arguments\":{\"command\":\"echo quick\",\"timeout\":0}}}') && echo \"\$response\" | jq -e '.result != null or .error != null'" \
    '[ $? -eq 0 ]'

# 5.15 Command with very large timeout
test_case "5.15 Very large timeout" \
    "response=\$(send_mcp_request '{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"exec\",\"arguments\":{\"command\":\"echo test\",\"timeout\":999999}}}') && echo \"\$response\" | jq -e '.result != null' && parse_exec_timeout \"\$response\" | grep -q false" \
    '[ $? -eq 0 ]'

echo ""
echo "6. Response format tests:"
echo ""

# 6.1 Check for content in response
test_case "6.1 Content presence in response" \
    "response=\$(send_mcp_request '{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"exec\",\"arguments\":{\"command\":\"echo test\"}}}') && echo \"\$response\" | jq -e '.result.content != null and (.result.content | type) == \"array\" and .result.content[0].type == \"text\"'" \
    '[ $? -eq 0 ]'

# 6.2 Content format check (type and text)
test_case "6.2 Content format (type and text)" \
    "response=\$(send_mcp_request '{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"exec\",\"arguments\":{\"command\":\"echo test\"}}}') && echo \"\$response\" | jq -e '(.result.content[0].text | type) == \"string\"'" \
    '[ $? -eq 0 ]'

# Cleanup
rm -rf $TEST_DIR

# Print results and exit
print_test_results
exit $?
