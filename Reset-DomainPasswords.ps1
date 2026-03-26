<#
.SYNOPSIS
    Domain Password Reset Tool with Infisical Export
#>
[CmdletBinding()]
param(
    [string]$ConfigPath = ".\config.psd1",
    [string]$InputCsv,
    [switch]$DryRun,
    [switch]$SkipAD,
    [switch]$SkipInfisical,
    [switch]$Force,
    [switch]$GenerateOnly
)

 $ErrorActionPreference = "Stop"
 $script:StartTime = Get-Date
 $script:ScriptDir = if ($MyInvocation.MyCommand.Path) { Split-Path -Parent $MyInvocation.MyCommand.Path } else { $PWD.Path }

function Write-Log {
    param([string]$Message, [ValidateSet("Info","Warning","Error","Success")][string]$Level = "Info")
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $prefix = @{ Info = "[INFO]"; Warning = "[WARN]"; Error = "[ERROR]"; Success = "[OK]" }[$Level]
    $color = @{ Info = "White"; Warning = "Yellow"; Error = "Red"; Success = "Green" }[$Level]
    $msg = "$ts $prefix $Message"
    Write-Host $msg -ForegroundColor $color
    if ($config.Logging.LogFilePath) { Add-Content -Path $config.Logging.LogFilePath -Value $msg -Encoding UTF8 }
}

function Write-Header { param([string]$Text) Write-Host "`n$("=" * 60)`n  $Text`n$("=" * 60)`n" -ForegroundColor Cyan }
function Write-Section { param([string]$Text) Write-Host "`n--- $Text ---" -ForegroundColor Yellow }

# ============================================
# Load Configuration
# ============================================
Write-Header "Domain Password Reset Tool"

Write-Log "Loading configuration..."
if (-not (Test-Path $ConfigPath)) { Write-Log "Config not found: $ConfigPath" -Level Error; exit 1 }
try { $config = Import-PowerShellDataFile -Path $ConfigPath; Write-Log "Config loaded" -Level Success } catch { Write-Log "Config error: $_" -Level Error; exit 1 }

if ($DryRun) { $config.Security.DryRun = $true }
if ($InputCsv) { $config.IO.InputCsvPath = $InputCsv }
if ($GenerateOnly) { $SkipAD = $true; $SkipInfisical = $true }

# ============================================
# Load Modules
# ============================================
Write-Section "Loading Modules"
foreach ($m in @("PasswordGenerator.psm1", "ADManager.psm1", "InfisicalManager.psm1")) {
    $p = Join-Path $script:ScriptDir $m
    if (Test-Path $p) { Import-Module $p -Force; Write-Log "$m loaded" -Level Success } else { Write-Log "$m not found" -Level Error; exit 1 }
}

# ============================================
# Load Users from CSV
# ============================================
Write-Section "Loading Users"

 $csvPath = $config.IO.InputCsvPath

# Fix: use full path relative to script directory
if (-not [System.IO.Path]::IsPathRooted($csvPath)) {
    $csvPath = Join-Path $script:ScriptDir $csvPath
}

Write-Log "CSV path: $csvPath" -Level Info

if (-not (Test-Path $csvPath)) {
    Write-Log "CSV file not found: $csvPath" -Level Error
    exit 1
}

# Encoding
 $encName = $config.IO.CsvEncoding
if (-not $encName) { $encName = "Windows1251" }
 $encoding = switch ($encName) {
    "Windows1251" { [System.Text.Encoding]::GetEncoding("windows-1251") }
    "UTF8" { [System.Text.Encoding]::UTF8 }
    default { [System.Text.Encoding]::GetEncoding("windows-1251") }
}
Write-Log "CSV encoding: $encName" -Level Info

