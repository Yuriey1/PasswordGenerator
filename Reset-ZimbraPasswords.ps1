<#
.SYNOPSIS
    Zimbra Password Reset Tool with Infisical Export
#>
[CmdletBinding()]
param(
    [string]$ConfigPath = ".\config.psd1",
    [string]$ZimbraConfigPath = ".\config-zimbra.psd1",
    [string]$InputCsv,
    [switch]$DryRun,
    [switch]$SkipZimbra,
    [switch]$SkipInfisical,
    [switch]$Force,
    [switch]$GenerateOnly,
    [switch]$DebugMode
)

$ErrorActionPreference = "Stop"
$script:StartTime = Get-Date
$script:ScriptDir = if ($MyInvocation.MyCommand.Path) { Split-Path -Parent $MyInvocation.MyCommand.Path } else { $PWD.Path }
$script:DryRunMode = $DryRun

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
Write-Header "Zimbra Password Reset Tool"

# Load main config
Write-Log "Loading main configuration..."
$mainConfigPath = $ConfigPath
if (-not [System.IO.Path]::IsPathRooted($mainConfigPath)) {
    $mainConfigPath = Join-Path $script:ScriptDir $mainConfigPath
}
if (-not (Test-Path $mainConfigPath)) { Write-Log "Config not found: $mainConfigPath" -Level Error; exit 1 }
try { $config = Import-PowerShellDataFile -Path $mainConfigPath; Write-Log "Main config loaded" -Level Success } catch { Write-Log "Config error: $_" -Level Error; exit 1 }

# Load Zimbra config
Write-Log "Loading Zimbra configuration..."
$zimbraConfigPath = $ZimbraConfigPath
if (-not [System.IO.Path]::IsPathRooted($zimbraConfigPath)) {
    $zimbraConfigPath = Join-Path $script:ScriptDir $zimbraConfigPath
}
if (-not (Test-Path $zimbraConfigPath)) { Write-Log "Zimbra config not found: $zimbraConfigPath" -Level Error; exit 1 }
try { $zimbraConfig = Import-PowerShellDataFile -Path $zimbraConfigPath; Write-Log "Zimbra config loaded" -Level Success } catch { Write-Log "Zimbra config error: $_" -Level Error; exit 1 }

# Merge configs
$config.Zimbra = $zimbraConfig.Zimbra

# Set DryRun mode
if ($DryRun) { $script:DryRunMode = $true }

if ($InputCsv) { $config.IO.InputCsvPath = $InputCsv }
if ($GenerateOnly) { $SkipZimbra = $true; $SkipInfisical = $true }

# ============================================
# Load Modules
# ============================================
Write-Section "Loading Modules"
foreach ($m in @("PasswordGenerator.psm1", "ZimbraManager.psm1", "InfisicalManager.psm1")) {
    $p = Join-Path $script:ScriptDir $m
    if (Test-Path $p) { Import-Module $p -Force; Write-Log "$m loaded" -Level Success } else { Write-Log "$m not found" -Level Error; exit 1 }
}

# ============================================
# Load Users from CSV
# ============================================
Write-Section "Loading Users"

$csvPath = $config.IO.InputCsvPath

if (-not [System.IO.Path]::IsPathRooted($csvPath)) {
    $csvPath = Join-Path $script:ScriptDir $csvPath
}

Write-Log "CSV path: $csvPath" -Level Info

if (-not (Test-Path $csvPath)) {
    Write-Log "CSV file not found: $csvPath" -Level Error
    exit 1
}

$encName = $config.IO.CsvEncoding
if (-not $encName) { $encName = "UTF8" }
$encoding = switch ($encName) {
    "Windows1251" { [System.Text.Encoding]::GetEncoding("windows-1251") }
    "UTF8" { [System.Text.Encoding]::UTF8 }
    default { [System.Text.Encoding]::UTF8 }
}
Write-Log "CSV encoding: $encName" -Level Info

