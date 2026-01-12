# MCP File Edit Server

Простой MCP (Model Context Protocol) сервер на Go для редактирования файлов.

## Возможности

- **edit_file** - создание/редактирование файлов с частичной или полной заменой
- **read_file** - чтение содержимого файлов
- **view** - чтение содержимого файлов (алиас для read_file)
- **exec** - выполнение shell команд с поддержкой таймаута и рабочей директории

## Параметры edit_file

| Параметр | Описание |
|----------|----------|
| `filename` | Путь к файлу (обязательный) |
| `content` | Полное содержимое файла (приоритетнее old_string/old_text) |
| `old_string` | Текст для замены (приоритетнее old_text) |
| `new_string` | Новый текст (если пустой - удаляет old_string) |
| `old_text` | Текст для замены (устаревший, используйте old_string) |
| `new_text` | Новый текст (устаревший, используйте new_string) |

**Примечание**: Поддерживаются как `old_string`/`new_string`, так и `old_text`/`new_text` для обратной совместимости. `old_string`/`new_string` имеют приоритет.

### Режимы работы:

1. **Полная запись** (`content`): Записывает файл целиком
2. **Частичная замена** (`old_string`/`old_text` + `new_string`/`new_text`): Заменяет текст
3. **Удаление** (`old_string`/`old_text` без `new_string`/`new_text`): Удаляет указанный текст
4. **Добавление** (только `new_string`/`new_text`): Добавляет в конец файла
5. **Полная замена** (`old_string`/`old_text: "*"` + `new_string`/`new_text`): Заменяет всё содержимое

## Параметры read_file

| Параметр | Описание |
|----------|----------|
| `filename` | Путь к файлу (обязательный) |

**Возвращаемое значение**: Объект с полем `content`, содержащим массив объектов формата `[{"type": "text", "text": "содержимое файла"}]` для совместимости с MCP протоколом.

## Параметры view

| Параметр | Описание |
|----------|----------|
| `filename` | Путь к файлу (обязательный) |

**Примечание**: `view` является алиасом для `read_file` и имеет идентичную функциональность. Возвращает тот же формат данных.

## Параметры exec

| Параметр | Описание |
|----------|----------|
| `command` | Shell команда для выполнения (обязательный) |
| `work_dir` | Рабочая директория для выполнения команды (опционально, по умолчанию - текущая директория) |
| `timeout` | Таймаут в секундах (опционально, по умолчанию: 300 секунд / 5 минут) |

**Возвращаемое значение**: Объект с полями:
- `stdout` - стандартный вывод команды
- `stderr` - стандартный поток ошибок
- `exit_code` - код возврата команды (0 при успехе)
- `status` - статус выполнения ("success" или "failed")
- `timeout` - булево значение, указывающее, был ли превышен таймаут

**Примечание**: Команда выполняется через `bash -c`. При завершении сервера все активные команды автоматически завершаются (SIGTERM, затем SIGKILL при необходимости).

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

### Чтение файла (view - алиас для read_file)
```bash
echo '{"method": "tools/call", "params": {"name": "view", "arguments": {"filename": "test.txt"}}}' | ./mcp-file-edit
```

### Выполнение команды
```bash
echo '{"method": "tools/call", "params": {"name": "exec", "arguments": {"command": "ls -la", "work_dir": "/tmp", "timeout": 60}}}' | ./mcp-file-edit
```
