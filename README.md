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
├── users.csv                      # Единый CSV файл для всех скриптов
├── backup\                        # Папка для резервных копий
└── report-*.csv                   # Отчёты о выполнении
```

## Требования

- Windows Server / Windows 10+ с PowerShell 5.1+
- Модуль Active Directory (`RSAT-AD-PowerShell`) — для AD скриптов
- Infisical CLI v0.43.62+ (установка: см. ниже)
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
   # Скачать с GitHub
   # https://github.com/Infisical/cli/releases/latest
   
   # Или через winget
   winget install Infisical.cli
   ```

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
        IncludeSpecialChars = $true        # Специальные символы
        MinUppercase = 2
        MinLowercase = 2
        MinDigits = 2
        MinSpecialChars = 2
        ExcludeAmbiguous = $true           # Исключить 0, O, 1, l, I
    }
    
    Infisical = @{
        ApiUrl = "https://infisical.krasintegra.ru"
        ServiceToken = "st.xxx"
        WorkspaceId = "xxx"
        SecretPath = "/"
        
        # Маппинг environment name -> slug
        Environments = @{
            "AD/gmkzoloto.ru" = "prod"
            "krasintegra.ru" = "krasintegra-ru"
            "ag.gold" = "ag-gold"
            "kc124.ru" = "kc124-ru"
            "krasprom.com" = "krasprom-com"
            "sibzoloto24.ru" = "sibzoloto-ru"
            "vagon-k.ru" = "vagon-k-ru"
            "tkkrasline.ru" = "tkkrasline-ru"
        }
        
        # Порядок поиска паролей (имена environments)
        EnvironmentOrder = @(
            "AD/gmkzoloto.ru"
            "krasintegra.ru"
            "ag.gold"
            "kc124.ru"
            "krasprom.com"
            "sibzoloto24.ru"
            "vagon-k.ru"
            "tkkrasline.ru"
        )
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
        ServerUrl = "https://mail.gmkzoloto.ru:7071"
        AdminUser = "admin@domain.ru"
        AdminPassword = "ваш_пароль_админа"
        Domain = "domain.ru"
    }
}
```

## Формат CSV

Все скрипты используют единый файл `users.csv` (путь настраивается в `config.psd1` → `IO.InputCsvPath`):

```csv
Имя учетной записи;email
Иванов Иван Иванович;ivanov@ag.gold
Петров Петр Петрович;petrov@krasintegra.ru
Механик уч. Пит-Городок;meh-pit@gmkzoloto.ru
```

**Формат:**
- Первая колонка — ФИО пользователя (или любое имя/описание)
- Колонка `email` — email адрес пользователя
- Разделитель — точка с запятой (`;`)
- Кодировка — UTF-8 (можно изменить в конфиге на `Windows1251`)

**Принцип работы:**
- Скрипт извлекает логин из email (часть до `@`)
- Домен из email определяет environment для экспорта в Infisical
- Логин нормализуется к нижнему регистру при поиске и сохранении

## Использование

### Reset-ZimbraPasswords.ps1 — Zimbra (основной скрипт)

```powershell
# Тестовый режим (показывает что будет сделано)
.\Reset-ZimbraPasswords.ps1 -DryRun

# Рабочий запуск
.\Reset-ZimbraPasswords.ps1

# С отладкой
.\Reset-ZimbraPasswords.ps1 -DebugMode

# Пропустить Zimbra (только генерация и экспорт)
.\Reset-ZimbraPasswords.ps1 -SkipZimbra

# Пропустить экспорт в Infisical
.\Reset-ZimbraPasswords.ps1 -SkipInfisical

# Принудительный запуск без подтверждения
.\Reset-ZimbraPasswords.ps1 -Force
```

**Алгоритм работы:**

1. **Загрузка конфигурации** — чтение маппинга environments и порядка поиска
2. **Нормализация логина** — логин приводится к нижнему регистру для поиска
3. **Поиск существующих паролей** — перебор environments в указанном порядке:
   - Загружает все секреты из environment
   - Сравнивает ФИО и нормализованный логин
   - Сначала ищет в `AD/gmkzoloto.ru`
   - Если не найден — ищет в `krasintegra.ru`
   - И так далее по списку `EnvironmentOrder`
4. **Переиспользование или генерация**:
   - Если пароль найден в любом environment — использует его
   - Если не найден нигде — генерирует новый
5. **Смена пароля в Zimbra** — через SOAP API (`SetPasswordRequest`)
6. **Экспорт в Infisical** — в environment, соответствующий домену пользователя (логин в нижнем регистре)

**Пример:**
```
Email: ivanov@ag.gold
1. Поиск пароля в AD/gmkzoloto.ru → не найден
2. Поиск пароля в krasintegra.ru → не найден
3. Поиск пароля в ag.gold → найден! → использовать этот пароль
4. Сменить пароль в Zimbra
5. Экспортировать в environment "ag.gold" (slug: ag-gold)
```

### Reset-DomainPasswords.ps1 — AD поиск по ФИО

```powershell
# Тестовый режим
.\Reset-DomainPasswords.ps1 -DryRun

# Рабочий запуск
.\Reset-DomainPasswords.ps1

# Принудительный запуск без подтверждения
.\Reset-DomainPasswords.ps1 -Force
```

### Reset-DomainPasswords-ByEmail.ps1 — AD поиск по email

```powershell
# Тестовый режим
.\Reset-DomainPasswords-ByEmail.ps1 -DryRun

