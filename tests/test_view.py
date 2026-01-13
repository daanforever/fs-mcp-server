#!/usr/bin/env python3
"""Tests for view tool (alias for read_file)"""

import os
import shutil
import sys
import json
from test_helper import send_mcp_request, test_case, print_test_results, PASSED, FAILED

TEST_DIR = "tmp/test_view_dir"

# Cleanup and setup
os.makedirs("tmp", exist_ok=True)
if os.path.exists(TEST_DIR):
    shutil.rmtree(TEST_DIR)
os.makedirs(TEST_DIR, exist_ok=True)

print("=== Тесты view tool ===")
print()

# Подготовка: создаем тестовые файлы
print("Подготовка тестовых файлов...")
with open(f"{TEST_DIR}/test.txt", "w", encoding="utf-8") as f:
    f.write("Hello, World!")

with open(f"{TEST_DIR}/multiline.txt", "w", encoding="utf-8") as f:
    f.write("Line 1\nLine 2\nLine 3")

with open(f"{TEST_DIR}/empty.txt", "w", encoding="utf-8") as f:
    pass  # Empty file

with open(f"{TEST_DIR}/utf8.txt", "w", encoding="utf-8") as f:
    f.write("Привет 🌍")

os.makedirs(f"{TEST_DIR}/nested/deep", exist_ok=True)
with open(f"{TEST_DIR}/nested/deep/file.txt", "w", encoding="utf-8") as f:
    f.write("Nested content")

print("1. Базовые тесты view (arguments как объект):")
print()

# 1.1 Чтение обычного файла
def test_1_1():
    request = {
        "jsonrpc": "2.0",
        "id": 2,
        "method": "tools/call",
        "params": {
            "name": "view",
            "arguments": {"filename": f"{TEST_DIR}/test.txt"}
        }
    }
    response = send_mcp_request(request)
    if response and "result" in response and "content" in response["result"]:
        if response["result"]["content"] and len(response["result"]["content"]) > 0:
            return response["result"]["content"][0].get("text", "")
    return None

test_case("1.1 Чтение обычного файла", test_1_1, lambda r: r == "Hello, World!")

# 1.2 Чтение многострочного файла
def test_1_2():
    request = {
        "jsonrpc": "2.0",
        "id": 2,
        "method": "tools/call",
        "params": {
            "name": "view",
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
            "name": "view",
            "arguments": {"filename": f"{TEST_DIR}/empty.txt"}
        }
    }
    response = send_mcp_request(request)
    if response and "result" in response and "content" in response["result"]:
        if response["result"]["content"] and len(response["result"]["content"]) > 0:
            return response["result"]["content"][0].get("text", "")
    return None

test_case("1.3 Чтение пустого файла", test_1_3, lambda r: r == "")

# 1.4 Чтение файла с UTF-8
def test_1_4():
    request = {
        "jsonrpc": "2.0",
        "id": 2,
        "method": "tools/call",
        "params": {
            "name": "view",
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

# 1.5 Проверка формата ответа
def test_1_5():
    request = {
        "jsonrpc": "2.0",
        "id": 2,
        "method": "tools/call",
        "params": {
            "name": "view",
            "arguments": {"filename": f"{TEST_DIR}/test.txt"}
        }
    }
    response = send_mcp_request(request)
    if response and "result" in response:
        return isinstance(response["result"].get("content"), list)
    return False

test_case("1.5 Формат ответа (объект с content как массив)", test_1_5,
          lambda r: r is True)

print()
print("2. Тесты с arguments как строкой JSON:")
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
            "name": "view",
            "arguments": json.dumps({"filename": f"{TEST_DIR}/test.txt"})
        }
    }
    response = send_mcp_request(request)
    if response:
        return response.get("result", {}).get("isError") is True or "error" in response
    return False

test_case("2.1 Чтение с arguments как строкой (unsupported)", test_2_1,
          lambda r: r is True)

