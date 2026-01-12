#!/bin/bash

# Тесты для функции view (alias для read_file)
# Проверяет, что view работает идентично read_file

# Source helper functions
source "$(dirname "$0")/helper.sh"

TEST_DIR="test_view_dir"
rm -rf $TEST_DIR
mkdir -p $TEST_DIR

PASSED=0
FAILED=0

# Override test_case to add timeout handling
test_case() {
    local name="$1"
    local test_cmd="$2"
    local expected="$3"
    
    echo -n "  $name: "
    # Add timeout to prevent hanging
    set +e
    result=$(timeout 10 bash -c "$test_cmd" 2>/dev/null)
    timeout_exit=$?
    set -e
    
    if [ $timeout_exit -eq 124 ]; then
        echo "FAIL (timeout)"
        echo "    Test timed out after 10 seconds"
        ((FAILED++))
        return
    fi
    
    if eval "$expected"; then
        echo "PASS"
        ((PASSED++))
    else
        echo "FAIL"
        echo "    Result: $result"
        ((FAILED++))
    fi
}

echo "=== Тесты view tool ==="
echo ""

# Подготовка: создаем тестовые файлы
echo "Подготовка тестовых файлов..."
echo "Hello, World!" > $TEST_DIR/test.txt
echo "Line 1
Line 2
Line 3" > $TEST_DIR/multiline.txt
echo -n "" > $TEST_DIR/empty.txt
echo "Привет 🌍" > $TEST_DIR/utf8.txt
mkdir -p $TEST_DIR/nested/deep
echo "Nested content" > $TEST_DIR/nested/deep/file.txt

echo "1. Базовые тесты view (arguments как объект):"
echo ""

# 1.1 Чтение обычного файла
test_case "1.1 Чтение обычного файла" \
    "echo '{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"view\",\"arguments\":{\"filename\":\"$TEST_DIR/test.txt\"}}}' | $SERVER | jq -r '.result.content[0].text'" \
    '[ "$result" == "Hello, World!" ]'

# 1.2 Чтение многострочного файла
test_case "1.2 Чтение многострочного файла" \
    "result=\$(echo '{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"view\",\"arguments\":{\"filename\":\"$TEST_DIR/multiline.txt\"}}}' | $SERVER | jq -r '.result.content[0].text') && [[ \"\$result\" == *\"Line 1\"* ]] && [[ \"\$result\" == *\"Line 2\"* ]] && [[ \"\$result\" == *\"Line 3\"* ]]" \
    '[ $? -eq 0 ]'

# 1.3 Чтение пустого файла
test_case "1.3 Чтение пустого файла" \
    "echo '{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"view\",\"arguments\":{\"filename\":\"$TEST_DIR/empty.txt\"}}}' | $SERVER | jq -r '.result.content[0].text'" \
    '[ "$result" == "" ]'

# 1.4 Чтение файла с UTF-8
test_case "1.4 Чтение файла с UTF-8" \
    "result=\$(echo '{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"view\",\"arguments\":{\"filename\":\"$TEST_DIR/utf8.txt\"}}}' | $SERVER | jq -r '.result.content[0].text') && [[ \"\$result\" == *\"Привет\"* ]] && [[ \"\$result\" == *\"🌍\"* ]]" \
    '[ $? -eq 0 ]'

# 1.5 Проверка формата ответа
test_case "1.5 Формат ответа (объект с content как массив)" \
    "echo '{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"view\",\"arguments\":{\"filename\":\"$TEST_DIR/test.txt\"}}}' | $SERVER | jq -e '.result.content != null and (.result.content | type) == \"array\"'" \
    '[ $? -eq 0 ]'

echo ""
echo "2. Тесты с arguments как строкой JSON:"
echo ""

# 2.1 Чтение обычного файла (arguments как строка)
test_case "2.1 Чтение с arguments как строкой" \
    "echo '{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"view\",\"arguments\":\"{\\\"filename\\\":\\\"$TEST_DIR/test.txt\\\"}\"}}' | $SERVER | jq -r '.result.content[0].text'" \
    '[ "$result" == "Hello, World!" ]'

# 2.2 Чтение многострочного файла (arguments как строка)
test_case "2.2 Многострочный файл (arguments как строка)" \
    "result=\$(echo '{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"view\",\"arguments\":\"{\\\"filename\\\":\\\"$TEST_DIR/multiline.txt\\\"}\"}}' | $SERVER | jq -r '.result.content[0].text') && [[ \"\$result\" == *\"Line 1\"* ]] && [[ \"\$result\" == *\"Line 2\"* ]] && [[ \"\$result\" == *\"Line 3\"* ]]" \
    '[ $? -eq 0 ]'

