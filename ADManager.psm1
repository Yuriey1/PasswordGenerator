function Test-ADModuleAvailable {
    $module = Get-Module -Name ActiveDirectory -ListAvailable -ErrorAction SilentlyContinue
    if (-not $module) { throw "ActiveDirectory module not found. Install RSAT." }
    return $true
}

function Initialize-ADConnection {
    param([string]$DomainController, [System.Management.Automation.PSCredential]$Credential)
    Test-ADModuleAvailable | Out-Null
    Import-Module ActiveDirectory -ErrorAction Stop
    $params = @{ ErrorAction = 'Stop' }
    if ($DomainController) { $params.Server = $DomainController }
    if ($Credential) { $params.Credential = $Credential }
    $domain = Get-ADDomain @params
    Write-Host "Connected to domain: $($domain.DNSRoot)" -ForegroundColor Green
    return [PSCustomObject]@{ Connected = $true; Domain = $domain.DNSRoot }
}

function Find-ADUser {
    param(
        [string]$Identifier,
        [string]$DomainController,
        [System.Management.Automation.PSCredential]$Credential
    )
    
    $baseParams = @{
        Properties = @('SamAccountName','DisplayName','Name','CN','EmailAddress','Enabled','LockedOut','PasswordExpired','PasswordLastSet','LastLogonDate','DistinguishedName')
        ErrorAction = 'SilentlyContinue'
    }
    if ($DomainController) { $baseParams.Server = $DomainController }
    if ($Credential) { $baseParams.Credential = $Credential }
    
    # 1. Try exact SamAccountName
    try {
        $user = Get-ADUser -Identity $Identifier @baseParams
        if ($user) { return $user }
    } catch {}
    
    # 2. Use Where-Object with -match (works with Cyrillic!)
    try {
        $user = Get-ADUser -Filter * @baseParams | Where-Object { 
            $_.DisplayName -match [regex]::Escape($Identifier) -or
            $_.Name -match [regex]::Escape($Identifier)
        } | Select-Object -First 1
        
        if ($user) { return $user }
    } catch {}
    
    # 3. Try partial match (contains)
    try {
        $user = Get-ADUser -Filter * @baseParams | Where-Object { 
            $_.DisplayName -like "*$Identifier*" -or
            $_.Name -like "*$Identifier*"
        } | Select-Object -First 1
        
        if ($user) { return $user }
    } catch {}
    
    # 4. Try Email
    try {
        $user = Get-ADUser -Filter * @baseParams | Where-Object { 
            $_.EmailAddress -eq $Identifier
        } | Select-Object -First 1
        
        if ($user) { return $user }
    } catch {}
    
    return $null
}

function Get-ADUserInfo {
    param([string]$Identifier, [string]$DomainController, [System.Management.Automation.PSCredential]$Credential)
    
    try {
        $user = Find-ADUser -Identifier $Identifier -DomainController $DomainController -Credential $Credential
        if ($user) {
            return [PSCustomObject]@{
                Found = $true
                SamAccountName = $user.SamAccountName
                DisplayName = $user.DisplayName
                Name = $user.Name
                Email = $user.EmailAddress
                Enabled = $user.Enabled
                LockedOut = $user.LockedOut
                PasswordExpired = $user.PasswordExpired
                PasswordLastSet = $user.PasswordLastSet
                LastLogonDate = $user.LastLogonDate
                DistinguishedName = $user.DistinguishedName
                Error = $null
            }
        }
    } catch {}
    
    return [PSCustomObject]@{
        Found = $false
        SamAccountName = $null
        DisplayName = $null
        Name = $null
        Email = $null
        Enabled = $false
        LockedOut = $false
        PasswordExpired = $false
        PasswordLastSet = $null
        LastLogonDate = $null
        DistinguishedName = $null
        Error = "User not found: $Identifier"
    }
}