# 2.2 Многострочный файл (arguments как строка) - should fail or be unsupported
def test_2_2():
    request = {
        "jsonrpc": "2.0",
        "id": 2,
        "method": "tools/call",
        "params": {
            "name": "view",
            "arguments": json.dumps({"filename": f"{TEST_DIR}/multiline.txt"})
        }
    }
    response = send_mcp_request(request)
    if response:
        return response.get("result", {}).get("isError") is True or "error" in response
    return False

test_case("2.2 Многострочный файл (arguments как строка, unsupported)", test_2_2,
          lambda r: r is True)

# 2.3 Пустой файл (arguments как строка) - should fail or be unsupported
def test_2_3():
    request = {
        "jsonrpc": "2.0",
        "id": 2,
        "method": "tools/call",
        "params": {
            "name": "view",
            "arguments": json.dumps({"filename": f"{TEST_DIR}/empty.txt"})
        }
    }
    response = send_mcp_request(request)
    if response:
        return response.get("result", {}).get("isError") is True or "error" in response
    return False

test_case("2.3 Пустой файл (arguments как строка, unsupported)", test_2_3,
          lambda r: r is True)

# 2.4 UTF-8 файл (arguments как строка) - should fail or be unsupported
def test_2_4():
    request = {
        "jsonrpc": "2.0",
        "id": 2,
        "method": "tools/call",
        "params": {
            "name": "view",
            "arguments": json.dumps({"filename": f"{TEST_DIR}/utf8.txt"})
        }
    }
    response = send_mcp_request(request)
    if response:
        return response.get("result", {}).get("isError") is True or "error" in response
    return False

test_case("2.4 UTF-8 файл (arguments как строка, unsupported)", test_2_4,
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
            "name": "view",
            "arguments": {"filename": f"{TEST_DIR}/nonexistent.txt"}
        }
    }
    response = send_mcp_request(request)
    if response:
        return response.get("result", {}).get("isError") is True or "error" in response
    return False

test_case("3.1 Несуществующий файл", test_3_1, lambda r: r is True)

# 3.2 Несуществующий файл (arguments как строка)
def test_3_2():
    request = {
        "jsonrpc": "2.0",
        "id": 2,
        "method": "tools/call",
        "params": {
            "name": "view",
            "arguments": json.dumps({"filename": f"{TEST_DIR}/nonexistent2.txt"})
        }
    }
    response = send_mcp_request(request)
    if response:
        return response.get("result", {}).get("isError") is True or "error" in response
    return False

test_case("3.2 Несуществующий файл (arguments как строка)", test_3_2, lambda r: r is True)

# 3.3 Отсутствие обязательного параметра filename
def test_3_3():
    request = {
        "jsonrpc": "2.0",
        "id": 2,
        "method": "tools/call",
        "params": {
            "name": "view",
            "arguments": {}
        }
    }
    response = send_mcp_request(request)
    if response:
        return response.get("result", {}).get("isError") is True or "error" in response
    return False

test_case("3.3 Отсутствие filename", test_3_3, lambda r: r is True)

# 3.4 Некорректный JSON в arguments
def test_3_4():
    request = {
        "jsonrpc": "2.0",
        "id": 2,
        "method": "tools/call",
        "params": {
            "name": "view",
            "arguments": "{invalid json}"
        }
    }
    response = send_mcp_request(request)
    if response:
        return response.get("result", {}).get("isError") is True or "error" in response
    return False

test_case("3.4 Некорректный JSON в arguments", test_3_4, lambda r: r is True)

print()
print("4. Тесты совместимости с read_file:")
print()

# 4.1 Сравнение результатов view и read_file
def test_4_1():
    request1 = {
        "jsonrpc": "2.0",
        "id": 2,
        "method": "tools/call",
        "params": {
            "name": "view",
            "arguments": {"filename": f"{TEST_DIR}/test.txt"}
        }
    }
    request2 = {
        "jsonrpc": "2.0",
        "id": 2,
        "method": "tools/call",
        "params": {
            "name": "read_file",
            "arguments": {"filename": f"{TEST_DIR}/test.txt"}
        }
    }
    response1 = send_mcp_request(request1)
    response2 = send_mcp_request(request2)
    if response1 and response2 and "result" in response1 and "result" in response2:
        result1 = response1["result"]
        result2 = response2["result"]
        if "content" in result1 and "content" in result2:
            content1 = result1["content"]
            content2 = result2["content"]
            if content1 and content2 and len(content1) > 0 and len(content2) > 0:
                text1 = content1[0].get("text", "")
                text2 = content2[0].get("text", "")
                return text1 == text2
    return False

