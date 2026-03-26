 $script:CharacterSets = @{
    Uppercase = "ABCDEFGHJKLMNPQRSTUVWXYZ"
    Lowercase = "abcdefghjkmnpqrstuvwxyz"
    Digits = "23456789"
#    SpecialChars = "!@#$%^&*()_+-=[]{}|;:,.<>?"
    SpecialChars = "!-="
    Ambiguous = "0O1lI"
}

function Remove-AmbiguousCharacters {
    param([string]$CharacterSet, [string]$AmbiguousChars)
    $result = $CharacterSet
    foreach ($char in $AmbiguousChars.ToCharArray()) {
        $result = $result -replace [regex]::Escape($char), ""
    }
    return $result
}

function Get-RandomCharacters {
    param([string]$CharacterSet, [int]$Count)
    $result = New-Object System.Text.StringBuilder
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    $bytes = New-Object byte[] 4
    for ($i = 0; $i -lt $Count; $i++) {
        $rng.GetBytes($bytes)
        $randomIndex = [BitConverter]::ToUInt32($bytes, 0) % $CharacterSet.Length
        [void]$result.Append($CharacterSet[$randomIndex])
    }
    return $result.ToString()
}

function Test-PasswordStrength {
    param([string]$Password, [hashtable]$Config)
    $result = @{ IsValid = $true; Errors = @(); Strength = 0 }
    if ($Password.Length -lt $Config.Length) {
        $result.IsValid = $false
        $result.Errors += "Password too short (min: $($Config.Length))"
    }
    $counts = @{
        Uppercase = ([regex]::Matches($Password, '[A-Z]')).Count
        Lowercase = ([regex]::Matches($Password, '[a-z]')).Count
        Digits = ([regex]::Matches($Password, '[0-9]')).Count
        SpecialChars = ([regex]::Matches($Password, '[^a-zA-Z0-9]')).Count
    }
    if ($Config.IncludeUppercase -and $counts.Uppercase -lt $Config.MinUppercase) {
        $result.IsValid = $false; $result.Errors += "Not enough uppercase"
    }
    if ($Config.IncludeLowercase -and $counts.Lowercase -lt $Config.MinLowercase) {
        $result.IsValid = $false; $result.Errors += "Not enough lowercase"
    }
    if ($Config.IncludeDigits -and $counts.Digits -lt $Config.MinDigits) {
        $result.IsValid = $false; $result.Errors += "Not enough digits"
    }
    if ($Config.IncludeSpecialChars -and $counts.SpecialChars -lt $Config.MinSpecialChars) {
        $result.IsValid = $false; $result.Errors += "Not enough special chars"
    }
    $strength = [Math]::Min($Password.Length * 4, 40) + $counts.Uppercase * 5 + $counts.Lowercase * 3 + $counts.Digits * 4 + $counts.SpecialChars * 6
    $result.Strength = [Math]::Min($strength, 100)
    return $result
}