# Рабочий запуск
.\Reset-DomainPasswords-ByEmail.ps1
```

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
Фамилия Имя Отчество (login)
```

**Примеры:**
```
Иванов Иван Иванович (ivanov)
Петров Петр Петрович (petrov)
```

**Важно:** При поиске и сохранении секретов логин нормализуется к нижнему регистру. Это позволяет находить пароли даже если в разных системах логин записан в разном регистре (например, `AEG004` в AD и `aeg004` в Zimbra будут распознаны как один пользователь).

## Структура environments в Infisical

```
Project (WorkspaceId)
├── Environment: AD/gmkzoloto.ru (slug: prod)
│   └── "Иванов Иван Иванович (ivanov)" = "password123"
├── Environment: ag.gold (slug: ag-gold)
│   └── "Иванов Иван Иванович (ivanov)" = "password123"
├── Environment: krasintegra.ru (slug: krasintegra-ru)
│   └── "Петров Петр Петрович (petrov)" = "password456"
```

**Важно:** Service Token должен иметь права на запись во все environments.

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
| `-DebugMode` | Вывод отладочной информации (SOAP запросы/ответы) |

## Выходные файлы

### Backup
- Zimbra: `.\backup\zimbra-passwords-YYYYMMDD-HHMMSS.csv`
- Содержит: Username, Login, Email, Domain, Password, PasswordSource, FoundInEnv, ZimbraChanged, InfisicalExported, Timestamp

### Report
- `.\report-YYYYMMDD-HHMMSS.csv`
- Содержит: Username, Login, Email, Domain, PasswordSource, ADPasswordChanged, InfisicalExported, Environment, Timestamp

## Zimbra SOAP API

Скрипт использует Zimbra Admin SOAP API на порту 7071:

1. **AuthRequest** — авторизация администратора, получение authToken
2. **GetAccountRequest** — получение ID аккаунта по email
3. **SetPasswordRequest** — установка нового пароля

Пример SOAP запроса для авторизации:
```xml
<soap:Envelope xmlns:soap="http://www.w3.org/2003/05/soap-envelope">
  <soap:Header>
    <context xmlns="urn:zimbra"/>
  </soap:Header>
  <soap:Body>
    <AuthRequest xmlns="urn:zimbraAdmin">
      <name>admin@example.com</name>
      <password>password</password>
    </AuthRequest>
  </soap:Body>
</soap:Envelope>
```

Пример SetPasswordRequest:
```xml
<soap:Envelope xmlns:soap="http://www.w3.org/2003/05/soap-envelope">
  <soap:Header>
    <context xmlns="urn:zimbra">
      <authToken>полученный_токен</authToken>
    </context>
  </soap:Header>
  <soap:Body>
    <SetPasswordRequest xmlns="urn:zimbraAdmin" id="account-id" newPassword="newPassword123"/>
  </soap:Body>
</soap:Envelope>
```

## Интеграция с Infisical

### Получение Service Token

1. Войдите в Infisical: `https://infisical.krasintegra.ru`
2. Перейдите в Project → Settings → Service Tokens
3. Создайте токен с правами на **запись секретов во все environments**
4. Скопируйте `Service Token` и `Project ID` в `config.psd1`

### Определение slug для environment

```powershell
# Проверить что slug правильный
infisical secrets list --env=ag-gold --projectId=ВАШ_ID --token=ВАШ_ТОКЕН --domain=https://infisical.krasintegra.ru
```

### Проверка CLI

```powershell
infisical --version
# Должно быть: infisical version 0.43.62 или выше
```

## Решение проблем

### Ошибка "Execution Policy"
```powershell
Set-ExecutionPolicy RemoteSigned -Scope CurrentUser
```

### Ошибка "Config parsing error"
Убедитесь, что в `.psd1` файлах нет комментариев внутри хеш-таблицы.

### Ошибка "environment not found for domain"
Проверьте, что домен из email есть в маппинге `Environments`:
```powershell
# Email: user@newdomain.ru
# Должно быть в конфиге:
Environments = @{
    "newdomain.ru" = "newdomain-slug"
}
```

### Ошибка Infisical "You are not allowed to create on secrets"
Service Token не имеет прав на запись в этот environment. Создайте токен с правами на все нужные environments.

### Ошибка Infisical "unsupported protocol scheme"
Убедитесь, что `ApiUrl` содержит полный адрес с `https://`.

### Ошибка Zimbra "account.NO_SUCH_ACCOUNT"
Аккаунт с указанным email не существует на сервере Zimbra.

### Ошибка Zimbra "connection refused"
Проверьте доступность сервера и правильность URL в `config-zimbra.psd1`. Порт 7071 должен быть доступен.

### Ошибка Zimbra 500 Server Error
Проверьте отладочный вывод `-DebugMode` для анализа SOAP ответа.

## Безопасность

- Пароли генерируются криптографически стойким генератором (`System.Security.Cryptography.RandomNumberGenerator`)
- Service Token даёт доступ только к указанному Project
- Пароль администратора Zimbra хранится в конфиге в открытом виде — ограничьте доступ к файлу
- Локальные бэкапы содержат пароли в открытом виде — защитите папку `backup\`
- Используйте `-DryRun` для тестирования перед реальным запуском
- Рекомендуется удалить локальные бэкапы после проверки экспорта в Infisical

## Лицензия

Внутреннее использование.
