# Domain Password Reset Tool

Набор PowerShell скриптов для автоматической смены паролей пользователей Active Directory с экспортом учётных данных в Infisical.

## Структура проекта

```
C:\2\
├── config.psd1              # Файл конфигурации
├── Reset-DomainPasswords.ps1 # Основной скрипт
├── Generate-Passwords.ps1   # Генератор тестовых паролей
├── PasswordGenerator.psm1   # Модуль генерации паролей
├── ADManager.psm1           # Модуль работы с Active Directory
├── InfisicalManager.psm1    # Модуль работы с Infisical
├── users.csv                # Исходный файл с пользователями
├── backup\                  # Папка для резервных копий
└── report-*.csv             # Отчёты о выполнении
```

## Требования

- Windows Server / Windows 10+ с PowerShell 5.1
- Модуль Active Directory (`RSAT-AD-PowerShell`)
- Infisical CLI (установка: `winget install Infisical`)
- Доступ к контроллеру домена
- Доступ к Infisical серверу

## Установка

1. Скачайте все файлы в одну директорию
2. Разблокируйте скрипты:
   ```powershell
   Get-ChildItem *.ps1, *.psm1, *.psd1 | Unblock-File
   ```
3. Установите политику выполнения:
   ```powershell
   Set-ExecutionPolicy RemoteSigned -Scope CurrentUser
   ```
4. Установите Infisical CLI:
   ```powershell
   winget install Infisical
   ```
5. Настройте `config.psd1`

## Конфигурация (config.psd1)

```powershell
@{
    AD = @{
        DomainController = ""              # Пусто = автоматическое определение
        SearchBase = ""                    # Пусто = весь домен
    }
    
    PasswordGenerator = @{
        Length = 12                        # Длина пароля
        IncludeUppercase = $true           # Заглавные буквы
        IncludeLowercase = $true           # Строчные буквы
        IncludeDigits = $true              # Цифры
        IncludeSpecial = $true             # Специальные символы
        SpecialChars = "!@#$%^&*()_+-=[]{}|;:,.<>?"
    }
    
    Infisical = @{
        ApiUrl = "https://infisical.krasintegra.ru"  # Адрес self-hosted сервера
        ServiceToken = "st.xxx"                       # Service Token
        WorkspaceId = "xxx"                           # Project ID
        Environment = "dev"                           # Окружение (dev/prod)
        SecretPath = "/"                              # Путь к секретам
    }
    
    IO = @{
        InputCsvPath = ".\users.csv"      # Путь к CSV с пользователями
        CsvEncoding = "UTF8"              # Кодировка: UTF8 или Windows1251
        BackupPath = ".\backup"           # Папка для бэкапов
        SaveLocalBackup = $true           # Сохранять локальную копию
    }
    
    Security = @{
        DryRun = $false                   # Режим тестирования (без изменений)
        RequireConfirmation = $true       # Запрашивать подтверждение
    }
    
    Logging = @{
        LogFilePath = $null               # Путь к логу (null = не логировать в файл)
    }
}
```

## Формат CSV

Файл `users.csv` должен содержать:
- Разделитель: `;` (точка с запятой)
- Кодировка: UTF-8 или Windows-1251
- Столбцы:
  - `Имя учетной записи` — ФИО пользователя (для поиска в AD по DisplayName)
  - Второй столбец — Email (опционально)

**Пример:**
```csv
Имя учетной записи;Email
Иванов Иван Иванович;ivanov@gmkzoloto.ru
Петров Петр Петрович;petrov@gmkzoloto.ru
```

## Использование

### Основной скрипт

```powershell
# Обычный запуск (с подтверждением)
.\Reset-DomainPasswords.ps1

# Тестовый режим (без изменений)
.\Reset-DomainPasswords.ps1 -DryRun

# Принудительный запуск (без подтверждения)
.\Reset-DomainPasswords.ps1 -Force

# Указать другой CSV файл
.\Reset-DomainPasswords.ps1 -InputCsv ".\other-users.csv"

# Только генерация паролей (без AD и Infisical)
.\Reset-DomainPasswords.ps1 -GenerateOnly

# Пропустить сброс AD
.\Reset-DomainPasswords.ps1 -SkipAD

# Пропустить экспорт в Infisical
.\Reset-DomainPasswords.ps1 -SkipInfisical
```

