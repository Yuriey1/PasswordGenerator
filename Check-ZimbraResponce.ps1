 $authToken = "0_0f1844bda232e70f1a7a7f1cc93f98344f01620f_69643d33363a39353862373936352d386565362d343533612d623331342d3135623233363361323636383b6578703d31333a313737343533343239323636363b61646d696e3d313a313b76763d313a313b747970653d363a7a696d6272613b753d313a613b7469643d393a3636303739353236373b76657273696f6e3d31343a382e382e31355f47415f333836393b"
 $accountId = "79c2afea-ebc5-4a21-80bb-fb963264a439"

 $soapXml = @"
<soap:Envelope xmlns:soap="http://www.w3.org/2003/05/soap-envelope">
  <soap:Header>
    <context xmlns="urn:zimbra">
      <authToken>$authToken</authToken>
    </context>
  </soap:Header>
  <soap:Body>
    <ModifyAccountRequest xmlns="urn:zimbraAdmin" id="$accountId">
      <a n="password">TestPass123!</a>
    </ModifyAccountRequest>
  </soap:Body>
</soap:Envelope>
"@

try {
    $r = Invoke-WebRequest -Uri "https://mail.gmkzoloto.ru:7071/service/admin/soap" -Method POST -ContentType "application/soap+xml; charset=utf-8" -Body $soapXml -UseBasicParsing -SkipCertificateCheck
    Write-Host "SUCCESS: $($r.Content)" -ForegroundColor Green
} catch {
    Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
    if ($_.Exception.Response) {
        $reader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
        Write-Host "BODY:" -ForegroundColor Yellow
        Write-Host $reader.ReadToEnd()
    }
}