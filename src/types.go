package main

import (
	"context"
	"os/exec"
	"sync"
)

type EditFileRequest struct {
	Filename  string  `json:"filename"`
	Content   *string `json:"content,omitempty"`
	OldString *string `json:"old_string,omitempty"`
	NewString *string `json:"new_string,omitempty"`
	// Backward compatibility
	OldText *string `json:"old_text,omitempty"`
	NewText *string `json:"new_text,omitempty"`
}

type ReadFileRequest struct {
	Filename    string  `json:"filename"`
	StartLine   *int    `json:"start_line,omitempty"`
	EndLine     *int    `json:"end_line,omitempty"`
	Encoding    *string `json:"encoding,omitempty"`
	LineNumbers *bool   `json:"line_numbers,omitempty"`
	SkipEmpty   *bool   `json:"skip_empty,omitempty"`
	MaxLines    *int    `json:"max_lines,omitempty"`
	Pattern     *string `json:"pattern,omitempty"`
}

type ExecRequest struct {
	Command string  `json:"command"`
	Timeout *int    `json:"timeout,omitempty"` // Default: 300 seconds
	WorkDir *string `json:"work_dir,omitempty"` // Working directory for command execution (default: current working directory)
}

type WriteFileRequest struct {
	Filename string `json:"filename"`
	Content  string `json:"content"`
}

type commandTracker struct {
	mu       sync.Mutex
	commands map[*exec.Cmd]context.CancelFunc
}
