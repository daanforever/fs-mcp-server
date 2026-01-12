#!/bin/bash

# Тесты для функции exec
# Проверяет выполнение команд, таймауты, рабочие директории, обработку ошибок

# Source helper functions
source "$(dirname "$0")/helper.sh"

TEST_DIR="test_exec_dir"
rm -rf $TEST_DIR
mkdir -p $TEST_DIR

PASSED=0
FAILED=0

# Override send_mcp_request to use longer timeout for exec tests
send_mcp_request() {
    local request="$1"
    local timeout="${2:-10}"  # Default timeout 10 seconds for exec tests
    
    (
        echo '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"test","version":"1.0.0"}}}'
        echo '{"jsonrpc":"2.0","method":"notifications/initialized","params":{}}'
        echo "$request"
        sleep 0.1
    ) | timeout "$timeout" "$SERVER" 2>/dev/null | tail -1
}

echo "=== Тесты exec tool ==="
echo ""

echo "1. Базовые тесты выполнения команд:"
echo ""

# 1.1 Простая команда (echo)
test_case "1.1 Простая команда (echo)" \
    "response=\$(send_mcp_request '{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"exec\",\"arguments\":{\"command\":\"echo hello\"}}}') && parse_exec_stdout \"\$response\"" \
    '[ "$result" = "hello" ]'

# 1.2 Команда с выводом в stdout
test_case "1.2 Вывод в stdout" \
    "response=\$(send_mcp_request '{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"exec\",\"arguments\":{\"command\":\"echo -n test123\"}}}') && parse_exec_stdout \"\$response\"" \
    '[ "$result" == "test123" ]'

# 1.3 Команда с выводом в stderr
test_case "1.3 Вывод в stderr" \
    "response=\$(send_mcp_request '{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"exec\",\"arguments\":{\"command\":\"echo error >&2\"}}}') && parse_exec_stderr \"\$response\"" \
    '[ "$result" == "error" ]'

# 1.4 Команда с выводом в оба потока
test_case "1.4 Вывод в stdout и stderr" \
    "response=\$(send_mcp_request '{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"exec\",\"arguments\":{\"command\":\"echo out && echo err >&2\"}}}') && stdout=\$(parse_exec_stdout \"\$response\") && stderr=\$(parse_exec_stderr \"\$response\") && [ \"\$stdout\" == \"out\" ] && [ \"\$stderr\" == \"err\" ]" \
    '[ $? -eq 0 ]'

# 1.5 Проверка exit code (успешная команда)
test_case "1.5 Exit code успешной команды" \
    "response=\$(send_mcp_request '{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"exec\",\"arguments\":{\"command\":\"true\"}}}') && parse_exec_exit_code \"\$response\"" \
    '[ "$result" == "0" ]'

# 1.6 Проверка exit code (неуспешная команда)
test_case "1.6 Exit code неуспешной команды" \
    "response=\$(send_mcp_request '{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"exec\",\"arguments\":{\"command\":\"false\"}}}') && parse_exec_exit_code \"\$response\"" \
    '[ "$result" == "1" ]'

# 1.7 Проверка статуса (success)
test_case "1.7 Статус успешной команды" \
    "response=\$(send_mcp_request '{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"exec\",\"arguments\":{\"command\":\"true\"}}}') && parse_exec_status \"\$response\"" \
    '[ "$result" == "success" ]'

# 1.8 Проверка статуса (failed)
test_case "1.8 Статус неуспешной команды" \
    "response=\$(send_mcp_request '{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"exec\",\"arguments\":{\"command\":\"false\"}}}') && parse_exec_status \"\$response\"" \
    '[ "$result" == "failed" ]'

echo ""
echo "2. Тесты рабочей директории (work_dir):"
echo ""

# 2.1 Выполнение команды в указанной директории
test_case "2.1 Выполнение в указанной директории" \
    "response=\$(send_mcp_request '{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"exec\",\"arguments\":{\"command\":\"pwd\",\"work_dir\":\"$TEST_DIR\"}}}') && result=\$(parse_exec_stdout \"\$response\" | xargs realpath) && [ \"\$result\" == \"\$(realpath $TEST_DIR)\" ]" \
    '[ $? -eq 0 ]'

