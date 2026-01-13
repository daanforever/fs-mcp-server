#!/bin/bash

# Run all test scripts for MCP File Edit Server
# This script executes all test scripts in the tests directory and provides a summary

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Change to project root
cd "$PROJECT_ROOT"

# Check if mcp-file-edit binary exists, build if not
if [ ! -f "./mcp-file-edit" ]; then
    echo -e "${YELLOW}Binary mcp-file-edit not found. Building...${NC}"
    if [ ! -f "./go.mod" ]; then
        echo -e "${RED}Error: go.mod not found. Are you in the correct directory?${NC}"
        exit 1
    fi
    go mod tidy
    go build -o mcp-file-edit ./src
    if [ ! -f "./mcp-file-edit" ]; then
        echo -e "${RED}Error: Failed to build mcp-file-edit${NC}"
        exit 1
    fi
    echo -e "${GREEN}Build successful!${NC}"
    echo ""
fi

# Make sure binary is executable
chmod +x ./mcp-file-edit

# Track results
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0
FAILED_SCRIPT_NAMES=()

# Find all test scripts (excluding helper.sh and this script)
SHELL_TEST_SCRIPTS=(
    "test_example.sh"
    "test_exec.sh"
    "test_error_arguments.sh"
    "test_notifications.sh"
    "test_debug.sh"
)

PYTHON_TEST_SCRIPTS=(
    "test_read_file.py"
    "test_read_file_params.py"
    "test_write_file.py"
    "test_view.py"
    "test_list_files.py"
    "edge_cases_test.py"
)

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  MCP File Edit Server - Test Suite${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""
echo -e "Running all test scripts..."
echo ""

# Function to run a test script
run_test() {
    local test_script="$1"
    local test_type="$2"  # "shell" or "python"
    local test_path="$SCRIPT_DIR/$test_script"
    
    # Check if script exists
    if [ ! -f "$test_path" ]; then
        echo -e "${YELLOW}Warning: Test script $test_script not found, skipping...${NC}"
        return 2
    fi
    
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    
    echo -e "${BLUE}----------------------------------------${NC}"
    echo -e "${BLUE}Running: $test_script (${test_type})${NC}"
    echo -e "${BLUE}----------------------------------------${NC}"
    
    # Run the test script and capture exit code
    set +e  # Don't exit on error for individual tests
    if [ "$test_type" = "python" ]; then
        # Run Python test
        if python3 "$test_path"; then
            echo -e "${GREEN}✓ $test_script PASSED${NC}"
            PASSED_TESTS=$((PASSED_TESTS + 1))
            result=0
        else
            exit_code=$?
            echo -e "${RED}✗ $test_script FAILED (exit code: $exit_code)${NC}"
            FAILED_TESTS=$((FAILED_TESTS + 1))
            FAILED_SCRIPT_NAMES+=("$test_script")
            result=1
        fi
    else
        # Run shell test
        # Make sure script is executable
        chmod +x "$test_path"
        if "$test_path"; then
            echo -e "${GREEN}✓ $test_script PASSED${NC}"
            PASSED_TESTS=$((PASSED_TESTS + 1))
            result=0
        else
            exit_code=$?
            echo -e "${RED}✗ $test_script FAILED (exit code: $exit_code)${NC}"
            FAILED_TESTS=$((FAILED_TESTS + 1))
            FAILED_SCRIPT_NAMES+=("$test_script")
            result=1
        fi
    fi
    set -e  # Re-enable exit on error
    
    echo ""
    return $result
}

# Run shell test scripts
for test_script in "${SHELL_TEST_SCRIPTS[@]}"; do
    run_test "$test_script" "shell"
done

# Run Python test scripts
for test_script in "${PYTHON_TEST_SCRIPTS[@]}"; do
    run_test "$test_script" "python"
done

# Cleanup temporary directories if they exist
if [ -d "$PROJECT_ROOT/tmp" ]; then
    echo -e "${YELLOW}Cleaning up temporary test directories...${NC}"
    rm -rf "$PROJECT_ROOT/tmp"
fi

# Print summary
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  Test Summary${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""
echo -e "Total test scripts: ${TOTAL_TESTS}"
echo -e "${GREEN}Passed: ${PASSED_TESTS}${NC}"
if [ $FAILED_TESTS -gt 0 ]; then
    echo -e "${RED}Failed: ${FAILED_TESTS}${NC}"
    echo ""
    echo -e "${RED}Failed test scripts:${NC}"
    for failed_script in "${FAILED_SCRIPT_NAMES[@]}"; do
        echo -e "${RED}  - $failed_script${NC}"
    done
else
    echo -e "${GREEN}Failed: ${FAILED_TESTS}${NC}"
fi
echo ""

# Exit with appropriate code
if [ $FAILED_TESTS -eq 0 ]; then
    echo -e "${GREEN}All tests passed! ✓${NC}"
    exit 0
else
    echo -e "${RED}Some tests failed. Please review the output above.${NC}"
    exit 1
fi
