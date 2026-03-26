@{
    AD = @{
        DomainController = "dc-mira-2019.gmkzoloto.ru"
        SearchBase = "gmkzoloto.ru"
        ChangePasswordAtLogon = $false
    }
    
    PasswordGenerator = @{
        Length = 9
        IncludeUppercase = $true
        IncludeLowercase = $true
        IncludeDigits = $true
        IncludeSpecialChars = $true
        ExcludeAmbiguous = $true
        MinUppercase = 2
        MinLowercase = 2
        MinDigits = 2
        MinSpecialChars = 2
    }
    
    Infisical = @{
        ApiUrl = "https://infisical.krasintegra.ru"
        ServiceToken = "st.210ff6ef-7da0-4697-bfc1-3a90aa7c7186.f2c16e938dd29a1cf81e0df7ab981598.9dfac17a02ad9f5c958b2b2452db9311"
        WorkspaceId = "9db52232-b84f-4905-9478-6b640150db46"
        Environment = "prod"
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
        OutputLogPath = ""
        BackupPath = ".\backup"
        SaveLocalBackup = $true
        CsvEncoding = "UTF-8"
    }
    
    Logging = @{
        LogLevel = "Info"
        LogFilePath = ".\password-manager.log"
        ConsoleOutput = $true
    }
    
    Notification = @{
        SendEmailNotification = $false
        SmtpServer = ""
        SmtpPort = 587
        FromEmail = ""
        ToEmails = @()
        EmailSubject = "Password Reset Report"
    }
    
    Security = @{
        SkipNonExistentUsers = $true
        SkipDisabledAccounts = $true
        RequireConfirmation = $true
        DryRun = $false
    }
}
