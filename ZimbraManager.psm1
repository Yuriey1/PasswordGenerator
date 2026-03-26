<#
.SYNOPSIS
    Zimbra Manager using SOAP API
#>

$script:ZimbraUrl = $null
$script:AuthToken = $null
$script:ZimbraDomain = $null

function Initialize-ZimbraConnection {
    param(
        [string]$ServerUrl,
        [string]$AdminUser,
        [string]$AdminPassword,
        [string]$Domain,
        [switch]$DebugMode
    )
    
    $script:ZimbraUrl = $ServerUrl.TrimEnd('/')
    $script:ZimbraDomain = $Domain
    
    Write-Host "Connecting to Zimbra: $ServerUrl ..." -NoNewline
    
    # SOAP AuthRequest
    $soapXml = @"
<soap:Envelope xmlns:soap="http://www.w3.org/2003/05/soap-envelope">
  <soap:Header>
    <context xmlns="urn:zimbra"/>
  </soap:Header>
  <soap:Body>
    <AuthRequest xmlns="urn:zimbraAdmin">
      <name>$AdminUser</name>
      <password>$AdminPassword</password>
    </AuthRequest>
  </soap:Body>
</soap:Envelope>
"@
    
    if ($DebugMode) {
        Write-Host "`n[DEBUG] SOAP Request:" -ForegroundColor DarkGray
        Write-Host $soapXml -ForegroundColor DarkGray
    }
    
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        
        $response = Invoke-WebRequest -Uri "$script:ZimbraUrl/service/admin/soap" `
            -Method POST `
            -ContentType "application/soap+xml; charset=utf-8" `
            -Body $soapXml `
            -UseBasicParsing `
            -SkipCertificateCheck
        
        if ($DebugMode) {
            Write-Host "`n[DEBUG] Response Status: $($response.StatusCode)" -ForegroundColor DarkGray
            Write-Host "[DEBUG] Response:" -ForegroundColor DarkGray
            Write-Host $response.Content -ForegroundColor DarkGray
        }
        
        [xml]$xml = $response.Content
        
        $ns = New-Object System.Xml.XmlNamespaceManager($xml.NameTable)
        $ns.AddNamespace("soap", "http://www.w3.org/2003/05/soap-envelope")
        $ns.AddNamespace("zimbra", "urn:zimbraAdmin")
        
        $authNode = $xml.SelectSingleNode("//zimbra:authToken", $ns)
        
        if ($authNode) {
            $script:AuthToken = $authNode.InnerText
            Write-Host " OK" -ForegroundColor Green
            return $true
        } else {
            Write-Host " FAILED (no token)" -ForegroundColor Red
            return $false
        }
    }
    catch {
        Write-Host " ERROR" -ForegroundColor Red
        Write-Host "  $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

function Get-ZimbraAccount {
    param(
        [string]$AccountEmail
    )
    
    if (-not $script:AuthToken) {
        throw "Not authenticated. Call Initialize-ZimbraConnection first."
    }
    
    $soapXml = @"
<soap:Envelope xmlns:soap="http://www.w3.org/2003/05/soap-envelope">
  <soap:Header>
    <context xmlns="urn:zimbra">
      <authToken>$script:AuthToken</authToken>
    </context>
  </soap:Header>
  <soap:Body>
    <GetAccountRequest xmlns="urn:zimbraAdmin">
      <account by="name">$AccountEmail</account>
    </GetAccountRequest>
  </soap:Body>
</soap:Envelope>
"@
    
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        
        $response = Invoke-WebRequest -Uri "$script:ZimbraUrl/service/admin/soap" `
            -Method POST `
            -ContentType "application/soap+xml; charset=utf-8" `
            -Body $soapXml `
            -UseBasicParsing `
            -SkipCertificateCheck `
            -ErrorAction Stop
        
        [xml]$xml = $response.Content
        
        $ns = New-Object System.Xml.XmlNamespaceManager($xml.NameTable)
        $ns.AddNamespace("soap", "http://www.w3.org/2003/05/soap-envelope")
        $ns.AddNamespace("zimbra", "urn:zimbraAdmin")
        
        $accountNode = $xml.SelectSingleNode("//zimbra:account", $ns)
        
        if ($accountNode) {
            return @{
                Found = $true
                Id = $accountNode.id
                Name = $accountNode.name
            }
        }
        
        return @{ Found = $false }
    }
    catch {
        if ($_.Exception.Message -match "account.NO_SUCH_ACCOUNT" -or 
            $_.Exception.Message -match "no such account") {
            return @{ Found = $false }
        }
        throw $_
    }
}

