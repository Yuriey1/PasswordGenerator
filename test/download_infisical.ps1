# Полная установка
New-Item -ItemType Directory -Path "C:\Tools\infisical" -Force
Invoke-WebRequest -Uri "https://github.com/Infisical/cli/releases/latest/download/infisical_windows_amd64.exe" -OutFile "C:\Tools\infisical\infisical.exe"
 $env:PATH += ";C:\Tools\infisical"
infisical --version