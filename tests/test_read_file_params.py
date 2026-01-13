#!/usr/bin/env python3
"""Тесты для новых параметров read_file
Тестирует: start_line, end_line, encoding, line_numbers, skip_empty, max_lines, pattern"""

import os
import shutil
import sys
import json
import re
from test_helper import send_mcp_request, test_case, print_test_results

TEST_DIR = "tmp/test_read_params_dir"

# Cleanup and setup
os.makedirs("tmp", exist_ok=True)
if os.path.exists(TEST_DIR):
    shutil.rmtree(TEST_DIR)
os.makedirs(TEST_DIR, exist_ok=True)

print("=== Тесты новых параметров read_file ===")
print()

# Подготовка: создаем тестовые файлы
print("Подготовка тестовых файлов...")
with open(f"{TEST_DIR}/multiline.txt", "w") as f:
    f.write("Line 1\nLine 2\nLine 3\nLine 4\nLine 5")

with open(f"{TEST_DIR}/mixed.txt", "w") as f:
    f.write("First line\nSecond line\n\nFourth line (empty line above)\nFifth line")

with open(f"{TEST_DIR}/search.txt", "w") as f:
    f.write("error: something went wrong\ninfo: processing started\nwarning: low memory\nerror: another error\ninfo: processing complete")

print("1. Тесты start_line и end_line:")
print()

# 1.1 Чтение с start_line
def test_1_1():
    request = {
        "jsonrpc": "2.0",
        "id": 2,
        "method": "tools/call",
        "params": {
            "name": "read_file",
            "arguments": {
                "filename": f"{TEST_DIR}/multiline.txt",
                "start_line": 2
            }
        }
    }
    response = send_mcp_request(request)
    if response and "result" in response and "content" in response["result"]:
        if response["result"]["content"] and len(response["result"]["content"]) > 0:
            return response["result"]["content"][0].get("text", "")
    return ""

test_case("1.1 Чтение с start_line=2", test_1_1,
          lambda r: "Line 2" in r and "Line 5" in r and "Line 1" not in r)

# 1.2 Чтение с end_line
def test_1_2():
    request = {
        "jsonrpc": "2.0",
        "id": 2,
        "method": "tools/call",
        "params": {
            "name": "read_file",
            "arguments": {
                "filename": f"{TEST_DIR}/multiline.txt",
                "end_line": 3
            }
        }
    }
    response = send_mcp_request(request)
    if response and "result" in response and "content" in response["result"]:
        if response["result"]["content"] and len(response["result"]["content"]) > 0:
            return response["result"]["content"][0].get("text", "")
    return ""

test_case("1.2 Чтение с end_line=3", test_1_2,
          lambda r: "Line 1" in r and "Line 3" in r and "Line 4" not in r)

# 1.3 Чтение с start_line и end_line
def test_1_3():
    request = {
        "jsonrpc": "2.0",
        "id": 2,
        "method": "tools/call",
        "params": {
            "name": "read_file",
            "arguments": {
                "filename": f"{TEST_DIR}/multiline.txt",
                "start_line": 2,
                "end_line": 4
            }
        }
    }
    response = send_mcp_request(request)
    if response and "result" in response and "content" in response["result"]:
        if response["result"]["content"] and len(response["result"]["content"]) > 0:
            return response["result"]["content"][0].get("text", "")
    return ""

test_case("1.3 Чтение с start_line=2, end_line=4", test_1_3,
          lambda r: "Line 2" in r and "Line 4" in r and "Line 1" not in r and "Line 5" not in r)

# 1.4 Проверка граничных случаев - start_line за пределами файла
def test_1_4():
    request = {
        "jsonrpc": "2.0",
        "id": 2,
        "method": "tools/call",
        "params": {
            "name": "read_file",
            "arguments": {
                "filename": f"{TEST_DIR}/multiline.txt",
                "start_line": 10
            }
        }
    }
    response = send_mcp_request(request)
    if response and "result" in response and "content" in response["result"]:
        if response["result"]["content"] and len(response["result"]["content"]) > 0:
            return response["result"]["content"][0].get("text", "")
    return ""

test_case("1.4 start_line за пределами файла (должен вернуть пустой результат)", test_1_4,
          lambda r: r == "")

print()
print("2. Тесты line_numbers:")
print()

