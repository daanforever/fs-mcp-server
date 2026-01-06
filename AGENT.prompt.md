# AGENTS.prompt.md

Analyze this codebase and create or update an `AGENTS.md` file in the root directory. This file serves as a "brain dump" and a set of operational guidelines for future AI agents (like yourself) working on this specific Go project.

### Goal
Document everything an agent needs to know to work effectively in this repository—commands, architecture patterns, conventions, and common pitfalls.

### Discovery & Analysis Process
0. **Directory**: You are already in the working (project) directory.
1. **Initial Scan**: Explore the directory structure using `ls -R` or `tree -L 2`.
2. **Existing Rules**: Check for existing rule files (e.g., `.golangci.yml`, `Makefile`, `.cursorrules`, or `docs/`) and incorporate their essence.
3. **Tech Stack Confirmation**: 
    - Check `go.mod` for Go version and key dependencies (e.g., Gin, Echo, GORM, sqlx, Protobuf).
    - Identify the database (PostgreSQL, MongoDB, etc.) and migration tool (golang-migrate, pressly/goose).
4. **Pattern Recognition**: Read representative files in `cmd/`, `internal/`, and `pkg/` to understand the specific coding style.
5. **Refinement**: If `AGENTS.md` already exists, read it first and improve/update it based on current findings.

### Content to Include
*   **Essential Commands**: Document exact commands for local development. Use `make` targets if a `Makefile` exists, otherwise use standard `go` CLI (e.g., `go run ./cmd/app`, `go test ./...`, `go mod tidy`).
*   **Project Structure**: Explain the layout. Is it following the "Standard Go Project Layout" (`/cmd`, `/internal`, `/pkg`)? Is it a Clean Architecture, Hexagonal, or a simple flat structure?
*   **Concurrency & Context**: Document how `context.Context` is passed and how goroutines/channels are managed (e.g., use of `errgroup` or specific worker patterns).
*   **Error Handling**: Document the project's approach to errors (e.g., using `fmt.Errorf` with `%w`, custom error types, or specific library like `pkg/errors`).
*   **Testing Approach**: Document testing conventions (e.g., table-driven tests, use of `testify/assert`, `mockery` for mocks, or integration tests with `testcontainers`).
*   **Naming & Style**: Specific conventions observed (e.g., interface naming like `Getter`, receiver names, use of "Internal" vs "Public" packages).
*   **Tooling & Linting**: Configuration for `golangci-lint` and any code generation tools used (e.g., `sqlc`, `easyjson`, `stringer`).
*   **Gotchas**: Non-obvious patterns, pointer vs value receiver choices in the project, manual memory management (if any), or environment variable requirements.

### LLM-Friendly Formatting (Critical)
The content of `AGENTS.md` must be optimized for LLM consumption:
*   **Imperative Language**: Use direct instructions (e.g., "Use `internal/repository` for database logic" instead of "We usually put...").
*   **Token Efficiency**: Be concise. Use bullet points and clear headings. Avoid conversational "fluff."
*   **Hierarchical Structure**: Organize from "High-Level Architecture" to "Low-Level Implementation Details."
*   **Searchability**: Use clear keywords that an agent can quickly find via semantic search or grep.

### Strict Constraints
*   **Evidence-Based Only**: Only document what you actually observe in the codebase (check `go.mod` and file tree). Never invent commands or patterns that do not exist.
*   **No Placeholders**: If you cannot find information on a specific topic (e.g., deployment or CI/CD), omit that section rather than guessing.

### Output Format
Markdown with clear sections. The goal is to make a "README for AI" that allows a new agent to be productive within seconds of reading the file.