try {
    $csvContent = [System.IO.File]::ReadAllText($csvPath, $encoding)
    $csvUsers = $csvContent | ConvertFrom-Csv -Delimiter ";"
    Write-Log "Loaded $($csvUsers.Count) rows from CSV" -Level Info
    
    # Show first row for debug
    if ($csvUsers.Count -gt 0) {
        $firstCol = $csvUsers[0].PSObject.Properties.Name[0]
        Write-Host "  First column: '$firstCol'" -ForegroundColor Gray
        Write-Host "  First value: '$($csvUsers[0].$firstCol)'" -ForegroundColor Gray
    }
    
    $normalized = @()
    foreach ($u in $csvUsers) {
        # First column = FIO/Username
        $username = $u.PSObject.Properties.Value[0]
        # Second column = Email (if exists)
        $email = if ($u.PSObject.Properties.Count -ge 2) { $u.PSObject.Properties.Value[1] } else { $null }
        
        if ($username -and $username.Trim()) {
            $normalized += [PSCustomObject]@{
                Username = $username.Trim()
                Email = if ($email) { $email.Trim() } else { $null }
            }
        }
    }
    
    Write-Log "Normalized: $($normalized.Count) users" -Level Success
    Write-Host ""
    $normalized | Format-Table Username, Email -AutoSize
}
catch { Write-Log "CSV error: $_" -Level Error; exit 1 }

# ============================================
# Get Infisical Environments (mapping name -> slug)
# ============================================
$envMap = @{}

if (-not $SkipInfisical) {
    Write-Section "Fetching Infisical Environments"
    
    $ic = $config.Infisical
    
    # Check CLI
    $cliExists = Test-InfisicalCLI
    
    if (-not $cliExists) {
        Write-Log "Infisical CLI not found" -Level Error
        Write-Log "Install: https://github.com/Infisical/infisical/releases/latest" -Level Warning
        exit 1
    }
    
    # Get environments
    $envResult = Get-InfisicalEnvironments `
        -ServiceToken $ic.ServiceToken `
        -WorkspaceId $ic.WorkspaceId `
        -ApiUrl $ic.ApiUrl
    
    if (-not $envResult.Success) {
        Write-Log "Failed to get environments: $($envResult.Error)" -Level Error
        exit 1
    }
    
    $envMap = $envResult.Environments
    
    Write-Host ""
    Write-Host "  Environment mapping:" -ForegroundColor Cyan
    foreach ($key in $envMap.Keys) {
        Write-Host "    '$key' -> '$($envMap[$key])'" -ForegroundColor Gray
    }
}

# ============================================
# Process Users: Check existing passwords and generate new ones
# ============================================
Write-Section "Processing Passwords"

$usersWithPasswords = @()
$reusedCount = 0
$generatedCount = 0
$skippedCount = 0

foreach ($u in $normalized) {
    $email = $u.Email
    $fio = $u.Username
    
    # Extract login from email
    $login = $null
    $domain = $null
    if ($email -match "^([^@]+)@(.+)$") {
        $login = $matches[1]
        $domain = $matches[2]
    }
    
    if (-not $login) {
        Write-Host "  [SKIP] $($fio): no email or cannot extract login" -ForegroundColor Yellow
        $skippedCount++
        continue
    }
    
    # Find environment slug for this domain
    $envSlug = $null
    if ($envMap.Count -gt 0) {
        $envSlug = $envMap[$domain]
        Write-Host "  [DEBUG] Domain '$domain' -> slug '$envSlug'" -ForegroundColor DarkGray
    }
    
    if (-not $envSlug -and -not $SkipInfisical) {
        Write-Host "  [SKIP] $($fio): environment not found for domain '$domain'" -ForegroundColor Yellow
        Write-Host "  [DEBUG] Available environments: $($envMap.Keys -join ', ')" -ForegroundColor DarkGray
        $skippedCount++
        continue
    }
    
    # Check if password already exists in Infisical (READ operation - always execute)
    $existingPassword = $null
    $passwordSource = "generated"
    
    if (-not $SkipInfisical) {
        $existingSecret = Find-InfisicalSecretInAllEnvironments `
            -FIO $fio `
            -Login $login `
            -ServiceToken $ic.ServiceToken `
            -WorkspaceId $ic.WorkspaceId `
            -EnvironmentMap $envMap `
            -SecretPath $ic.SecretPath `
            -ApiUrl $ic.ApiUrl
        
        if ($existingSecret.Found) {
            $existingPassword = $existingSecret.Value
            $passwordSource = "reused from '$($existingSecret.EnvironmentName)'"
            $reusedCount++
            Write-Host "  [REUSE] $fio ($login@$domain) - found in '$($existingSecret.EnvironmentName)'" -ForegroundColor Cyan
        }
    }
    
    # Generate new password if not found
    if (-not $existingPassword) {
        $pwResult = New-SinglePassword -Username $fio -Config $config.PasswordGenerator
        if ($pwResult.IsValid) {
            $existingPassword = $pwResult.Password
            $generatedCount++
            Write-Host "  [NEW] $fio ($login@$domain)" -ForegroundColor Green
        } else {
            Write-Host "  [ERROR] $fio: password generation failed" -ForegroundColor Red
            $skippedCount++
            continue
        }
    }
    
    $usersWithPasswords += [PSCustomObject]@{
        Username = $fio
        Email = $email
        Login = $login
        Domain = $domain
        EnvSlug = $envSlug
        Password = $existingPassword
        PasswordSource = $passwordSource
    }
}

