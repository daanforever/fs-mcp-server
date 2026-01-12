#!/usr/bin/env python3
"""Тесты для функции write_file
Проверяет запись файлов с различным содержимым"""

import os
import shutil
import sys
from test_helper import send_mcp_request, test_case, print_test_results, PASSED, FAILED

TEST_DIR = "test_write_dir"

# Cleanup and setup
if os.path.exists(TEST_DIR):
    shutil.rmtree(TEST_DIR)
os.makedirs(TEST_DIR, exist_ok=True)

print("=== Тесты write_file ===")
print()

print("1. Базовые тесты записи:")
print()

# 1.1 Запись простого файла
def test_1_1():
    request = {
        "jsonrpc": "2.0",
        "id": 2,
        "method": "tools/call",
        "params": {
            "name": "write_file",
            "arguments": {
                "filename": f"{TEST_DIR}/simple.txt",
                "content": "Hello, World!"
            }
        }
    }
    response = send_mcp_request(request)
    if response and "result" in response and "content" in response["result"]:
        if response["result"]["content"] and len(response["result"]["content"]) > 0:
            text = response["result"]["content"][0].get("text", "")
            # Проверяем, что файл был создан и содержит правильное содержимое
            if os.path.exists(f"{TEST_DIR}/simple.txt"):
                with open(f"{TEST_DIR}/simple.txt", "r") as f:
                    file_content = f.read()
                    return file_content == "Hello, World!" and "successfully" in text.lower()
    return False

test_case("1.1 Запись простого файла", test_1_1,
          lambda r: r is True)

# 1.2 Запись многострочного файла
def test_1_2():
    content = "Line 1\nLine 2\nLine 3"
    request = {
        "jsonrpc": "2.0",
        "id": 2,
        "method": "tools/call",
        "params": {
            "name": "write_file",
            "arguments": {
                "filename": f"{TEST_DIR}/multiline.txt",
                "content": content
            }
        }
    }
    response = send_mcp_request(request)
    if response and "result" in response:
        if os.path.exists(f"{TEST_DIR}/multiline.txt"):
            with open(f"{TEST_DIR}/multiline.txt", "r") as f:
                file_content = f.read()
                return file_content == content
    return False

test_case("1.2 Запись многострочного файла", test_1_2,
          lambda r: r is True)

# 1.3 Запись пустого файла
def test_1_3():
    request = {
        "jsonrpc": "2.0",
        "id": 2,
        "method": "tools/call",
        "params": {
            "name": "write_file",
            "arguments": {
                "filename": f"{TEST_DIR}/empty.txt",
                "content": ""
            }
        }
    }
    response = send_mcp_request(request)
    if response and "result" in response:
        if os.path.exists(f"{TEST_DIR}/empty.txt"):
            with open(f"{TEST_DIR}/empty.txt", "r") as f:
                file_content = f.read()
                return file_content == ""
    return False

test_case("1.3 Запись пустого файла", test_1_3,
          lambda r: r is True)

# 1.4 Запись файла с UTF-8
def test_1_4():
    content = "Привет 🌍"
    request = {
        "jsonrpc": "2.0",
        "id": 2,
        "method": "tools/call",
        "params": {
            "name": "write_file",
            "arguments": {
                "filename": f"{TEST_DIR}/utf8.txt",
                "content": content
            }
        }
    }
    response = send_mcp_request(request)
    if response and "result" in response:
        if os.path.exists(f"{TEST_DIR}/utf8.txt"):
            with open(f"{TEST_DIR}/utf8.txt", "r", encoding="utf-8") as f:
                file_content = f.read()
                return file_content == content
    return False

test_case("1.4 Запись файла с UTF-8", test_1_4,
          lambda r: r is True)

# 1.5 Перезапись существующего файла
def test_1_5():
    # Сначала создаем файл с одним содержимым
    with open(f"{TEST_DIR}/overwrite.txt", "w") as f:
        f.write("Old content")
    
    # Затем перезаписываем его
    request = {
        "jsonrpc": "2.0",
        "id": 2,
        "method": "tools/call",
        "params": {
            "name": "write_file",
            "arguments": {
                "filename": f"{TEST_DIR}/overwrite.txt",
                "content": "New content"
            }
        }
    }
    response = send_mcp_request(request)
    if response and "result" in response:
        if os.path.exists(f"{TEST_DIR}/overwrite.txt"):
            with open(f"{TEST_DIR}/overwrite.txt", "r") as f:
                file_content = f.read()
                return file_content == "New content"
    return False

test_case("1.5 Перезапись существующего файла", test_1_5,
          lambda r: r is True)

print()
print("2. Тесты создания директорий:")
print()

# 2.1 Создание файла во вложенной директории
def test_2_1():
    request = {
        "jsonrpc": "2.0",
        "id": 2,
        "method": "tools/call",
        "params": {
            "name": "write_file",
            "arguments": {
                "filename": f"{TEST_DIR}/nested/deep/file.txt",
                "content": "Nested content"
            }
        }
    }
    response = send_mcp_request(request)
    if response and "result" in response:
        if os.path.exists(f"{TEST_DIR}/nested/deep/file.txt"):
            with open(f"{TEST_DIR}/nested/deep/file.txt", "r") as f:
                file_content = f.read()
                return file_content == "Nested content"
    return False

