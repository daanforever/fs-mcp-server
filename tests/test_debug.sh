#!/bin/bash

# Тесты для проверки флага --debug
# Проверяет, что полные запросы и ответы записываются в mcp.log

# Source helper functions
source "$(dirname "$0")/helper.sh"

TEST_DIR="tmp/test_debug_dir"
LOG_FILE="mcp.log"
mkdir -p tmp
rm -rf $TEST_DIR
rm -f $LOG_FILE
mkdir -p $TEST_DIR

PASSED=0
FAILED=0

echo "=== Тесты --debug флага ==="
echo ""

# Функция для отправки запроса с debug-сервером
send_debug_request() {
    local request="$1"
    local timeout="${2:-2}"
    
    # Запускаем сервер с --debug и отправляем запрос
    (
        echo '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"test","version":"1.0.0"}}}'
        echo '{"jsonrpc":"2.0","method":"notifications/initialized","params":{}}'
        echo "$request"
        sleep 0.1
    ) | timeout "$timeout" "$SERVER" --debug 2>/dev/null >/dev/null
    # Даем время на запись в лог после завершения процесса
    sleep 0.5
}

# Проверка наличия строки в логе
check_log_contains() {
    local pattern="$1"
    local description="$2"
    
    echo -n "  $description: "
    if grep -q "$pattern" "$LOG_FILE" 2>/dev/null; then
        echo "PASS"
        ((PASSED++))
        return 0
    else
        echo "FAIL"
        echo "    Pattern not found: $pattern"
        ((FAILED++))
        return 1
    fi
}

# Проверка наличия JSON структуры в логе
check_log_has_json() {
    local tool_name="$1"
    local json_type="$2"  # REQUEST or RESPONSE
    
    echo -n "  $tool_name $json_type в логе: "
    
    # Ищем строку с логом (например: "edit_file REQUEST" или "edit_file RESPONSE")
    # slog text handler форматирует как: msg="tool_name REQUEST" request="..."
    if grep -q "$tool_name $json_type" "$LOG_FILE" 2>/dev/null; then
        # Проверяем, что есть поле request= или response= (slog формат)
        if grep "$tool_name $json_type" "$LOG_FILE" | grep -qE "(request=|response=)" 2>/dev/null; then
            echo "PASS"
            ((PASSED++))
            return 0
        else
            echo "FAIL (JSON структура не найдена)"
            ((FAILED++))
            return 1
        fi
    else
        echo "FAIL (строка лога не найдена)"
        ((FAILED++))
        return 1
    fi
}

# Проверка, что в логе есть структурированные данные (JSON-подобные)
check_log_has_structured_data() {
    local tool_name="$1"
    local json_type="$2"
    
    echo -n "  $tool_name $json_type содержит структурированные данные: "
    
    # Извлекаем строку лога
    local log_line=$(grep "$tool_name $json_type" "$LOG_FILE" 2>/dev/null | head -1)
    
    if [ -z "$log_line" ]; then
        echo "FAIL (строка лога не найдена)"
        ((FAILED++))
        return 1
    fi
    
    # Проверяем наличие структурированных данных
    # slog text handler форматирует как request="..." или response="..."
    local has_structure=false
    
    # Для REQUEST ищем: name, arguments, params в JSON строке
    if [ "$json_type" = "REQUEST" ]; then
        if echo "$log_line" | grep -qE "(\"name\"|\"arguments\"|\"params\")" 2>/dev/null; then
            has_structure=true
        fi
    fi
    
    # Для RESPONSE ищем: content в JSON строке
    if [ "$json_type" = "RESPONSE" ]; then
        if echo "$log_line" | grep -qE "\"content\"" 2>/dev/null; then
            has_structure=true
        fi
    fi
    
    if [ "$has_structure" = true ]; then
        echo "PASS"
        ((PASSED++))
        return 0
    else
        echo "FAIL (структурированные данные не найдены)"
        ((FAILED++))
        return 1
    fi
}

echo "1. Проверка создания лог-файла:"
echo ""

# Создаем тестовый файл для успешного запроса
echo "Test content" > $TEST_DIR/test.txt

# Выполняем простой запрос для создания лога
send_debug_request '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"read_file","arguments":{"filename":"'$TEST_DIR'/test.txt"}}}' >/dev/null 2>&1

test_case "1.1 Лог-файл создан" \
    "[ -f \"$LOG_FILE\" ]" \
    '[ $? -eq 0 ]'

