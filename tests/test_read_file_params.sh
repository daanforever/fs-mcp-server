#!/bin/bash

# Тесты для новых параметров read_file
# Тестирует: start_line, end_line, encoding, line_numbers, skip_empty, max_lines, pattern

# Source helper functions
source "$(dirname "$0")/helper.sh"

TEST_DIR="tmp/test_read_params_dir"
mkdir -p tmp
rm -rf $TEST_DIR
mkdir -p $TEST_DIR

PASSED=0
FAILED=0

echo "=== Тесты новых параметров read_file ==="
echo ""

# Подготовка: создаем тестовые файлы
echo "Подготовка тестовых файлов..."
cat > $TEST_DIR/multiline.txt << 'EOF'
Line 1
Line 2
Line 3
Line 4
Line 5
EOF

cat > $TEST_DIR/mixed.txt << 'EOF'
First line
Second line

Fourth line (empty line above)
Fifth line
EOF

cat > $TEST_DIR/search.txt << 'EOF'
error: something went wrong
info: processing started
warning: low memory
error: another error
info: processing complete
EOF

echo "1. Тесты start_line и end_line:"
echo ""

# 1.1 Чтение с start_line
test_case "1.1 Чтение с start_line=2" \
    "send_mcp_request \"{\\\"jsonrpc\\\":\\\"2.0\\\",\\\"id\\\":2,\\\"method\\\":\\\"tools/call\\\",\\\"params\\\":{\\\"name\\\":\\\"read_file\\\",\\\"arguments\\\":{\\\"filename\\\":\\\"$TEST_DIR/multiline.txt\\\",\\\"start_line\\\":2}}}\" | jq -r '.result.content[0].text // empty'" \
    'echo "$result" | grep -q "Line 2" && echo "$result" | grep -q "Line 5" && ! echo "$result" | grep -q "Line 1"'

# 1.2 Чтение с end_line
test_case "1.2 Чтение с end_line=3" \
    "send_mcp_request \"{\\\"jsonrpc\\\":\\\"2.0\\\",\\\"id\\\":2,\\\"method\\\":\\\"tools/call\\\",\\\"params\\\":{\\\"name\\\":\\\"read_file\\\",\\\"arguments\\\":{\\\"filename\\\":\\\"$TEST_DIR/multiline.txt\\\",\\\"end_line\\\":3}}}\" | jq -r '.result.content[0].text // empty'" \
    'echo "$result" | grep -q "Line 1" && echo "$result" | grep -q "Line 3" && ! echo "$result" | grep -q "Line 4"'

# 1.3 Чтение с start_line и end_line
test_case "1.3 Чтение с start_line=2, end_line=4" \
    "send_mcp_request \"{\\\"jsonrpc\\\":\\\"2.0\\\",\\\"id\\\":2,\\\"method\\\":\\\"tools/call\\\",\\\"params\\\":{\\\"name\\\":\\\"read_file\\\",\\\"arguments\\\":{\\\"filename\\\":\\\"$TEST_DIR/multiline.txt\\\",\\\"start_line\\\":2,\\\"end_line\\\":4}}}\" | jq -r '.result.content[0].text // empty'" \
    'echo "$result" | grep -q "Line 2" && echo "$result" | grep -q "Line 4" && ! echo "$result" | grep -q "Line 1" && ! echo "$result" | grep -q "Line 5"'

# 1.4 Проверка граничных случаев - start_line за пределами файла
test_case "1.4 start_line за пределами файла (должен вернуть пустой результат)" \
    "send_mcp_request \"{\\\"jsonrpc\\\":\\\"2.0\\\",\\\"id\\\":2,\\\"method\\\":\\\"tools/call\\\",\\\"params\\\":{\\\"name\\\":\\\"read_file\\\",\\\"arguments\\\":{\\\"filename\\\":\\\"$TEST_DIR/multiline.txt\\\",\\\"start_line\\\":10}}}\" | jq -r '.result.content[0].text // empty'" \
    '[ "$result" == "" ]'

echo ""
echo "2. Тесты line_numbers:"
echo ""

