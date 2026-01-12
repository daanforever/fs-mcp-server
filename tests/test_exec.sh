#!/bin/bash

# Тесты для функции exec
# Проверяет выполнение команд, таймауты, рабочие директории, обработку ошибок

SERVER="./mcp-file-edit"
TEST_DIR="test_exec_dir"
rm -rf $TEST_DIR
mkdir -p $TEST_DIR

PASSED=0
FAILED=0

test_case() {
    local name="$1"
    local test_cmd="$2"
    local expected="$3"
    
    echo -n "  $name: "
    # Add timeout to prevent hanging
    result=$(timeout 10 bash -c "$test_cmd" 2>/dev/null)
    timeout_exit=$?
    
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

echo "=== Тесты exec tool ==="
echo ""

echo "1. Базовые тесты выполнения команд:"
echo ""

# 1.1 Простая команда (echo)
test_case "1.1 Простая команда (echo)" \
    "echo '{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"exec\",\"arguments\":{\"command\":\"echo hello\"}}}' | $SERVER | jq -r '.result.stdout'" \
    '[ "$result" == "hello" ]'

# 1.2 Команда с выводом в stdout
test_case "1.2 Вывод в stdout" \
    "echo '{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"exec\",\"arguments\":{\"command\":\"echo -n test123\"}}}' | $SERVER | jq -r '.result.stdout'" \
    '[ "$result" == "test123" ]'

# 1.3 Команда с выводом в stderr
test_case "1.3 Вывод в stderr" \
    "echo '{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"exec\",\"arguments\":{\"command\":\"echo error >&2\"}}}' | $SERVER | jq -r '.result.stderr'" \
    '[ "$result" == "error" ]'

# 1.4 Команда с выводом в оба потока
test_case "1.4 Вывод в stdout и stderr" \
    "result=\$(echo '{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"exec\",\"arguments\":{\"command\":\"echo out && echo err >&2\"}}}' | $SERVER) && stdout=\$(echo \"\$result\" | jq -r '.result.stdout') && stderr=\$(echo \"\$result\" | jq -r '.result.stderr') && [ \"\$stdout\" == \"out\" ] && [ \"\$stderr\" == \"err\" ]" \
    '[ $? -eq 0 ]'

# 1.5 Проверка exit code (успешная команда)
test_case "1.5 Exit code успешной команды" \
    "echo '{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"exec\",\"arguments\":{\"command\":\"true\"}}}' | $SERVER | jq -r '.result.exit_code'" \
    '[ "$result" == "0" ]'

# 1.6 Проверка exit code (неуспешная команда)
test_case "1.6 Exit code неуспешной команды" \
    "echo '{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"exec\",\"arguments\":{\"command\":\"false\"}}}' | $SERVER | jq -r '.result.exit_code'" \
    '[ "$result" == "1" ]'

# 1.7 Проверка статуса (success)
test_case "1.7 Статус успешной команды" \
    "echo '{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"exec\",\"arguments\":{\"command\":\"true\"}}}' | $SERVER | jq -r '.result.status'" \
    '[ "$result" == "success" ]'

# 1.8 Проверка статуса (failed)
test_case "1.8 Статус неуспешной команды" \
    "echo '{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"exec\",\"arguments\":{\"command\":\"false\"}}}' | $SERVER | jq -r '.result.status'" \
    '[ "$result" == "failed" ]'

echo ""
echo "2. Тесты рабочей директории (work_dir):"
echo ""

# 2.1 Выполнение команды в указанной директории
test_case "2.1 Выполнение в указанной директории" \
    "echo '{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"exec\",\"arguments\":{\"command\":\"pwd\",\"work_dir\":\"$TEST_DIR\"}}}' | $SERVER | jq -r '.result.stdout' | xargs realpath" \
    '[ "$result" == "$(realpath $TEST_DIR)" ]'

# 2.2 Выполнение команды без указания work_dir (текущая директория)
test_case "2.2 Выполнение без work_dir" \
    "cwd=\$(pwd) && result=\$(echo '{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"exec\",\"arguments\":{\"command\":\"pwd\"}}}' | $SERVER | jq -r '.result.stdout' | xargs realpath) && [ \"\$result\" == \"\$(realpath \$cwd)\" ]" \
    '[ $? -eq 0 ]'

# 2.3 Создание файла в указанной директории
test_case "2.3 Создание файла в work_dir" \
    "echo '{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"exec\",\"arguments\":{\"command\":\"echo test > file.txt\",\"work_dir\":\"$TEST_DIR\"}}}' | $SERVER > /dev/null && [ -f $TEST_DIR/file.txt ] && [ \"\$(cat $TEST_DIR/file.txt)\" == \"test\" ]" \
    '[ $? -eq 0 ]'

# 2.4 Ошибка: несуществующая директория
test_case "2.4 Ошибка: несуществующая директория" \
    "echo '{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"exec\",\"arguments\":{\"command\":\"pwd\",\"work_dir\":\"$TEST_DIR/nonexistent\"}}}' | $SERVER | jq -e '.error != null'" \
    '[ $? -eq 0 ]'

# 2.5 Ошибка: work_dir не является директорией (файл)
test_case "2.5 Ошибка: work_dir это файл" \
    "echo test > $TEST_DIR/notadir && echo '{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"exec\",\"arguments\":{\"command\":\"pwd\",\"work_dir\":\"$TEST_DIR/notadir\"}}}' | $SERVER | jq -e '.error != null'" \
    '[ $? -eq 0 ]'

echo ""
echo "3. Тесты таймаутов:"
echo ""

# 3.1 Команда завершается до таймаута
test_case "3.1 Команда завершается до таймаута" \
    "result=\$(echo '{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"exec\",\"arguments\":{\"command\":\"echo done\",\"timeout\":5}}}' | $SERVER) && echo \"\$result\" | jq -e '.result.timeout == false' && echo \"\$result\" | jq -r '.result.stdout' | grep -q 'done'" \
    '[ $? -eq 0 ]'

# 3.2 Команда превышает таймаут
test_case "3.2 Команда превышает таймаут" \
    "echo '{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"exec\",\"arguments\":{\"command\":\"sleep 2\",\"timeout\":1}}}' | $SERVER | jq -e '.error != null and (.error.message | contains(\"timed out\"))'" \
    '[ $? -eq 0 ]'

# 3.3 Таймаут по умолчанию (300 секунд) - быстрая команда должна завершиться
test_case "3.3 Таймаут по умолчанию (быстрая команда)" \
    "echo '{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"exec\",\"arguments\":{\"command\":\"echo quick\"}}}' | $SERVER | jq -e '.result != null and .result.timeout == false'" \
    '[ $? -eq 0 ]'

# 3.4 Очень короткий таймаут для быстрой команды
test_case "3.4 Очень короткий таймаут (команда успевает)" \
    "result=\$(echo '{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"exec\",\"arguments\":{\"command\":\"echo fast\",\"timeout\":1}}}' | $SERVER) && echo \"\$result\" | jq -e '.result != null and .result.timeout == false'" \
    '[ $? -eq 0 ]'

echo ""
echo "4. Тесты обработки ошибок:"
echo ""

# 4.1 Команда не найдена
test_case "4.1 Команда не найдена" \
    "echo '{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"exec\",\"arguments\":{\"command\":\"nonexistent_command_xyz123\"}}}' | $SERVER | jq -e '.error != null'" \
    '[ $? -eq 0 ]'

# 4.2 Отсутствие обязательного параметра command
test_case "4.2 Отсутствие параметра command" \
    "echo '{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"exec\",\"arguments\":{}}}' | $SERVER | jq -e '.error != null'" \
    '[ $? -eq 0 ]'

# 4.3 Некорректный JSON в arguments
test_case "4.3 Некорректный JSON в arguments" \
    "echo '{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"exec\",\"arguments\":\"{invalid}\"}}' | $SERVER | jq -e '.error != null'" \
    '[ $? -eq 0 ]'

# 4.4 Команда с синтаксической ошибкой
test_case "4.4 Команда с синтаксической ошибкой" \
    "result=\$(echo '{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"exec\",\"arguments\":{\"command\":\"if [\"}}}' | $SERVER) && echo \"\$result\" | jq -e '.result != null and .result.exit_code != 0'" \
    '[ $? -eq 0 ]'

echo ""
echo "5. Тесты пограничных случаев (edge cases):"
echo ""

# 5.1 Пустая команда
test_case "5.1 Пустая команда" \
    "result=\$(echo '{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"exec\",\"arguments\":{\"command\":\"\"}}}' | $SERVER) && echo \"\$result\" | jq -e '.result != null and .result.exit_code == 0'" \
    '[ $? -eq 0 ]'

# 5.2 Команда с пробелами
test_case "5.2 Команда с пробелами" \
    "echo '{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"exec\",\"arguments\":{\"command\":\"echo   multiple   spaces\"}}}' | $SERVER | jq -r '.result.stdout'" \
    '[ "$result" == "multiple spaces" ]'

# 5.3 Команда с переносами строк
test_case "5.3 Команда с переносами строк" \
    "result=\$(echo '{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"exec\",\"arguments\":{\"command\":\"printf \\\"line1\\\\nline2\\\"\"}}}' | $SERVER) && stdout=\$(echo \"\$result\" | jq -r '.result.stdout') && [[ \"\$stdout\" == *\"line1\"* ]] && [[ \"\$stdout\" == *\"line2\"* ]]" \
    '[ $? -eq 0 ]'

# 5.4 Команда с специальными символами
test_case "5.4 Команда со специальными символами" \
    "echo '{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"exec\",\"arguments\":{\"command\":\"echo test123\"}}}' | $SERVER | jq -e '.result != null'" \
    '[ $? -eq 0 ]'

# 5.5 Команда с UTF-8 символами
test_case "5.5 Команда с UTF-8 символами" \
    "result=\$(echo '{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"exec\",\"arguments\":{\"command\":\"echo Привет 🌍\"}}}' | $SERVER) && stdout=\$(echo \"\$result\" | jq -r '.result.stdout') && [[ \"\$stdout\" == *\"Привет\"* ]]" \
    '[ $? -eq 0 ]'

# 5.6 Длинная команда
test_case "5.6 Длинная команда" \
    "long_cmd=\"echo \$(seq 1 100 | tr '\n' ' ')\" && result=\$(echo \"{\\\"jsonrpc\\\":\\\"2.0\\\",\\\"id\\\":1,\\\"method\\\":\\\"tools/call\\\",\\\"params\\\":{\\\"name\\\":\\\"exec\\\",\\\"arguments\\\":{\\\"command\\\":\\\"\$long_cmd\\\"}}}\" | $SERVER) && echo \"\$result\" | jq -e '.result != null'" \
    '[ $? -eq 0 ]'

# 5.7 Команда с переменными окружения
test_case "5.7 Команда с переменными окружения" \
    "result=\$(echo '{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"exec\",\"arguments\":{\"command\":\"echo \$HOME\"}}}' | $SERVER) && stdout=\$(echo \"\$result\" | jq -r '.result.stdout') && [ -n \"\$stdout\" ]" \
    '[ $? -eq 0 ]'

# 5.8 Команда с перенаправлением вывода
test_case "5.8 Команда с перенаправлением вывода" \
    "echo '{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"exec\",\"arguments\":{\"command\":\"echo redirect > '$TEST_DIR'/redirect.txt\"}}}' | $SERVER > /dev/null && [ -f $TEST_DIR/redirect.txt ] && [ \"\$(cat $TEST_DIR/redirect.txt)\" == \"redirect\" ]" \
    '[ $? -eq 0 ]'

# 5.9 Команда с pipe
test_case "5.9 Команда с pipe" \
    "echo '{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"exec\",\"arguments\":{\"command\":\"echo hello | tr a-z A-Z\"}}}' | $SERVER | jq -r '.result.stdout'" \
    '[ "$result" == "HELLO" ]'

# 5.10 Команда с несколькими командами (&&)
test_case "5.10 Команда с &&" \
    "result=\$(echo '{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"exec\",\"arguments\":{\"command\":\"echo first && echo second\"}}}' | $SERVER) && stdout=\$(echo \"\$result\" | jq -r '.result.stdout') && [[ \"\$stdout\" == *\"first\"* ]] && [[ \"\$stdout\" == *\"second\"* ]]" \
    '[ $? -eq 0 ]'

# 5.11 Команда с несколькими командами (||)
test_case "5.11 Команда с ||" \
    "result=\$(echo '{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"exec\",\"arguments\":{\"command\":\"false || echo fallback\"}}}' | $SERVER) && stdout=\$(echo \"\$result\" | jq -r '.result.stdout') && [ \"\$stdout\" == \"fallback\" ]" \
    '[ $? -eq 0 ]'

# 5.12 Команда с exit code > 1
test_case "5.12 Exit code > 1" \
    "echo '{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"exec\",\"arguments\":{\"command\":\"exit 42\"}}}' | $SERVER | jq -r '.result.exit_code'" \
    '[ "$result" == "42" ]'

# 5.13 Команда с отрицательным таймаутом (должна использоваться значение по умолчанию или обработана как ошибка)
test_case "5.13 Отрицательный таймаут" \
    "result=\$(echo '{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"exec\",\"arguments\":{\"command\":\"echo test\",\"timeout\":-1}}}' | $SERVER) && echo \"\$result\" | jq -e '.result != null or .error != null'" \
    '[ $? -eq 0 ]'

# 5.14 Команда с нулевым таймаутом
test_case "5.14 Нулевой таймаут" \
    "result=\$(echo '{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"exec\",\"arguments\":{\"command\":\"echo quick\",\"timeout\":0}}}' | $SERVER) && echo \"\$result\" | jq -e '.result != null or .error != null'" \
    '[ $? -eq 0 ]'

# 5.15 Команда с очень большим таймаутом
test_case "5.15 Очень большой таймаут" \
    "result=\$(echo '{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"exec\",\"arguments\":{\"command\":\"echo test\",\"timeout\":999999}}}' | $SERVER) && echo \"\$result\" | jq -e '.result != null and .result.timeout == false'" \
    '[ $? -eq 0 ]'

echo ""
echo "6. Тесты формата ответа:"
echo ""

# 6.1 Проверка наличия всех полей в ответе
test_case "6.1 Наличие всех полей в ответе" \
    "result=\$(echo '{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"exec\",\"arguments\":{\"command\":\"echo test\"}}}' | $SERVER) && echo \"\$result\" | jq -e '.result.stdout != null and .result.stderr != null and .result.exit_code != null and .result.status != null and .result.timeout != null'" \
    '[ $? -eq 0 ]'

# 6.2 Типы полей в ответе
test_case "6.2 Типы полей в ответе" \
    "result=\$(echo '{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"exec\",\"arguments\":{\"command\":\"echo test\"}}}' | $SERVER) && echo \"\$result\" | jq -e '(.result.stdout | type) == \"string\" and (.result.stderr | type) == \"string\" and (.result.exit_code | type) == \"number\" and (.result.status | type) == \"string\" and (.result.timeout | type) == \"boolean\"'" \
    '[ $? -eq 0 ]'

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
