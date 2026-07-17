param(
  [switch]$ForceAllDart,
  [switch]$Hard
)

$ErrorActionPreference = 'Stop'

if (-not $Hard) {
  Write-Host 'This script is a hard reset and intentionally terminates Dart/Flutter daemons.'
  Write-Host 'VS Code will show "daemon terminated" notifications when those processes are killed.'
  Write-Host ''
  Write-Host 'For normal use, do NOT run this task. Use one of these instead:'
  Write-Host '  1. Ctrl+Shift+P -> Developer: Reload Window'
  Write-Host '  2. Terminal -> Run Task... -> Safe project check'
  Write-Host ''
  Write-Host 'If Dart/Flutter tools are truly stuck and you accept the notifications, run:'
  Write-Host '  powershell -NoProfile -ExecutionPolicy Bypass -File scripts\reset_dart_tools.ps1 -Hard'
  exit 0
}

Write-Host 'Hard resetting VS Code Dart/Flutter background tools...'

$patterns = @(
  'tooling-daemon --machine',
  'devtools --machine',
  'analysis_server',
  'language-server',
  'flutter_tools.snapshot daemon',
  'flutter.bat.*daemon',
  'dart.bat.*format',
  'flutter.bat.*analyze'
)

$processes = Get-CimInstance Win32_Process |
  Where-Object {
    $cmd = $_.CommandLine
    if ([string]::IsNullOrWhiteSpace($cmd)) { return $false }

    if ($ForceAllDart -and ($_.Name -in @('dart.exe', 'dartvm.exe'))) {
      return $true
    }

    foreach ($pattern in $patterns) {
      if ($cmd -match $pattern) { return $true }
    }
    return $false
  }

if (-not $processes) {
  Write-Host 'No Dart/Flutter background tool processes found.'
  exit 0
}

foreach ($process in $processes) {
  $processId = [int]$process.ProcessId
  $name = $process.Name
  Write-Host "Stopping $name ($processId)"
  & taskkill.exe /PID $processId /T /F | Out-Host
}

Write-Host ''
Write-Host 'Done. In VS Code, run "Developer: Reload Window" if Dart still shows stale errors.'