Write-Log "Users processed: $($usersWithPasswords.Count) (reused: $reusedCount, generated: $generatedCount, skipped: $skippedCount)" -Level $(if ($skippedCount -gt 0) { "Warning" } else { "Success" })

if ($usersWithPasswords.Count -eq 0) {
    Write-Log "No users to process" -Level Warning
    exit 0
}

# ============================================
# Confirm
# ============================================
if ($config.Security.RequireConfirmation -and -not $Force -and -not $config.Security.DryRun) {
    Write-Host "`nACTIONS:`n  1. Processed $($usersWithPasswords.Count) users`n  2. Reset AD passwords`n  3. Export to Infisical`n" -ForegroundColor Yellow
    if ($SkipAD) { Write-Host "  [SKIP] AD reset" -ForegroundColor Yellow }
    if ($SkipInfisical) { Write-Host "  [SKIP] Infisical" -ForegroundColor Yellow }
    if ($DryRun) { Write-Host "  [DRYRUN] No changes" -ForegroundColor Cyan }
    if ((Read-Host "Continue? (Y/N)") -notmatch "^[Yy]$") { Write-Log "Cancelled" -Level Warning; exit 0 }
}

# ============================================
# AD Reset
# ============================================
 $adResults = @()
if (-not $SkipAD) {
    Write-Section "Resetting AD Passwords"
    try { Test-ADModuleAvailable | Out-Null; $adConn = Initialize-ADConnection -DomainController $config.AD.DomainController } catch { Write-Log "AD error: $_" -Level Error; exit 1 }
    
    # Prepare users for AD reset
    $adUsers = @()
    foreach ($u in $usersWithPasswords) {
        $adUsers += [PSCustomObject]@{
            Username = $u.Username
            Email = $u.Email
            Password = $u.Password
        }
    }
    
    $adResults = Reset-BatchADPasswords -UsersWithPasswords $adUsers -ADConfig $config.AD -SecurityConfig $config.Security -WhatIf:$config.Security.DryRun
    $s = ($adResults | Where-Object { $_.PasswordChanged }).Count
    Write-Log "AD: $s passwords changed" -Level $(if ($s -eq $usersWithPasswords.Count) { "Success" } else { "Warning" })
} else {
    Write-Section "AD Reset - SKIPPED"
    foreach ($u in $usersWithPasswords) {
        $adResults += [PSCustomObject]@{ Username = $u.Username; SamAccountName = $u.Login; Email = $u.Email; Found = $true; PasswordChanged = $true; Warnings = @(); Errors = @(); Skipped = $false }
    }
}

# ============================================
# Export to Infisical
# ============================================
 $infResults = @()

