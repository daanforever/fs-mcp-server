#!/bin/bash

# Execute all test scripts for the MCP File Edit Server.
# This script iterates through all test files in the 'tests' directory, runs them,
# and provides a comprehensive summary of the results.

# Define color codes for terminal output for better readability
RED='\033[0;31m'      # Red for failures
GREEN='\033[0;32m'    # Green for successes
YELLOW='\033[1;33m'   # Yellow for warnings or building information
BLUE='\033[0;34m'     # Blue for general information and headers
NC='\033[0m'          # No Color - resets terminal color to default

# Determine the directory of the current script and the project root.
# SCRIPT_DIR will be the directory where 'run_all_tests.sh' is located.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# PROJECT_ROOT will be the parent directory of SCRIPT_DIR, assuming the 'tests' folder is at the project root.
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../" && pwd)"

# Navigate to the project's root directory to ensure all commands (like 'go build') are executed from the correct context.
cd "$PROJECT_ROOT"

# Check if the 'mcp-file-edit' binary already exists. If not, build it.
if [ ! -f "./mcp-file-edit" ]; then
    # Inform the user that the binary is not found and the build process is starting.
    echo -e "${YELLOW}Binary 'mcp-file-edit' not found. Building...${NC}"
    # Verify that 'go.mod' exists, which is essential for Go projects. If not, prompt the user and exit.
    if [ ! -f "./go.mod" ]; then
        echo -e "${RED}Error: 'go.mod' not found. Please ensure you are in the correct project directory.${NC}"
        exit 1
    fi
    # Update Go module dependencies.
    go mod tidy
    # Build the 'mcp-file-edit' binary, placing it in the project root.
    go build -o mcp-file-edit ./src
    # Verify if the build was successful. If the binary file doesn't exist after the build command, report an error and exit.
    if [ ! -f "./mcp-file-edit" ]; then
        echo -e "${RED}Error: Failed to build 'mcp-file-edit'. Check build output for details.${NC}"
        exit 1
    fi
    # Confirm that the build was successful.
    echo -e "${GREEN}Build successful!${NC}"
    echo "" # Add a blank line for spacing.
fi

# Ensure the binary is executable. This is important for running tests that might be in subdirectories or require direct execution.
chmod +x ./mcp-file-edit

# Initialize counters and arrays to track test results.
TOTAL_TESTS=0          # Total number of test scripts executed.
PASSED_TESTS=0         # Number of test scripts that passed.
FAILED_TESTS=0         # Number of test scripts that failed.
FAILED_SCRIPT_NAMES=() # An array to store the names of scripts that failed.

# Define lists of shell and Python test scripts to be executed.
# Excludes 'helper.sh' and this script itself to prevent self-execution or reliance on uncalled helpers.
SHELL_TEST_SCRIPTS=(
    "test_example.sh"         # Basic example tests.
    "test_exec.sh"            # Tests for the 'exec' command.
    "test_error_arguments.sh" # Tests for handling incorrect arguments.
    "test_notifications.sh"   # Tests for notification functionalities.
    "test_debug.sh"           # Tests for debug mode.
)

PYTHON_TEST_SCRIPTS=(
    "test_read_file.py"       # Tests for the 'read_file' command.
    "test_read_file_params.py"# Tests for 'read_file' with various parameters.
    "test_write_file.py"      # Tests for the 'write_file' command.
    "test_view.py"            # Tests for the 'view' command (alias for 'read_file').
    "test_list_files.py"      # Tests for the 'list_files' command.
    "edge_cases_test.py"      # Tests covering various edge cases.
)

# Print the main header for the test suite.
echo -e "${BLUE}=============================================${NC}"
echo -e "${BLUE}  MCP File Edit Server - Comprehensive Test Suite${NC}"
echo -e "${BLUE}=============================================${NC}"
echo "" # Blank line for spacing.
echo -e "Starting execution of all test scripts..."
echo "" # Blank line for spacing.

