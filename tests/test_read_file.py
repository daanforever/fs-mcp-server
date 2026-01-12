#!/usr/bin/env python3
"""Тесты для функции read_file
Проверяет обработку arguments как строки JSON и как объекта"""

import os
import shutil
import sys
from test_helper import send_mcp_request, test_case, print_test_results, PASSED, FAILED

TEST_DIR = "test_read_dir"

# Cleanup and setup
if os.path.exists(TEST_DIR):
    shutil.rmtree(TEST_DIR)
os.makedirs(TEST_DIR, exist_ok=True)

print("=== Тесты read_file ===")
print()

# Подготовка: создаем тестовые файлы
print("Подготовка тестового файла...")
with open(f"{TEST_DIR}/test.txt", "w") as f:
    f.write("Hello, World!")

with open(f"{TEST_DIR}/multiline.txt", "w") as f:
    f.write("Line 1\nLine 2\nLine 3")

with open(f"{TEST_DIR}/empty.txt", "w") as f:
    pass  # Empty file

with open(f"{TEST_DIR}/utf8.txt", "w", encoding="utf-8") as f:
    f.write("Привет 🌍")

print("1. Тесты с arguments как объектом (обычный формат):")
print()

# 1.1 Чтение обычного файла
def test_1_1():
    request = {
        "jsonrpc": "2.0",
        "id": 2,
        "method": "tools/call",
        "params": {
            "name": "read_file",
            "arguments": {"filename": f"{TEST_DIR}/test.txt"}
        }
    }
    response = send_mcp_request(request)
    if response and "result" in response and "content" in response["result"]:
        if response["result"]["content"] and len(response["result"]["content"]) > 0:
            return response["result"]["content"][0].get("text", "")
    return None

test_case("1.1 Чтение обычного файла", test_1_1, 
          lambda r: r == "Hello, World!")

# 1.2 Чтение многострочного файла
def test_1_2():
    request = {
        "jsonrpc": "2.0",
        "id": 2,
        "method": "tools/call",
        "params": {
            "name": "read_file",
            "arguments": {"filename": f"{TEST_DIR}/multiline.txt"}
        }
    }
    response = send_mcp_request(request)
    if response and "result" in response and "content" in response["result"]:
        if response["result"]["content"] and len(response["result"]["content"]) > 0:
            return response["result"]["content"][0].get("text", "")
    return None

test_case("1.2 Чтение многострочного файла", test_1_2,
          lambda r: r and "Line 1" in r and "Line 2" in r and "Line 3" in r)

# 1.3 Чтение пустого файла
def test_1_3():
    request = {
        "jsonrpc": "2.0",
        "id": 2,
        "method": "tools/call",
        "params": {
            "name": "read_file",
            "arguments": {"filename": f"{TEST_DIR}/empty.txt"}
        }
    }
    response = send_mcp_request(request)
    if response and "result" in response and "content" in response["result"]:
        if response["result"]["content"] and len(response["result"]["content"]) > 0:
            return response["result"]["content"][0].get("text", "")
    return None

test_case("1.3 Чтение пустого файла", test_1_3,
          lambda r: r == "")

# 1.4 Чтение файла с UTF-8
def test_1_4():
    request = {
        "jsonrpc": "2.0",
        "id": 2,
        "method": "tools/call",
        "params": {
            "name": "read_file",
            "arguments": {"filename": f"{TEST_DIR}/utf8.txt"}
        }
    }
    response = send_mcp_request(request)
    if response and "result" in response and "content" in response["result"]:
        if response["result"]["content"] and len(response["result"]["content"]) > 0:
            return response["result"]["content"][0].get("text", "")
    return None

test_case("1.4 Чтение файла с UTF-8", test_1_4,
          lambda r: r and "Привет" in r and "🌍" in r)

# 1.5 Проверка формата ответа (должен быть объект с полем content как массив)
def test_1_5():
    request = {
        "jsonrpc": "2.0",
        "id": 2,
        "method": "tools/call",
        "params": {
            "name": "read_file",
            "arguments": {"filename": f"{TEST_DIR}/test.txt"}
        }
    }
    response = send_mcp_request(request)
    if response and "result" in response:
        return isinstance(response["result"].get("content"), list)
    return False

