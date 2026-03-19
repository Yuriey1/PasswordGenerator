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
        ServiceToken = "st.4b9dd06c-79a9-4480-b6b9-14f15f6f662f.3e91acd752976bec15f4a39d3b41dd00.42826d96a2482f7b9c7207602dfc3b2e"
        WorkspaceId = "9db52232-b84f-4905-9478-6b640150db46"
        Environment = "prod"
        SecretPath = "/"
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