if (-not $SkipInfisical) {
    Write-Section "Exporting to Infisical"
    
    $ic = $config.Infisical
    $successCount = 0
    $errorCount = 0
    
    foreach ($u in $usersWithPasswords) {
        $ad = $adResults | Where-Object { $_.Username -eq $u.Username } | Select-Object -First 1
        
        if (-not $ad -or (-not $ad.PasswordChanged -and -not $SkipAD)) {
            Write-Host "  [SKIP] $($u.Username): AD password not changed" -ForegroundColor DarkGray
            continue
        }
        
        # Secret key format: "Фамилия Имя Отчество (login)"
        $secretKey = "$($u.Username) ($($u.Login))"
        
        Write-Host "  Exporting: $secretKey" -NoNewline
        Write-Host " [env=$($u.Domain), slug=$($u.EnvSlug)]" -NoNewline -ForegroundColor DarkGray
        
        if ($config.Security.DryRun) {
            Write-Host " [DRYRUN]" -ForegroundColor Cyan
            $infResults += [PSCustomObject]@{
                Username = $u.Username
                SecretKey = $secretKey
                Environment = $u.Domain
                Success = $true
                Error = $null
            }
            $successCount++
            continue
        }
        
        Write-Host " ..." -NoNewline
        
        $r = Set-InfisicalSecretCLI `
            -ServiceToken $ic.ServiceToken `
            -WorkspaceId $ic.WorkspaceId `
            -Environment $u.EnvSlug `
            -SecretPath $ic.SecretPath `
            -SecretKey $secretKey `
            -SecretValue $u.Password `
            -ApiUrl $ic.ApiUrl
        
        $infResults += [PSCustomObject]@{
            Username = $u.Username
            SecretKey = $secretKey
            Environment = $u.Domain
            Success = $r.Success
            Error = $r.Error
        }
        
        if ($r.Success) {
            Write-Host " OK" -ForegroundColor Green
            $successCount++
        } else {
            Write-Host " ERROR" -ForegroundColor Red
            if ($r.Error) {
                $errLines = $r.Error -split "`n" | Select-Object -First 3
                foreach ($line in $errLines) {
                    if ($line) { Write-Host "    $line" -ForegroundColor DarkGray }
                }
            }
            $errorCount++
        }
    }
    
    Write-Log "Infisical: $successCount exported, $errorCount errors" -Level $(if ($errorCount -eq 0) { "Success" } else { "Warning" })
} else {
    Write-Section "Infisical - SKIPPED"
}

# ============================================
# Backup
# ============================================
if ($config.IO.SaveLocalBackup) {
    Write-Section "Saving Backup"
    $bp = $config.IO.BackupPath; if (-not $bp) { $bp = ".\backup" }
    if (-not (Test-Path $bp)) { New-Item -ItemType Directory -Path $bp -Force | Out-Null }
    $bf = Join-Path $bp "passwords-$(Get-Date -Format 'yyyyMMdd-HHmmss').csv"
    $bd = @()
    foreach ($u in $usersWithPasswords) {
        $ad = $adResults | Where-Object { $_.Username -eq $u.Username } | Select-Object -First 1
        $bd += [PSCustomObject]@{ 
            Username = $u.Username
            Login = $u.Login
            Email = $u.Email
            Domain = $u.Domain
            Password = $u.Password
            PasswordSource = $u.PasswordSource
            Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        }
    }
    $bd | Export-Csv -Path $bf -NoTypeInformation -Encoding UTF8 -Delimiter ";"
    Write-Log "Backup: $bf" -Level Success
}

# ============================================
# Report
# ============================================
Write-Section "Report"
 $rp = ".\report-$(Get-Date -Format 'yyyyMMdd-HHmmss').csv"
 $report = @()
foreach ($u in $usersWithPasswords) {
    $ad = $adResults | Where-Object { $_.Username -eq $u.Username } | Select-Object -First 1
    $inf = $infResults | Where-Object { $_.Username -eq $u.Username } | Select-Object -First 1
    $report += [PSCustomObject]@{
        Username = $u.Username
        Login = $u.Login
        Email = $u.Email
        Domain = $u.Domain
        PasswordSource = $u.PasswordSource
        ADPasswordChanged = $ad.PasswordChanged
        InfisicalExported = if ($inf) { $inf.Success } else { $false }
        Environment = $u.Domain
        Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    }
}
 $report | Export-Csv -Path $rp -NoTypeInformation -Encoding UTF8 -Delimiter ";"
Write-Log "Report: $rp" -Level Success

# ============================================
# Summary
# ============================================
Write-Header "SUMMARY"
 $d = (Get-Date) - $script:StartTime
Write-Host "Time: $($d.ToString('mm\:ss'))" -ForegroundColor Cyan
Write-Host "Users in CSV: $($normalized.Count)" -ForegroundColor Cyan
Write-Host "Users processed: $($usersWithPasswords.Count)" -ForegroundColor Cyan
Write-Host "  - Reused passwords: $reusedCount" -ForegroundColor Cyan
Write-Host "  - Generated passwords: $generatedCount" -ForegroundColor Cyan
Write-Host "  - Skipped: $skippedCount" -ForegroundColor $(if ($skippedCount -gt 0) { "Yellow" } else { "Cyan" })
if ($config.Security.DryRun) { Write-Host "`nDRYRUN - NO CHANGES MADE" -ForegroundColor Yellow }
Write-Log "Completed" -Level Success
