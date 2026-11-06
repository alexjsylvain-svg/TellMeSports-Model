param([int]$Minutes = 240, [string]$Dir = "")
# Feeds harness.js __BT: waits for tracking\btreq.json ({want:"yyyymmdd"}) and copies that night's archived finals and slate
# into tracking\btrun (finals first, so the page never sees a new slate beside old finals). Nights come from tracking\btNN
# (Oct 22-28) or tracking\slate-<date>.json + finals-<date>.json (later nights). Stops after $Minutes.
$ErrorActionPreference = "Stop"
$trk = Join-Path (Split-Path $PSScriptRoot -Parent) "tracking"
$run = Join-Path $trk "btrun"; $req = Join-Path $trk "btreq.json"
$end = (Get-Date).AddMinutes($Minutes)
while((Get-Date) -lt $end){
  if(Test-Path $req){
    $want = (Get-Content $req -Raw | ConvertFrom-Json).want; Remove-Item $req
    $bt = Join-Path $trk ("bt" + $want.Substring(6,2))
    if($Dir){ $dd = Join-Path (Split-Path $trk -Parent) $Dir; $sl = Join-Path $dd "slate-$want.json"; $fn = Join-Path $dd "finals-$want.json" }
    elseif($want -le "20261028" -and (Test-Path (Join-Path $bt "slate.json"))){ $sl = Join-Path $bt "slate.json"; $fn = Join-Path $bt "finals.json" }
    else { $sl = Join-Path $trk "slate-$want.json"; $fn = Join-Path $trk "finals-$want.json" }
    Copy-Item $fn (Join-Path $run "finals.json") -Force; Copy-Item $sl (Join-Path $run "slate.json") -Force
    Write-Host "$(Get-Date -Format T) fed $want"
  }
  Start-Sleep -Milliseconds 300
}