try {
    $csvContent = [System.IO.File]::ReadAllText($csvPath, $encoding)
    $csvUsers = $csvContent | ConvertFrom-Csv -Delimiter ";"
    Write-Log "Loaded $($csvUsers.Count) rows from CSV" -Level Info
    
    if ($csvUsers.Count -gt 0) {
        $cols = $csvUsers[0].PSObject.Properties.Name
        Write-Host "  Columns: $($cols -join ', ')" -ForegroundColor Gray
    }
    
    $script:NormalizedUsers = @()
    foreach ($u in $csvUsers) {
        $firstCol = $u.PSObject.Properties.Name[0]
        $username = $u.$firstCol
        
        $email = $null
        $emailCol = $u.PSObject.Properties.Name | Where-Object { $_ -match "^email$" }
        if ($emailCol) {
            $email = $u.$emailCol
        }
        
        if ($username -and $username.Trim()) {
            $script:NormalizedUsers += [PSCustomObject]@{
                Username = $username.Trim()
                Email = if ($email) { $email.Trim().ToLower() } else { $null }
            }
        }
    }
    
    Write-Log "Normalized: $($script:NormalizedUsers.Count) users" -Level Success
    Write-Host ""
    $script:NormalizedUsers | Format-Table Username, Email -AutoSize
}
catch { Write-Log "CSV error: $_" -Level Error; exit 1 }

# ============================================
# Confirm
# ============================================
$requireConfirm = $true
if ($config.Security -and $config.Security.RequireConfirmation) {
    $requireConfirm = $config.Security.RequireConfirmation
}

if ($requireConfirm -and -not $Force -and -not $script:DryRunMode) {
    Write-Host "`nACTIONS:`n  1. Generate passwords for $($script:NormalizedUsers.Count) users`n  2. Reset Zimbra passwords`n  3. Export to Infisical`n" -ForegroundColor Yellow
    if ($SkipZimbra) { Write-Host "  [SKIP] Zimbra reset" -ForegroundColor Yellow }
    if ($SkipInfisical) { Write-Host "  [SKIP] Infisical" -ForegroundColor Yellow }
    if ($DryRun) { Write-Host "  [DRYRUN] No changes" -ForegroundColor Cyan }
    if ((Read-Host "Continue? (Y/N)") -notmatch "^[Yy]$") { Write-Log "Cancelled" -Level Warning; exit 0 }
}

# ============================================
# Generate Passwords
# ============================================
Write-Section "Generating Passwords"
$pwResults = New-BatchPasswords -Users $script:NormalizedUsers -Config $config.PasswordGenerator
$validPw = @($pwResults | Where-Object { $_.IsValid })
Write-Log "Generated: $($pwResults.Count), Valid: $($validPw.Count)" -Level Success

