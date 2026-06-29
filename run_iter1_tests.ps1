# PowerShell: Run Iteration 1 tests via Godot with test_runner.tscn as main scene

$projectDir = "e:\Stride\godot\CpuDerp"
$projectFile = "$projectDir\project.godot"
$backupFile = "$projectDir\project.godot.bak"
$godotExe = "E:\SteamLibrary\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe"

Write-Host "=== CpuDerp Iteration 1 Test Runner ===" -ForegroundColor Cyan

# Backup project.godot
Copy-Item -Path $projectFile -Destination $backupFile -Force

try {
    # Change main_scene to test_runner
    $content = Get-Content -Path $projectFile -Raw
    $content = $content -replace 'run/main_scene="res://scenes/main.tscn"', 'run/main_scene="res://scenes/test_runner.tscn"'
    Set-Content -Path $projectFile -Value $content -NoNewline
    
    Write-Host "Running Godot with test scene..." -ForegroundColor Yellow
    
    # Run Godot headless
    & $godotExe --headless --path $projectDir
    
    $exitCode = $LASTEXITCODE
    Write-Host "Godot exited with code: $exitCode" -ForegroundColor Yellow
    
    # Check for results
    $resultsFile = "$projectDir\res\data\test_iter1_results.txt"
    if (Test-Path $resultsFile) {
        Write-Host "`n=== Test Results ===" -ForegroundColor Green
        Get-Content -Path $resultsFile
    } else {
        Write-Host "No results file found at $resultsFile" -ForegroundColor Red
    }
}
finally {
    # Restore project.godot
    if (Test-Path $backupFile) {
        Copy-Item -Path $backupFile -Destination $projectFile -Force
        Remove-Item -Path $backupFile -Force
        Write-Host "project.godot restored." -ForegroundColor Gray
    }
}

Write-Host "Done." -ForegroundColor Cyan