function Set-ZimbraPassword {
    param(
        [string]$AccountEmail,
        [string]$NewPassword,
        [switch]$WhatIf,
        [switch]$DebugMode
    )
    
    if (-not $script:AuthToken) {
        throw "Not authenticated. Call Initialize-ZimbraConnection first."
    }
    
    # First get account ID
    $account = Get-ZimbraAccount -AccountEmail $AccountEmail
    
    if (-not $account.Found) {
        return @{
            Success = $false
            Error = "Account not found: $AccountEmail"
        }
    }
    
    $accountId = $account.Id
    
    if ($WhatIf) {
        return @{
            Success = $true
            AccountId = $accountId
            WhatIf = $true
            Error = $null
        }
    }
    
    $soapXml = @"
<soap:Envelope xmlns:soap="http://www.w3.org/2003/05/soap-envelope">
  <soap:Header>
    <context xmlns="urn:zimbra">
      <authToken>$script:AuthToken</authToken>
    </context>
  </soap:Header>
  <soap:Body>
    <SetPasswordRequest xmlns="urn:zimbraAdmin" id="$accountId" newPassword="$NewPassword"/>
  </soap:Body>
</soap:Envelope>
"@
    
    if ($DebugMode) {
        Write-Host ""
        Write-Host "    [DEBUG] Account: $AccountEmail (id=$accountId)" -ForegroundColor DarkGray
        Write-Host "    [DEBUG] Using SetPasswordRequest API" -ForegroundColor DarkGray
    }
    
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

        # Use try-catch inside to capture response even on error
        $response = $null
        $errorBody = $null

        try {
            $response = Invoke-WebRequest -Uri "$script:ZimbraUrl/service/admin/soap" `
                -Method POST `
                -ContentType "application/soap+xml; charset=utf-8" `
                -Body $soapXml `
                -UseBasicParsing `
                -SkipCertificateCheck
        }
        catch {
            # PowerShell 7+ throws HttpResponseException, older versions throw WebException
            $ex = $_.Exception
            if ($ex.Response) {
                # For HttpResponseException (PowerShell 7+)
                $errorBody = $ex.Response.Content
            }
            elseif ($ex -is [System.Net.WebException] -and $ex.Response) {
                # For WebException (PowerShell 5.1)
                $reader = New-Object System.IO.StreamReader($ex.Response.GetResponseStream())
                $errorBody = $reader.ReadToEnd()
                $reader.Close()
            }
            else {
                $errorBody = $ex.Message
            }
            $response = $null
        }
        
        # Show response or error body
        if ($DebugMode) {
            if ($response) {
                Write-Host "    [DEBUG] HTTP Status: $($response.StatusCode)" -ForegroundColor DarkGray
                Write-Host "    [DEBUG] Response: $($response.Content)" -ForegroundColor DarkGray
            }
            if ($errorBody) {
                Write-Host "    [DEBUG] Error Response: $errorBody" -ForegroundColor DarkGray
            }
        }
        
        # Parse error body for SOAP fault
        if ($errorBody) {
            $faultCode = ""
            $faultText = ""
            $faultDetail = ""
            
            if ($errorBody -match '<soap:Fault') {
                if ($errorBody -match '<soap:Value[^>]*>([^<]+)</soap:Value>') { $faultCode = $matches[1] }
                if ($errorBody -match '<soap:Text[^>]*>([^<]+)</soap:Text>') { $faultText = $matches[1] }
                if ($errorBody -match '<a n="message">([^<]+)</a>') { $faultDetail = $matches[1] }
                
                $errorDetail = "SOAP Fault: $faultCode"
                if ($faultText) { $errorDetail += " - $faultText" }
                if ($faultDetail) { $errorDetail += " ($faultDetail)" }
                
                return @{
                    Success = $false
                    AccountId = $accountId
                    Error = $errorDetail
                }
            }
            
            return @{
                Success = $false
                AccountId = $accountId
                Error = "HTTP Error with unknown response"
            }
        }
        
        # Check response
        if ($response) {
            # Check for SOAP fault in response
            if ($response.Content -match '<soap:Fault') {
                $faultCode = ""
                $faultText = ""
                $faultDetail = ""
                
                if ($response.Content -match '<soap:Value[^>]*>([^<]+)</soap:Value>') { $faultCode = $matches[1] }
                if ($response.Content -match '<soap:Text[^>]*>([^<]+)</soap:Text>') { $faultText = $matches[1] }
                if ($response.Content -match '<a n="message">([^<]+)</a>') { $faultDetail = $matches[1] }
                
                $errorDetail = "SOAP Fault: $faultCode"
                if ($faultText) { $errorDetail += " - $faultText" }
                if ($faultDetail) { $errorDetail += " ($faultDetail)" }
                
                return @{
                    Success = $false
                    AccountId = $accountId
                    Error = $errorDetail
                }
            }
            
            return @{
                Success = $true
                AccountId = $accountId
                Error = $null
            }
        }
        
        return @{
            Success = $false
            AccountId = $accountId
            Error = "No response"
        }
    }
    catch {
        return @{
            Success = $false
            AccountId = $accountId
            Error = $_.Exception.Message
        }
    }
}

function Reset-BatchZimbraPasswords {
    param(
        [array]$UsersWithPasswords,
        [switch]$WhatIf,
        [switch]$DebugMode
    )
    
    $results = @()
    $successCount = 0
    $errorCount = 0
    
    foreach ($u in $UsersWithPasswords) {
        $email = $u.Email
        
        if (-not $email) {
            $results += [PSCustomObject]@{
                Username = $u.Username
                Email = $null
                PasswordChanged = $false
                Error = "No email provided"
            }
            $errorCount++
            continue
        }
        
        Write-Host "  Setting password for $email ... " -NoNewline
        
        $r = Set-ZimbraPassword -AccountEmail $email -NewPassword $u.Password -WhatIf:$WhatIf -DebugMode:$DebugMode
        
        if ($r.Success) {
            if ($WhatIf) {
                Write-Host "[WHAT-IF]" -ForegroundColor Cyan
            } else {
                Write-Host "OK" -ForegroundColor Green
            }
            $successCount++
            $results += [PSCustomObject]@{
                Username = $u.Username
                Email = $email
                PasswordChanged = $true
                Error = $null
            }
        } else {
            Write-Host "ERROR" -ForegroundColor Red
            Write-Host "    $($r.Error)" -ForegroundColor DarkGray
            $errorCount++
            $results += [PSCustomObject]@{
                Username = $u.Username
                Email = $email
                PasswordChanged = $false
                Error = $r.Error
            }
        }
    }
    
    Write-Host ""
    Write-Host "Done: $successCount ok, $errorCount errors" -ForegroundColor $(if ($errorCount -eq 0) { "Green" } else { "Yellow" })
    
    return $results
}

Export-ModuleMember -Function @(
    'Initialize-ZimbraConnection',
    'Get-ZimbraAccount',
    'Set-ZimbraPassword',
    'Reset-BatchZimbraPasswords'
)