# 2.1 Чтение с line_numbers
def test_2_1():
    request = {
        "jsonrpc": "2.0",
        "id": 2,
        "method": "tools/call",
        "params": {
            "name": "read_file",
            "arguments": {
                "filename": f"{TEST_DIR}/multiline.txt",
                "line_numbers": True
            }
        }
    }
    response = send_mcp_request(request)
    if response and "result" in response and "content" in response["result"]:
        if response["result"]["content"] and len(response["result"]["content"]) > 0:
            return response["result"]["content"][0].get("text", "")
    return ""

test_case("2.1 Чтение с line_numbers=true", test_2_1,
          lambda r: "1:" in r and "2:" in r and "3:" in r)

# 2.2 Чтение с line_numbers и start_line
def test_2_2():
    request = {
        "jsonrpc": "2.0",
        "id": 2,
        "method": "tools/call",
        "params": {
            "name": "read_file",
            "arguments": {
                "filename": f"{TEST_DIR}/multiline.txt",
                "start_line": 2,
                "line_numbers": True
            }
        }
    }
    response = send_mcp_request(request)
    if response and "result" in response and "content" in response["result"]:
        if response["result"]["content"] and len(response["result"]["content"]) > 0:
            return response["result"]["content"][0].get("text", "")
    return ""

test_case("2.2 Чтение с line_numbers=true и start_line=2", test_2_2,
          lambda r: "2:" in r and "3:" in r and not r.strip().startswith("1:"))

print()
print("3. Тесты skip_empty:")
print()

# 3.1 Чтение с skip_empty=true
def test_3_1():
    request = {
        "jsonrpc": "2.0",
        "id": 2,
        "method": "tools/call",
        "params": {
            "name": "read_file",
            "arguments": {
                "filename": f"{TEST_DIR}/mixed.txt",
                "skip_empty": True
            }
        }
    }
    response = send_mcp_request(request)
    if response and "result" in response and "content" in response["result"]:
        if response["result"]["content"] and len(response["result"]["content"]) > 0:
            return response["result"]["content"][0].get("text", "")
    return ""

test_case("3.1 Чтение с skip_empty=true", test_3_1,
          lambda r: "First line" in r and "Fourth line" in r and "\n\n" not in r)

# 3.2 Проверка что пустые строки действительно пропущены
def test_3_2():
    request = {
        "jsonrpc": "2.0",
        "id": 2,
        "method": "tools/call",
        "params": {
            "name": "read_file",
            "arguments": {
                "filename": f"{TEST_DIR}/mixed.txt",
                "skip_empty": True
            }
        }
    }
    response = send_mcp_request(request)
    if response and "result" in response and "content" in response["result"]:
        if response["result"]["content"] and len(response["result"]["content"]) > 0:
            text = response["result"]["content"][0].get("text", "")
            lines = [l for l in text.split("\n") if l.strip()]
            return len(lines)
    return 0

test_case("3.2 Проверка пропуска пустых строк", test_3_2,
          lambda r: r == 4)

print()
print("4. Тесты max_lines:")
print()

# 4.1 Чтение с max_lines
def test_4_1():
    request = {
        "jsonrpc": "2.0",
        "id": 2,
        "method": "tools/call",
        "params": {
            "name": "read_file",
            "arguments": {
                "filename": f"{TEST_DIR}/multiline.txt",
                "max_lines": 2
            }
        }
    }
    response = send_mcp_request(request)
    if response and "result" in response and "content" in response["result"]:
        if response["result"]["content"] and len(response["result"]["content"]) > 0:
            text = response["result"]["content"][0].get("text", "")
            lines = [l for l in text.split("\n") if l.strip()]
            return len(lines)
    return 0

test_case("4.1 Чтение с max_lines=2", test_4_1,
          lambda r: r == 2)

# 4.2 max_lines с start_line
def test_4_2():
    request = {
        "jsonrpc": "2.0",
        "id": 2,
        "method": "tools/call",
        "params": {
            "name": "read_file",
            "arguments": {
                "filename": f"{TEST_DIR}/multiline.txt",
                "start_line": 2,
                "max_lines": 2
            }
        }
    }
    response = send_mcp_request(request)
    if response and "result" in response and "content" in response["result"]:
        if response["result"]["content"] and len(response["result"]["content"]) > 0:
            return response["result"]["content"][0].get("text", "")
    return ""

