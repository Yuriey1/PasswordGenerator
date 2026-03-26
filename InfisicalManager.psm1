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
    
    Write-Host "Infisical CLI not found" -ForegroundColor Red
    return $false
}

function Test-InfisicalCLICore {
    param([string]$CliPath = "infisical")
    
    try {
        $version = & $CliPath --version 2>&1
        if ($LASTEXITCODE -eq 0) {
            return $true
        }
    }
    catch {}
    
    return $false
}

function Get-InfisicalEnvironments {
    param(
        [hashtable]$ConfigEnvironments  # @{ "name" = "slug" } from config
    )
    
    $result = @{
        Success = $false
        Environments = @{}
        Error = $null
    }
    
    if ($ConfigEnvironments -and $ConfigEnvironments.Count -gt 0) {
        $result.Environments = $ConfigEnvironments
        $result.Success = $true
        Write-Host "  Loaded $($result.Environments.Count) environments from config" -ForegroundColor Green
    } else {
        $result.Error = "No environments configured. Add 'Environments' hashtable to Infisical config section."
        Write-Host "  ERROR: No environments in config" -ForegroundColor Red
    }
    
    return [PSCustomObject]$result
}

function Find-InfisicalSecretInAllEnvironments {
    param(
        [string]$FIO,
        [string]$Login,
        [string]$ServiceToken,
        [string]$WorkspaceId,
        [hashtable]$EnvironmentMap,  # @{ "name" = "slug" }
        [string]$SecretPath = "/",
        [string]$ApiUrl,
        [string]$CliPath = "infisical"
    )
    
    $result = @{
        Found = $false
        SecretKey = $null
        Value = $null
        EnvironmentName = $null
        EnvironmentSlug = $null
        Error = $null
    }
    
    # Format: "Фамилия Имя Отчество (login)"
    $secretName = "$FIO ($Login)"
    
    foreach ($envName in $EnvironmentMap.Keys) {
        $envSlug = $EnvironmentMap[$envName]
        
        try {
            $output = & $CliPath secrets get $secretName `
                "--env=$envSlug" `
                "--path=$SecretPath" `
                "--projectId=$WorkspaceId" `
                "--token=$ServiceToken" `
                "--domain=$ApiUrl" 2>&1
            
            $outputStr = $output -join "`n"
            
            # Check if found
            if ($outputStr -match "\*not found\*" -or $outputStr -match "not found") {
                continue  # Try next environment
            }
            
            # Parse value
            $lines = $outputStr -split "`n"
            foreach ($line in $lines) {
                if ($line -match "│\s*[^│]+\s*│\s*([^│]+)\s*│\s*[^│]+\s*│") {
                    $value = $matches[1].Trim()
                    if ($value -and $value -ne "*not found*" -and $value -ne "SECRET VALUE") {
                        $result.Found = $true
                        $result.SecretKey = $secretName
                        $result.Value = $value
                        $result.EnvironmentName = $envName
                        $result.EnvironmentSlug = $envSlug
                        return [PSCustomObject]$result
                    }
                }
            }
        }
        catch {
            # Continue to next environment
            continue
        }
    }
    
    return [PSCustomObject]$result
}

function Get-InfisicalSecretByFioAndLogin {
    param(
        [string]$FIO,
        [string]$Login,
        [string]$ServiceToken,
        [string]$WorkspaceId,
        [string]$Environment = "dev",
        [string]$SecretPath = "/",
        [string]$ApiUrl,
        [string]$CliPath = "infisical"
    )
    
    $result = @{
        Found = $false
        SecretKey = $null
        Value = $null
        Error = $null
    }
    
    # Format: "Фамилия Имя Отчество (login)"
    $secretName = "$FIO ($Login)"
    
    Write-Host "[DEBUG] Searching: '$secretName'" -ForegroundColor DarkGray
    
    try {
        $output = & $CliPath secrets get $secretName `
            "--env=$Environment" `
            "--path=$SecretPath" `
            "--projectId=$WorkspaceId" `
            "--token=$ServiceToken" `
            "--domain=$ApiUrl" 2>&1
        
        $outputStr = $output -join "`n"
        Write-Host "[DEBUG] Output: $outputStr" -ForegroundColor DarkGray
        
        # Check for "not found" in output
        if ($outputStr -match "\*not found\*" -or $outputStr -match "not found") {
            Write-Host "[DEBUG] Secret NOT found" -ForegroundColor DarkGray
            $result.Found = $false
            return [PSCustomObject]$result
        }
        
        # Parse table output
        $lines = $outputStr -split "`n"
        foreach ($line in $lines) {
            # Match: │ SECRET_NAME │ SECRET_VALUE │ SECRET_TYPE │
            if ($line -match "│\s*[^│]+\s*│\s*([^│]+)\s*│\s*[^│]+\s*│") {
                $value = $matches[1].Trim()
                Write-Host "[DEBUG] Parsed value: '$value'" -ForegroundColor DarkGray
                
                if ($value -and $value -ne "*not found*" -and $value -ne "SECRET VALUE") {
                    $result.Found = $true
                    $result.SecretKey = $secretName
                    $result.Value = $value
                    break
                }
            }
        }
        
        if (-not $result.Found) {
            Write-Host "[DEBUG] No valid value in output" -ForegroundColor DarkGray
        }
    }
    catch {
        $result.Error = $_.Exception.Message
        Write-Host "[DEBUG] Error: $($_.Exception.Message)" -ForegroundColor DarkGray
    }
    
    return [PSCustomObject]$result
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
    
    if ([string]::IsNullOrWhiteSpace($ApiUrl)) {
        $result.Error = "ApiUrl is empty"
        return [PSCustomObject]$result
    }
    
    try {
        Write-Host "    [CMD] infisical secrets set $SecretKey=*** --env=$Environment --projectId=$WorkspaceId --domain=$ApiUrl" -ForegroundColor DarkGray
        
        $output = & $CliPath secrets set "$SecretKey=$SecretValue" `
            "--env=$Environment" `
            "--path=$SecretPath" `
            "--projectId=$WorkspaceId" `
            "--token=$ServiceToken" `
            "--domain=$ApiUrl" 2>&1
        
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
        [string]$Environment = "dev",
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
        $name = $sec.SamAccountName
        if (-not $name) { $name = $sec.Email }
        
        # Extract login from email
        $loginOnly = $name
        if ($name -match "^([^@]+)@") {
            $loginOnly = $matches[1]
        }
        
        $fio = $sec.Username
        
        # Format: "Фамилия Имя Отчество (login)"
        $key = "$fio ($loginOnly)"
        
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
    'Test-InfisicalCLICore',
    'Get-InfisicalEnvironments',
    'Find-InfisicalSecretInAllEnvironments',
    'Get-InfisicalSecretByFioAndLogin',
    'Set-InfisicalSecretCLI',
    'Import-BatchSecretsCLI'
)
