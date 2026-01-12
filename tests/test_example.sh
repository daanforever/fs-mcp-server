#!/bin/bash

# Пример использования MCP сервера

# Source helper functions
source "$(dirname "$0")/helper.sh"

echo "=== Тестирование MCP File Edit Server ==="
echo ""

# 1. Инициализация
echo "1. Инициализация сервера:"
send_mcp_request '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}' | jq .
echo ""

# 2. Создание файла
echo "2. Создание файла example.go:"
send_mcp_request '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"edit_file","arguments":{"filename":"example.go","content":"package main\n\nfunc main() {\n\tprintln(\"Hello, MCP!\")\n}\n"}}}' | jq .
echo ""

# 3. Чтение файла
echo "3. Чтение файла example.go:"
send_mcp_request '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"read_file","arguments":{"filename":"example.go"}}}' | jq .
echo ""

# 4. Создание файла в поддиректории
echo "4. Создание файла в поддиректории:"
send_mcp_request '{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"edit_file","arguments":{"filename":"notes/readme.txt","content":"Это файл в поддиректории."}}}' | jq .
echo ""

# Проверка созданных файлов
echo "=== Проверка файлов ==="
ls -la example.go notes/readme.txt 2>/dev/null && cat example.go && echo "" && cat notes/readme.txt
