#!/bin/bash

# Тесты для функции read_file
# Проверяет обработку arguments как строки JSON и как объекта

SERVER="./mcp-file-edit"
TEST_DIR="test_read_dir"
rm -rf $TEST_DIR
mkdir -p $TEST_DIR

PASSED=0
FAILED=0

test_case() {
    local name="$1"
    local test_cmd="$2"
    local expected="$3"
    
    echo -n "  $name: "
    result=$(eval "$test_cmd" 2>/dev/null)
    
    if eval "$expected"; then
        echo "PASS"
        ((PASSED++))
    else
        echo "FAIL"
        echo "    Result: $result"
        ((FAILED++))
    fi
}

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
    "echo '{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"read_file\",\"arguments\":{\"filename\":\"$TEST_DIR/test.txt\"}}}' | $SERVER | jq -r '.result.content'" \
    '[ "$result" == "Hello, World!" ]'

# 1.2 Чтение многострочного файла
test_case "1.2 Чтение многострочного файла" \
    "echo '{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"read_file\",\"arguments\":{\"filename\":\"$TEST_DIR/multiline.txt\"}}}' | $SERVER | jq -r '.result.content'" \
    '[[ "$result" == *"Line 1"* ]] && [[ "$result" == *"Line 2"* ]] && [[ "$result" == *"Line 3"* ]]'

# 1.3 Чтение пустого файла
test_case "1.3 Чтение пустого файла" \
    "echo '{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"read_file\",\"arguments\":{\"filename\":\"$TEST_DIR/empty.txt\"}}}' | $SERVER | jq -r '.result.content'" \
    '[ "$result" == "" ]'

# 1.4 Чтение файла с UTF-8
test_case "1.4 Чтение файла с UTF-8" \
    "echo '{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"read_file\",\"arguments\":{\"filename\":\"$TEST_DIR/utf8.txt\"}}}' | $SERVER | jq -r '.result.content'" \
    '[[ "$result" == *"Привет"* ]] && [[ "$result" == *"🌍"* ]]'

# 1.5 Проверка формата ответа (должен быть объект с полем content)
test_case "1.5 Формат ответа (объект с content)" \
    "echo '{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"read_file\",\"arguments\":{\"filename\":\"$TEST_DIR/test.txt\"}}}' | $SERVER | jq -e '.result.content != null'" \
    '[ $? -eq 0 ]'

# 1.6 Проверка отсутствия поля status в ответе
test_case "1.6 Отсутствие поля status" \
    "echo '{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"read_file\",\"arguments\":{\"filename\":\"$TEST_DIR/test.txt\"}}}' | $SERVER | jq -e '.result.status == null'" \
    '[ $? -eq 0 ]'

echo ""
echo "2. Тесты с arguments как строкой JSON (новый формат):"
echo ""

# 2.1 Чтение обычного файла (arguments как строка)
test_case "2.1 Чтение с arguments как строкой" \
    "echo '{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"read_file\",\"arguments\":\"{\\\"filename\\\":\\\"$TEST_DIR/test.txt\\\"}\"}}' | $SERVER | jq -r '.result.content'" \
    '[ "$result" == "Hello, World!" ]'

# 2.2 Чтение многострочного файла (arguments как строка)
test_case "2.2 Многострочный файл (arguments как строка)" \
    "echo '{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"read_file\",\"arguments\":\"{\\\"filename\\\":\\\"$TEST_DIR/multiline.txt\\\"}\"}}' | $SERVER | jq -r '.result.content'" \
    '[[ "$result" == *"Line 1"* ]] && [[ "$result" == *"Line 2"* ]] && [[ "$result" == *"Line 3"* ]]'

# 2.3 Чтение пустого файла (arguments как строка)
test_case "2.3 Пустой файл (arguments как строка)" \
    "echo '{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"read_file\",\"arguments\":\"{\\\"filename\\\":\\\"$TEST_DIR/empty.txt\\\"}\"}}' | $SERVER | jq -r '.result.content'" \
    '[ "$result" == "" ]'

# 2.4 Чтение файла с UTF-8 (arguments как строка)
test_case "2.4 UTF-8 файл (arguments как строка)" \
    "echo '{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"read_file\",\"arguments\":\"{\\\"filename\\\":\\\"$TEST_DIR/utf8.txt\\\"}\"}}' | $SERVER | jq -r '.result.content'" \
    '[[ "$result" == *"Привет"* ]] && [[ "$result" == *"🌍"* ]]'

echo ""
echo "3. Тесты обработки ошибок:"
echo ""

# 3.1 Чтение несуществующего файла
test_case "3.1 Несуществующий файл" \
    "echo '{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"read_file\",\"arguments\":{\"filename\":\"$TEST_DIR/nonexistent.txt\"}}}' | $SERVER | jq -e '.error != null'" \
    '[ $? -eq 0 ]'

# 3.2 Несуществующий файл (arguments как строка)
test_case "3.2 Несуществующий файл (arguments как строка)" \
    "echo '{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"read_file\",\"arguments\":\"{\\\"filename\\\":\\\"$TEST_DIR/nonexistent2.txt\\\"}\"}}' | $SERVER | jq -e '.error != null'" \
    '[ $? -eq 0 ]'

# 3.3 Отсутствие обязательного параметра filename
test_case "3.3 Отсутствие filename" \
    "echo '{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"read_file\",\"arguments\":{}}}' | $SERVER | jq -e '.error != null'" \
    '[ $? -eq 0 ]'

# 3.4 Некорректный JSON в arguments (строка)
test_case "3.4 Некорректный JSON в arguments" \
    "echo '{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"read_file\",\"arguments\":\"{invalid json}\"}}' | $SERVER | jq -e '.error != null'" \
    '[ $? -eq 0 ]'

echo ""
echo "4. Тесты совместимости форматов:"
echo ""

# 4.1 Сравнение результатов обоих форматов
test_case "4.1 Одинаковый результат для обоих форматов" \
    "result1=\$(echo '{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"read_file\",\"arguments\":{\"filename\":\"$TEST_DIR/test.txt\"}}}' | $SERVER | jq -r '.result.content') && result2=\$(echo '{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"read_file\",\"arguments\":\"{\\\"filename\\\":\\\"$TEST_DIR/test.txt\\\"}\"}}' | $SERVER | jq -r '.result.content') && [ \"\$result1\" == \"\$result2\" ]" \
    '[ $? -eq 0 ]'

# 4.2 Проверка работы с вложенными директориями
mkdir -p $TEST_DIR/nested/deep
echo "Nested content" > $TEST_DIR/nested/deep/file.txt

test_case "4.2 Файл во вложенной директории (объект)" \
    "echo '{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"read_file\",\"arguments\":{\"filename\":\"$TEST_DIR/nested/deep/file.txt\"}}}' | $SERVER | jq -r '.result.content'" \
    '[ "$result" == "Nested content" ]'

test_case "4.3 Файл во вложенной директории (строка)" \
    "echo '{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"read_file\",\"arguments\":\"{\\\"filename\\\":\\\"$TEST_DIR/nested/deep/file.txt\\\"}\"}}' | $SERVER | jq -r '.result.content'" \
    '[ "$result" == "Nested content" ]'

echo ""
echo "=== Результаты ==="
echo "Пройдено: $PASSED"
echo "Провалено: $FAILED"
echo ""

# Очистка
rm -rf $TEST_DIR

if [ $FAILED -eq 0 ]; then
    echo "Все тесты пройдены успешно!"
    exit 0
else
    echo "Некоторые тесты провалились."
    exit 1
fi

