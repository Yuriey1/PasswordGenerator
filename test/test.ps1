# Проверка доступных endpoints
$token = "st.4b9dd06c-79a9-4480-b6b9-14f15f6f662f.3e91acd752976bec15f4a39d3b41dd00.42826d96a2482f7b9c7207602dfc3b2e"
$url = "https://infisical.krasintegra.ru"
$workspaceId = "9db52232-b84f-4905-9478-6b640150db46"

# Попробуем создать тестовый секрет
 $body = @{
    workspaceId = $workspaceId
    environment = "prod"
    secretPath = "/"
    secretKey = "TEST_SECRET"
    secretValue = "test123"
    type = "shared"
} | ConvertTo-Json

Write-Host "Request body:"
Write-Host $body

 $response = Invoke-RestMethod -Uri "$url/api/v3/secrets/raw" -Method POST -Body $body -ContentType "application/json" -Headers @{ Authorization = "Bearer $token" }
 $response