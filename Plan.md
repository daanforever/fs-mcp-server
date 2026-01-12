---
name: Add exec tool
overview: Add a new "exec" tool to the MCP server that executes shell commands in a specified or current working directory, returning stdout, stderr, and exit code separately. Commands are gracefully terminated with SIGTERM when the server shuts down or connection is lost.
todos:
  - id: add_import
    content: Add bytes, os/exec, context, time, os/signal, sync, and syscall imports to main.go
    status: completed
  - id: add_tracker
    content: Create commandTracker struct and global activeCommands variable for tracking running commands
    status: completed
  - id: add_struct
    content: Create ExecRequest struct with Command, optional Timeout, and optional WorkDir fields
    status: completed
  - id: update_main
    content: Update main function to add signal handling, context cancellation, and call cleanupCommands on EOF
    status: completed
  - id: add_tool_def
    content: Add 'exec' tool definition to tools/list handler
    status: completed
  - id: add_handler
    content: Add 'exec' case to tools/call switch statement
    status: completed
  - id: implement_function
    content: Implement execCommand function with timeout support, stdout/stderr/exit_code capture, and command tracking (register after Start succeeds)
    status: completed
  - id: implement_cleanup
    content: Implement cleanupCommands function with race-condition-free map copying and proper process state checks
    status: completed
---

## Status

**Implementation Status**: ✅ **COMPLETE**

All planned features for the "exec" tool have been successfully implemented and verified:

### Completed Components

1. **Imports** ✅ - All required packages imported:
   - `bytes`, `context`, `os/exec`, `os/signal`, `sync`, `syscall`, `time`

2. **Command Tracking** ✅ - `commandTracker` struct and `activeCommands` global variable implemented with thread-safe mutex protection

3. **Request Struct** ✅ - `ExecRequest` struct with:
   - `Command` (string, required)
   - `Timeout` (*int, optional, default: 300 seconds)
   - `WorkDir` (*string, optional, default: current working directory)

4. **Main Function Updates** ✅ - Signal handling and graceful shutdown:
   - Root context with cancellation
   - SIGTERM and SIGINT signal handlers
   - `cleanupCommands()` called on EOF and shutdown signals
   - Context-aware main loop

5. **Tool Definition** ✅ - "exec" tool registered in `tools/list` handler with:
   - Proper description
   - Complete input schema with all parameters
   - Required/optional field specifications

6. **Tool Handler** ✅ - "exec" case added to `tools/call` switch statement with:
   - Argument parsing and validation
   - Error handling with detailed error messages
   - Integration with `execCommand` function

7. **execCommand Function** ✅ - Fully implemented with:
   - Timeout support (default: 300 seconds, configurable)
   - Separate stdout/stderr capture using `bytes.Buffer`
   - Exit code extraction and reporting
   - Command registration after successful `Start()`
   - Automatic unregistration on completion (defer)
   - Timeout detection and error reporting
   - Work directory validation
   - Status reporting ("success" or "failed" based on exit code)

8. **cleanupCommands Function** ✅ - Graceful shutdown implementation:
   - Race-condition-free map copying (lock-protected)
   - Context cancellation for all active commands
   - SIGTERM signal to running processes
   - 5-second grace period for termination
   - Force kill (SIGKILL) after grace period
   - Proper process state checks (only signal if ProcessState is nil)

### Verification Results

- ✅ All imports present and correct
- ✅ All structs and types defined
- ✅ Signal handling properly integrated
- ✅ Tool definition matches specification
- ✅ Handler correctly routes to implementation
- ✅ Function implements all required features
- ✅ Cleanup function handles race conditions safely
- ✅ Code follows Go best practices and error handling patterns

### Ready for Testing

The implementation is complete and ready for integration testing. All planned functionality has been verified against the implementation plan.

---

## Implementation Plan

Add a new "exec" tool to the MCP file edit server that executes shell commands in a specified or current working directory.

### Changes to `main.go`

1. **Add imports**: Add `bytes`, `os/exec`, `context`, `time`, `os/signal`, `sync`, and `syscall` packages for command execution, timeout, and signal handling
   ```go
   import (
       ...
       "bytes"
       "context"
       "os/exec"
       "os/signal"
       "sync"
       "syscall"
       "time"
   )
   ```

2. **Add global state**: Add a struct to track running commands for graceful shutdown
   ```go
   type commandTracker struct {
       mu       sync.Mutex
       commands map[*exec.Cmd]context.CancelFunc
   }
   
   var activeCommands = &commandTracker{
       commands: make(map[*exec.Cmd]context.CancelFunc),
   }
   ```

3. **Add request struct**: Create `ExecRequest` struct after `ReadFileRequest`
   ```go
   type ExecRequest struct {
       Command string  `json:"command"`
       Timeout *int    `json:"timeout,omitempty"` // Timeout in seconds, default: 300 (5 minutes)
       WorkDir *string `json:"work_dir,omitempty"` // Working directory for command execution (default: current working directory)
   }
   ```

4. **Update main function**: Modify the main function to add signal handling and graceful shutdown

   - Create a root context: `ctx, cancel := context.WithCancel(context.Background())`
   - Set up signal channel: `sigChan := make(chan os.Signal, 1)` and register SIGTERM, SIGINT
   - Start goroutine to handle signals: when signal received, call `cancel()` and `cleanupCommands()`
   - Modify the main loop to check context: `select { case <-ctx.Done(): cleanupCommands(); return default: ... }`
   - When `io.EOF` is detected (line 54), call `cleanupCommands()` before returning
   - Use a channel or context to break out of the loop on shutdown