# ============================================
# Zimbra Reset
# ============================================
$zimbraResults = @()
if (-not $SkipZimbra) {
    Write-Section "Resetting Zimbra Passwords"
    
    # Connect to Zimbra
    $connected = Initialize-ZimbraConnection `
        -ServerUrl $config.Zimbra.ServerUrl `
        -AdminUser $config.Zimbra.AdminUser `
        -AdminPassword $config.Zimbra.AdminPassword `
        -Domain $config.Zimbra.Domain `
        -DebugMode:$DebugMode
    
    if (-not $connected) {
        Write-Log "Failed to connect to Zimbra" -Level Error
        exit 1
    }
    
    # Prepare users with passwords
    $usersToReset = @()
    foreach ($p in $validPw) {
        $origUser = $script:NormalizedUsers | Where-Object { $_.Username -eq $p.Username } | Select-Object -First 1
        $usersToReset += [PSCustomObject]@{
            Username = $p.Username
            Email = $origUser.Email
            Password = $p.Password
        }
    }
    
    $zimbraResults = Reset-BatchZimbraPasswords -UsersWithPasswords $usersToReset -WhatIf:$script:DryRunMode
    
    $s = ($zimbraResults | Where-Object { $_.PasswordChanged }).Count
    Write-Log "Zimbra: $s passwords changed" -Level $(if ($s -eq $validPw.Count) { "Success" } else { "Warning" })
} else {
    Write-Section "Zimbra Reset - SKIPPED"
    foreach ($p in $validPw) {
        $origUser = $script:NormalizedUsers | Where-Object { $_.Username -eq $p.Username } | Select-Object -First 1
        $zimbraResults += [PSCustomObject]@{ Username = $p.Username; Email = $origUser.Email; PasswordChanged = $true; Error = $null }
    }
}

# ============================================
# Export to Infisical
# ============================================
$infResults = @()

if (-not $SkipInfisical) {
    Write-Section "Exporting to Infisical"
    
    $ic = $config.Infisical
    
    $cliExists = Test-InfisicalCLI
    
    if (-not $cliExists) {
        Write-Log "Infisical CLI not found" -Level Error
        Write-Log "Install: https://github.com/Infisical/infisical/releases/latest" -Level Warning
        exit 1
    }
    
    $secrets = @()
    foreach ($p in $validPw) {
        $zim = $zimbraResults | Where-Object { $_.Username -eq $p.Username } | Select-Object -First 1
        if ($zim -and ($zim.PasswordChanged -or $SkipZimbra)) {
            $secrets += [PSCustomObject]@{
                Username = $p.Username
                SamAccountName = $zim.Email
                Email = $zim.Email
                Password = $p.Password
            }
        }
    }
    
    Write-Log "Exporting $($secrets.Count) secrets" -Level Info
    
    if ($secrets.Count -gt 0) {
        $infResults = Import-BatchSecretsCLI `
            -ServiceToken $ic.ServiceToken `
            -WorkspaceId $ic.WorkspaceId `
            -Environment $ic.Environment `
            -SecretPath $ic.SecretPath `
            -Secrets $secrets `
            -ApiUrl $ic.ApiUrl
    }
} else {
    Write-Section "Infisical - SKIPPED"
}

# ============================================
# Backup
# ============================================
$saveBackup = $true
if ($config.IO.SaveLocalBackup -ne $null) {
    $saveBackup = $config.IO.SaveLocalBackup
}

if ($saveBackup) {
    Write-Section "Saving Backup"
    $bp = $config.IO.BackupPath; if (-not $bp) { $bp = ".\backup" }
    if (-not (Test-Path $bp)) { New-Item -ItemType Directory -Path $bp -Force | Out-Null }
    $bf = Join-Path $bp "zimbra-passwords-$(Get-Date -Format 'yyyyMMdd-HHmmss').csv"
    $bd = @()
    foreach ($p in $validPw) {
        $zim = $zimbraResults | Where-Object { $_.Username -eq $p.Username } | Select-Object -First 1
        $bd += [PSCustomObject]@{ Username = $p.Username; Email = $zim.Email; Password = $p.Password; Strength = $p.Strength; Timestamp = $p.Timestamp }
    }
    $bd | Export-Csv -Path $bf -NoTypeInformation -Encoding UTF8 -Delimiter ";"
    Write-Log "Backup: $bf" -Level Success
}

# ============================================
# Report
# ============================================
Write-Section "Report"
$rp = ".\zimbra-report-$(Get-Date -Format 'yyyyMMdd-HHmmss').csv"
$report = @()
foreach ($u in $script:NormalizedUsers) {
    $pw = $pwResults | Where-Object { $_.Username -eq $u.Username } | Select-Object -First 1
    $zim = $zimbraResults | Where-Object { $_.Username -eq $u.Username } | Select-Object -First 1
    $inf = $infResults | Where-Object { $_.Username -eq $u.Username } | Select-Object -First 1
    $report += [PSCustomObject]@{
        Username = $u.Username
        Email = $u.Email
        PasswordGenerated = $pw.IsValid
        ZimbraPasswordChanged = $zim.PasswordChanged
        InfisicalExported = $inf.Success
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
Write-Host "Time: $($d.ToString('mm\:ss'))`nUsers: $($script:NormalizedUsers.Count)`nPasswords: $($validPw.Count)" -ForegroundColor Cyan
if ($script:DryRunMode) { Write-Host "`nDRYRUN - NO CHANGES MADE" -ForegroundColor Yellow }
Write-Log "Completed" -Level Success