package main

import (
	"context"
	"log/slog"
	"os/exec"
)

var (
	debugMode     bool
	logger        *slog.Logger
	activeCommands = &commandTracker{
		commands: make(map[*exec.Cmd]context.CancelFunc),
	}
)