test_case("4.2 max_lines=2 с start_line=2", test_4_2,
          lambda r: len([l for l in r.split("\n") if l.strip()]) == 2 and "Line 2" in r)

print()
print("5. Тесты pattern (regex filter):")
print()

# 5.1 Чтение с pattern (поиск error)
def test_5_1():
    request = {
        "jsonrpc": "2.0",
        "id": 2,
        "method": "tools/call",
        "params": {
            "name": "read_file",
            "arguments": {
                "filename": f"{TEST_DIR}/search.txt",
                "pattern": "error"
            }
        }
    }
    response = send_mcp_request(request)
    if response and "result" in response and "content" in response["result"]:
        if response["result"]["content"] and len(response["result"]["content"]) > 0:
            return response["result"]["content"][0].get("text", "")
    return ""

test_case("5.1 Чтение с pattern=\"error\"", test_5_1,
          lambda r: "error" in r and "info" not in r and "warning" not in r)

# 5.2 Чтение с pattern (поиск info)
def test_5_2():
    request = {
        "jsonrpc": "2.0",
        "id": 2,
        "method": "tools/call",
        "params": {
            "name": "read_file",
            "arguments": {
                "filename": f"{TEST_DIR}/search.txt",
                "pattern": "info"
            }
        }
    }
    response = send_mcp_request(request)
    if response and "result" in response and "content" in response["result"]:
        if response["result"]["content"] and len(response["result"]["content"]) > 0:
            return response["result"]["content"][0].get("text", "")
    return ""

test_case("5.2 Чтение с pattern=\"info\"", test_5_2,
          lambda r: "info" in r and "error" not in r)

# 5.3 Проверка невалидного regex
def test_5_3():
    request = {
        "jsonrpc": "2.0",
        "id": 2,
        "method": "tools/call",
        "params": {
            "name": "read_file",
            "arguments": {
                "filename": f"{TEST_DIR}/search.txt",
                "pattern": "[invalid"
            }
        }
    }
    response = send_mcp_request(request)
    if response:
        return response.get("result", {}).get("isError") is True or "error" in response
    return False

test_case("5.3 Невалидный regex pattern (должна быть ошибка)", test_5_3,
          lambda r: r is True)

print()
print("6. Тесты encoding:")
print()

# 6.1 Чтение с encoding=utf-8 (явно)
def test_6_1():
    request = {
        "jsonrpc": "2.0",
        "id": 2,
        "method": "tools/call",
        "params": {
            "name": "read_file",
            "arguments": {
                "filename": f"{TEST_DIR}/multiline.txt",
                "encoding": "utf-8"
            }
        }
    }
    response = send_mcp_request(request)
    if response and "result" in response and "content" in response["result"]:
        if response["result"]["content"] and len(response["result"]["content"]) > 0:
            return response["result"]["content"][0].get("text", "")
    return ""

test_case("6.1 Чтение с encoding=utf-8", test_6_1,
          lambda r: "Line 1" in r)

# 6.2 Проверка невалидной кодировки
def test_6_2():
    request = {
        "jsonrpc": "2.0",
        "id": 2,
        "method": "tools/call",
        "params": {
            "name": "read_file",
            "arguments": {
                "filename": f"{TEST_DIR}/multiline.txt",
                "encoding": "invalid-encoding"
            }
        }
    }
    response = send_mcp_request(request)
    if response:
        return response.get("result", {}).get("isError") is True or "error" in response
    return False

test_case("6.2 Невалидная кодировка (должна быть ошибка)", test_6_2,
          lambda r: r is True)

print()
print("7. Тесты комбинаций параметров:")
print()

# 7.1 Комбинация start_line, end_line, line_numbers
def test_7_1():
    request = {
        "jsonrpc": "2.0",
        "id": 2,
        "method": "tools/call",
        "params": {
            "name": "read_file",
            "arguments": {
                "filename": f"{TEST_DIR}/multiline.txt",
                "start_line": 2,
                "end_line": 4,
                "line_numbers": True
            }
        }
    }
    response = send_mcp_request(request)
    if response and "result" in response and "content" in response["result"]:
        if response["result"]["content"] and len(response["result"]["content"]) > 0:
            return response["result"]["content"][0].get("text", "")
    return ""

