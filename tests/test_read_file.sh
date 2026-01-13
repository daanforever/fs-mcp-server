#!/bin/bash

# Тесты для функции read_file
# Проверяет обработку arguments как строки JSON и как объекта

# Source helper functions
source "$(dirname "$0")/helper.sh"

TEST_DIR="tmp/test_read_dir"
mkdir -p tmp
rm -rf $TEST_DIR
mkdir -p $TEST_DIR

PASSED=0
FAILED=0

echo "=== Тесты read_file ==="
echo ""

# Подготовка: создаем тестовый файл
echo "Подготовка тестового файла..."
echo "Hello, World!" > $TEST_DIR/test.txt
echo "Line 1
Line 2
Line 3" > $TEST_DIR/multiline.txt
echo -n "" > $TEST_DIR/empty.txt
echo "Привет 🌍" > $TEST_DIR/utf8.txt

echo "1. Тесты с arguments как объектом (обычный формат):"
echo ""

# 1.1 Чтение обычного файла
test_case "1.1 Чтение обычного файла" \
    "send_mcp_request '{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"read_file\",\"arguments\":{\"filename\":\"$TEST_DIR/test.txt\"}}}' | jq -r '.result.content[0].text'" \
    '[ "$result" == "Hello, World!" ]'

# 1.2 Чтение многострочного файла
test_case "1.2 Чтение многострочного файла" \
    "send_mcp_request '{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"read_file\",\"arguments\":{\"filename\":\"$TEST_DIR/multiline.txt\"}}}' | jq -r '.result.content[0].text'" \
    '[[ "$result" == *"Line 1"* ]] && [[ "$result" == *"Line 2"* ]] && [[ "$result" == *"Line 3"* ]]'

# 1.3 Чтение пустого файла
test_case "1.3 Чтение пустого файла" \
    "send_mcp_request '{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"read_file\",\"arguments\":{\"filename\":\"$TEST_DIR/empty.txt\"}}}' | jq -r '.result.content[0].text'" \
    '[ "$result" == "" ]'

# 1.4 Чтение файла с UTF-8
test_case "1.4 Чтение файла с UTF-8" \
    "send_mcp_request '{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"read_file\",\"arguments\":{\"filename\":\"$TEST_DIR/utf8.txt\"}}}' | jq -r '.result.content[0].text'" \
    '[[ "$result" == *"Привет"* ]] && [[ "$result" == *"🌍"* ]]'

# 1.5 Проверка формата ответа (должен быть объект с полем content как массив)
test_case "1.5 Формат ответа (объект с content как массив)" \
    "send_mcp_request '{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"read_file\",\"arguments\":{\"filename\":\"$TEST_DIR/test.txt\"}}}' | jq -e '.result.content != null and (.result.content | type) == \"array\"'" \
    '[ $? -eq 0 ]'

# 1.6 Проверка формата content[0] (должен быть объект с type и text)
test_case "1.6 Формат content[0] (type и text)" \
    "send_mcp_request '{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"read_file\",\"arguments\":{\"filename\":\"$TEST_DIR/test.txt\"}}}' | jq -e '.result.content[0].type == \"text\" and (.result.content[0].text | type) == \"string\"'" \
    '[ $? -eq 0 ]'

echo ""
echo "2. Тесты с arguments как строкой JSON (новый формат):"
echo ""
echo "  Note: SDK only supports JSON object format for arguments"
echo "  JSON string format is not supported by the SDK"
echo ""

# 2.1 Чтение обычного файла (arguments как строка) - should fail or be unsupported
test_case "2.1 Чтение с arguments как строкой (unsupported)" \
    "send_mcp_request '{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"read_file\",\"arguments\":\"{\\\"filename\\\":\\\"$TEST_DIR/test.txt\\\"}\"}}' | jq -e '.result.isError == true or .error != null'" \
    '[ $? -eq 0 ]'

echo ""
echo "3. Тесты обработки ошибок:"
echo ""

# 3.1 Чтение несуществующего файла
test_case "3.1 Несуществующий файл" \
    "send_mcp_request '{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"read_file\",\"arguments\":{\"filename\":\"$TEST_DIR/nonexistent.txt\"}}}' | jq -e '.result.isError == true or .error != null'" \
    '[ $? -eq 0 ]'

# 3.2 Отсутствие обязательного параметра filename
test_case "3.2 Отсутствие filename" \
    "send_mcp_request '{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"read_file\",\"arguments\":{}}}' | jq -e '.result.isError == true or .error != null'" \
    '[ $? -eq 0 ]'

# 3.3 Некорректный JSON в arguments
test_case "3.3 Некорректный JSON в arguments" \
    "send_mcp_request '{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"read_file\",\"arguments\":\"{invalid json}\"}}' | jq -e '.result.isError == true or .error != null'" \
    '[ $? -eq 0 ]'

echo ""
echo "4. Тесты совместимости форматов:"
echo ""

# 4.1 Проверка работы с вложенными директориями
mkdir -p $TEST_DIR/nested/deep
echo "Nested content" > $TEST_DIR/nested/deep/file.txt

test_case "4.1 Файл во вложенной директории" \
    "send_mcp_request '{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"read_file\",\"arguments\":{\"filename\":\"$TEST_DIR/nested/deep/file.txt\"}}}' | jq -r '.result.content[0].text'" \
    '[ "$result" == "Nested content" ]'

# Очистка
rm -rf $TEST_DIR

# Print results and exit
print_test_results
exit $?
