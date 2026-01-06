#!/bin/bash

SERVER="./mcp-file-edit"
rm -rf test_dir
mkdir -p test_dir

echo "=== Edge Cases Tests ==="

# 1. Пустой файл (content='')
echo -n "1. Пустой файл: "
echo '{"method": "tools/call", "params": {"name": "edit_file", "arguments": {"filename": "test_dir/empty.txt", "content": ""}}}' | $SERVER > /dev/null 2>&1
if [ -f test_dir/empty.txt ] && [ ! -s test_dir/empty.txt ]; then echo "PASS"; else echo "FAIL"; fi

# 2. Замена текста
echo -n "2. Замена текста: "
echo '{"method": "tools/call", "params": {"name": "edit_file", "arguments": {"filename": "test_dir/replace.txt", "content": "old value"}}}' | $SERVER > /dev/null 2>&1
echo '{"method": "tools/call", "params": {"name": "edit_file", "arguments": {"filename": "test_dir/replace.txt", "old_text": "old", "new_text": "new"}}}' | $SERVER > /dev/null 2>&1
[ "$(cat test_dir/replace.txt)" == "new value" ] && echo "PASS" || echo "FAIL"

# 3. Удаление текста
echo -n "3. Удаление текста: "
echo '{"method": "tools/call", "params": {"name": "edit_file", "arguments": {"filename": "test_dir/delete.txt", "content": "remove me\nkeep"}}}' | $SERVER > /dev/null 2>&1
echo '{"method": "tools/call", "params": {"name": "edit_file", "arguments": {"filename": "test_dir/delete.txt", "old_text": "remove me\n"}}}' | $SERVER > /dev/null 2>&1
[ "$(cat test_dir/delete.txt)" == "keep" ] && echo "PASS" || echo "FAIL"

# 4. Множественные вхождения
echo -n "4. Множественные вхождения: "
echo '{"method": "tools/call", "params": {"name": "edit_file", "arguments": {"filename": "test_dir/multi.txt", "content": "old old old"}}}' | $SERVER > /dev/null 2>&1
echo '{"method": "tools/call", "params": {"name": "edit_file", "arguments": {"filename": "test_dir/multi.txt", "old_text": "old", "new_text": "NEW"}}}' | $SERVER > /dev/null 2>&1
[ "$(cat test_dir/multi.txt)" == "NEW NEW NEW" ] && echo "PASS" || echo "FAIL"

# 5. Вложенные директории
echo -n "5. Вложенные директории: "
echo '{"method": "tools/call", "params": {"name": "edit_file", "arguments": {"filename": "test_dir/a/b/c/deep.txt", "content": "deep"}}}' | $SERVER > /dev/null 2>&1
[ -f test_dir/a/b/c/deep.txt ] && echo "PASS" || echo "FAIL"

# 6. Чтение несуществующего файла
echo -n "6. Чтение несуществующего: "
result=$(echo '{"method": "tools/call", "params": {"name": "read_file", "arguments": {"filename": "test_dir/nonexistent.txt"}}}' | $SERVER 2>/dev/null)
[[ "$result" == *"error"* ]] && echo "PASS" || echo "FAIL"

# 7. Полная замена через *
echo -n "7. Полная замена (*): "
echo '{"method": "tools/call", "params": {"name": "edit_file", "arguments": {"filename": "test_dir/asterisk.txt", "content": "old"}}}' | $SERVER > /dev/null 2>&1
echo '{"method": "tools/call", "params": {"name": "edit_file", "arguments": {"filename": "test_dir/asterisk.txt", "old_text": "*", "new_text": "NEW"}}}' | $SERVER > /dev/null 2>&1
[ "$(cat test_dir/asterisk.txt)" == "NEW" ] && echo "PASS" || echo "FAIL"

# 8. UTF-8
echo -n "8. UTF-8 символы: "
echo '{"method": "tools/call", "params": {"name": "edit_file", "arguments": {"filename": "test_dir/utf8.txt", "content": "Привет 🌍"}}}' | $SERVER > /dev/null 2>&1
grep -q "Привет" test_dir/utf8.txt && echo "PASS" || echo "FAIL"