# 2.3 Чтение пустого файла (arguments как строка)
test_case "2.3 Пустой файл (arguments как строка)" \
    "echo '{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"view\",\"arguments\":\"{\\\"filename\\\":\\\"$TEST_DIR/empty.txt\\\"}\"}}' | $SERVER | jq -r '.result.content[0].text'" \
    '[ "$result" == "" ]'

# 2.4 Чтение файла с UTF-8 (arguments как строка)
test_case "2.4 UTF-8 файл (arguments как строка)" \
    "result=\$(echo '{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"view\",\"arguments\":\"{\\\"filename\\\":\\\"$TEST_DIR/utf8.txt\\\"}\"}}' | $SERVER | jq -r '.result.content[0].text') && [[ \"\$result\" == *\"Привет\"* ]] && [[ \"\$result\" == *\"🌍\"* ]]" \
    '[ $? -eq 0 ]'

echo ""
echo "3. Тесты обработки ошибок:"
echo ""

# 3.1 Чтение несуществующего файла
test_case "3.1 Несуществующий файл" \
    "echo '{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"view\",\"arguments\":{\"filename\":\"$TEST_DIR/nonexistent.txt\"}}}' | $SERVER | jq -e '.error != null'" \
    '[ $? -eq 0 ]'

# 3.2 Несуществующий файл (arguments как строка)
test_case "3.2 Несуществующий файл (arguments как строка)" \
    "echo '{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"view\",\"arguments\":\"{\\\"filename\\\":\\\"$TEST_DIR/nonexistent2.txt\\\"}\"}}' | $SERVER | jq -e '.error != null'" \
    '[ $? -eq 0 ]'

# 3.3 Отсутствие обязательного параметра filename
test_case "3.3 Отсутствие filename" \
    "echo '{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"view\",\"arguments\":{}}}' | $SERVER | jq -e '.error != null'" \
    '[ $? -eq 0 ]'

# 3.4 Некорректный JSON в arguments
test_case "3.4 Некорректный JSON в arguments" \
    "echo '{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"view\",\"arguments\":\"{invalid json}\"}}' | $SERVER | jq -e '.error != null'" \
    '[ $? -eq 0 ]'

echo ""
echo "4. Тесты совместимости с read_file:"
echo ""

# 4.1 Сравнение результатов view и read_file
test_case "4.1 Одинаковый результат view и read_file" \
    "result1=\$(echo '{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"view\",\"arguments\":{\"filename\":\"$TEST_DIR/test.txt\"}}}' | $SERVER | jq -r '.result.content[0].text') && result2=\$(echo '{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"read_file\",\"arguments\":{\"filename\":\"$TEST_DIR/test.txt\"}}}' | $SERVER | jq -r '.result.content[0].text') && [ \"\$result1\" == \"\$result2\" ]" \
    '[ $? -eq 0 ]'

# 4.2 Сравнение формата ответа
test_case "4.2 Одинаковый формат ответа" \
    "result1=\$(echo '{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"view\",\"arguments\":{\"filename\":\"$TEST_DIR/test.txt\"}}}' | $SERVER | jq -c '.result') && result2=\$(echo '{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"read_file\",\"arguments\":{\"filename\":\"$TEST_DIR/test.txt\"}}}' | $SERVER | jq -c '.result') && [ \"\$result1\" == \"\$result2\" ]" \
    '[ $? -eq 0 ]'

# 4.3 Сравнение обработки ошибок
test_case "4.3 Одинаковая обработка ошибок" \
    "result1=\$(echo '{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"view\",\"arguments\":{\"filename\":\"$TEST_DIR/nonexistent.txt\"}}}' | $SERVER | jq -c '.error') && result2=\$(echo '{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"read_file\",\"arguments\":{\"filename\":\"$TEST_DIR/nonexistent.txt\"}}}' | $SERVER | jq -c '.error') && [ \"\$result1\" == \"\$result2\" ]" \
    '[ $? -eq 0 ]'

echo ""
echo "5. Тесты вложенных директорий:"
echo ""

# 5.1 Файл во вложенной директории (объект)
test_case "5.1 Файл во вложенной директории (объект)" \
    "echo '{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"view\",\"arguments\":{\"filename\":\"$TEST_DIR/nested/deep/file.txt\"}}}' | $SERVER | jq -r '.result.content[0].text'" \
    '[ "$result" == "Nested content" ]'

# 5.2 Файл во вложенной директории (строка)
test_case "5.2 Файл во вложенной директории (строка)" \
    "echo '{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"view\",\"arguments\":\"{\\\"filename\\\":\\\"$TEST_DIR/nested/deep/file.txt\\\"}\"}}' | $SERVER | jq -r '.result.content[0].text'" \
    '[ "$result" == "Nested content" ]'

# Очистка
rm -rf $TEST_DIR

# Print results and exit
print_test_results
exit $?