test_case("2.1 Создание файла во вложенной директории", test_2_1,
          lambda r: r is True)

print()
print("3. Тесты формата ответа:")
print()

# 3.1 Проверка формата ответа
def test_3_1():
    request = {
        "jsonrpc": "2.0",
        "id": 2,
        "method": "tools/call",
        "params": {
            "name": "write_file",
            "arguments": {
                "filename": f"{TEST_DIR}/format_test.txt",
                "content": "Test"
            }
        }
    }
    response = send_mcp_request(request)
    if response and "result" in response:
        return isinstance(response["result"].get("content"), list)
    return False

test_case("3.1 Формат ответа (объект с content как массив)", test_3_1,
          lambda r: r is True)

# 3.2 Проверка формата content[0]
def test_3_2():
    request = {
        "jsonrpc": "2.0",
        "id": 2,
        "method": "tools/call",
        "params": {
            "name": "write_file",
            "arguments": {
                "filename": f"{TEST_DIR}/format_test2.txt",
                "content": "Test"
            }
        }
    }
    response = send_mcp_request(request)
    if response and "result" in response and "content" in response["result"]:
        if response["result"]["content"] and len(response["result"]["content"]) > 0:
            item = response["result"]["content"][0]
            return item.get("type") == "text" and isinstance(item.get("text"), str)
    return False

test_case("3.2 Формат content[0] (type и text)", test_3_2,
          lambda r: r is True)

# 3.3 Проверка сообщения об успехе
def test_3_3():
    request = {
        "jsonrpc": "2.0",
        "id": 2,
        "method": "tools/call",
        "params": {
            "name": "write_file",
            "arguments": {
                "filename": f"{TEST_DIR}/success_test.txt",
                "content": "Test content"
            }
        }
    }
    response = send_mcp_request(request)
    if response and "result" in response and "content" in response["result"]:
        if response["result"]["content"] and len(response["result"]["content"]) > 0:
            text = response["result"]["content"][0].get("text", "")
            return "successfully" in text.lower() and "bytes written" in text.lower()
    return False

test_case("3.3 Сообщение об успехе содержит информацию", test_3_3,
          lambda r: r is True)

print()
print("4. Тесты обработки ошибок:")
print()

# 4.1 Отсутствие обязательного параметра filename
def test_4_1():
    request = {
        "jsonrpc": "2.0",
        "id": 2,
        "method": "tools/call",
        "params": {
            "name": "write_file",
            "arguments": {
                "content": "Test"
            }
        }
    }
    response = send_mcp_request(request)
    if response:
        return response.get("result", {}).get("isError") is True or "error" in response
    return False

test_case("4.1 Отсутствие filename", test_4_1,
          lambda r: r is True)

# 4.2 Отсутствие обязательного параметра content
def test_4_2():
    request = {
        "jsonrpc": "2.0",
        "id": 2,
        "method": "tools/call",
        "params": {
            "name": "write_file",
            "arguments": {
                "filename": f"{TEST_DIR}/test.txt"
            }
        }
    }
    response = send_mcp_request(request)
    if response:
        return response.get("result", {}).get("isError") is True or "error" in response
    return False

test_case("4.2 Отсутствие content", test_4_2,
          lambda r: r is True)

# 4.3 Пустые аргументы
def test_4_3():
    request = {
        "jsonrpc": "2.0",
        "id": 2,
        "method": "tools/call",
        "params": {
            "name": "write_file",
            "arguments": {}
        }
    }
    response = send_mcp_request(request)
    if response:
        return response.get("result", {}).get("isError") is True or "error" in response
    return False

test_case("4.3 Пустые аргументы", test_4_3,
          lambda r: r is True)

print()
print("5. Тесты специальных символов:")
print()

# 5.1 Запись файла со специальными символами
def test_5_1():
    content = "Special chars: !@#$%^&*()_+-=[]{}|;':\",./<>?"
    request = {
        "jsonrpc": "2.0",
        "id": 2,
        "method": "tools/call",
        "params": {
            "name": "write_file",
            "arguments": {
                "filename": f"{TEST_DIR}/special.txt",
                "content": content
            }
        }
    }
    response = send_mcp_request(request)
    if response and "result" in response:
        if os.path.exists(f"{TEST_DIR}/special.txt"):
            with open(f"{TEST_DIR}/special.txt", "r") as f:
                file_content = f.read()
                return file_content == content
    return False

test_case("5.1 Специальные символы", test_5_1,
          lambda r: r is True)

# 5.2 Запись файла с табуляциями и пробелами
def test_5_2():
    content = "Line with\t\ttabs\nLine with    spaces"
    request = {
        "jsonrpc": "2.0",
        "id": 2,
        "method": "tools/call",
        "params": {
            "name": "write_file",
            "arguments": {
                "filename": f"{TEST_DIR}/whitespace.txt",
                "content": content
            }
        }
    }
    response = send_mcp_request(request)
    if response and "result" in response:
        if os.path.exists(f"{TEST_DIR}/whitespace.txt"):
            with open(f"{TEST_DIR}/whitespace.txt", "r") as f:
                file_content = f.read()
                return file_content == content
    return False

test_case("5.2 Табуляции и пробелы", test_5_2,
          lambda r: r is True)

# Очистка
shutil.rmtree(TEST_DIR)

# Print results and exit
sys.exit(print_test_results())