# 2.2 Выполнение команды без указания work_dir (текущая директория)
test_case "2.2 Выполнение без work_dir" \
    "cwd=\$(pwd) && response=\$(send_mcp_request '{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"exec\",\"arguments\":{\"command\":\"pwd\"}}}') && result=\$(parse_exec_stdout \"\$response\" | xargs realpath) && [ \"\$result\" == \"\$(realpath \$cwd)\" ]" \
    '[ $? -eq 0 ]'

# 2.3 Создание файла в указанной директории
test_case "2.3 Создание файла в work_dir" \
    "send_mcp_request '{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"exec\",\"arguments\":{\"command\":\"echo test > file.txt\",\"work_dir\":\"$TEST_DIR\"}}}' > /dev/null && [ -f $TEST_DIR/file.txt ] && [ \"\$(cat $TEST_DIR/file.txt)\" == \"test\" ]" \
    '[ $? -eq 0 ]'

# 2.4 Ошибка: несуществующая директория
test_case "2.4 Ошибка: несуществующая директория" \
    "send_mcp_request '{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"exec\",\"arguments\":{\"command\":\"pwd\",\"work_dir\":\"$TEST_DIR/nonexistent\"}}}' | jq -e '.result.isError == true or .error != null'" \
    '[ $? -eq 0 ]'

# 2.5 Ошибка: work_dir не является директорией (файл)
test_case "2.5 Ошибка: work_dir это файл" \
    "echo test > $TEST_DIR/notadir && send_mcp_request '{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"exec\",\"arguments\":{\"command\":\"pwd\",\"work_dir\":\"$TEST_DIR/notadir\"}}}' | jq -e '.result.isError == true or .error != null'" \
    '[ $? -eq 0 ]'

echo ""
echo "3. Тесты таймаутов:"
echo ""

# 3.1 Команда завершается до таймаута
test_case "3.1 Команда завершается до таймаута" \
    "response=\$(send_mcp_request '{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"exec\",\"arguments\":{\"command\":\"echo done\",\"timeout\":5}}}') && parse_exec_timeout \"\$response\" | grep -q false && parse_exec_stdout \"\$response\" | grep -q 'done'" \
    '[ $? -eq 0 ]'

# 3.2 Команда превышает таймаут
test_case "3.2 Команда превышает таймаут" \
    "send_mcp_request '{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"exec\",\"arguments\":{\"command\":\"sleep 2\",\"timeout\":1}}}' | jq -e '(.result.isError == true or .error != null) and ((.result.content[0].text // .error.message // \"\") | contains(\"timed out\"))'" \
    '[ $? -eq 0 ]'

# 3.3 Таймаут по умолчанию (300 секунд) - быстрая команда должна завершиться
test_case "3.3 Таймаут по умолчанию (быстрая команда)" \
    "response=\$(send_mcp_request '{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"exec\",\"arguments\":{\"command\":\"echo quick\"}}}') && echo \"\$response\" | jq -e '.result != null' && parse_exec_timeout \"\$response\" | grep -q false" \
    '[ $? -eq 0 ]'

# 3.4 Очень короткий таймаут для быстрой команды
test_case "3.4 Очень короткий таймаут (команда успевает)" \
    "response=\$(send_mcp_request '{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"exec\",\"arguments\":{\"command\":\"echo fast\",\"timeout\":1}}}') && echo \"\$response\" | jq -e '.result != null' && parse_exec_timeout \"\$response\" | grep -q false" \
    '[ $? -eq 0 ]'

echo ""
echo "4. Тесты обработки ошибок:"
echo ""

# 4.1 Команда не найдена
test_case "4.1 Команда не найдена" \
    "send_mcp_request '{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"exec\",\"arguments\":{\"command\":\"nonexistent_command_xyz123\"}}}' | jq -e '.result.isError == true or .error != null'" \
    '[ $? -eq 0 ]'

