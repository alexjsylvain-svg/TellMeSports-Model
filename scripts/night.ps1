param(
  [string]$Date,                 # YYYYMMDD, default today (Eastern)
  [string[]]$Placed = @(),       # bets the user placed: "Anfernee Simons under 1.5 AST @-125 1.5u" (@price and stake optional)
  [string[]]$Ovr = @(),          # injury overrides: "CHA|Moussa Diabate=q:0.5", "TOR|Scottie Barnes=out", "PHX|Jordan Goodwin=active"
  [switch]$Lock,                 # mark the night final after freezing (only on the user's say-so)
  [switch]$Unlock,               # reopen a locked night first (the user asked for another pass)
  [switch]$NoBuild,              # skip the data refetch (reuse site\slate.json)
  [switch]$NoPush,               # freeze locally but don't publish (for tests)
  [string]$Note = "",
  [int]$Sims = 50000,
  [int]$TimeoutMin = 40
)
# One command for an on-demand NBA night (replaces ~15-25 manual steps):
#   pull -> build.ps1 -Refetch -> local server -> hidden Edge runs the page with ?auto=1 (50k sims, freezePicks, exportBoard,
#   optional lock) -> push-site.ps1 -> a short summary. The card logic is the page's own; this only drives it.
#   .\scripts\night.ps1
#   .\scripts\night.ps1 -Placed "Anfernee Simons under 1.5 AST @-125" -Ovr "CHA|Moussa Diabate=q:0.5" -Lock
# The claude.ai artifact isn't touched (a script can't publish it); publish it afterwards if wanted.
$ErrorActionPreference = "Stop"
$root = Split-Path $PSScriptRoot -Parent; Set-Location $root
$et = [TimeZoneInfo]::ConvertTimeBySystemTimeZoneId([DateTime]::UtcNow, 'Eastern Standard Time')
if(-not $Date){ $Date = $et.ToString("yyyyMMdd") }
$t0 = Get-Date
function Say($m){ Write-Host ("[{0,4}s] {1}" -f [int]((Get-Date)-$t0).TotalSeconds, $m) }
$picksF = "tracking/picks-$Date.json"; $statusF = "tracking/night-status-$Date.json"

# 1. latest from GitHub (scheduled runs or the user's lock may have landed)
git pull --rebase --autostash -q 2>&1 | Out-Null
$y = $et.AddDays(-1).ToString("yyyyMMdd"); if($Date -eq $et.ToString("yyyyMMdd") -and -not (Test-Path "tracking/results-$y.json")){ Say "warning: $y isn't graded yet (no tracking/results-$y.json)" }
if(Test-Path $picksF){ $cur = Get-Content $picksF -Raw | ConvertFrom-Json
  if($cur.final -and -not $Unlock){ Say "tonight's card is locked (final $($cur.finalAt)); pass -Unlock to reopen it. Nothing run."; exit 1 }
  if($cur.final -and $Unlock){ $cur.final = $false; $cur | Add-Member -Force unlockedAt ((Get-Date).ToUniversalTime().ToString("o"))
    [IO.File]::WriteAllText((Resolve-Path $picksF), ($cur | ConvertTo-Json -Depth 12)); Say "reopened the locked card" } }

# 2. data
if(-not $NoBuild){ Say "building $Date (lines, injuries, lineups)..."
  $bt = Get-Date; $b = & "$PSScriptRoot/build.ps1" -Date $Date -Refetch *>&1 | Out-String -Width 4096
  if((Get-Item site/slate.json).LastWriteTime -lt $bt){ Write-Host $b; throw "build.ps1 didn't write site/slate.json" }
  $fan = [regex]::Matches($b, 'Fanatics props (\d+)') | % { [int]$_.Groups[1].Value }; Say "built: $($fan.Count) games, Fanatics props per game $($fan -join '/')" }
$slate = Get-Content site/slate.json -Raw | ConvertFrom-Json
if("$($slate.date)" -ne $Date){ throw "site/slate.json is $($slate.date), not $Date" }