# 2.1 Чтение с line_numbers
test_case "2.1 Чтение с line_numbers=true" \
    "send_mcp_request \"{\\\"jsonrpc\\\":\\\"2.0\\\",\\\"id\\\":2,\\\"method\\\":\\\"tools/call\\\",\\\"params\\\":{\\\"name\\\":\\\"read_file\\\",\\\"arguments\\\":{\\\"filename\\\":\\\"$TEST_DIR/multiline.txt\\\",\\\"line_numbers\\\":true}}}\" | jq -r '.result.content[0].text // empty'" \
    'echo "$result" | grep -q "1:" && echo "$result" | grep -q "2:" && echo "$result" | grep -q "3:"'

# 2.2 Чтение с line_numbers и start_line
test_case "2.2 Чтение с line_numbers=true и start_line=2" \
    "send_mcp_request \"{\\\"jsonrpc\\\":\\\"2.0\\\",\\\"id\\\":2,\\\"method\\\":\\\"tools/call\\\",\\\"params\\\":{\\\"name\\\":\\\"read_file\\\",\\\"arguments\\\":{\\\"filename\\\":\\\"$TEST_DIR/multiline.txt\\\",\\\"start_line\\\":2,\\\"line_numbers\\\":true}}}\" | jq -r '.result.content[0].text // empty'" \
    'echo "$result" | grep -q "2:" && echo "$result" | grep -q "3:" && ! echo "$result" | grep -q "^1:"'

echo ""
echo "3. Тесты skip_empty:"
echo ""

# 3.1 Чтение с skip_empty=true
test_case "3.1 Чтение с skip_empty=true" \
    "send_mcp_request \"{\\\"jsonrpc\\\":\\\"2.0\\\",\\\"id\\\":2,\\\"method\\\":\\\"tools/call\\\",\\\"params\\\":{\\\"name\\\":\\\"read_file\\\",\\\"arguments\\\":{\\\"filename\\\":\\\"$TEST_DIR/mixed.txt\\\",\\\"skip_empty\\\":true}}}\" | jq -r '.result.content[0].text // empty'" \
    'echo "$result" | grep -q "First line" && echo "$result" | grep -q "Fourth line" && ! echo "$result" | grep -q "^$"'

# 3.2 Проверка что пустые строки действительно пропущены
test_case "3.2 Проверка пропуска пустых строк" \
    "result=\$(send_mcp_request \"{\\\"jsonrpc\\\":\\\"2.0\\\",\\\"id\\\":2,\\\"method\\\":\\\"tools/call\\\",\\\"params\\\":{\\\"name\\\":\\\"read_file\\\",\\\"arguments\\\":{\\\"filename\\\":\\\"$TEST_DIR/mixed.txt\\\",\\\"skip_empty\\\":true}}}\" | jq -r '.result.content[0].text // empty') && lines=\$(echo \"\$result\" | grep -c . || echo 0) && [ \"\$lines\" -eq 4 ]" \
    '[ $? -eq 0 ]'

echo ""
echo "4. Тесты max_lines:"
echo ""

# 4.1 Чтение с max_lines
test_case "4.1 Чтение с max_lines=2" \
    "send_mcp_request \"{\\\"jsonrpc\\\":\\\"2.0\\\",\\\"id\\\":2,\\\"method\\\":\\\"tools/call\\\",\\\"params\\\":{\\\"name\\\":\\\"read_file\\\",\\\"arguments\\\":{\\\"filename\\\":\\\"$TEST_DIR/multiline.txt\\\",\\\"max_lines\\\":2}}}\" | jq -r '.result.content[0].text // empty'" \
    'result_lines=$(echo "$result" | grep -c . || echo 0) && [ "$result_lines" -eq 2 ]'

# 4.2 max_lines с start_line
test_case "4.2 max_lines=2 с start_line=2" \
    "send_mcp_request \"{\\\"jsonrpc\\\":\\\"2.0\\\",\\\"id\\\":2,\\\"method\\\":\\\"tools/call\\\",\\\"params\\\":{\\\"name\\\":\\\"read_file\\\",\\\"arguments\\\":{\\\"filename\\\":\\\"$TEST_DIR/multiline.txt\\\",\\\"start_line\\\":2,\\\"max_lines\\\":2}}}\" | jq -r '.result.content[0].text // empty'" \
    'result_lines=$(echo "$result" | grep -c . || echo 0) && [ "$result_lines" -eq 2 ] && [[ "$result" == *"Line 2"* ]]'

echo ""
echo "5. Тесты pattern (regex filter):"
echo ""