test_case "1.2 Лог-файл не пустой" \
    "[ -s \"$LOG_FILE\" ]" \
    '[ $? -eq 0 ]'

test_case "1.3 Лог содержит стартовое сообщение" \
    "grep -q 'MCP Server started in debug mode' $LOG_FILE" \
    '[ $? -eq 0 ]'

echo ""
echo "2. Проверка логирования запросов и ответов для edit_file:"
echo ""

# Выполняем edit_file запрос (не очищаем лог, чтобы сохранить предыдущие записи)
send_debug_request '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"edit_file","arguments":{"filename":"'$TEST_DIR'/test2.txt","content":"Test content 2"}}}' >/dev/null 2>&1

check_log_has_json "edit_file" "REQUEST"
check_log_has_json "edit_file" "RESPONSE"
check_log_contains "edit_file called" "edit_file called в логе"
check_log_contains "edit_file completed" "edit_file completed в логе"

echo ""
echo "3. Проверка логирования запросов и ответов для read_file:"
echo ""

# Выполняем read_file запрос
send_debug_request '{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"read_file","arguments":{"filename":"'$TEST_DIR'/test2.txt"}}}' >/dev/null 2>&1

check_log_has_json "read_file" "REQUEST"
check_log_has_json "read_file" "RESPONSE"
check_log_contains "read_file called" "read_file called в логе"
check_log_contains "read_file completed" "read_file completed в логе"

echo ""
echo "4. Проверка логирования запросов и ответов для exec:"
echo ""

# Выполняем exec запрос
send_debug_request '{"jsonrpc":"2.0","id":5,"method":"tools/call","params":{"name":"exec","arguments":{"command":"echo hello"}}}' >/dev/null 2>&1

check_log_has_json "exec" "REQUEST"
check_log_has_json "exec" "RESPONSE"
check_log_contains "exec called" "exec called в логе"
check_log_contains "exec completed" "exec completed в логе"

echo ""
echo "5. Проверка структурированных данных в логах:"
echo ""

check_log_has_structured_data "edit_file" "REQUEST"
check_log_has_structured_data "edit_file" "RESPONSE"
check_log_has_structured_data "read_file" "REQUEST"
check_log_has_structured_data "read_file" "RESPONSE"
check_log_has_structured_data "exec" "REQUEST"
check_log_has_structured_data "exec" "RESPONSE"

echo ""
echo "6. Проверка содержимого запросов в логе:"
echo ""

# Проверяем, что в REQUEST есть ожидаемые поля
test_case "6.1 edit_file REQUEST содержит name" \
    "grep 'edit_file REQUEST' $LOG_FILE | grep -q '\"name\"'" \
    '[ $? -eq 0 ]'

test_case "6.2 read_file REQUEST содержит filename" \
    "grep 'read_file REQUEST' $LOG_FILE | grep -q 'filename'" \
    '[ $? -eq 0 ]'

test_case "6.3 exec REQUEST содержит command" \
    "grep 'exec REQUEST' $LOG_FILE | grep -q 'command'" \
    '[ $? -eq 0 ]'

echo ""
echo "7. Проверка содержимого ответов в логе:"
echo ""

# Проверяем, что в RESPONSE есть ожидаемые поля
test_case "7.1 edit_file RESPONSE содержит content" \
    "grep 'edit_file RESPONSE' $LOG_FILE | grep -q '\"content\"'" \
    '[ $? -eq 0 ]'

test_case "7.2 read_file RESPONSE содержит content" \
    "grep 'read_file RESPONSE' $LOG_FILE | grep -q '\"content\"'" \
    '[ $? -eq 0 ]'

test_case "7.3 exec RESPONSE содержит content" \
    "grep 'exec RESPONSE' $LOG_FILE | grep -q '\"content\"'" \
    '[ $? -eq 0 ]'

echo ""
echo "8. Проверка отсутствия логов без --debug:"
echo ""

# Очищаем лог
rm -f $LOG_FILE

# Выполняем запрос БЕЗ --debug
send_mcp_request '{"jsonrpc":"2.0","id":6,"method":"tools/call","params":{"name":"read_file","arguments":{"filename":"'$TEST_DIR'/test.txt"}}}' >/dev/null 2>&1

sleep 0.2

test_case "8.1 Лог-файл не создан без --debug" \
    "[ ! -f \"$LOG_FILE\" ]" \
    '[ $? -eq 0 ]'

# Очистка
rm -rf $TEST_DIR
rm -f $LOG_FILE

# Print results and exit
print_test_results
exit $?
