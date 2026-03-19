<#
.SYNOPSIS
    Infisical Manager using CLI (supports E2EE)
#>

function Test-InfisicalCLI {
    param([string]$CliPath = "infisical")
    
    try {
        $version = & $CliPath --version 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Host "Infisical CLI found: $version" -ForegroundColor Green
            return $true
        }
    }
    catch {
        Write-Host "Infisical CLI not found" -ForegroundColor Red
        return $false
    }
}

function Set-InfisicalSecretCLI {
    param(
        [string]$ServiceToken,
        [string]$WorkspaceId,
        [string]$Environment,
        [string]$SecretPath,
        [string]$SecretKey,
        [string]$SecretValue,
        [string]$ApiUrl,
        [string]$CliPath = "infisical"
    )
    
    $result = @{
        Success = $false
        SecretKey = $SecretKey
        Error = $null
    }
    
    # Проверка ApiUrl
    if ([string]::IsNullOrWhiteSpace($ApiUrl)) {
        $result.Error = "ApiUrl is empty. Check config.psd1 has 'ApiUrl' parameter."
        Write-Host "    ERROR: $result.Error" -ForegroundColor Red
        return [PSCustomObject]$result
    }
    
    try {
        # Build arguments for 'secrets set'
        $args = @(
            "secrets", "set",
            "$SecretKey=$SecretValue",
            "--env=$Environment",
            "--path=$SecretPath",
            "--projectId=$WorkspaceId",
            "--token=$ServiceToken",
            "--domain=$ApiUrl"
        )
        
        Write-Host "    [CMD] infisical secrets set $SecretKey=***" -ForegroundColor DarkGray
        Write-Host "    [DEBUG] --domain=$ApiUrl" -ForegroundColor DarkGray
        
        $output = & $CliPath @args 2>&1
        
        if ($LASTEXITCODE -eq 0) {
            $result.Success = $true
        }
        else {
            $result.Error = $output -join "`n"
        }
    }
    catch {
        $result.Error = $_.Exception.Message
    }
    
    return [PSCustomObject]$result
}

function Import-BatchSecretsCLI {
    param(
        [string]$ServiceToken,
        [string]$WorkspaceId,
        [string]$Environment = "prod",
        [string]$SecretPath = "/",
        [array]$Secrets,
        [string]$ApiUrl,
        [string]$CliPath = "infisical"
    )
    
    $results = @()
    $successCount = 0
    $errorCount = 0
    
    Write-Host "Importing $($Secrets.Count) secrets via CLI..." -ForegroundColor Cyan
    Write-Host "[DEBUG] ApiUrl: $ApiUrl" -ForegroundColor DarkGray
    


    foreach ($sec in $Secrets) {
        $fio = $sec.Username
        $login = $sec.SamAccountName
        if (-not $login) { $login = $fio }
    
        # Заменяем пробелы на подчёркивания
        #$fioClean = $fio -replace '\s+', '_'
        #$key = "$fioClean ($login)"
        $key = "$fio ($login)"
    
        Write-Host "  Setting: $key ... " -NoNewline

        $r = Set-InfisicalSecretCLI `
            -ServiceToken $ServiceToken `
            -WorkspaceId $WorkspaceId `
            -Environment $Environment `
            -SecretPath $SecretPath `
            -SecretKey $key `
            -SecretValue $sec.Password `
            -ApiUrl $ApiUrl `
            -CliPath $CliPath
        
        $results += [PSCustomObject]@{
            Username = $sec.Username
            SamAccountName = $sec.SamAccountName
            SecretKey = $key
            Success = $r.Success
            Error = $r.Error
        }
        
        if ($r.Success) {
            $successCount++
            Write-Host "OK" -ForegroundColor Green
        }
        else {
            $errorCount++
            Write-Host "ERROR" -ForegroundColor Red
            if ($r.Error) {
                $errLines = $r.Error -split "`n" | Select-Object -First 3
                foreach ($line in $errLines) {
                    if ($line) { Write-Host "    $line" -ForegroundColor DarkGray }
                }
            }
        }
    }
    
    Write-Host "`nDone: $successCount ok, $errorCount errors" -ForegroundColor $(if ($errorCount -eq 0) { "Green" } else { "Yellow" })
    return $results
}

Export-ModuleMember -Function @(
    'Test-InfisicalCLI',
    'Set-InfisicalSecretCLI',
    'Import-BatchSecretsCLI'
)