5. **Add tool definition**: Add "exec" tool to the `tools/list` handler (around line 160, after `read_file` tool)

   - Name: "exec"
   - Description: "Execute a shell command in a specified or current working directory"
   - Parameters:
     - `command` (string, required): The shell command to execute
     - `timeout` (integer, optional): Timeout in seconds (default: 300, i.e., 5 minutes)
     - `work_dir` (string, optional): Working directory for command execution (default: current working directory)

6. **Add tool handler**: Add case for "exec" in the `tools/call` switch statement (around line 236, after `read_file` case)

   - Parse `ExecRequest` from arguments
   - Call `execCommand` function
   - Return result or error

7. **Implement `execCommand` function**: Create new function after `readFile` (around line 439)

   - Determine timeout: Use `args.Timeout` if provided, otherwise default to 300 seconds (5 minutes)
   - Create context with timeout: `ctx, cancel := context.WithTimeout(context.Background(), time.Duration(timeout)*time.Second)`
   - Use `exec.CommandContext(ctx, "bash", "-c", args.Command)` to execute the command with timeout
   - Set working directory: If `args.WorkDir` is provided, use `cmd.Dir = *args.WorkDir`, otherwise default to current working directory (cwd) - don't set `cmd.Dir` in this case to use the process's current working directory
   - Capture stdout and stderr separately using `cmd.StdoutPipe()` and `cmd.StderrPipe()`
   - Start the command: Call `cmd.Start()` and check for errors
   - Register command with tracker: Only after `cmd.Start()` succeeds, add `cmd` and `cancel` to `activeCommands` (use defer to unregister)
   - Wait for command completion: Call `cmd.Wait()` to wait for the process to finish
   - Unregister command: Remove from `activeCommands` when done (use defer to ensure cleanup even on errors)
   - Handle timeout: If context deadline exceeded, return error indicating timeout
   - Return response with:
     - `stdout`: captured stdout as string
     - `stderr`: captured stderr as string
     - `exit_code`: exit code (even if non-zero, still return success response)
     - `status`: "success" or "failed" based on exit code
     - `timeout`: boolean indicating if command timed out (if applicable)

8. **Implement cleanup function**: Create function to send SIGTERM to all active commands
   ```go
   func cleanupCommands() {
       // Copy commands and cancels while holding lock to avoid race condition
       activeCommands.mu.Lock()
       cmds := make([]*exec.Cmd, 0, len(activeCommands.commands))
       cancels := make([]context.CancelFunc, 0, len(activeCommands.commands))
       for cmd, cancel := range activeCommands.commands {
           cmds = append(cmds, cmd)
           cancels = append(cancels, cancel)
       }
       activeCommands.mu.Unlock()
       
       // Cancel contexts and send SIGTERM
       for i, cmd := range cmds {
           cancels[i]() // Cancel context first
           if cmd.Process != nil && cmd.ProcessState == nil {
               cmd.Process.Signal(syscall.SIGTERM)
           }
       }
       
       // Wait for processes to terminate (with timeout)
       done := make(chan struct{})
       go func() {
           for _, cmd := range cmds {
               if cmd.Process != nil && cmd.ProcessState == nil {
                   cmd.Process.Wait()
               }
           }
           close(done)
       }()
       
       select {
       case <-done:
       case <-time.After(5 * time.Second):
           // Force kill if still running after 5 seconds
           for _, cmd := range cmds {
               if cmd.Process != nil && cmd.ProcessState == nil {
                   cmd.Process.Kill()
               }
           }
       }
   }
   ```


### Implementation Details

- Command execution: Use `exec.CommandContext(ctx, "bash", "-c", command)` to execute shell commands with timeout support
- Timeout handling: Default timeout is 300 seconds (5 minutes). If `timeout` parameter is provided, use that value in seconds
- Context cancellation: Use `context.WithTimeout` to automatically cancel command if timeout is exceeded
- Working directory: The `work_dir` parameter defaults to the current working directory (cwd). If `work_dir` is provided, commands will execute in that directory. If not provided, `cmd.Dir` should not be set, allowing the command to use the process's current working directory. Validate that the directory exists before execution if `work_dir` is provided.
- Command tracking: All active commands are tracked in a thread-safe map. Commands are registered only after `cmd.Start()` succeeds, and unregistered when they complete (using defer to ensure cleanup even on errors).
- Graceful shutdown: 
  - Set up signal handlers for SIGTERM and SIGINT in main function using `signal.Notify()`
  - Use a context that can be cancelled to break out of the main loop
  - Monitor stdin for EOF (connection lost) - when `io.EOF` is detected, call `cleanupCommands()` before returning
  - When shutdown signal received or connection lost, call `cleanupCommands()` which:
    - Copies the commands map while holding the lock to avoid race conditions
    - Cancels all command contexts
    - Sends SIGTERM to all active command processes (only if ProcessState is nil, meaning not already finished)
    - Waits up to 5 seconds for graceful termination
    - Force kills (SIGKILL) any processes still running after grace period
- Error handling: 
  - Validate work_dir exists and is a directory if provided, return error if invalid
  - Capture execution errors (command not found, etc.) and return as MCP errors
  - If timeout occurs, return error with code -32000 and message indicating timeout
- Exit codes: Always return success response, but include exit_code in result (0 = success, non-zero = failed)
- Output capture: Use `bytes.Buffer` to capture stdout and stderr separately
- Timeout detection: Check `context.DeadlineExceeded` error to detect timeout vs other execution errors
- Thread safety: Use `sync.Mutex` to protect the `activeCommands` map from concurrent access