test_case("7.1 start_line + end_line + line_numbers", test_7_1,
          lambda r: "2:" in r and "4:" in r and not r.strip().startswith("1:") and not r.strip().startswith("5:"))

# 7.2 Комбинация pattern + skip_empty
def test_7_2():
    request = {
        "jsonrpc": "2.0",
        "id": 2,
        "method": "tools/call",
        "params": {
            "name": "read_file",
            "arguments": {
                "filename": f"{TEST_DIR}/search.txt",
                "pattern": "error",
                "skip_empty": True
            }
        }
    }
    response = send_mcp_request(request)
    if response and "result" in response and "content" in response["result"]:
        if response["result"]["content"] and len(response["result"]["content"]) > 0:
            return response["result"]["content"][0].get("text", "")
    return ""

test_case("7.2 pattern + skip_empty", test_7_2,
          lambda r: "error" in r and "info" not in r)

# 7.3 Комбинация всех параметров
def test_7_3():
    request = {
        "jsonrpc": "2.0",
        "id": 2,
        "method": "tools/call",
        "params": {
            "name": "read_file",
            "arguments": {
                "filename": f"{TEST_DIR}/search.txt",
                "start_line": 1,
                "end_line": 5,
                "pattern": "error",
                "line_numbers": True,
                "skip_empty": True
            }
        }
    }
    response = send_mcp_request(request)
    if response and "result" in response and "content" in response["result"]:
        if response["result"]["content"] and len(response["result"]["content"]) > 0:
            return response["result"]["content"][0].get("text", "")
    return ""

test_case("7.3 Комбинация всех параметров", test_7_3,
          lambda r: "error" in r and ":" in r)

print()
print("8. Тесты валидации параметров:")
print()

# 8.1 Невалидный start_line (< 1)
def test_8_1():
    request = {
        "jsonrpc": "2.0",
        "id": 2,
        "method": "tools/call",
        "params": {
            "name": "read_file",
            "arguments": {
                "filename": f"{TEST_DIR}/multiline.txt",
                "start_line": 0
            }
        }
    }
    response = send_mcp_request(request)
    if response:
        return response.get("result", {}).get("isError") is True or "error" in response
    return False

test_case("8.1 start_line < 1 (должна быть ошибка)", test_8_1,
          lambda r: r is True)

# 8.2 Невалидный диапазон (end_line < start_line)
def test_8_2():
    request = {
        "jsonrpc": "2.0",
        "id": 2,
        "method": "tools/call",
        "params": {
            "name": "read_file",
            "arguments": {
                "filename": f"{TEST_DIR}/multiline.txt",
                "start_line": 3,
                "end_line": 2
            }
        }
    }
    response = send_mcp_request(request)
    if response:
        return response.get("result", {}).get("isError") is True or "error" in response
    return False

test_case("8.2 end_line < start_line (должна быть ошибка)", test_8_2,
          lambda r: r is True)

# 8.3 Невалидный max_lines (<= 0)
def test_8_3():
    request = {
        "jsonrpc": "2.0",
        "id": 2,
        "method": "tools/call",
        "params": {
            "name": "read_file",
            "arguments": {
                "filename": f"{TEST_DIR}/multiline.txt",
                "max_lines": 0
            }
        }
    }
    response = send_mcp_request(request)
    if response:
        return response.get("result", {}).get("isError") is True or "error" in response
    return False

test_case("8.3 max_lines <= 0 (должна быть ошибка)", test_8_3,
          lambda r: r is True)

print()
print("9. Тесты обратной совместимости:")
print()

# 9.1 Чтение без новых параметров (должно работать как раньше)
def test_9_1():
    request = {
        "jsonrpc": "2.0",
        "id": 2,
        "method": "tools/call",
        "params": {
            "name": "read_file",
            "arguments": {
                "filename": f"{TEST_DIR}/multiline.txt"
            }
        }
    }
    response = send_mcp_request(request)
    if response and "result" in response and "content" in response["result"]:
        if response["result"]["content"] and len(response["result"]["content"]) > 0:
            return response["result"]["content"][0].get("text", "")
    return ""

test_case("9.1 Чтение без новых параметров (обратная совместимость)", test_9_1,
          lambda r: "Line 1" in r and "Line 5" in r)

# Очистка
shutil.rmtree(TEST_DIR, ignore_errors=True)

# Print results and exit
sys.exit(print_test_results())
