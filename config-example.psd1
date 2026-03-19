@{
    # ============================================
    # Active Directory Settings
    # ============================================
    AD = @{
        # Домен для поиска пользователей (опционально, если пусто - используется текущий домен)
        DomainController = ""
        # Путь к поиску пользователей (опционально)
        SearchBase = ""
        # Требовать ли смену пароля при следующем входе
        ChangePasswordAtLogon = $false
    }
    
    # ============================================
    # Password Generator Settings
    # ============================================
    PasswordGenerator = @{
        # Длина генерируемого пароля
        Length = 16
        # Включать прописные буквы (A-Z)
        IncludeUppercase = $true
        # Включать строчные буквы (a-z)
        IncludeLowercase = $true
        # Включать цифры (0-9)
        IncludeDigits = $true
        # Включать специальные символы (!@#$%^&*()_+-=[]{}|;:,.<>?)
        IncludeSpecialChars = $false
        # Исключить неоднозначные символы (0O, 1lI, и т.д.)
        ExcludeAmbiguous = $false
        # Минимальное количество символов каждого типа
        MinUppercase = 2
        MinLowercase = 2
        MinDigits = 2
        MinSpecialChars = 2
    }
    
    # ============================================
    # Infisical Settings
    # ============================================
    Infisical = @{
        # URL API Infisical (для облачной версии используйте https://app.infisical.com)
        ApiUrl = "https://infisical.krasintegra.ru"
        
        # Client ID из Machine Identity (Service Token)
        # Получается в Infisical: Project Settings -> Machine Identities -> Service Tokens
        ClientId = "nur001@krasintegra.ru"
        
        # Client Secret из Machine Identity
        ClientSecret = "st.2ca5994c-111d-4ab5-923e-9041239c37f3.591c880d3efd47164b330a1d8b41f6a0.4b12af328fcd839fdafac3804f23740d"
        
        # ID проекта в Infisical
        # Можно найти в URL проекта или через API
        ProjectId = "AD-Secrets"
        
        # Имя окружения (dev, staging, prod, и т.д.)
        Environment = "prod"
        
        # Путь для хранения секретов (например: "domain-users" или "/services/users")
        SecretPath = "/domain-users"
        
        # Тип аутентификации: "client_credentials" или "universal_auth"
        AuthType = "universal_auth"
    }
    
    # ============================================
    # Input/Output Settings
    # ============================================
    IO = @{
        # Путь к CSV файлу со списком пользователей
        InputCsvPath = ".\users.csv"
        
        # Путь для сохранения результатов (лога)
        OutputLogPath = ".\password-reset-log-$(Get-Date -Format 'yyyyMMdd-HHmmss').csv"
        
        # Путь для сохранения резервной копии (зашифрованной)
        BackupPath = ".\backup"
        
        # Сохранять ли локальную копию паролей (зашифрованную)
        SaveLocalBackup = $true
    }
    
    # ============================================
    # Logging Settings
    # ============================================
    Logging = @{
        # Уровень логирования: Debug, Info, Warning, Error
        LogLevel = "Info"
        
        # Путь к файлу лога
        LogFilePath = ".\password-manager.log"
        
        # Выводить ли лог в консоль
        ConsoleOutput = $true
    }
    
    # ============================================
    # Notification Settings (опционально)
    # ============================================
    Notification = @{
        # Отправлять ли уведомления на email
        SendEmailNotification = $false
        
        # SMTP сервер
        SmtpServer = ""
        
        # Порт SMTP
        SmtpPort = 587
        
        # От кого отправлять
        FromEmail = ""
        
        # Кому отправлять отчет (список email)
        ToEmails = @()
        
        # Тема письма
        EmailSubject = "Password Reset Report"
    }
    
    # ============================================
    # Security Settings
    # ============================================
    Security = @{
        # Пропускать пользователей, которых нет в AD (не выдавать ошибку)
        SkipNonExistentUsers = $true
        
        # Пропускать отключенные учетные записи
        SkipDisabledAccounts = $true
        
        # Подтверждение перед выполнением (true = интерактивный режим)
        RequireConfirmation = $true
        
        # Сухой запуск (только симуляция, без реальных изменений)
        DryRun = $true
    }
}