test_case("1.5 Формат ответа (объект с content как массив)", test_1_5,
          lambda r: r is True)

# 1.6 Проверка формата content[0] (должен быть объект с type и text)
def test_1_6():
    request = {
        "jsonrpc": "2.0",
        "id": 2,
        "method": "tools/call",
        "params": {
            "name": "read_file",
            "arguments": {"filename": f"{TEST_DIR}/test.txt"}
        }
    }
    response = send_mcp_request(request)
    if response and "result" in response and "content" in response["result"]:
        if response["result"]["content"] and len(response["result"]["content"]) > 0:
            item = response["result"]["content"][0]
            return item.get("type") == "text" and isinstance(item.get("text"), str)
    return False

test_case("1.6 Формат content[0] (type и text)", test_1_6,
          lambda r: r is True)

print()
print("2. Тесты с arguments как строкой JSON (новый формат):")
print()
print("  Note: SDK only supports JSON object format for arguments")
print("  JSON string format is not supported by the SDK")
print()

# 2.1 Чтение обычного файла (arguments как строка) - should fail or be unsupported
def test_2_1():
    request = {
        "jsonrpc": "2.0",
        "id": 2,
        "method": "tools/call",
        "params": {
            "name": "read_file",
            "arguments": json.dumps({"filename": f"{TEST_DIR}/test.txt"})
        }
    }
    response = send_mcp_request(request)
    if response:
        return response.get("result", {}).get("isError") is True or "error" in response
    return False

import json
test_case("2.1 Чтение с arguments как строкой (unsupported)", test_2_1,
          lambda r: r is True)

print()
print("3. Тесты обработки ошибок:")
print()

# 3.1 Чтение несуществующего файла
def test_3_1():
    request = {
        "jsonrpc": "2.0",
        "id": 2,
        "method": "tools/call",
        "params": {
            "name": "read_file",
            "arguments": {"filename": f"{TEST_DIR}/nonexistent.txt"}
        }
    }
    response = send_mcp_request(request)
    if response:
        return response.get("result", {}).get("isError") is True or "error" in response
    return False

test_case("3.1 Несуществующий файл", test_3_1,
          lambda r: r is True)

# 3.2 Отсутствие обязательного параметра filename
def test_3_2():
    request = {
        "jsonrpc": "2.0",
        "id": 2,
        "method": "tools/call",
        "params": {
            "name": "read_file",
            "arguments": {}
        }
    }
    response = send_mcp_request(request)
    if response:
        return response.get("result", {}).get("isError") is True or "error" in response
    return False

test_case("3.2 Отсутствие filename", test_3_2,
          lambda r: r is True)

# 3.3 Некорректный JSON в arguments
def test_3_3():
    request = {
        "jsonrpc": "2.0",
        "id": 2,
        "method": "tools/call",
        "params": {
            "name": "read_file",
            "arguments": "{invalid json}"
        }
    }
    response = send_mcp_request(request)
    if response:
        return response.get("result", {}).get("isError") is True or "error" in response
    return False

test_case("3.3 Некорректный JSON в arguments", test_3_3,
          lambda r: r is True)

print()
print("4. Тесты совместимости форматов:")
print()

# 4.1 Проверка работы с вложенными директориями
os.makedirs(f"{TEST_DIR}/nested/deep", exist_ok=True)
with open(f"{TEST_DIR}/nested/deep/file.txt", "w") as f:
    f.write("Nested content")

def test_4_1():
    request = {
        "jsonrpc": "2.0",
        "id": 2,
        "method": "tools/call",
        "params": {
            "name": "read_file",
            "arguments": {"filename": f"{TEST_DIR}/nested/deep/file.txt"}
        }
    }
    response = send_mcp_request(request)
    if response and "result" in response and "content" in response["result"]:
        if response["result"]["content"] and len(response["result"]["content"]) > 0:
            return response["result"]["content"][0].get("text", "")
    return None

test_case("4.1 Файл во вложенной директории", test_4_1,
          lambda r: r == "Nested content")

# Очистка
shutil.rmtree(TEST_DIR)

# Print results and exit
sys.exit(print_test_results())