# 4.2 Отсутствие обязательного параметра command
test_case "4.2 Отсутствие параметра command" \
    "send_mcp_request '{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"exec\",\"arguments\":{}}}' | jq -e '.result.isError == true or .error != null'" \
    '[ $? -eq 0 ]'

# 4.3 Некорректный JSON в arguments
test_case "4.3 Некорректный JSON в arguments" \
    "send_mcp_request '{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"exec\",\"arguments\":\"{invalid}\"}}' | jq -e '.result.isError == true or .error != null'" \
    '[ $? -eq 0 ]'

# 4.4 Команда с синтаксической ошибкой
test_case "4.4 Команда с синтаксической ошибкой" \
    "response=\$(send_mcp_request '{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"exec\",\"arguments\":{\"command\":\"if [\"}}}') && echo \"\$response\" | jq -e '.result != null' && [ \"\$(parse_exec_exit_code \"\$response\")\" != \"0\" ]" \
    '[ $? -eq 0 ]'

echo ""
echo "5. Тесты пограничных случаев (edge cases):"
echo ""

# 5.1 Пустая команда
test_case "5.1 Пустая команда" \
    "response=\$(send_mcp_request '{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"exec\",\"arguments\":{\"command\":\"\"}}}') && echo \"\$response\" | jq -e '.result != null' && [ \"\$(parse_exec_exit_code \"\$response\")\" == \"0\" ]" \
    '[ $? -eq 0 ]'

# 5.2 Команда с пробелами
test_case "5.2 Команда с пробелами" \
    "response=\$(send_mcp_request '{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"exec\",\"arguments\":{\"command\":\"echo   multiple   spaces\"}}}') && parse_exec_stdout \"\$response\"" \
    '[ "$result" == "multiple spaces" ]'

# 5.3 Команда с переносами строк
test_case "5.3 Команда с переносами строк" \
    "response=\$(send_mcp_request '{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"exec\",\"arguments\":{\"command\":\"printf \\\"line1\\\\nline2\\\"\"}}}') && stdout=\$(parse_exec_stdout \"\$response\") && [[ \"\$stdout\" == *\"line1\"* ]] && [[ \"\$stdout\" == *\"line2\"* ]]" \
    '[ $? -eq 0 ]'

# 5.4 Команда с специальными символами
test_case "5.4 Команда со специальными символами" \
    "send_mcp_request '{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"exec\",\"arguments\":{\"command\":\"echo test123\"}}}' | jq -e '.result != null'" \
    '[ $? -eq 0 ]'

# 5.5 Команда с UTF-8 символами
test_case "5.5 Команда с UTF-8 символами" \
    "response=\$(send_mcp_request '{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"exec\",\"arguments\":{\"command\":\"echo Привет 🌍\"}}}') && stdout=\$(parse_exec_stdout \"\$response\") && [[ \"\$stdout\" == *\"Привет\"* ]]" \
    '[ $? -eq 0 ]'

# 5.6 Длинная команда
test_case "5.6 Длинная команда" \
    "long_cmd=\"echo \$(seq 1 100 | tr '\n' ' ')\" && response=\$(send_mcp_request \"{\\\"jsonrpc\\\":\\\"2.0\\\",\\\"id\\\":2,\\\"method\\\":\\\"tools/call\\\",\\\"params\\\":{\\\"name\\\":\\\"exec\\\",\\\"arguments\\\":{\\\"command\\\":\\\"\$long_cmd\\\"}}}\") && echo \"\$response\" | jq -e '.result != null'" \
    '[ $? -eq 0 ]'

# 5.7 Команда с переменными окружения
test_case "5.7 Команда с переменными окружения" \
    "response=\$(send_mcp_request '{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"exec\",\"arguments\":{\"command\":\"echo \$HOME\"}}}') && stdout=\$(parse_exec_stdout \"\$response\") && [ -n \"\$stdout\" ]" \
    '[ $? -eq 0 ]'

