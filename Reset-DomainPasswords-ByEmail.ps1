<#
.SYNOPSIS
    Domain Password Reset Tool with Infisical Export
    Searches users by email username (part before @)
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
Write-Header "Domain Password Reset Tool (Email-based search)"

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

if (-not [System.IO.Path]::IsPathRooted($csvPath)) {
    $csvPath = Join-Path $script:ScriptDir $csvPath
}

Write-Log "CSV path: $csvPath" -Level Info

if (-not (Test-Path $csvPath)) {
    Write-Log "CSV file not found: $csvPath" -Level Error
    exit 1
}

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
        
        $emailUsername = $null
        if ($email -and $email -match "^([^@]+)@") {
            $emailUsername = $matches[1]
        }
        
        if ($username -and $username.Trim()) {
            $script:NormalizedUsers += [PSCustomObject]@{
                Username = $username.Trim()
                Email = if ($email) { $email.Trim() } else { $null }
                EmailUsername = $emailUsername
            }
        }
    }
    
    Write-Log "Normalized: $($script:NormalizedUsers.Count) users" -Level Success
    Write-Host ""
    $script:NormalizedUsers | Format-Table Username, Email, EmailUsername -AutoSize
}
catch { Write-Log "CSV error: $_" -Level Error; exit 1 }

# ============================================
# Confirm
# ============================================
if ($config.Security.RequireConfirmation -and -not $Force -and -not $config.Security.DryRun) {
    Write-Host "`nACTIONS:`n  1. Generate passwords for $($script:NormalizedUsers.Count) users`n  2. Reset AD passwords (search by email username)`n  3. Export to Infisical`n" -ForegroundColor Yellow
    if ($SkipAD) { Write-Host "  [SKIP] AD reset" -ForegroundColor Yellow }
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
# AD Reset (by email username)
# ============================================
$adResults = @()
if (-not $SkipAD) {
    Write-Section "Resetting AD Passwords"
    try { Test-ADModuleAvailable | Out-Null; $adConn = Initialize-ADConnection -DomainController $config.AD.DomainController } catch { Write-Log "AD error: $_" -Level Error; exit 1 }
    
    $whatIf = $config.Security.DryRun
    
    foreach ($p in $validPw) {
        $origUser = $script:NormalizedUsers | Where-Object { $_.Username -eq $p.Username } | Select-Object -First 1
        $emailUser = $origUser.EmailUsername
        $username = $p.Username
        
        Write-Host "  Searching by email username: $emailUser ... " -NoNewline
        
        $result = [PSCustomObject]@{
            Username = $username
            SamAccountName = $null
            Email = $origUser.Email
            Found = $false
            PasswordChanged = $false
            Warnings = @()
            Errors = @()
            Skipped = $false
        }
        
        if (-not $emailUser) {
            Write-Host "NO EMAIL" -ForegroundColor Yellow
            $result.Warnings += "No email username to search"
            $adResults += $result
            continue
        }
        
        try {
            $adUser = Get-ADUser -Filter "SamAccountName -eq '$emailUser'" -ErrorAction SilentlyContinue
            
            if (-not $adUser) {
                $adUser = Get-ADUser -Filter "UserPrincipalName -like '$emailUser*'" -ErrorAction SilentlyContinue
            }
            
            if ($adUser) {
                Write-Host "FOUND ($($adUser.SamAccountName))" -ForegroundColor Green -NoNewline
                $result.Found = $true
                $result.SamAccountName = $adUser.SamAccountName
                
                if ($whatIf) {
                    Write-Host " [WHAT-IF]" -ForegroundColor Cyan
                    $result.PasswordChanged = $true
                    $result.Warnings += "DryRun: password not actually changed"
                } else {
                    try {
                        $ErrorActionPreference = "Stop"
                        Set-ADAccountPassword -Identity $adUser -Reset -NewPassword (ConvertTo-SecureString -AsPlainText $p.Password -Force)
                        Write-Host " CHANGED" -ForegroundColor Green
                        $result.PasswordChanged = $true
                    } catch {
                        Write-Host " ERROR" -ForegroundColor Red
                        Write-Host "    Error: $($_.Exception.Message)" -ForegroundColor Red
                        $result.Errors += $_.Exception.Message
                    }
                }
            } else {
                Write-Host "NOT FOUND" -ForegroundColor Red
                $result.Warnings += "User not found by email username: $emailUser"
            }
        } catch {
            Write-Host "ERROR" -ForegroundColor Red
            Write-Host "    Error: $($_.Exception.Message)" -ForegroundColor Red
            $result.Errors += $_.Exception.Message
        }
        
        $adResults += $result
    }
    
    $s = ($adResults | Where-Object { $_.PasswordChanged }).Count
    Write-Log "AD: $s passwords changed" -Level $(if ($s -eq $validPw.Count) { "Success" } else { "Warning" })
} else {
    Write-Section "AD Reset - SKIPPED"
    foreach ($p in $validPw) {
        $origUser = $script:NormalizedUsers | Where-Object { $_.Username -eq $p.Username } | Select-Object -First 1
        $adResults += [PSCustomObject]@{ Username = $p.Username; SamAccountName = $origUser.EmailUsername; Email = $origUser.Email; Found = $true; PasswordChanged = $true; Warnings = @(); Errors = @(); Skipped = $false }
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
        $ad = $adResults | Where-Object { $_.Username -eq $p.Username } | Select-Object -First 1
        if ($ad -and ($ad.PasswordChanged -or $SkipAD)) {
            $secrets += [PSCustomObject]@{
                Username = $p.Username
                SamAccountName = $ad.SamAccountName
                Email = $ad.Email
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
if ($config.IO.SaveLocalBackup) {
    Write-Section "Saving Backup"
    $bp = $config.IO.BackupPath; if (-not $bp) { $bp = ".\backup" }
    if (-not (Test-Path $bp)) { New-Item -ItemType Directory -Path $bp -Force | Out-Null }
    $bf = Join-Path $bp "passwords-$(Get-Date -Format 'yyyyMMdd-HHmmss').csv"
    $bd = @()
    foreach ($p in $validPw) {
        $ad = $adResults | Where-Object { $_.Username -eq $p.Username } | Select-Object -First 1
        $bd += [PSCustomObject]@{ Username = $p.Username; SamAccountName = $ad.SamAccountName; Email = $ad.Email; Password = $p.Password; Strength = $p.Strength; Timestamp = $p.Timestamp }
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
foreach ($u in $script:NormalizedUsers) {
    $pw = $pwResults | Where-Object { $_.Username -eq $u.Username } | Select-Object -First 1
    $ad = $adResults | Where-Object { $_.Username -eq $u.Username } | Select-Object -First 1
    $inf = $infResults | Where-Object { $_.Username -eq $u.Username } | Select-Object -First 1
    $report += [PSCustomObject]@{
        Username = $u.Username
        EmailUsername = $u.EmailUsername
        SamAccountName = $ad.SamAccountName
        Email = $u.Email
        PasswordGenerated = $pw.IsValid
        ADPasswordChanged = $ad.PasswordChanged
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
if ($config.Security.DryRun) { Write-Host "`nDRYRUN - NO CHANGES MADE" -ForegroundColor Yellow }
Write-Log "Completed" -Level Success
