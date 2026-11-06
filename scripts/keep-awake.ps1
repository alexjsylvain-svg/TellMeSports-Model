param([string]$Until = "02:30", [switch]$Hold)
# Keeps the PC from idle-sleeping during game hours so the live-score job keeps running (Nov 5 it slept at 9:16 PM ET
# and nothing ran until morning). It asks Windows the same way a video player does (SetThreadExecutionState): no power
# settings change, and the request ends when this process exits. A closed laptop lid or choosing Sleep still sleeps.
# Usage: keep-awake.ps1 [-Until HH:mm ET, default 02:30 the next morning]. It starts one hidden background copy and returns;
# running it again while a copy is alive does nothing. The copy also exits early once every game in site\live.json is final
# and the night's slate has no game left to start.
$ErrorActionPreference = "Stop"
$root = Split-Path $PSScriptRoot -Parent; $pidFile = Join-Path $root "tracking\keep-awake.pid"
function EtNow { [System.TimeZoneInfo]::ConvertTimeBySystemTimeZoneId([DateTime]::UtcNow, 'Eastern Standard Time') }
if(-not $Hold){
  if(Test-Path $pidFile){ $old = [int](Get-Content $pidFile -Raw); if(Get-Process -Id $old -ErrorAction SilentlyContinue){ "keep-awake already running (pid $old)"; exit 0 } }
  $p = Start-Process powershell -WindowStyle Hidden -PassThru -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',"`"$PSCommandPath`"",'-Until',$Until,'-Hold')
  Set-Content $pidFile $p.Id; "keep-awake started (pid $($p.Id)) until $Until ET"; exit 0
}
Add-Type -Namespace W -Name P -MemberDefinition '[DllImport("kernel32.dll")] public static extern uint SetThreadExecutionState(uint f);'
$et = EtNow; $h,$m = $Until.Split(':'); $end = $et.Date.AddHours([int]$h).AddMinutes([int]$m); if($end -le $et){ $end = $end.AddDays(1) }
$ES = [uint32]2147483649   # ES_CONTINUOUS | ES_SYSTEM_REQUIRED (the display may still turn off)
try {
  while((EtNow) -lt $end){
    [void][W.P]::SetThreadExecutionState($ES)
    # done early: every slate game has a final in live.json
    try { $sl = [IO.File]::ReadAllText((Join-Path $root "site\slate.json")) | ConvertFrom-Json
      $n = EtNow; if($n.Hour -lt 5){ $n = $n.AddDays(-1) }; if("$($sl.date)" -ne $n.ToString('yyyyMMdd')){ throw "not tonight's slate" }
      $lv = [IO.File]::ReadAllText((Join-Path $root "site\live.json")) | ConvertFrom-Json
      $ids = @($sl.games | % { "$($_.espnId)" }); $fin = @($lv.games | ? { $_.state -eq 'post' -and $ids -contains "$($_.espnId)" }).Count
      if($ids.Count -gt 0 -and $fin -ge $ids.Count){ break } } catch {}
    Start-Sleep -Seconds 120
  }
} finally { [void][W.P]::SetThreadExecutionState([uint32]2147483648); Remove-Item $pidFile -ErrorAction SilentlyContinue }
