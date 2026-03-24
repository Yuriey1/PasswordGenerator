# Domain Password Reset Tool

Набор PowerShell скриптов для автоматической смены паролей пользователей Active Directory и Zimbra с экспортом учётных данных в Infisical.

## Структура проекта

```
C:\2\
├── config.psd1                    # Основной файл конфигурации
├── config-zimbra.psd1             # Конфигурация Zimbra
├── Reset-DomainPasswords.ps1      # Скрипт смены паролей AD (поиск по ФИО)
├── Reset-DomainPasswords-ByEmail.ps1  # Скрипт смены паролей AD (поиск по email)
├── Reset-ZimbraPasswords.ps1      # Скрипт смены паролей Zimbra
├── Generate-Passwords.ps1         # Генератор тестовых паролей
├── PasswordGenerator.psm1         # Модуль генерации паролей
├── ADManager.psm1                 # Модуль работы с Active Directory
├── ZimbraManager.psm1             # Модуль работы с Zimbra (SOAP API)
├── InfisicalManager.psm1          # Модуль работы с Infisical
├── users.csv                      # CSV для AD скриптов
├── zimbra-users.csv               # CSV для Zimbra скрипта
├── backup\                        # Папка для резервных копий
└── report-*.csv                   # Отчёты о выполнении
```

## Требования

- Windows Server / Windows 10+ с PowerShell 5.1
- Модуль Active Directory (`RSAT-AD-PowerShell`) — для AD скриптов
- Infisical CLI (установка: `winget install Infisical`)
- Доступ к контроллеру домена
- Доступ к Infisical серверу
- Доступ к Zimbra серверу — для Zimbra скрипта

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
5. Настройте конфигурационные файлы

## Конфигурация

### config.psd1 — Основной конфиг

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
        ApiUrl = "https://infisical.krasintegra.ru"
        ServiceToken = "st.xxx"
        WorkspaceId = "xxx"
        Environment = "dev"
        SecretPath = "/"
    }
    
    IO = @{
        InputCsvPath = ".\users.csv"
        CsvEncoding = "UTF8"               # UTF8 или Windows1251
        BackupPath = ".\backup"
        SaveLocalBackup = $true
    }
    
    Security = @{
        DryRun = $false
        RequireConfirmation = $true
    }
    
    Logging = @{
        LogFilePath = $null
    }
}
```

### config-zimbra.psd1 — Конфиг Zimbra

```powershell
@{
    Zimbra = @{
        ServerUrl = "https://mail.gmkzoloto.ru"
        AdminUser = "admin@gmkzoloto.ru"
        AdminPassword = "ваш_пароль_админа"
        Domain = "gmkzoloto.ru"
    }
}
```

## Формат CSV

### Для AD скриптов (users.csv)

**Reset-DomainPasswords.ps1** (поиск по ФИО):
```csv
Имя учетной записи;Email
Иванов Иван Иванович;ivanov@gmkzoloto.ru
Петров Петр Петрович;petrov@gmkzoloto.ru
```

**Reset-DomainPasswords-ByEmail.ps1** (поиск по email):
```csv
Имя учетной записи;email
Механик уч. Пит-Городок;meh-pit@gmkzoloto.ru
Охрана Караган;ohranakaragan@gmkzoloto.ru
```

### Для Zimbra скрипта (zimbra-users.csv)

```csv
Имя учетной записи;email
Иванов Иван;ivanov@gmkzoloto.ru
Петров Петр;petrov@gmkzoloto.ru
```

## Использование

### Reset-DomainPasswords.ps1 — AD поиск по ФИО

```powershell
# Тестовый режим
.\Reset-DomainPasswords.ps1 -DryRun

# Рабочий запуск
.\Reset-DomainPasswords.ps1

# Принудительный запуск без подтверждения
.\Reset-DomainPasswords.ps1 -Force

# Указать другой CSV
.\Reset-DomainPasswords.ps1 -InputCsv ".\other-users.csv"
```

**Алгоритм:**
1. Читает ФИО из CSV
2. Ищет пользователя в AD по DisplayName
3. Меняет пароль
4. Экспортирует в Infisical

### Reset-DomainPasswords-ByEmail.ps1 — AD поиск по email

```powershell
# Тестовый режим
.\Reset-DomainPasswords-ByEmail.ps1 -DryRun

# Рабочий запуск
.\Reset-DomainPasswords-ByEmail.ps1
```

**Алгоритм:**
1. Извлекает логин из email (часть до @)
2. Ищет пользователя в AD по SamAccountName
3. Меняет пароль
4. Экспортирует в Infisical

**Пример:**
```
Email: meh-pit@gmkzoloto.ru
→ Поиск в AD: SamAccountName = "meh-pit"
```

### Reset-ZimbraPasswords.ps1 — Zimbra

```powershell
# Тестовый режим
.\Reset-ZimbraPasswords.ps1 -DryRun

# Рабочий запуск
.\Reset-ZimbraPasswords.ps1