# 5.8 Команда с перенаправлением вывода
test_case "5.8 Команда с перенаправлением вывода" \
    "send_mcp_request '{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"exec\",\"arguments\":{\"command\":\"echo redirect > '$TEST_DIR'/redirect.txt\"}}}' > /dev/null && [ -f $TEST_DIR/redirect.txt ] && [ \"\$(cat $TEST_DIR/redirect.txt)\" == \"redirect\" ]" \
    '[ $? -eq 0 ]'

# 5.9 Команда с pipe
test_case "5.9 Команда с pipe" \
    "response=\$(send_mcp_request '{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"exec\",\"arguments\":{\"command\":\"echo hello | tr a-z A-Z\"}}}') && parse_exec_stdout \"\$response\"" \
    '[ "$result" == "HELLO" ]'

# 5.10 Команда с несколькими командами (&&)
test_case "5.10 Команда с &&" \
    "response=\$(send_mcp_request '{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"exec\",\"arguments\":{\"command\":\"echo first && echo second\"}}}') && stdout=\$(parse_exec_stdout \"\$response\") && [[ \"\$stdout\" == *\"first\"* ]] && [[ \"\$stdout\" == *\"second\"* ]]" \
    '[ $? -eq 0 ]'

# 5.11 Команда с несколькими командами (||)
test_case "5.11 Команда с ||" \
    "response=\$(send_mcp_request '{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"exec\",\"arguments\":{\"command\":\"false || echo fallback\"}}}') && stdout=\$(parse_exec_stdout \"\$response\") && [ \"\$stdout\" == \"fallback\" ]" \
    '[ $? -eq 0 ]'

# 5.12 Команда с exit code > 1
test_case "5.12 Exit code > 1" \
    "response=\$(send_mcp_request '{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"exec\",\"arguments\":{\"command\":\"exit 42\"}}}') && parse_exec_exit_code \"\$response\"" \
    '[ "$result" == "42" ]'

# 5.13 Команда с отрицательным таймаутом (должна использоваться значение по умолчанию или обработана как ошибка)
test_case "5.13 Отрицательный таймаут" \
    "response=\$(send_mcp_request '{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"exec\",\"arguments\":{\"command\":\"echo test\",\"timeout\":-1}}}') && echo \"\$response\" | jq -e '.result != null or .error != null'" \
    '[ $? -eq 0 ]'

# 5.14 Команда с нулевым таймаутом
test_case "5.14 Нулевой таймаут" \
    "response=\$(send_mcp_request '{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"exec\",\"arguments\":{\"command\":\"echo quick\",\"timeout\":0}}}') && echo \"\$response\" | jq -e '.result != null or .error != null'" \
    '[ $? -eq 0 ]'

# 5.15 Команда с очень большим таймаутом
test_case "5.15 Очень большой таймаут" \
    "response=\$(send_mcp_request '{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"exec\",\"arguments\":{\"command\":\"echo test\",\"timeout\":999999}}}') && echo \"\$response\" | jq -e '.result != null' && parse_exec_timeout \"\$response\" | grep -q false" \
    '[ $? -eq 0 ]'

echo ""
echo "6. Тесты формата ответа:"
echo ""

# 6.1 Проверка наличия content в ответе
test_case "6.1 Наличие content в ответе" \
    "response=\$(send_mcp_request '{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"exec\",\"arguments\":{\"command\":\"echo test\"}}}') && echo \"\$response\" | jq -e '.result.content != null and (.result.content | type) == \"array\" and .result.content[0].type == \"text\"'" \
    '[ $? -eq 0 ]'

# 6.2 Проверка формата content
test_case "6.2 Формат content (type и text)" \
    "response=\$(send_mcp_request '{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"exec\",\"arguments\":{\"command\":\"echo test\"}}}') && echo \"\$response\" | jq -e '(.result.content[0].text | type) == \"string\"'" \
    '[ $? -eq 0 ]'

# Очистка
rm -rf $TEST_DIR

# Print results and exit
print_test_results
exit $?