test_case("4.1 Одинаковый результат view и read_file", test_4_1, lambda r: r is True)

# 4.2 Сравнение формата ответа
def test_4_2():
    request1 = {
        "jsonrpc": "2.0",
        "id": 2,
        "method": "tools/call",
        "params": {
            "name": "view",
            "arguments": {"filename": f"{TEST_DIR}/test.txt"}
        }
    }
    request2 = {
        "jsonrpc": "2.0",
        "id": 2,
        "method": "tools/call",
        "params": {
            "name": "read_file",
            "arguments": {"filename": f"{TEST_DIR}/test.txt"}
        }
    }
    response1 = send_mcp_request(request1)
    response2 = send_mcp_request(request2)
    if response1 and response2 and "result" in response1 and "result" in response2:
        result1 = response1["result"]
        result2 = response2["result"]
        # Compare JSON structure
        result1_json = json.dumps(result1, sort_keys=True)
        result2_json = json.dumps(result2, sort_keys=True)
        return result1_json == result2_json
    return False

test_case("4.2 Одинаковый формат ответа", test_4_2, lambda r: r is True)

# 4.3 Сравнение обработки ошибок
def test_4_3():
    request1 = {
        "jsonrpc": "2.0",
        "id": 2,
        "method": "tools/call",
        "params": {
            "name": "view",
            "arguments": {"filename": f"{TEST_DIR}/nonexistent.txt"}
        }
    }
    request2 = {
        "jsonrpc": "2.0",
        "id": 2,
        "method": "tools/call",
        "params": {
            "name": "read_file",
            "arguments": {"filename": f"{TEST_DIR}/nonexistent.txt"}
        }
    }
    response1 = send_mcp_request(request1)
    response2 = send_mcp_request(request2)
    if response1 and response2:
        # Both should have errors
        error1 = response1.get("error")
        error2 = response2.get("error")
        is_error1 = response1.get("result", {}).get("isError") is True
        is_error2 = response2.get("result", {}).get("isError") is True
        
        # Both should have errors
        if (error1 is not None or is_error1) and (error2 is not None or is_error2):
            return True
    return False

test_case("4.3 Одинаковая обработка ошибок", test_4_3, lambda r: r is True)

print()
print("5. Тесты вложенных директорий:")
print()

# 5.1 Файл во вложенной директории (объект)
def test_5_1():
    request = {
        "jsonrpc": "2.0",
        "id": 2,
        "method": "tools/call",
        "params": {
            "name": "view",
            "arguments": {"filename": f"{TEST_DIR}/nested/deep/file.txt"}
        }
    }
    response = send_mcp_request(request)
    if response and "result" in response and "content" in response["result"]:
        if response["result"]["content"] and len(response["result"]["content"]) > 0:
            return response["result"]["content"][0].get("text", "")
    return None

test_case("5.1 Файл во вложенной директории (объект)", test_5_1,
          lambda r: r == "Nested content")

# 5.2 Файл во вложенной директории (строка) - should fail or be unsupported
def test_5_2():
    request = {
        "jsonrpc": "2.0",
        "id": 2,
        "method": "tools/call",
        "params": {
            "name": "view",
            "arguments": json.dumps({"filename": f"{TEST_DIR}/nested/deep/file.txt"})
        }
    }
    response = send_mcp_request(request)
    if response:
        return response.get("result", {}).get("isError") is True or "error" in response
    return False

test_case("5.2 Файл во вложенной директории (строка, unsupported)", test_5_2,
          lambda r: r is True)

# Очистка
shutil.rmtree(TEST_DIR, ignore_errors=True)

# Print results and exit
sys.exit(print_test_results())