# 9. Добавление в конец
echo -n "9. Добавление в конец: "
echo '{"method": "tools/call", "params": {"name": "edit_file", "arguments": {"filename": "test_dir/append.txt", "content": "start"}}}' | $SERVER > /dev/null 2>&1
echo '{"method": "tools/call", "params": {"name": "edit_file", "arguments": {"filename": "test_dir/append.txt", "new_text": "end"}}}' | $SERVER > /dev/null 2>&1
[ "$(cat test_dir/append.txt)" == "start\nend" ] && echo "PASS" || echo "FAIL"

# 10. Content приоритет
echo -n "10. Content приоритет: "
echo '{"method": "tools/call", "params": {"name": "edit_file", "arguments": {"filename": "test_dir/priority.txt", "content": "first"}}}' | $SERVER > /dev/null 2>&1
echo '{"method": "tools/call", "params": {"name": "edit_file", "arguments": {"filename": "test_dir/priority.txt", "content": "second", "old_text": "ignored", "new_text": "ignored"}}}' | $SERVER > /dev/null 2>&1
[ "$(cat test_dir/priority.txt)" == "second" ] && echo "PASS" || echo "FAIL"

# 11. Пустая замена (old_text с пустым new_text)
echo -n "11. Пустая замена: "
echo '{"method": "tools/call", "params": {"name": "edit_file", "arguments": {"filename": "test_dir/empty_replace.txt", "content": "aaa bbb ccc"}}}' | $SERVER > /dev/null 2>&1
echo '{"method": "tools/call", "params": {"name": "edit_file", "arguments": {"filename": "test_dir/empty_replace.txt", "old_text": "bbb ", "new_text": ""}}}' | $SERVER > /dev/null 2>&1
[ "$(cat test_dir/empty_replace.txt)" == "aaa ccc" ] && echo "PASS" || echo "FAIL"

# 12. Длинный файл
echo -n "12. Длинный файл (10000 байт): "
python3 -c "print('A'*10000)" > /tmp/long.txt
echo '{"method": "tools/call", "params": {"name": "edit_file", "arguments": {"filename": "test_dir/long.txt", "content": "'$(cat /tmp/long.txt)'"}}}' | $SERVER > /dev/null 2>&1
[ $(wc -c < test_dir/long.txt) -eq 10000 ] && echo "PASS" || echo "FAIL"
rm /tmp/long.txt

# 13. Замена несуществующего (добавление)
echo -n "13. Замена несуществующего: "
echo '{"method": "tools/call", "params": {"name": "edit_file", "arguments": {"filename": "test_dir/missing.txt", "content": "base"}}}' | $SERVER > /dev/null 2>&1
echo '{"method": "tools/call", "params": {"name": "edit_file", "arguments": {"filename": "test_dir/missing.txt", "old_text": "notfound", "new_text": "added"}}}' | $SERVER > /dev/null 2>&1
[[ "$(cat test_dir/missing.txt)" == *"added"* ]] && echo "PASS" || echo "FAIL"

# 14. Файл без расширения
echo -n "14. Без расширения: "
echo '{"method": "tools/call", "params": {"name": "edit_file", "arguments": {"filename": "test_dir/noext", "content": "test"}}}' | $SERVER > /dev/null 2>&1
[ -f test_dir/noext ] && echo "PASS" || echo "FAIL"

# 15. Перезапись файла
echo -n "15. Перезапись: "
echo '{"method": "tools/call", "params": {"name": "edit_file", "arguments": {"filename": "test_dir/rewrite.txt", "content": "OLD"}}}' | $SERVER > /dev/null 2>&1
echo '{"method": "tools/call", "params": {"name": "edit_file", "arguments": {"filename": "test_dir/rewrite.txt", "content": "NEW"}}}' | $SERVER > /dev/null 2>&1
[ "$(cat test_dir/rewrite.txt)" == "NEW" ] && echo "PASS" || echo "FAIL"

echo ""
rm -rf test_dir
echo "Тесты завершены."