# 5.1 Чтение с pattern (поиск error)
test_case "5.1 Чтение с pattern=\"error\"" \
    "send_mcp_request \"{\\\"jsonrpc\\\":\\\"2.0\\\",\\\"id\\\":2,\\\"method\\\":\\\"tools/call\\\",\\\"params\\\":{\\\"name\\\":\\\"read_file\\\",\\\"arguments\\\":{\\\"filename\\\":\\\"$TEST_DIR/search.txt\\\",\\\"pattern\\\":\\\"error\\\"}}}\" | jq -r '.result.content[0].text // empty'" \
    'echo "$result" | grep -q "error" && ! echo "$result" | grep -q "info" && ! echo "$result" | grep -q "warning"'

# 5.2 Чтение с pattern (поиск info)
test_case "5.2 Чтение с pattern=\"info\"" \
    "send_mcp_request \"{\\\"jsonrpc\\\":\\\"2.0\\\",\\\"id\\\":2,\\\"method\\\":\\\"tools/call\\\",\\\"params\\\":{\\\"name\\\":\\\"read_file\\\",\\\"arguments\\\":{\\\"filename\\\":\\\"$TEST_DIR/search.txt\\\",\\\"pattern\\\":\\\"info\\\"}}}\" | jq -r '.result.content[0].text // empty'" \
    'echo "$result" | grep -q "info" && ! echo "$result" | grep -q "error"'

# 5.3 Проверка невалидного regex
test_case "5.3 Невалидный regex pattern (должна быть ошибка)" \
    "send_mcp_request \"{\\\"jsonrpc\\\":\\\"2.0\\\",\\\"id\\\":2,\\\"method\\\":\\\"tools/call\\\",\\\"params\\\":{\\\"name\\\":\\\"read_file\\\",\\\"arguments\\\":{\\\"filename\\\":\\\"$TEST_DIR/search.txt\\\",\\\"pattern\\\":\\\"[invalid\\\"}}}\" | jq -e '.result.isError == true or .error != null'" \
    '[ $? -eq 0 ]'

echo ""
echo "6. Тесты encoding:"
echo ""

# 6.1 Чтение с encoding=utf-8 (явно)
test_case "6.1 Чтение с encoding=utf-8" \
    "send_mcp_request \"{\\\"jsonrpc\\\":\\\"2.0\\\",\\\"id\\\":2,\\\"method\\\":\\\"tools/call\\\",\\\"params\\\":{\\\"name\\\":\\\"read_file\\\",\\\"arguments\\\":{\\\"filename\\\":\\\"$TEST_DIR/multiline.txt\\\",\\\"encoding\\\":\\\"utf-8\\\"}}}\" | jq -r '.result.content[0].text // empty'" \
    '[[ "$result" == *"Line 1"* ]]'

# 6.2 Проверка невалидной кодировки
test_case "6.2 Невалидная кодировка (должна быть ошибка)" \
    "send_mcp_request \"{\\\"jsonrpc\\\":\\\"2.0\\\",\\\"id\\\":2,\\\"method\\\":\\\"tools/call\\\",\\\"params\\\":{\\\"name\\\":\\\"read_file\\\",\\\"arguments\\\":{\\\"filename\\\":\\\"$TEST_DIR/multiline.txt\\\",\\\"encoding\\\":\\\"invalid-encoding\\\"}}}\" | jq -e '.result.isError == true or .error != null'" \
    '[ $? -eq 0 ]'

echo ""
echo "7. Тесты комбинаций параметров:"
echo ""

# 7.1 Комбинация start_line, end_line, line_numbers
test_case "7.1 start_line + end_line + line_numbers" \
    "send_mcp_request \"{\\\"jsonrpc\\\":\\\"2.0\\\",\\\"id\\\":2,\\\"method\\\":\\\"tools/call\\\",\\\"params\\\":{\\\"name\\\":\\\"read_file\\\",\\\"arguments\\\":{\\\"filename\\\":\\\"$TEST_DIR/multiline.txt\\\",\\\"start_line\\\":2,\\\"end_line\\\":4,\\\"line_numbers\\\":true}}}\" | jq -r '.result.content[0].text // empty'" \
    'echo "$result" | grep -q "2:" && echo "$result" | grep -q "4:" && ! echo "$result" | grep -q "^1:" && ! echo "$result" | grep -q "^5:"'

