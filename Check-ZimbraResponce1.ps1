# Добавьте -OutVariable чтобы получить ответ
 $zimbraUrl = "https://mail.gmkzoloto.ru:7071/service/admin/soap"
 $accountId = "79c2afea-ebc5-4a21-80bb-fb963264a439"
 $authToken = "ВАШ_ТОКЕН_ИЗ_ЛОГА"
 $password = "TestPass123!"

 $soapXml = @"
<soap:Envelope xmlns:soap="http://www.w3.org/2003/05/soap-envelope">
  <soap:Header>
    <context xmlns="urn:zimbra">
      <authToken>$authToken</authToken>
    </context>
  </soap:Header>
  <soap:Body>
    <ModifyAccountRequest xmlns="urn:zimbraAdmin" id="$accountId">
      <a n="password">$password</a>
    </ModifyAccountRequest>
  </soap:Body>
</soap:Envelope>
"@

# Используем System.Net.WebRequest вместо Invoke-WebRequest
 $req = [System.Net.WebRequest]::Create($zimbraUrl)
 $req.Method = "POST"
 $req.ContentType = "application/soap+xml; charset=utf-8"

 $bodyBytes = [System.Text.Encoding]::UTF8.GetBytes($soapXml)
 $req.ContentLength = $bodyBytes.Length
 $stream = $req.GetRequestStream()
 $stream.Write($bodyBytes, 0, $bodyBytes.Length)
 $stream.Close()

try {
    $resp = $req.GetResponse()
    $reader = New-Object System.IO.StreamReader($resp.GetResponseStream())
    $content = $reader.ReadToEnd()
    $reader.Close()
    Write-Host "SUCCESS:" -ForegroundColor Green
    Write-Host $content
}
catch [System.Net.WebException] {
    $ex = $_.Exception
    Write-Host "ERROR: $($ex.Message)" -ForegroundColor Red
    Write-Host "Status: $($ex.Status)" -ForegroundColor Red
    
    if ($ex.Response) {
        Write-Host "HTTP Status: $([int]$ex.Response.StatusCode)" -ForegroundColor Yellow
        $reader = New-Object System.IO.StreamReader($ex.Response.GetResponseStream())
        $errorBody = $reader.ReadToEnd()
        $reader.Close()
        Write-Host "Response Body:" -ForegroundColor Cyan
        Write-Host $errorBody
    }
}