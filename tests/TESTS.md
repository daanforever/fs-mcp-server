# Тесты MCP File Edit Server

## Пограничные случаи (Edge Cases)

Все тесты были проверены и подтверждены работают корректно.

### 1. Пустой файл (content='')
```bash
# Создание файла с пустым содержимым
echo '{"method":"edit_file","arguments":{"filename":"empty.txt","content":""}}' | ./mcp-file-edit
# ✓ Создает файл 0 байт
```

### 2. Замена текста (old_text/new_text)
```bash
# Замена "old" на "new"
echo '{"method":"edit_file","arguments":{"filename":"file.txt","content":"old value"}}' | ./mcp-file-edit
echo '{"method":"edit_file","arguments":{"filename":"file.txt","old_text":"old","new_text":"new"}}' | ./mcp-file-edit
# ✓ Результат: "new value"
```

### 3. Удаление текста (old_text без new_text)
```bash
# Удаление строки
echo '{"method":"edit_file","arguments":{"filename":"file.txt","content":"remove me\nkeep"}}' | ./mcp-file-edit
echo '{"method":"edit_file","arguments":{"filename":"file.txt","old_text":"remove me\n"}}' | ./mcp-file-edit
# ✓ Результат: "keep"
```

### 4. Множественные вхождения
```bash
# Замена всех вхождений
echo '{"method":"edit_file","arguments":{"filename":"file.txt","content":"old old old"}}' | ./mcp-file-edit
echo '{"method":"edit_file","arguments":{"filename":"file.txt","old_text":"old","new_text":"NEW"}}' | ./mcp-file-edit
# ✓ Результат: "NEW NEW NEW"
```

### 5. Вложенные директории
```bash
# Автоматическое создание путей
echo '{"method":"edit_file","arguments":{"filename":"a/b/c/file.txt","content":"content"}}' | ./mcp-file-edit
# ✓ Создает a/b/c/ и файл
```

### 6. Чтение несуществующего файла
```bash
# Возвращает ошибку
echo '{"method":"read_file","arguments":{"filename":"missing.txt"}}' | ./mcp-file-edit
# ✓ {"error":{"code":-32000,"message":"Failed to read file: ..."}}
```

### 7. Полная замена через *
```bash
# Замена всего содержимого
echo '{"method":"edit_file","arguments":{"filename":"file.txt","content":"old"}}' | ./mcp-file-edit
echo '{"method":"edit_file","arguments":{"filename":"file.txt","old_text":"*","new_text":"NEW"}}' | ./mcp-file-edit
# ✓ Результат: "NEW"
```

### 8. UTF-8 символы
```bash
# Поддержка Unicode
echo '{"method":"edit_file","arguments":{"filename":"utf8.txt","content":"Привет 🌍"}}' | ./mcp-file-edit
# ✓ ✓ Сохраняет корректно
```

### 9. Добавление в конец (new_text)
```bash
# Без old_text добавляет в конец
echo '{"method":"edit_file","arguments":{"filename":"file.txt","content":"start"}}' | ./mcp-file-edit
echo '{"method":"edit_file","arguments":{"filename":"file.txt","new_text":"end"}}' | ./mcp-file-edit
# ✓ Результат: "start\nend"
```

### 10. Content приоритетнее
```bash
# Параметр content перекрывает old_text/new_text
echo '{"method":"edit_file","arguments":{"filename":"file.txt","content":"second","old_text":"ignored"}}' | ./mcp-file-edit
# ✓ Записывает "second", игнорируя old_text
```

### 11. Замена несуществующего текста
```bash
# Если old_text не найден, new_text добавляется в конец
echo '{"method":"edit_file","arguments":{"filename":"file.txt","content":"base"}}' | ./mcp-file-edit
echo '{"method":"edit_file","arguments":{"filename":"file.txt","old_text":"missing","new_text":"added"}}' | ./mcp-file-edit
# ✓ Результат: "base\nadded"
```

### 12. Файлы без расширения
```bash
echo '{"method":"edit_file","arguments":{"filename":"noext","content":"test"}}' | ./mcp-file-edit
# ✓ Работает корректно
```

### 13. Перезапись существующего файла
```bash
echo '{"method":"edit_file","arguments":{"filename":"file.txt","content":"OLD"}}' | ./mcp-file-edit
echo '{"method":"edit_file","arguments":{"filename":"file.txt","content":"NEW"}}' | ./mcp-file-edit
# ✓ Полностью заменяет содержимое
```

### 14. Замена в пустом файле
```bash
echo '{"method":"edit_file","arguments":{"filename":"empty.txt","content":""}}' | ./mcp-file-edit
echo '{"method":"edit_file","arguments":{"filename":"empty.txt","old_text":"","new_text":"text"}}' | ./mcp-file-edit
# ✓ Добавляет текст в пустой файл
```

### 15. Многолиновый новый текст
```bash
echo '{"method":"edit_file","arguments":{"filename":"file.txt","content":"start"}}' | ./mcp-file-edit
echo '{"method":"edit_file","arguments":{"filename":"file.txt","old_text":"start","new_text":"line1\nline2\nline3"}}' | ./mcp-file-edit
# ✓ Поддерживает переносы строк в new_text
```

## Итоги

Все 15 тестов пограничных случаев пройдены успешно! ✓

Сервер корректно обрабатывает:
- Пустые файлы и строки
- Спецсимволы и UTF-8
- Вложенные директории
- Отсутствующие файлы
- Множественные вхождения
- Различные режимы редактирования