# 7.2 Комбинация pattern + skip_empty
test_case "7.2 pattern + skip_empty" \
    "send_mcp_request \"{\\\"jsonrpc\\\":\\\"2.0\\\",\\\"id\\\":2,\\\"method\\\":\\\"tools/call\\\",\\\"params\\\":{\\\"name\\\":\\\"read_file\\\",\\\"arguments\\\":{\\\"filename\\\":\\\"$TEST_DIR/search.txt\\\",\\\"pattern\\\":\\\"error\\\",\\\"skip_empty\\\":true}}}\" | jq -r '.result.content[0].text // empty'" \
    'echo "$result" | grep -q "error" && ! echo "$result" | grep -q "info"'

# 7.3 Комбинация всех параметров
test_case "7.3 Комбинация всех параметров" \
    "send_mcp_request \"{\\\"jsonrpc\\\":\\\"2.0\\\",\\\"id\\\":2,\\\"method\\\":\\\"tools/call\\\",\\\"params\\\":{\\\"name\\\":\\\"read_file\\\",\\\"arguments\\\":{\\\"filename\\\":\\\"$TEST_DIR/search.txt\\\",\\\"start_line\\\":1,\\\"end_line\\\":5,\\\"pattern\\\":\\\"error\\\",\\\"line_numbers\\\":true,\\\"skip_empty\\\":true}}}\" | jq -r '.result.content[0].text // empty'" \
    'echo "$result" | grep -q "error" && echo "$result" | grep -q ":"'

echo ""
echo "8. Тесты валидации параметров:"
echo ""

# 8.1 Невалидный start_line (< 1)
test_case "8.1 start_line < 1 (должна быть ошибка)" \
    "send_mcp_request \"{\\\"jsonrpc\\\":\\\"2.0\\\",\\\"id\\\":2,\\\"method\\\":\\\"tools/call\\\",\\\"params\\\":{\\\"name\\\":\\\"read_file\\\",\\\"arguments\\\":{\\\"filename\\\":\\\"$TEST_DIR/multiline.txt\\\",\\\"start_line\\\":0}}}\" | jq -e '.result.isError == true or .error != null'" \
    '[ $? -eq 0 ]'

# 8.2 Невалидный диапазон (end_line < start_line)
test_case "8.2 end_line < start_line (должна быть ошибка)" \
    "send_mcp_request \"{\\\"jsonrpc\\\":\\\"2.0\\\",\\\"id\\\":2,\\\"method\\\":\\\"tools/call\\\",\\\"params\\\":{\\\"name\\\":\\\"read_file\\\",\\\"arguments\\\":{\\\"filename\\\":\\\"$TEST_DIR/multiline.txt\\\",\\\"start_line\\\":3,\\\"end_line\\\":2}}}\" | jq -e '.result.isError == true or .error != null'" \
    '[ $? -eq 0 ]'

# 8.3 Невалидный max_lines (<= 0)
test_case "8.3 max_lines <= 0 (должна быть ошибка)" \
    "send_mcp_request \"{\\\"jsonrpc\\\":\\\"2.0\\\",\\\"id\\\":2,\\\"method\\\":\\\"tools/call\\\",\\\"params\\\":{\\\"name\\\":\\\"read_file\\\",\\\"arguments\\\":{\\\"filename\\\":\\\"$TEST_DIR/multiline.txt\\\",\\\"max_lines\\\":0}}}\" | jq -e '.result.isError == true or .error != null'" \
    '[ $? -eq 0 ]'

echo ""
echo "9. Тесты обратной совместимости:"
echo ""

# 9.1 Чтение без новых параметров (должно работать как раньше)
test_case "9.1 Чтение без новых параметров (обратная совместимость)" \
    "send_mcp_request \"{\\\"jsonrpc\\\":\\\"2.0\\\",\\\"id\\\":2,\\\"method\\\":\\\"tools/call\\\",\\\"params\\\":{\\\"name\\\":\\\"read_file\\\",\\\"arguments\\\":{\\\"filename\\\":\\\"$TEST_DIR/multiline.txt\\\"}}}\" | jq -r '.result.content[0].text // empty'" \
    'echo "$result" | grep -q "Line 1" && echo "$result" | grep -q "Line 5"'

# Очистка
rm -rf $TEST_DIR

# Print results and exit
print_test_results
exit $?