function New-SecurePassword {
    param([hashtable]$Config)
    if (-not $Config) { $Config = @{} }
    if (-not $Config.ContainsKey('Length')) { $Config.Length = 16 }
    if (-not $Config.ContainsKey('IncludeUppercase')) { $Config.IncludeUppercase = $true }
    if (-not $Config.ContainsKey('IncludeLowercase')) { $Config.IncludeLowercase = $true }
    if (-not $Config.ContainsKey('IncludeDigits')) { $Config.IncludeDigits = $true }
    if (-not $Config.ContainsKey('IncludeSpecialChars')) { $Config.IncludeSpecialChars = $true }
    if (-not $Config.ContainsKey('ExcludeAmbiguous')) { $Config.ExcludeAmbiguous = $true }
    if (-not $Config.ContainsKey('MinUppercase')) { $Config.MinUppercase = 2 }
    if (-not $Config.ContainsKey('MinLowercase')) { $Config.MinLowercase = 2 }
    if (-not $Config.ContainsKey('MinDigits')) { $Config.MinDigits = 2 }
    if (-not $Config.ContainsKey('MinSpecialChars')) { $Config.MinSpecialChars = 2 }
    
    $charSets = @{}
    if ($Config.IncludeUppercase) {
        $charSets.Uppercase = $script:CharacterSets.Uppercase
        if ($Config.ExcludeAmbiguous) { $charSets.Uppercase = Remove-AmbiguousCharacters $charSets.Uppercase $script:CharacterSets.Ambiguous }
    }
    if ($Config.IncludeLowercase) {
        $charSets.Lowercase = $script:CharacterSets.Lowercase
        if ($Config.ExcludeAmbiguous) { $charSets.Lowercase = Remove-AmbiguousCharacters $charSets.Lowercase $script:CharacterSets.Ambiguous }
    }
    if ($Config.IncludeDigits) {
        $charSets.Digits = $script:CharacterSets.Digits
        if ($Config.ExcludeAmbiguous) { $charSets.Digits = Remove-AmbiguousCharacters $charSets.Digits $script:CharacterSets.Ambiguous }
    }
    if ($Config.IncludeSpecialChars) { $charSets.SpecialChars = $script:CharacterSets.SpecialChars }
    
    $password = New-Object System.Text.StringBuilder
    $remainingLength = $Config.Length
    if ($Config.IncludeUppercase) { [void]$password.Append((Get-RandomCharacters $charSets.Uppercase $Config.MinUppercase)); $remainingLength -= $Config.MinUppercase }
    if ($Config.IncludeLowercase) { [void]$password.Append((Get-RandomCharacters $charSets.Lowercase $Config.MinLowercase)); $remainingLength -= $Config.MinLowercase }
    if ($Config.IncludeDigits) { [void]$password.Append((Get-RandomCharacters $charSets.Digits $Config.MinDigits)); $remainingLength -= $Config.MinDigits }
    if ($Config.IncludeSpecialChars) { [void]$password.Append((Get-RandomCharacters $charSets.SpecialChars $Config.MinSpecialChars)); $remainingLength -= $Config.MinSpecialChars }
    
    $allChars = ($charSets.Values -join '')
    if ($remainingLength -gt 0) { [void]$password.Append((Get-RandomCharacters $allChars $remainingLength)) }
    
    $shuffled = $password.ToString().ToCharArray()
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    $bytes = New-Object byte[] 4
    for ($i = $shuffled.Length - 1; $i -gt 0; $i--) {
        $rng.GetBytes($bytes)
        $j = [BitConverter]::ToUInt32($bytes, 0) % ($i + 1)
        $temp = $shuffled[$i]; $shuffled[$i] = $shuffled[$j]; $shuffled[$j] = $temp
    }
    
    $final = -join $shuffled
    $strength = Test-PasswordStrength $final $Config
    return [PSCustomObject]@{ Password = $final; Strength = $strength.Strength; IsValid = $strength.IsValid; Errors = $strength.Errors }
}

function New-BatchPasswords {
    param([array]$Users, [hashtable]$Config)
    $results = @()
    foreach ($user in $Users) {
        $username = $user.SamAccountName ?? $user.Username ?? $user.DisplayName ?? $user.CN ?? $user.PSObject.Properties.Value[0]
        $email = $user.Email ?? $user.email ?? $user.Mail
        try {
            $pwd = New-SecurePassword $Config
            $results += [PSCustomObject]@{ Username = $username; Email = $email; Password = $pwd.Password; Strength = $pwd.Strength; IsValid = $pwd.IsValid; Error = $null; Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss" }
        } catch {
            $results += [PSCustomObject]@{ Username = $username; Email = $email; Password = $null; Strength = 0; IsValid = $false; Error = $_.Exception.Message; Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss" }
        }
    }
    return $results
}

function New-SinglePassword {
    param(
        [string]$Username,
        [hashtable]$Config
    )
    
    try {
        $pwd = New-SecurePassword $Config
        return [PSCustomObject]@{ 
            Username = $Username
            Password = $pwd.Password
            Strength = $pwd.Strength
            IsValid = $pwd.IsValid
            Error = $null
        }
    } catch {
        return [PSCustomObject]@{ 
            Username = $Username
            Password = $null
            Strength = 0
            IsValid = $false
            Error = $_.Exception.Message
        }
    }
}

Export-ModuleMember -Function @('New-SecurePassword', 'New-BatchPasswords', 'New-SinglePassword', 'Test-PasswordStrength')