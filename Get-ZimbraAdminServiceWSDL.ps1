Invoke-WebRequest -Uri "https://mail.gmkzoloto.ru:7071/service/wsdl/ZimbraAdminService.wsdl" -SkipCertificateCheck -UseBasicParsing | Select-Object -ExpandProperty Content | Out-File "C:\2\ZimbraAdminService.wsdl" -Encoding UTF8
Get-Content "C:\2\ZimbraAdminService.wsdl"
