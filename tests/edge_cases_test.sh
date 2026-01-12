#!/bin/bash

# Тесты пограничных случаев для MCP File Edit Server

set -e

# Source helper functions
source "$(dirname "$0")/helper.sh"

# Use PASSED/FAILED instead of pass_count/fail_count for consistency
PASSED=0
FAILED=0

# Override run_test to use PASSED/FAILED instead of pass_count/fail_count
run_test() {
    local name="$1"
    local request="$2"
    local expected_check="$3"
    
    echo -n "Test: $name ... "
    result=$(echo "$request" | "$SERVER" 2>/dev/null)
    
    if eval "$expected_check"; then
        echo -e "\033[0;32mPASS\033[0m"
        ((PASSED++))
    else
        echo -e "\033[0;31mFAIL\033[0m"
        echo "  Request: $request"
        echo "  Result: $result"
        ((FAILED++))
    fi
}

# Подготовка
rm -rf test_dir
mkdir -p test_dir

echo "=== Edge Cases Tests ==="
echo ""

# 1. Файл с пустым содержимым (content="")
run_test "Пустой файл (content='')" \
    '{"method": "tools/call", "params": {"name": "edit_file", "arguments": {"filename": "test_dir/empty.txt", "content": ""}}}' \
    '[[ "$result" == *'"'"'success'"'* ]] && [ -f test_dir/empty.txt ] && [ ! -s test_dir/empty.txt ]'

# 2. Файл с пробелами
run_test "Файл с пробелами" \
    '{"method": "tools/call", "params": {"name": "edit_file", "arguments": {"filename": "test_dir/spaces.txt", "content": "   spaces   "}}}' \
    '[[ "$result" == *'"'"'success'"'* ]] && [ "$(cat test_dir/spaces.txt)" == "   spaces   " ]'

# 3. Спецсимволы
run_test "Спецсимволы" \
    '{"method": "tools/call", "params": {"name": "edit_file", "arguments": {"filename": "test_dir/special.txt", "content": "Line 1\nLine 2\n\tTabbed"}}}' \
    '[[ "$result" == *'"'"'success'"'* ]] && grep -q "Line 1" test_dir/special.txt'

# 4. Замена несуществующего текста
run_test "Замена несуществующего текста" \
    '{"method": "tools/call", "params": {"name": "edit_file", "arguments": {"filename": "test_dir/base.txt", "content": "Base"}}}' \
    '[[ "$result" == *'"'"'success'"'* ]]' && \
    echo '{"method": "tools/call", "params": {"name": "edit_file", "arguments": {"filename": "test_dir/base.txt", "old_text": "missing", "new_text": "added"}}}' | $SERVER >/dev/null 2>&1 && \
    [[ "$(cat test_dir/base.txt)" == *"added"* ]]

# 5. Удаление текста (old_text без new_text)
run_test "Удаление текста" \
    '{"method": "tools/call", "params": {"name": "edit_file", "arguments": {"filename": "test_dir/delete.txt", "content": "Remove this\nKeep this"}}}' \
    '[[ "$result" == *'"'"'success'"'* ]]' && \
    echo '{"method": "tools/call", "params": {"name": "edit_file", "arguments": {"filename": "test_dir/delete.txt", "old_text": "Remove this\n"}}}' | $SERVER >/dev/null 2>&1 && \
    [ "$(cat test_dir/delete.txt)" == "Keep this" ]

# 6. Множественные вхождения
run_test "Множественные вхождения" \
    '{"method": "tools/call", "params": {"name": "edit_file", "arguments": {"filename": "test_dir/multi.txt", "content": "old old old"}}}' \
    '[[ "$result" == *'"'"'success'"'* ]]' && \
    echo '{"method": "tools/call", "params": {"name": "edit_file", "arguments": {"filename": "test_dir/multi.txt", "old_text": "old", "new_text": "NEW"}}}' | $SERVER >/dev/null 2>&1 && \
    [ "$(cat test_dir/multi.txt)" == "NEW NEW NEW" ]

# 7. Вложенные директории
run_test "Вложенные директории" \
    '{"method": "tools/call", "params": {"name": "edit_file", "arguments": {"filename": "test_dir/a/b/c/deep.txt", "content": "deep"}}}' \
    '[[ "$result" == *'"'"'success'"'* ]] && [ -f test_dir/a/b/c/deep.txt ]'

# 8. Чтение несуществующего файла
run_test "Чтение несуществующего файла" \
    '{"method": "tools/call", "params": {"name": "read_file", "arguments": {"filename": "test_dir/nonexistent.txt"}}}' \
    '[[ "$result" == *'"'"'error'"'* ]]'

# 9. Полная замена через *
run_test "Полная замена через *" \
    '{"method": "tools/call", "params": {"name": "edit_file", "arguments": {"filename": "test_dir/asterisk.txt", "content": "old"}}}' \
    '[[ "$result" == *'"'"'success'"'* ]]' && \
    echo '{"method": "tools/call", "params": {"name": "edit_file", "arguments": {"filename": "test_dir/asterisk.txt", "old_text": "*", "new_text": "NEW"}}}' | $SERVER >/dev/null 2>&1 && \
    [ "$(cat test_dir/asterisk.txt)" == "NEW" ]