# Указать другие конфиги
.\Reset-ZimbraPasswords.ps1 -ConfigPath ".\my-config.psd1" -ZimbraConfigPath ".\my-zimbra.psd1"
```

**Алгоритм:**
1. Авторизация в Zimbra через SOAP API
2. Получение ID аккаунта по email
3. Установка нового пароля через ModifyAccountRequest
4. Экспорт в Infisical

### Generate-Passwords.ps1 — Генератор паролей

```powershell
# 15 паролей (скрытые)
.\Generate-Passwords.ps1

# Показать пароли
.\Generate-Passwords.ps1 -ShowPasswords

# 20 паролей
.\Generate-Passwords.ps1 -Count 20 -ShowPasswords
```

## Именование секретов в Infisical

Секреты именуются по шаблону:
```
Фамилия_Имя_Отчество_(login)_PASSWORD
```

**Примеры:**
```
Чжоу_Михаил_Александрович_(cma001)_PASSWORD
Механик_уч._Пит-Городок_(meh-pit@gmkzoloto.ru)_PASSWORD
```

Пробелы заменяются на подчёркивания.

## Параметры командной строки

### Общие параметры

| Параметр | Описание |
|----------|----------|
| `-ConfigPath` | Путь к основному конфигу (по умолчанию `.\config.psd1`) |
| `-InputCsv` | Путь к CSV файлу |
| `-DryRun` | Тестовый режим без реальных изменений |
| `-Force` | Запуск без запроса подтверждения |
| `-SkipAD` / `-SkipZimbra` | Пропустить смену паролей |
| `-SkipInfisical` | Пропустить экспорт в Infisical |
| `-GenerateOnly` | Только генерация паролей |

### Zimbra-специфичные

| Параметр | Описание |
|----------|----------|
| `-ZimbraConfigPath` | Путь к конфигу Zimbra (по умолчанию `.\config-zimbra.psd1`) |

## Выходные файлы

### Backup
- AD: `.\backup\passwords-YYYYMMDD-HHMMSS.csv`
- Zimbra: `.\backup\zimbra-passwords-YYYYMMDD-HHMMSS.csv`
- Содержит: Username, SamAccountName/Email, Password, Strength, Timestamp

### Report
- AD: `.\report-YYYYMMDD-HHMMSS.csv`
- Zimbra: `.\zimbra-report-YYYYMMDD-HHMMSS.csv`
- Содержит: Username, SamAccountName, Email, PasswordGenerated, PasswordChanged, InfisicalExported, Timestamp

## Zimbra SOAP API

Скрипт использует Zimbra Admin SOAP API:

1. **AuthRequest** — авторизация администратора, получение authToken
2. **GetAccountRequest** — получение ID аккаунта по email
3. **ModifyAccountRequest** — установка нового пароля

Пример SOAP запроса для авторизации:
```xml
<soap:Envelope xmlns:soap="http://www.w3.org/2003/05/soap-envelope">
  <soap:Body>
    <AuthRequest xmlns="urn:zimbraAdmin">
      <name>admin@example.com</name>
      <password>password</password>
    </AuthRequest>
  </soap:Body>
</soap:Envelope>
```

## Интеграция с Infisical

### Получение Service Token

1. Войдите в Infisical: `https://infisical.krasintegra.ru`
2. Перейдите в Project → Settings → Service Tokens
3. Создайте токен с правами на запись секретов
4. Скопируйте `Service Token` и `Project ID` в `config.psd1`

### Проверка CLI

```powershell
infisical version
```

## Решение проблем

### Ошибка "Execution Policy"
```powershell
Set-ExecutionPolicy RemoteSigned -Scope CurrentUser
```

### Ошибка "Config parsing error"
Убедитесь, что в `.psd1` файлах нет комментариев внутри хеш-таблицы.

### Пользователь не найден в AD (по ФИО)
```powershell
Get-ADUser -Filter * | Where-Object { $_.DisplayName -match "Фамилия" }
```

### Пользователь не найден в AD (по логину)
```powershell
Get-ADUser -Filter "SamAccountName -eq 'login'"
```

### Ошибка Infisical "unsupported protocol scheme"
Убедитесь, что `ApiUrl` содержит полный адрес с `https://`.

### Ошибка Zimbra "account.NO_SUCH_ACCOUNT"
Аккаунт с указанным email не существует на сервере Zimbra.

### Ошибка Zimbra "connection refused"
Проверьте доступность сервера и правильность URL в `config-zimbra.psd1`.

## Безопасность

- Пароли генерируются криптографически стойким генератором
- Service Token даёт доступ только к указанному Project
- Пароль администратора Zimbra хранится в конфиге в открытом виде — ограничьте доступ к файлу
- Локальные бэкапы содержат пароли в открытом виде — защитите папку `backup\`
- Используйте `-DryRun` для тестирования перед реальным запуском
- Рекомендуется удалить локальные бэкапы после проверки экспорта в Infisical

## Лицензия

Внутреннее использование.
