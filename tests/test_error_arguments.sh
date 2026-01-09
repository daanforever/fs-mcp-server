#!/bin/bash

# Тесты для проверки, что ошибки содержат переданные аргументы

echo "=== Тестирование ошибок с переданными аргументами ==="
echo ""

PASSED=0
FAILED=0

# Функция для проверки наличия received_arguments в ошибке
check_error_has_arguments() {
    local test_name="$1"
    local response="$2"
    local expected_arg="$3"
    
    echo "Тест: $test_name"
    
    # Проверяем наличие поля error.data.received_arguments
    if echo "$response" | jq -e '.error.data.received_arguments' > /dev/null 2>&1; then
        # Если указан ожидаемый аргумент, проверяем его наличие
        if [ -n "$expected_arg" ]; then
            if echo "$response" | jq -e ".error.data.received_arguments.$expected_arg" > /dev/null 2>&1; then
                echo "  ✓ PASS: Ошибка содержит received_arguments с $expected_arg"
                ((PASSED++))
            else
                echo "  ✗ FAIL: Ошибка не содержит $expected_arg в received_arguments"
                echo "  Ответ: $response"
                ((FAILED++))
            fi
        else
            echo "  ✓ PASS: Ошибка содержит received_arguments"
            ((PASSED++))
        fi
    else
        echo "  ✗ FAIL: Ошибка не содержит поле data.received_arguments"
        echo "  Ответ: $response"
        ((FAILED++))
    fi
    echo ""
}

# Тест 1: edit_file без обязательных параметров
echo "--- Тест 1: edit_file без обязательных параметров ---"
RESPONSE=$(echo '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"edit_file","arguments":{"filename":"test.txt"}}}' | ./mcp-file-edit)
check_error_has_arguments "edit_file без обязательных параметров" "$RESPONSE" "filename"
echo "$RESPONSE" | jq .

# Тест 2: edit_file с неправильными параметрами
echo "--- Тест 2: edit_file с неправильными параметрами ---"
RESPONSE=$(echo '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"edit_file","arguments":{"filename":"test.txt","wrong_param":"value"}}}' | ./mcp-file-edit)
check_error_has_arguments "edit_file с неправильными параметрами" "$RESPONSE" "wrong_param"
echo "$RESPONSE" | jq .

# Тест 3: edit_file с некорректным JSON в arguments
echo "--- Тест 3: edit_file с некорректным JSON в arguments ---"
RESPONSE=$(echo '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"edit_file","arguments":"{invalid json}"}}' | ./mcp-file-edit)
check_error_has_arguments "edit_file с некорректным JSON" "$RESPONSE"
echo "$RESPONSE" | jq .

# Тест 4: read_file без filename
echo "--- Тест 4: read_file без filename ---"
RESPONSE=$(echo '{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"read_file","arguments":{}}}' | ./mcp-file-edit)
check_error_has_arguments "read_file без filename" "$RESPONSE"
echo "$RESPONSE" | jq .

# Тест 5: read_file с некорректным JSON в arguments
echo "--- Тест 5: read_file с некорректным JSON в arguments ---"
RESPONSE=$(echo '{"jsonrpc":"2.0","id":5,"method":"tools/call","params":{"name":"read_file","arguments":"{invalid}"}}' | ./mcp-file-edit)
check_error_has_arguments "read_file с некорректным JSON" "$RESPONSE"
echo "$RESPONSE" | jq .

# Тест 6: read_file несуществующего файла (должна быть ошибка чтения с аргументами)
echo "--- Тест 6: read_file несуществующего файла ---"
RESPONSE=$(echo '{"jsonrpc":"2.0","id":6,"method":"tools/call","params":{"name":"read_file","arguments":{"filename":"nonexistent_file_12345.txt"}}}' | ./mcp-file-edit)
check_error_has_arguments "read_file несуществующего файла" "$RESPONSE" "filename"
echo "$RESPONSE" | jq .

# Тест 7: edit_file с несколькими неправильными параметрами
echo "--- Тест 7: edit_file с несколькими неправильными параметрами ---"
RESPONSE=$(echo '{"jsonrpc":"2.0","id":7,"method":"tools/call","params":{"name":"edit_file","arguments":{"filename":"test.txt","param1":"value1","param2":"value2"}}}' | ./mcp-file-edit)
check_error_has_arguments "edit_file с несколькими неправильными параметрами" "$RESPONSE" "param1"
echo "$RESPONSE" | jq .

# Тест 8: edit_file с пустым filename (должна быть ошибка валидации)
echo "--- Тест 8: edit_file с пустым filename ---"
RESPONSE=$(echo '{"jsonrpc":"2.0","id":8,"method":"tools/call","params":{"name":"edit_file","arguments":{"filename":"","content":"test"}}}' | ./mcp-file-edit)
# Этот тест может не вызвать ошибку валидации, но проверим наличие аргументов если ошибка есть
if echo "$RESPONSE" | jq -e '.error' > /dev/null 2>&1; then
    check_error_has_arguments "edit_file с пустым filename" "$RESPONSE" "filename"
else
    echo "  ℹ INFO: Ошибка не возникла (возможно, пустой filename допустим)"
fi
echo "$RESPONSE" | jq .

# Тест 9: Проверка значений аргументов в ошибке
echo "--- Тест 9: Проверка значений аргументов в ошибке ---"
RESPONSE=$(echo '{"jsonrpc":"2.0","id":9,"method":"tools/call","params":{"name":"edit_file","arguments":{"filename":"test.txt","custom_param":"custom_value","number":123}}}' | ./mcp-file-edit)
if echo "$RESPONSE" | jq -e '.error.data.received_arguments.custom_param == "custom_value"' > /dev/null 2>&1; then
    echo "  ✓ PASS: Значение custom_param корректно сохранено"
    ((PASSED++))
else
    echo "  ✗ FAIL: Значение custom_param не сохранено или неверно"
    ((FAILED++))
fi
if echo "$RESPONSE" | jq -e '.error.data.received_arguments.number == 123' > /dev/null 2>&1; then
    echo "  ✓ PASS: Значение number корректно сохранено"
    ((PASSED++))
else
    echo "  ✗ FAIL: Значение number не сохранено или неверно"
    ((FAILED++))
fi
echo "$RESPONSE" | jq .

# Итоги
echo "=== Итоги тестирования ==="
echo "Пройдено: $PASSED"
echo "Провалено: $FAILED"
TOTAL=$((PASSED + FAILED))
if [ $FAILED -eq 0 ]; then
    echo "✓ Все тесты пройдены успешно!"
    exit 0
else
    echo "✗ Некоторые тесты провалены"
    exit 1
fi