function Set-ADUserPassword {
    param(
        [string]$Identifier,
        [string]$NewPassword,
        [string]$DomainController,
        [System.Management.Automation.PSCredential]$Credential,
        [bool]$ChangePasswordAtLogon = $false,
        [switch]$UnlockAccount,
        [switch]$WhatIf
    )
    
    $result = @{
        Success = $false
        Identifier = $Identifier
        SamAccountName = $null
        PasswordChanged = $false
        AccountUnlocked = $false
        ChangeAtLogonSet = $false
        Error = $null
    }
    
    $userInfo = Get-ADUserInfo -Identifier $Identifier -DomainController $DomainController -Credential $Credential
    
    if (-not $userInfo.Found) {
        $result.Error = "User not found"
        return [PSCustomObject]$result
    }
    
    $result.SamAccountName = $userInfo.SamAccountName
    
    if ($WhatIf) {
        Write-Host "  [WHAT-IF] Password for '$($userInfo.SamAccountName)' would be changed" -ForegroundColor Yellow
        $result.Success = $true
        $result.PasswordChanged = $true
        return [PSCustomObject]$result
    }
    
    try {
        $securePwd = ConvertTo-SecureString $NewPassword -AsPlainText -Force
        $params = @{ Identity = $userInfo.SamAccountName; NewPassword = $securePwd; Reset = $true; ErrorAction = 'Stop' }
        if ($DomainController) { $params.Server = $DomainController }
        if ($Credential) { $params.Credential = $Credential }
        
        Set-ADAccountPassword @params
        $result.PasswordChanged = $true
        
        if ($ChangePasswordAtLogon) {
            $chgParams = @{ Identity = $userInfo.SamAccountName; ChangePasswordAtLogon = $true; ErrorAction = 'Stop' }
            if ($DomainController) { $chgParams.Server = $DomainController }
            if ($Credential) { $chgParams.Credential = $Credential }
            Set-ADUser @chgParams
            $result.ChangeAtLogonSet = $true
        }
        
        if ($UnlockAccount -and $userInfo.LockedOut) {
            Unlock-ADAccount -Identity $userInfo.SamAccountName -ErrorAction Stop
            $result.AccountUnlocked = $true
        }
        
        $result.Success = $true
    } catch {
        $result.Error = $_.Exception.Message
    }
    
    return [PSCustomObject]$result
}

function Reset-BatchADPasswords {
    param(
        [array]$UsersWithPasswords,
        [hashtable]$ADConfig = @{},
        [hashtable]$SecurityConfig = @{},
        [switch]$WhatIf
    )
    
    $results = @()
    $dc = $ADConfig.DomainController
    $skipDisabled = $SecurityConfig.SkipDisabledAccounts
    $skipNonExistent = $SecurityConfig.SkipNonExistentUsers
    
    foreach ($u in $UsersWithPasswords) {
        Write-Host "  Searching: $($u.Username) ... " -NoNewline
        
        $info = Get-ADUserInfo -Identifier $u.Username -DomainController $dc
        
        $r = [PSCustomObject]@{
            Username = $u.Username
            SamAccountName = $null
            Email = $u.Email
            Found = $false
            PasswordChanged = $false
            Warnings = @()
            Errors = @()
            Skipped = $false
        }
        
        if (-not $info.Found) {
            Write-Host "NOT FOUND" -ForegroundColor Red
            if ($skipNonExistent) { $r.Skipped = $true; $r.Errors += "User not found" }
            $results += $r
            continue
        }
        
        Write-Host "FOUND ($($info.SamAccountName))" -ForegroundColor Green
        $r.Found = $true
        $r.SamAccountName = $info.SamAccountName
        
        if (-not $info.Enabled -and $skipDisabled) {
            $r.Skipped = $true
            $r.Warnings += "Account disabled"
            $results += $r
            continue
        }
        
        $set = Set-ADUserPassword -Identifier $u.Username -NewPassword $u.Password -DomainController $dc -WhatIf:$WhatIf
        $r.PasswordChanged = $set.Success
        if (-not $set.Success) { $r.Errors += $set.Error }
        
        $results += $r
    }
    
    return $results
}

Export-ModuleMember -Function @(
    'Test-ADModuleAvailable',
    'Initialize-ADConnection',
    'Find-ADUser',
    'Get-ADUserInfo',
    'Set-ADUserPassword',
    'Reset-BatchADPasswords'
)