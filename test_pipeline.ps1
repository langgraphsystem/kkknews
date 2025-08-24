# 0) Для красивого вывода в кириллице (по желанию)
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# Set environment variable
$env:GOOGLE_SERVICE_ACCOUNT_JSON = "D:\Программы\claude\newsrss\secrets\service_account.json"

# 1) Базовые переменные
$todayDir = Join-Path (Get-Location) "storage\articles\$(Get-Date -Format 'yyyy\MM\dd')"
$before = if (Test-Path $todayDir) { (Get-ChildItem -Recurse $todayDir -File | Measure-Object).Count } else { 0 }
$t0 = Get-Date
Write-Host "Файлов до запуска: $before; старт: $t0"

# 2) Прогон пайплайна (бережно к квотам)
Write-Host "=== Запуск ensure ==="
python main.py ensure

Write-Host "=== Запуск discovery ==="
python main.py discovery --feed "https://feeds.bbci.co.uk/news/rss.xml"

Write-Host "=== Пауза 5 сек перед poll ==="
Start-Sleep -Seconds 5

Write-Host "=== Запуск poll ==="
python main.py poll

Write-Host "=== Пауза 5 сек перед work ==="
Start-Sleep -Seconds 5

Write-Host "=== Запуск work ==="
python main.py work --worker-id verifier

# 3) Проверка файлового результата
$after = if (Test-Path $todayDir) { (Get-ChildItem -Recurse $todayDir -File | Measure-Object).Count } else { 0 }
$delta = $after - $before
Write-Host "Файлов после запуска: $after (новых: $delta)"

# 4) Показать последний сохранённый файл и его размер
if (Test-Path $todayDir) {
  $latest = Get-ChildItem -Recurse $todayDir -File | Sort-Object LastWriteTime -Desc | Select-Object -First 1
  if ($latest) {
    $size = (Get-Item $latest.FullName).Length
    Write-Host "Последний файл:" $latest.FullName "Размер:" $size "байт"
    # первые 300 символов
    if ($size -gt 0) {
        $content = Get-Content -Raw $latest.FullName
        $preview = $content.Substring(0, [Math]::Min(300, $size))
        Write-Host $preview
    }
  }
}

# 5) Идемпотентность (дубликаты не должны добавляться)
Write-Host "=== Тест антидублей ==="
$before2 = if (Test-Path $todayDir) { (Get-ChildItem -Recurse $todayDir -File | Measure-Object).Count } else { 0 }

Write-Host "=== Повторный poll ==="
Start-Sleep -Seconds 3
python main.py poll

Write-Host "=== Повторный work ==="
Start-Sleep -Seconds 3
python main.py work --worker-id verifier

$after2 = if (Test-Path $todayDir) { (Get-ChildItem -Recurse $todayDir -File | Measure-Object).Count } else { 0 }
$delta2 = $after2 - $before2
Write-Host "Повторный прогон: новых файлов $delta2 (ожидается 0, если антидубли работает)"

# 6) Ручная проверка Sheets
Write-Host "Открой Google Sheets и проверь вкладки Raw articles / ArticlesIndex: новые строки после $t0"