# Define a function to execute a single test script.
# Takes the script name and its type ('shell' or 'python') as arguments.
run_test() {
    local test_script="$1" # The name of the test script file.
    local test_type="$2"   # The type of the script (e.g., 'shell', 'python').
    # Construct the full path to the test script. Assumes test scripts are in the same directory as run_all_tests.sh
    local test_path="$SCRIPT_DIR/$test_script"

    # Check if the test script file actually exists. If not, print a warning and skip it.
    if [ ! -f "$test_path" ]; then
        echo -e "${YELLOW}Warning: Test script '$test_script' not found at '$test_path'. Skipping...${NC}"
        # Return a non-zero status to indicate it was skipped, not passed or failed in execution terms.
        return 2
    fi

    # Increment the total test count.
    TOTAL_TESTS=$((TOTAL_TESTS + 1))

    # Print a separator and header for each test script being run.
    echo -e "${BLUE}---------------------------------------------${NC}"
    echo -e "${BLUE}Running: '$test_script' (${test_type})${NC}"
    echo -e "${BLUE}---------------------------------------------${NC}"

    # Temporarily disable exit-on-error to allow individual tests to fail without stopping the whole script.
    set +e
    local script_passed=false # Flag to check if the current script passed.

    # Execute the test script based on its type.
    if [ "$test_type" = "python" ]; then
        # Execute the Python test script using 'python3'.
        if python3 "$test_path"; then
            script_passed=true # Mark as passed.
        fi
    else
        # Make sure the shell script is executable before running.
        chmod +x "$test_path"
        # Execute the shell test script.
        if "$test_path"; then
            script_passed=true # Mark as passed.
        fi
    fi
    
    # Capture the exit code of the executed script.
    local exit_code=$?
    # Re-enable exit-on-error.
    set -e

    # Check the result and update counters.
    if $script_passed; then
        echo -e "${GREEN}✓ '$test_script' PASSED${NC}"
        PASSED_TESTS=$((PASSED_TESTS + 1))
        return 0 # Return success status.
    else
        # Report failure, including the exit code if available.
        echo -e "${RED}✗ '$test_script' FAILED (exit code: $exit_code)${NC}"
        FAILED_TESTS=$((FAILED_TESTS + 1))
        # Add the failed script name to the list for summary.
        FAILED_SCRIPT_NAMES+=("$test_script")
        return 1 # Return failure status.
    fi
}

# --- Execute Shell Tests ---
echo -e "${YELLOW}--- Running Shell Tests ---${NC}"
for test_script in "${SHELL_TEST_SCRIPTS[@]}"; do
    run_test "$test_script" "shell"
done
echo "" # Blank line for spacing after shell tests.

# --- Execute Python Tests ---
echo -e "${YELLOW}--- Running Python Tests ---${NC}"
for test_script in "${PYTHON_TEST_SCRIPTS[@]}"; do
    run_test "$test_script" "python"
done
echo "" # Blank line for spacing after Python tests.

# --- Cleanup ---
# Remove any temporary directories created during testing, if they exist.
if [ -d "$PROJECT_ROOT/tmp" ]; then
    echo -e "${YELLOW}Cleaning up temporary test directories ('$PROJECT_ROOT/tmp')...${NC}"
    rm -rf "$PROJECT_ROOT/tmp"
fi

# --- Test Summary ---
echo -e "${BLUE}=============================================${NC}"
echo -e "${BLUE}          Overall Test Summary${NC}"
echo -e "${BLUE}=============================================${NC}"
echo "" # Blank line.

# Display the total number of tests executed.
echo -e "Total test scripts executed: ${TOTAL_TESTS}"
# Display the number of passed tests with green color.
echo -e "${GREEN}Passed: ${PASSED_TESTS}${NC}"

# If there were any failures, display the count in red and list the failed scripts.
if [ $FAILED_TESTS -gt 0 ]; then
    echo -e "${RED}Failed: ${FAILED_TESTS}${NC}"
    echo "" # Blank line.
    echo -e "${RED}Details of failed test scripts:${NC}"
    # Iterate through the list of failed script names and print each one.
    for failed_script in "${FAILED_SCRIPT_NAMES[@]}"; do
        echo -e "${RED}  - '$failed_script'${NC}"
    done
else
    # If no tests failed, display the count (which should be 0) in green.
    echo -e "${GREEN}Failed: ${FAILED_TESTS}${NC}"
fi
echo "" # Blank line.

# --- Exit Status ---
# Determine the final exit code for the entire test suite.
if [ $FAILED_TESTS -eq 0 ]; then
    # If all tests passed, print a success message and exit with code 0.
    echo -e "${GREEN}All tests completed successfully! ✓${NC}"
    exit 0
else
    # If any tests failed, print a failure message and exit with code 1.
    echo -e "${RED}Test suite completed with failures. Please review the output above.${NC}"
    exit 1
fi
