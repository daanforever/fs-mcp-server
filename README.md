# MCP File Edit Server

Простой MCP (Model Context Protocol) сервер на Go для редактирования файлов.

## Возможности

- **edit_file** - создание/редактирование файлов с частичной или полной заменой
- **read_file** - чтение содержимого файлов

## Параметры edit_file

| Параметр | Описание |
|----------|----------|
| `filename` | Путь к файлу (обязательный) |
| `content` | Полное содержимое файла (приоритетнее old_text) |
| `old_text` | Текст для замены |
| `new_text` | Новый текст (если пустой - удаляет old_text) |

### Режимы работы:

1. **Полная запись** (`content`): Записывает файл целиком
2. **Частичная замена** (`old_text` + `new_text`): Заменяет текст
3. **Удаление** (`old_text` без `new_text`): Удаляет указанный текст
4. **Добавление** (только `new_text`): Добавляет в конец файла
5. **Полная замена** (`old_text: "*"` + `new_text`): Заменяет всё содержимое

## Установка

```bash
go mod tidy
go build -o mcp-file-edit main.go
```

## Примеры использования

### Полная запись
```bash
echo '{"method": "tools/call", "params": {"name": "edit_file", "arguments": {"filename": "test.txt", "content": "Hello World!"}}}' | ./mcp-file-edit
```

### Частичная замена
```bash
echo '{"method": "tools/call", "params": {"name": "edit_file", "arguments": {"filename": "test.txt", "old_text": "old", "new_text": "new"}}}' | ./mcp-file-edit
```

### Удаление текста
```bash
echo '{"method": "tools/call", "params": {"name": "edit_file", "arguments": {"filename": "test.txt", "old_text": "remove this"}}}' | ./mcp-file-edit
```

### Добавление в конец
```bash
echo '{"method": "tools/call", "params": {"name": "edit_file", "arguments": {"filename": "test.txt", "new_text": "new line"}}}' | ./mcp-file-edit
```

### Чтение файла
```bash
echo '{"method": "tools/call", "params": {"name": "read_file", "arguments": {"filename": "test.txt"}}}' | ./mcp-file-edit
```
