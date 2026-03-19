<#
.SYNOPSIS
    Экспорт пользователей из Active Directory в CSV формат
    
.DESCRIPTION
    Скрипт для создания CSV файла со списком пользователей AD,
    которые будут обработаны основным скриптом смены паролей.
    
.PARAMETER SearchBase
    OU для поиска пользователей (DistinguishedName)
    
.PARAMETER Filter
    Дополнительный фильтр LDAP
    
.PARAMETER OutputPath
    Путь к выходному CSV файлу
    
.PARAMETER IncludeDisabled
    Включать отключенные учётные записи
    
.EXAMPLE
    .\Export-ADUsers.ps1 -SearchBase "OU=Users,DC=company,DC=local" -OutputPath ".\users.csv"
    
.EXAMPLE
    .\Export-ADUsers.ps1 -Filter {Department -eq "IT"} -OutputPath ".\it_users.csv"
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$SearchBase,
    
    [Parameter(Mandatory = $false)]
    [string]$Filter = "*",
    
    [Parameter(Mandatory = $false)]
    [string]$OutputPath = ".\users.csv",
    
    [Parameter(Mandatory = $false)]
    [switch]$IncludeDisabled,
    
    [Parameter(Mandatory = $false)]
    [string]$DomainController
)

# Проверка модуля AD
try {
    Import-Module ActiveDirectory -ErrorAction Stop
}
catch {
    Write-Error "Модуль ActiveDirectory не найден. Установите RSAT."
    exit 1
}

# Формирование параметров запроса
$getADUserParams = @{
    Filter = $Filter
    Properties = @('EmailAddress', 'DisplayName', 'Department', 'Title', 'Enabled', 'LastLogonDate')
    ErrorAction = 'Stop'
}

if ($SearchBase) {
    $getADUserParams.SearchBase = $SearchBase
}

if ($DomainController) {
    $getADUserParams.Server = $DomainController
}

# Получение пользователей
Write-Host "Получение пользователей из Active Directory..." -ForegroundColor Cyan

try {
    $users = Get-ADUser @getADUserParams
    
    # Фильтрация отключенных
    if (-not $IncludeDisabled) {
        $users = $users | Where-Object { $_.Enabled -eq $true }
    }
    
    Write-Host "Найдено пользователей: $($users.Count)" -ForegroundColor Green
}
catch {
    Write-Error "Ошибка получения пользователей: $($_.Exception.Message)"
    exit 1
}

# Формирование данных для экспорта
$exportData = $users | Select-Object `
    @{N='Имя учетной записи';E={$_.SamAccountName}},
    @{N='email';E={$_.EmailAddress}},
    @{N='DisplayName';E={$_.DisplayName}},
    @{N='Department';E={$_.Department}},
    @{N='Title';E={$_.Title}},
    @{N='Enabled';E={$_.Enabled}},
    @{N='LastLogonDate';E={$_.LastLogonDate}}

# Экспорт в CSV
$exportData | Export-Csv -Path $OutputPath -NoTypeInformation -Encoding UTF8 -Delimiter ";"

Write-Host "Файл сохранён: $OutputPath" -ForegroundColor Green

# Вывод статистики
Write-Host ""
Write-Host "Статистика:" -ForegroundColor Cyan
Write-Host "  Всего пользователей: $($exportData.Count)" -ForegroundColor White
Write-Host "  С email: $(($exportData | Where-Object { $_.email }).Count)" -ForegroundColor White
Write-Host "  Без email: $(($exportData | Where-Object { -not $_.email }).Count)" -ForegroundColor Yellow

# Превью
Write-Host ""
Write-Host "Первые 5 записей:" -ForegroundColor Cyan
$exportData | Select-Object -First 5 | Format-Table -AutoSize
