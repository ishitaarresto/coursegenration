param([int]$ApiPort = 8000, [int]$WebPort = 5500)

$root = $PSScriptRoot

Write-Host ""
Write-Host "Arresto LMS - Dev Start" -ForegroundColor Cyan
Write-Host "Backend   http://localhost:$ApiPort" -ForegroundColor Green
Write-Host "Frontend  http://localhost:$WebPort" -ForegroundColor Green
Write-Host "API docs  http://localhost:$ApiPort/docs" -ForegroundColor Gray
Write-Host ""

# Backend API window
Start-Process powershell -ArgumentList "-NoExit", "-Command", "cd '$root'; .venv\Scripts\python.exe run_api.py --port $ApiPort --reload" -WindowStyle Normal

Start-Sleep -Milliseconds 800

# Flutter dev server window (hot-reload with 'r', full restart with 'R')
# Default JS renderer (no --wasm flag) is required for video_player to be visible on web
# (Skwasm/WASM renderer covers <video> elements with its canvas layer)
Start-Process powershell -ArgumentList "-NoExit", "-Command", "cd '$root\frontend-lms'; flutter run -d web-server --web-port $WebPort --web-hostname localhost" -WindowStyle Normal

Write-Host "Two windows opened." -ForegroundColor Cyan
Write-Host "Wait ~20s then open http://localhost:$WebPort" -ForegroundColor White
Write-Host ""
