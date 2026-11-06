# Stops every local preview server (serve.ps1), including ones left running after their launching shell was stopped.
Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" | Where-Object { $_.CommandLine -match 'serve\.ps1' -and $_.ProcessId -ne $PID } | ForEach-Object {
  Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue; "stopped $($_.ProcessId)" }