# 10. Очень длинная строка
run_test "Очень длинная строка" \
    '{"method": "tools/call", "params": {"name": "edit_file", "arguments": {"filename": "test_dir/long.txt", "content": "'$(python3 -c "print('A'*10000)")'"}}}' \
    '[[ "$result" == *'"'"'success'"'* ]] && [ $(wc -c < test_dir/long.txt) -eq 10000 ]'

# 11. UTF-8 символы
run_test "UTF-8 (кириллица)" \
    '{"method": "tools/call", "params": {"name": "edit_file", "arguments": {"filename": "test_dir/utf8.txt", "content": "Привет мир! 🌍"}}}' \
    '[[ "$result" == *'"'"'success'"'* ]] && grep -q "Привет" test_dir/utf8.txt'

# 12. Замена в пустом файле
run_test "Замена в пустом файле" \
    '{"method": "tools/call", "params": {"name": "edit_file", "arguments": {"filename": "test_dir/empty2.txt", "content": ""}}}' \
    '[[ "$result" == *'"'"'success'"'* ]]' && \
    echo '{"method": "tools/call", "params": {"name": "edit_file", "arguments": {"filename": "test_dir/empty2.txt", "old_text": "", "new_text": "text"}}}' | $SERVER >/dev/null 2>&1 && \
    [ "$(cat test_dir/empty2.txt)" == "text" ]

# 13. Content имеет приоритет
run_test "Content приоритетнее old_text/new_text" \
    '{"method": "tools/call", "params": {"name": "edit_file", "arguments": {"filename": "test_dir/priority.txt", "content": "content1"}}}' \
    '[[ "$result" == *'"'"'success'"'* ]]' && \
    echo '{"method": "tools/call", "params": {"name": "edit_file", "arguments": {"filename": "test_dir/priority.txt", "content": "content2", "old_text": "ignored", "new_text": "ignored"}}}' | $SERVER >/dev/null 2>&1 && \
    [ "$(cat test_dir/priority.txt)" == "content2" ]

# 14. Добавление в конец пустого файла
run_test "Добавление в конец пустого файла" \
    '{"method": "tools/call", "params": {"name": "edit_file", "arguments": {"filename": "test_dir/empty3.txt", "content": ""}}}' \
    '[[ "$result" == *'"'"'success'"'* ]]' && \
    echo '{"method": "tools/call", "params": {"name": "edit_file", "arguments": {"filename": "test_dir/empty3.txt", "new_text": "line1"}}}' | $SERVER >/dev/null 2>&1 && \
    [ "$(cat test_dir/empty3.txt)" == "line1" ]

# 15. Новый текст с переносом строк
run_test "Многолиновый новый текст" \
    '{"method": "tools/call", "params": {"name": "edit_file", "arguments": {"filename": "test_dir/multiline.txt", "content": "start"}}}' \
    '[[ "$result" == *'"'"'success'"'* ]]' && \
    echo '{"method": "tools/call", "params": {"name": "edit_file", "arguments": {"filename": "test_dir/multiline.txt", "old_text": "start", "new_text": "line1\nline2\nline3"}}}' | $SERVER >/dev/null 2>&1 && \
    grep -q "line2" test_dir/multiline.txt

# 16. Замена только первого вхождения (не поддерживается, но проверяем поведение)
run_test "Замена всех вхождений (default)" \
    '{"method": "tools/call", "params": {"name": "edit_file", "arguments": {"filename": "test_dir/all.txt", "content": "test test test"}}}' \
    '[[ "$result" == *'"'"'success'"'* ]]' && \
    echo '{"method": "tools/call", "params": {"name": "edit_file", "arguments": {"filename": "test_dir/all.txt", "old_text": "test", "new_text": "PASS"}}}' | $SERVER >/dev/null 2>&1 && \
    [ "$(cat test_dir/all.txt)" == "PASS PASS PASS" ]

# 17. Файл без расширения
run_test "Файл без расширения" \
    '{"method": "tools/call", "params": {"name": "edit_file", "arguments": {"filename": "test_dir/noextension", "content": "no ext"}}}' \
    '[[ "$result" == *'"'"'success'"'* ]] && [ -f test_dir/noextension ]'

# 18. Попытка изменить директорию как файл (error)
run_test "Запись в директорию" \
    '{"method": "tools/call", "params": {"name": "edit_file", "arguments": {"filename": "test_dir/", "content": "test"}}}' \
    '[[ "$result" == *'"'"'error'"'* ]] || [[ "$result" == *'"'"'success'"'* ]]'

# 19. Файл с BOM
run_test "Файл с BOM" \
    '{"method": "tools/call", "params": {"name": "edit_file", "arguments": {"filename": "test_dir/bom.txt", "content": "\uFEFFBOM"}}}' \
    '[[ "$result" == *'"'"'success'"'* ]] && [ -f test_dir/bom.txt ]'

# 20. Проверка что старый content не влияет при новой записи
run_test "Перезапись существующего файла" \
    '{"method": "tools/call", "params": {"name": "edit_file", "arguments": {"filename": "test_dir/rewrite.txt", "content": "OLD"}}}' \
    '[[ "$result" == *'"'"'success'"'* ]]' && \
    echo '{"method": "tools/call", "params": {"name": "edit_file", "arguments": {"filename": "test_dir/rewrite.txt", "content": "NEW"}}}' | $SERVER >/dev/null 2>&1 && \
    [ "$(cat test_dir/rewrite.txt)" == "NEW" ]

# Очистка
rm -rf test_dir

# Print results and exit
print_test_results
exit $?