# 3. local server (serve.ps1 on 8765; reuse one that's running)
$up = $false; try{ Invoke-WebRequest -UseBasicParsing "http://localhost:8765/slate.json" -TimeoutSec 5 | Out-Null; $up = $true }catch{}
$srv = $null
if(-not $up){ Say "starting the local server"
  $srv = Start-Process powershell -WindowStyle Hidden -PassThru -ArgumentList @("-NoProfile","-ExecutionPolicy","Bypass","-File","`"$root\scripts\serve.ps1`"","-Page","`"$root\nba-matchup-sim.html`"","-Data","`"$root\site\slate.json`"","-VideoDir","`"$root\videos`"")
  for($i=0;$i -lt 30 -and -not $up;$i++){ Start-Sleep -Milliseconds 500; try{ Invoke-WebRequest -UseBasicParsing "http://localhost:8765/slate.json" -TimeoutSec 3 | Out-Null; $up=$true }catch{} }
  if(-not $up){ throw "the local server didn't start" } }

# 4. overrides and placed bets -> URL
$ov = [ordered]@{}
foreach($o in $Ovr){ if($o -notmatch '^\s*([A-Z]{2,4}\|[^=]+?)\s*=\s*(q|out|active)(?::([\d.]+))?\s*$'){ throw "bad -Ovr '$o' (use TEAM|Name=q:0.5, =out or =active)" }
  $st = $matches[2]; $pr = if($st -eq 'q'){ if($matches[3]){ [double]$matches[3] } else { .5 } } elseif($st -eq 'out'){ 0 } else { 1 }
  $ov[$matches[1]] = @{ status = $st; prob = $pr } }
$enc = { param($s) [Uri]::EscapeDataString($s) }
$url = "http://localhost:8765/?view=full&sims=$Sims&run=$Date&auto=1"
if($ov.Count){ $url += "&ovr=" + (& $enc ($ov | ConvertTo-Json -Compress -Depth 4)) }
if($Placed.Count){ $url += "&placed=" + (& $enc (ConvertTo-Json @($Placed) -Compress)) }
if($Lock){ $url += "&lock=1"; if($Note){ $url += "&note=" + (& $enc $Note) } }

# 5. hidden Edge runs the page; wait for its status file
Remove-Item $statusF -ErrorAction SilentlyContinue
$edge = "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe"; if(-not (Test-Path $edge)){ $edge = "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe" }
$prof = Join-Path $env:TEMP "tellme-edge-$PID"
$ep = Start-Process $edge -PassThru -ArgumentList @("--headless=new","--disable-gpu","--no-first-run","--no-default-browser-check","--user-data-dir=`"$prof`"",
  "--disable-background-timer-throttling","--disable-renderer-backgrounding","--disable-backgrounding-occluded-windows","--window-size=1440,1000","`"$url`"")
Say "simulating $($slate.games.Count) games at $Sims sims each (hidden Edge)..."
$deadline = (Get-Date).AddMinutes($TimeoutMin + 2)
while(-not (Test-Path $statusF) -and (Get-Date) -lt $deadline){ Start-Sleep -Seconds 5 }
Get-CimInstance Win32_Process -Filter "Name='msedge.exe'" | ? { $_.CommandLine -like "*tellme-edge-$PID*" } | % { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
Start-Sleep -Milliseconds 800; Remove-Item $prof -Recurse -Force -ErrorAction SilentlyContinue
if($srv){ Stop-Process -Id $srv.Id -Force -ErrorAction SilentlyContinue }
if(-not (Test-Path $statusF)){ throw "no result from the page after $TimeoutMin minutes" }
$s = Get-Content $statusF -Raw | ConvertFrom-Json
if(-not $s.ok){ Say "FAILED: $($s.error)"; exit 1 }

# 6. summary
$pct = { param($p) "{0:N1}%" -f ($p*100) }; $odds = { param($o) if($o -gt 0){ "+$o" } else { "$o" } }
$card = @($s.card); $risk = ($card | Measure-Object stake -Sum).Sum
$when = [TimeZoneInfo]::ConvertTimeBySystemTimeZoneId([DateTime]::UtcNow,'Eastern Standard Time').ToString("h:mm tt")
Write-Host ""
Write-Host ("Slate {0}: {1} games, sims took {2}s, frozen {3} ET, {4}" -f $Date,$slate.games.Count,$s.simSeconds,$when,$(if($s.locked){"LOCKED"}else{"not locked"}))
Write-Host ("Card: {0} plays, {1}u at risk" -f $card.Count,$risk)
foreach($b in ($card | Sort-Object @{e='stake';Descending=$true},@{e='p';Descending=$true})){ Write-Host ("  {0,4}u  {1,-11} {2,-40} {3,5} {4,-3} {5}{6}" -f $b.stake,$b.game,$b.bet,(& $odds $b.odds),$b.book,(& $pct $b.p),$(if($b.placed){"  placed"}else{""})) }
if(@($s.alts).Count){ Write-Host "Alternatives (not on the card):"; foreach($b in $s.alts){ Write-Host ("  {0,4}u  {1,-11} {2,-40} {3,5} {4,-3} {5}" -f $b.stake,$b.game,$b.bet,(& $odds $b.odds),$b.book,(& $pct $b.p)) } }
if($null -ne $s.added){ Write-Host ("Changes vs the last freeze: added {0}; dropped {1}" -f $(if(@($s.added).Count){$s.added -join ", "}else{"none"}),$(if(@($s.dropped).Count){$s.dropped -join ", "}else{"none"})) }
if(@($s.missing).Count){ Write-Host ("NOT FOUND (check the bet text): " + ($s.missing -join "; ")) }
$q = foreach($t in $slate.teams.PSObject.Properties){ foreach($p in $t.Value.players){ $e="$($p.espnInj)"; $r="$($p.rwInj)"
  if(($e -and $e -ne "Out") -or ($r -and $r -notin "Out","OFS")){ if(-not ($e -eq "Out" -or $r -eq "Out")){ "$($t.Name) $($p.name) ($(@($e,$r) -ne '' -join '/'))" } } } }
$out = foreach($t in $slate.teams.PSObject.Properties){ $n = @($t.Value.players | ? { $_.espnInj -eq "Out" -or $_.rwInj -eq "Out" } | % { $_.name }); if($n.Count){ "$($t.Name): $($n -join ', ')" } }
Write-Host ("Questionable: " + $(if($q){ $q -join "; " } else { "none" }))
Write-Host ("Out: " + ($out -join " | "))
if($ov.Count){ Write-Host ("Overrides used: " + (($ov.GetEnumerator() | % { "$($_.Key)=$($_.Value.status)$(if($_.Value.status -eq 'q'){":"+$_.Value.prob})" }) -join ", ")) }
# paper-only line-gap list (Nov 14): logged with each freeze, never on the card; a failure here never stops the run
try { Write-Host (& "$PSScriptRoot/gap-paper.ps1" -Date $Date -Log) } catch { Write-Warning "gap-paper log failed: $_" }
# "How he gets it" panel data (Nov 14): caches last night's play-by-play, writes site/creates.json; context only, never stops the run
try { Write-Host (& "$PSScriptRoot/creates.ps1" -Date $Date) } catch { Write-Warning "creates failed: $_" }

# 7. publish to GitHub Pages
if($NoPush){ Say "not published (-NoPush)"; exit 0 }
$msg = "Slate $Date (night.ps1, $when ET, $Sims sims$(if($s.locked){', LOCKED'}else{', not locked'})): $($card.Count) plays, $($risk)u" +
  $(if(@($card | ? placed).Count){ "; placed: " + ((@($card | ? placed) | % { $_.bet }) -join ", ") } else { "" }) +
  $(if($ov.Count){ "; overrides: " + (($ov.Keys) -join ", ") } else { "" }) + $(if($Note){ "; $Note" } else { "" }) +
  "`n`nCo-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
$p = & "$PSScriptRoot/push-site.ps1" -Message $msg *>&1 | Out-String
Say ($(if($p -match 'pushed to GitHub'){ "published to GitHub Pages" } else { "push-site: " + ($p.Trim() -split "`n" | Select-Object -Last 2) -join " " }))
