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
        # Force TLS 1.2
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        
        $response = Invoke-WebRequest -Uri "$script:ZimbraUrl/service/admin/soap" `
            -Method POST `
            -ContentType "application/soap+xml; charset=utf-8" `
            -Body $soapXml `
            -UseBasicParsing `
            -SkipCertificateCheck `
            -ErrorAction SilentlyContinue
        
        if ($DebugMode) {
            Write-Host "`n[DEBUG] Response Status: $($response.StatusCode)" -ForegroundColor DarkGray
            Write-Host "[DEBUG] Response:" -ForegroundColor DarkGray
            Write-Host $response.Content -ForegroundColor DarkGray
        }
        
        [xml]$xml = $response.Content
        
        # Extract authToken from response
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
        
        # Try to get response body for error details
        $errorMsg = $_.Exception.Message
        
        if ($_.Exception.Response) {
            try {
                $reader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
                $errorBody = $reader.ReadToEnd()
                $reader.Close()
                
                Write-Host "  Status: $($_.Exception.Response.StatusCode.value__)" -ForegroundColor Red
                Write-Host "  Response Body:" -ForegroundColor Red
                Write-Host $errorBody -ForegroundColor DarkGray
                
                # Try to extract SOAP fault
                if ($errorBody -match '<soap:Text[^>]*>([^<]+)</soap:Text>') {
                    $errorMsg = $matches[1]
                }
                if ($errorBody -match '<Code>([^<]+)</Code>') {
                    $errorMsg = $matches[1]
                }
            } catch {
                Write-Host "  Could not read response body" -ForegroundColor Red
            }
        }
        
        Write-Host "  Error: $errorMsg" -ForegroundColor Red
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
    
    # SOAP GetAccountRequest
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
        # Check if account not found
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
        [switch]$WhatIf
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
    
    # SOAP ModifyAccountRequest
    $soapXml = @"
<soap:Envelope xmlns:soap="http://www.w3.org/2003/05/soap-envelope">
  <soap:Header>
    <context xmlns="urn:zimbra">
      <authToken>$script:AuthToken</authToken>
    </context>
  </soap:Header>
  <soap:Body>
    <ModifyAccountRequest xmlns="urn:zimbraAdmin" id="$accountId">
      <a n="password">$NewPassword</a>
    </ModifyAccountRequest>
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
        
        return @{
            Success = $true
            AccountId = $accountId
            Error = $null
        }
    }
    catch {
        $errorMsg = $_.Exception.Message
        
        # Try to extract SOAP fault
        try {
            if ($_.Exception.Response) {
                $reader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
                $errorXml = $reader.ReadToEnd()
                $reader.Close()
                
                if ($errorXml -match '<soap:Text[^>]*>([^<]+)</soap:Text>') {
                    $errorMsg = $matches[1]
                }
            }
        } catch {}
        
        return @{
            Success = $false
            AccountId = $accountId
            Error = $errorMsg
        }
    }
}

function Reset-BatchZimbraPasswords {
    param(
        [array]$UsersWithPasswords,
        [switch]$WhatIf
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
        
        $r = Set-ZimbraPassword -AccountEmail $email -NewPassword $u.Password -WhatIf:$WhatIf
        
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