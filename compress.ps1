$sourcePath = "C:\2"
$destinationPath = "C:\2\PasswordGenerator.zip"
$tempPath = Join-Path $env:TEMP "temp_archive_$(Get-Random)"

# Настройки исключений
$excludeFiles = @("*.csv", "config*.psd1", ".gitignore")
$excludeFolders = @("Backup", "Logs", ".git")

try {
    # Создаем временную папку
    New-Item -Path $tempPath -ItemType Directory -Force | Out-Null
    
    # Формируем аргументы для robocopy
    $robocopyArgs = @(
        $sourcePath,
        $tempPath,
        "/E",           # Копировать подпапки, включая пустые
        "/R:0",         # Без повторных попыток
        "/W:0"          # Без ожидания
    )
    
    # Добавляем исключения файлов
    if ($excludeFiles.Count -gt 0) {
        $robocopyArgs += "/XF"
        $robocopyArgs += $excludeFiles
    }
    
    # Добавляем исключения папок
    if ($excludeFolders.Count -gt 0) {
        $robocopyArgs += "/XD"
        $robocopyArgs += $excludeFolders
    }
    
    Write-Host "Копирование с исключениями..." -ForegroundColor Yellow
    Write-Host "Исключаемые файлы: $($excludeFiles -join ', ')"
    Write-Host "Исключаемые папки: $($excludeFolders -join ', ')"
    
    # Запускаем robocopy
    & robocopy @robocopyArgs
    
    # Проверяем результат
    $robocopyExitCode = $LASTEXITCODE
    
    switch ($robocopyExitCode) {
        0 { Write-Host "Нет изменений" }
        1 { Write-Host "Файлы скопированы успешно" -ForegroundColor Green }
        2 { Write-Host "Дополнительные файлы скопированы" -ForegroundColor Green }
        8 { Write-Warning "Некоторые файлы/папки не скопированы (возможно, из-за исключений)" }
        default { Write-Warning "Robocopy завершился с кодом: $robocopyExitCode" }
    }
    
    # Проверяем наличие файлов для архивации
    $fileCount = (Get-ChildItem -Path $tempPath -Recurse -File).Count
    if ($fileCount -eq 0) {
        Write-Warning "Нет файлов для архивации после фильтрации"
        return
    }
    
    Write-Host "Скопировано файлов: $fileCount"
    
    # Создаем архив
    Write-Host "Создание архива..." -ForegroundColor Yellow
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [System.IO.Compression.ZipFile]::CreateFromDirectory($tempPath, $destinationPath)
    
    Write-Host "Архив успешно создан: $destinationPath" -ForegroundColor Green
    Write-Host "Размер архива: $([math]::Round((Get-Item $destinationPath).Length / 1MB, 2)) MB"
}
catch {
    Write-Error "Ошибка при создании архива: $_"
}
finally {
    # Очистка временной папки
    if (Test-Path $tempPath) {
        Remove-Item -Path $tempPath -Recurse -Force -ErrorAction SilentlyContinue
        Write-Host "Временные файлы удалены"
    }
}