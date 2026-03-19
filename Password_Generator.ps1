<#
.SYNOPSIS
    Password Generator Wrapper
#>
[CmdletBinding()]
param(
    [string]$ConfigPath = ".\config.psd1",
    [int]$Count = 15,
    [switch]$ShowPasswords
)

 $ErrorActionPreference = "Stop"
 $scriptDir = if ($MyInvocation.MyCommand.Path) { Split-Path -Parent $MyInvocation.MyCommand.Path } else { $PWD.Path }

# Load config
if (-not (Test-Path $ConfigPath)) {
    Write-Host "Config not found: $ConfigPath" -ForegroundColor Red
    exit 1
}
 $config = Import-PowerShellDataFile -Path $ConfigPath

# Load module
 $modulePath = Join-Path $scriptDir "PasswordGenerator.psm1"
if (-not (Test-Path $modulePath)) {
    Write-Host "Module not found: $modulePath" -ForegroundColor Red
    exit 1
}
Import-Module $modulePath -Force

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  Password Generator" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

Write-Host "Settings:" -ForegroundColor Yellow
Write-Host "  Length:     $($config.PasswordGenerator.Length)"
Write-Host "  Uppercase:  $($config.PasswordGenerator.IncludeUppercase)"
Write-Host "  Lowercase:  $($config.PasswordGenerator.IncludeLowercase)"
Write-Host "  Digits:     $($config.PasswordGenerator.IncludeDigits)"
Write-Host "  Special:    $($config.PasswordGenerator.IncludeSpecial)"
Write-Host "`nGenerating $Count passwords...`n" -ForegroundColor Green

# Generate dummy users
 $users = 1..$Count | ForEach-Object {
    [PSCustomObject]@{ Username = "user$_" }
}

# Generate passwords
 $results = New-BatchPasswords -Users $users -Config $config.PasswordGenerator

# Output
 $i = 1
foreach ($r in $results) {
    $pwd = if ($ShowPasswords) { $r.Password } else { $r.Password -replace '(?<=.{3}).', '*' }
    $status = if ($r.IsValid) { "OK" } else { "WEAK" }
    $color = if ($r.IsValid) { "Green" } else { "Yellow" }
    
    Write-Host "  $i. " -NoNewline
    Write-Host "$pwd" -ForegroundColor White -NoNewline
    Write-Host " [$status] [$($r.Strength)]" -ForegroundColor $color
    
    $i++
}

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Generated: $($results.Count) passwords" -ForegroundColor Green
Write-Host "Valid:     $(($results | Where-Object { $_.IsValid }).Count)" -ForegroundColor Green

if (-not $ShowPasswords) {
    Write-Host "`nUse -ShowPasswords to display full passwords" -ForegroundColor DarkGray
}