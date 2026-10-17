# Restart the Flutter debug web server (readable stack traces) on http://localhost:8767/
$ErrorActionPreference = 'Continue'
$root = Split-Path -Parent $PSScriptRoot
$env:FLUTTER_SUPPRESS_ANALYTICS = 'true'
$env:CI = 'true'
Get-CimInstance Win32_Process | Where-Object { $_.CommandLine -match 'flutter_tools.snapshot' -and $_.CommandLine -match 'web-server' } |
  ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
Get-CimInstance Win32_Process | Where-Object { $_.CommandLine -match 'dart' -and $_.CommandLine -match '8767' } |
  ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
Start-Sleep -Seconds 2
Set-Location (Join-Path $root 'port')
$log = Join-Path $root 'work\flutter_web_run.log'
$err = Join-Path $root 'work\flutter_web_run.err'
Start-Process -FilePath (Join-Path $root 'tools\flutter\bin\flutter.bat') `
  -ArgumentList 'run', '-d', 'web-server', '--web-hostname', 'localhost', '--web-port', '8767' `
  -RedirectStandardOutput $log -RedirectStandardError $err -WindowStyle Hidden
for ($i = 0; $i -lt 90; $i++) {
  Start-Sleep -Seconds 2
  if ((Test-Path $log) -and (Select-String -Path $log -Pattern 'Flutter run key commands' -Quiet)) { 'ready'; break }
}