### Генератор тестовых паролей

```powershell
# Сгенерировать 15 паролей (скрытые)
.\Generate-Passwords.ps1

# Показать пароли полностью
.\Generate-Passwords.ps1 -ShowPasswords

# Указать количество
.\Generate-Passwords.ps1 -Count 20 -ShowPasswords
```

## Именование секретов в Infisical

Секреты именуются по шаблону:
```
Фамилия Имя Отчество (login)
```

**Пример:**
```
Чжоу Михаил Александрович (cma001)
```

Пробелы в ФИО заменяются на подчёркивания для совместимости с Infisical.

## Выходные файлы

### Backup
- Путь: `.\backup\passwords-YYYYMMDD-HHMMSS.csv`
- Содержит: Username, SamAccountName, Email, Password, Strength, Timestamp

### Report
- Путь: `.\report-YYYYMMDD-HHMMSS.csv`
- Содержит: Username, SamAccountName, Email, PasswordGenerated, ADPasswordChanged, InfisicalExported, Timestamp

## Параметры командной строки

| Параметр | Описание |
|----------|----------|
| `-ConfigPath` | Путь к файлу конфигурации (по умолчанию `.\config.psd1`) |
| `-InputCsv` | Путь к CSV файлу с пользователями |
| `-DryRun` | Тестовый режим без реальных изменений |
| `-Force` | Запуск без запроса подтверждения |
| `-SkipAD` | Пропустить сброс паролей в AD |
| `-SkipInfisical` | Пропустить экспорт в Infisical |
| `-GenerateOnly` | Только генерация паролей |

## Алгоритм работы

1. **Загрузка конфигурации** — чтение `config.psd1`
2. **Загрузка пользователей** — чтение CSV с определением кодировки
3. **Генерация паролей** — криптографически стойкие пароли по настройкам
4. **Поиск в AD** — поиск пользователей по DisplayName (ФИО)
5. **Сброс паролей** — установка новых паролей в Active Directory
6. **Экспорт в Infisical** — сохранение учётных данных через CLI
7. **Резервное копирование** — сохранение паролей в локальный файл
8. **Формирование отчёта** — CSV с результатами выполнения

## Интеграция с Infisical

### Получение Service Token

1. Войдите в Infisical: `https://infisical.krasintegra.ru`
2. Перейдите в Project → Settings → Service Tokens
3. Создайте токен с правами на запись секретов
4. Скопируйте `Service Token` и `Project ID` в `config.psd1`

### Проверка CLI

```powershell
# Проверка установки
infisical version

# Ручное добавление секрета (для теста)
infisical secrets set TEST_PASSWORD=value123 --token=st.xxx --domain=https://infisical.krasintegra.ru --projectId=xxx --env=dev
```

## Решение проблем

### Ошибка "Execution Policy"
```powershell
Set-ExecutionPolicy RemoteSigned -Scope CurrentUser
```

### Ошибка "Config parsing error"
Убедитесь, что в `config.psd1` нет комментариев внутри хеш-таблицы.

### Пользователь не найден в AD
Скрипт ищет по DisplayName. Проверьте:
```powershell
Get-ADUser -Filter * | Where-Object { $_.DisplayName -match "Фамилия" }
```

### Ошибка Infisical "unsupported protocol scheme"
Убедитесь, что в конфиге указан `ApiUrl` с полным адресом включая `https://`.

### Ошибка Infisical "ApiUrl is empty"
Проверьте, что параметр `ApiUrl` заполнен в секции `Infisical` конфига.

## Безопасность

- Пароли генерируются криптографически стойким генератором
- Service Token даёт доступ только к указанному Project
- Локальные бэкапы содержат пароли в открытом виде — защитите папку `backup\`
- Используйте `-DryRun` для тестирования перед реальным запуском
- Рекомендуется удалить локальные бэкапы после проверки экспорта в Infisical

## Лицензия

Внутреннее использование.
