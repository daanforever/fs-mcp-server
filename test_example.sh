#!/bin/bash

# Пример использования MCP сервера

echo "=== Тестирование MCP File Edit Server ==="
echo ""

# 1. Инициализация
echo "1. Инициализация сервера:"
echo '{"method": "initialize", "params": {}}' | ./mcp-file-edit | jq .
echo ""

# 2. Создание файла
echo "2. Создание файла example.go:"
echo '{"method": "tools/call", "params": {"name": "edit_file", "arguments": {"filename": "example.go", "content": "package main\n\nfunc main() {\n\tprintln(\"Hello, MCP!\")\n}\n"}}}' | ./mcp-file-edit | jq .
echo ""

# 3. Чтение файла
echo "3. Чтение файла example.go:"
echo '{"method": "tools/call", "params": {"name": "read_file", "arguments": {"filename": "example.go"}}}' | ./mcp-file-edit | jq .
echo ""

# 4. Создание файла в поддиректории
echo "4. Создание файла в поддиректории:"
echo '{"method": "tools/call", "params": {"name": "edit_file", "arguments": {"filename": "notes/readme.txt", "content": "Это файл в поддиректории."}}}' | ./mcp-file-edit | jq .
echo ""

# Проверка созданных файлов
echo "=== Проверка файлов ==="
ls -la example.go notes/readme.txt 2>/dev/null && cat example.go && echo "" && cat notes/readme.txt
