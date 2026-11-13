param([ValidateSet('all','nba','nfl')][string]$Only = 'all', [switch]$Update, [int]$Port = 8777, [int]$Sims = 5000,
  [string[]]$Nights = @('20261106','20261108','20261110','20261112'), [int]$TimeoutMin = 15)
# Model regression check: re-runs both models on fixed history with the code as it is now and compares the result to
# scripts\check-baseline.json. Read-only for the model: it changes no settings, picks or published files.
#   NBA: re-simulates archived nights (tracking\slate-/finals-<date>.json) at $Sims sims, fixed seed, through harness.js __BT,
#        and compares each night's card (picks, record, units) to the baseline.
#   NFL: NFLBT.EV with NFL.P0 (fit 2025, 2026 weeks 1-9 held out) at the openers and at Fanatics: card record and units,
#        per-stat log loss, and the held-out card's picks.
# It serves copies of the pages with the harness and a small auto-run script attached (the real pages are untouched) on
# its own port, runs them in a hidden Edge like night.ps1, and reads the results back from tracking\check-*.json.
# A refreshed tracking\nfl\data.json (nflverse corrections) can move NFL numbers without a code change; the report says what moved.
#   ./scripts/check.ps1                 everything, PASS or what moved (exit 1)
#   ./scripts/check.ps1 -Only nfl       one model (NFL takes ~30 s, NBA a few minutes)
#   ./scripts/check.ps1 -Update         write the current results as the new baseline (only after an approved model change)
$ErrorActionPreference = "Stop"
$root = Split-Path $PSScriptRoot -Parent; $trk = Join-Path $root "tracking"; $baseF = Join-Path $PSScriptRoot "check-baseline.json"
$tmp = Join-Path $env:TEMP "tellme-check-$PID"; New-Item -ItemType Directory -Force $tmp | Out-Null
$t0 = Get-Date; function Say($m){ "[{0,4}s] {1}" -f [int]((Get-Date) - $t0).TotalSeconds, $m }
$utf8 = New-Object Text.UTF8Encoding $false

# ---- page copies with the auto-run script attached
function Attach($src, $dest, $js){ $t = [IO.File]::ReadAllText($src); $i = $t.LastIndexOf('</body>'); if($i -lt 0){ $i = $t.Length }
  [IO.File]::WriteAllText($dest, $t.Substring(0, $i) + $js + $t.Substring($i), $utf8) }
$nbaJs = @'
<script src="/harness.js"></script>
<script>
(async()=>{ const Q=new URLSearchParams(location.search), D=JSON.parse(Q.get('nights')||'[]'), n=+Q.get('n')||5000, wait=ms=>new Promise(r=>setTimeout(r,ms));
  const post=o=>fetch('/upload?name=check-nba.json',{method:'POST',body:JSON.stringify(o)});
  try{ for(let k=0;k<480&&!(window.__BT&&typeof SLATE!=='undefined'&&SLATE&&$('runAll')&&!$('runAll').disabled);k++) await wait(500);
    if(!window.__BT) throw new Error('harness did not load');
    __BT(D,'check',[{name:'base',g:{}}],n);
    while(__BTstate.done<__BTstate.of&&!__BTstate.err) await wait(1000);
    if(__BTstate.err) throw new Error(__BTstate.err);
    await post({ok:true,nights:D,n});
  }catch(e){ await post({ok:false,error:String(e)}); } })();
</script>
'@
$nflJs = @'
<script>
(async()=>{ const wait=ms=>new Promise(r=>setTimeout(r,ms)), post=o=>fetch('/upload?name=check-nfl.json',{method:'POST',body:JSON.stringify(o)});
  try{ for(let k=0;k<120&&!window.NFLBT;k++) await wait(500); await NFLBT.load(); const out={ok:true};
    for(const book of ['OPEN','FAN']){ const o=NFLBT.EV(NFL.P0,{test:9,book,keep:true});
      out[book]={card26:o.card26, card25:o.card25, ll26:Object.fromEntries(Object.entries(o.test26).map(([k,v])=>[k,v.llB])), w:o.w,
        picks26:NFL.card(NFLBT.r26).map(r=>`${r.s} w${r.w} ${r.player} ${r.side} ${r.line} ${r.st} ${r.odds>0?'+':''}${r.odds}`).sort()}; }
    await post(out);
  }catch(e){ await post({ok:false,error:String(e)}); } })();
</script>
'@
Attach (Join-Path $root "nba-matchup-sim.html") (Join-Path $tmp "page.html") $nbaJs
Attach (Join-Path $root "nfl.html") (Join-Path $tmp "nfl.html") $nflJs

# ---- the archive feed's folder starts on the first night so the page loads; a server of our own on $Port
$btrun = Join-Path $trk "btrun"; New-Item -ItemType Directory -Force $btrun | Out-Null
Copy-Item (Join-Path $trk "finals-$($Nights[0]).json") (Join-Path $btrun "finals.json") -Force
Copy-Item (Join-Path $trk "slate-$($Nights[0]).json") (Join-Path $btrun "slate.json") -Force
$ps = @("-NoProfile","-ExecutionPolicy","Bypass","-File")
$srv = Start-Process powershell -WindowStyle Hidden -PassThru -ArgumentList ($ps + @("`"$PSScriptRoot\serve.ps1`"","-Page","`"$tmp\page.html`"","-Data","`"$btrun\slate.json`"","-VideoDir","`"$root\videos`"","-Port","$Port"))
$feed = $null; $edgeTag = "tellme-check-$PID"
$edge = "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe"; if(-not (Test-Path $edge)){ $edge = "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe" }
function StopEdge { Get-CimInstance Win32_Process -Filter "Name='msedge.exe'" | ? { $_.CommandLine -like "*$edgeTag*" } | % { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue } }
# open a URL in a hidden Edge and wait for the page to upload its result file
function RunPage($url, $file, $min){ Remove-Item $file -ErrorAction SilentlyContinue; $prof = Join-Path $tmp "edge"
  Start-Process $edge -ArgumentList @("--headless=new","--disable-gpu","--no-first-run","--no-default-browser-check","--user-data-dir=`"$prof`"",
    "--disable-background-timer-throttling","--disable-renderer-backgrounding","--disable-backgrounding-occluded-windows","--window-size=1440,1000","--$edgeTag","`"$url`"") | Out-Null
  $end = (Get-Date).AddMinutes($min); while(-not (Test-Path $file) -and (Get-Date) -lt $end){ Start-Sleep -Seconds 2 }
  StopEdge; Start-Sleep -Milliseconds 500
  if(-not (Test-Path $file)){ throw "no result from $url after $min minutes" }
  $r = [IO.File]::ReadAllText($file) | ConvertFrom-Json; if(-not $r.ok){ throw "page error: $($r.error)" }; $r }

$cur = [ordered]@{}
try {
  $up = $false; for($i = 0; $i -lt 40 -and -not $up; $i++){ Start-Sleep -Milliseconds 500; try{ Invoke-WebRequest -UseBasicParsing "http://localhost:$Port/slate.json" -TimeoutSec 3 | Out-Null; $up = $true }catch{} }
  if(-not $up){ throw "the check server didn't start on port $Port" }
  if($Only -ne 'nba'){ Say "NFL: backtest at openers and Fanatics..."
    $r = RunPage "http://localhost:$Port/nfl/?norun=1" (Join-Path $trk "check-nfl.json") 3
    $cur.nfl = [ordered]@{ OPEN = $r.OPEN; FAN = $r.FAN } }
  if($Only -ne 'nfl'){ Say "NBA: re-simulating $($Nights.Count) archived nights at $Sims sims..."
    $feed = Start-Process powershell -WindowStyle Hidden -PassThru -ArgumentList ($ps + @("`"$PSScriptRoot\bt-feed.ps1`"","-Minutes","$($TimeoutMin + 2)"))
    foreach($d in $Nights){ Remove-Item (Join-Path $trk "harness-$d-check.json") -ErrorAction SilentlyContinue }
    $q = [Uri]::EscapeDataString((ConvertTo-Json @($Nights) -Compress))
    RunPage "http://localhost:$Port/?view=full&norun=1&nights=$q&n=$Sims" (Join-Path $trk "check-nba.json") $TimeoutMin | Out-Null
    $cur.nba = [ordered]@{ sims = $Sims; nights = [ordered]@{} }
    foreach($d in $Nights){ $h = @([IO.File]::ReadAllText((Join-Path $trk "harness-$d-check.json")) | ConvertFrom-Json)[0]
      $cur.nba.nights[$d] = [ordered]@{ w = $h.w; l = $h.l; units = $h.units; staked = $h.staked; risked = $h.risked; picks = @($h.picks | Sort-Object) } } }
} finally {
  StopEdge; foreach($p in $srv, $feed){ if($p){ Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue } }
  Start-Sleep -Milliseconds 500; Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue }

# ---- compare with the baseline
$base = if(Test-Path $baseF){ [IO.File]::ReadAllText($baseF) | ConvertFrom-Json } else { $null }
$diffs = New-Object Collections.Generic.List[string]
$rec = { param($c) "{0}-{1} {2:+0.00;-0.00}u" -f $c.w, $c.l, [double]$c.staked }
if($cur.nfl){ foreach($bk in 'OPEN','FAN'){ $c = $cur.nfl[$bk]
    Say ("NFL {0,-4} card 2026 held out {1}, 2025 {2}" -f $bk, (& $rec $c.card26), (& $rec $c.card25))
    if($base.nfl){ $b = $base.nfl.$bk
      foreach($k in 'card26','card25'){ if((& $rec $c.$k) -ne (& $rec $b.$k)){ $diffs.Add("NFL $bk $k`: $(& $rec $b.$k) -> $(& $rec $c.$k)") } }
      foreach($st in $c.ll26.PSObject.Properties.Name){ $x = [double]$c.ll26.$st; $y = $b.ll26.$st
        if($y -eq $null -or [math]::Abs($x - [double]$y) -gt .00005){ $diffs.Add("NFL $bk $st log loss: $y -> $x") } }
      $was = @($b.picks26); $now = @($c.picks26)
      $add = @($now | ? { $was -notcontains $_ }); $drop = @($was | ? { $now -notcontains $_ })
      foreach($p in $add){ $diffs.Add("NFL $bk new pick: $p") }; foreach($p in $drop){ $diffs.Add("NFL $bk dropped pick: $p") } } } }
if($cur.nba){ $tw = 0; $tl = 0; $ts = 0
  foreach($d in $Nights){ $c = $cur.nba.nights[$d]; $tw += $c.w; $tl += $c.l; $ts += [double]$c.staked
    Say ("NBA {0}: {1}" -f $d, (& $rec $c))
    $b = if($base.nba){ $base.nba.nights.$d } else { $null }
    if($base.nba -and $base.nba.sims -ne $Sims){ $diffs.Add("NBA baseline was run at $($base.nba.sims) sims, this at ${Sims}: not comparable"); break }
    if($base.nba -and -not $b){ $diffs.Add("NBA $d isn't in the baseline") }
    elseif($b){ if((& $rec $c) -ne (& $rec $b)){ $diffs.Add("NBA $d card: $(& $rec $b) -> $(& $rec $c)") }
      $was = @($b.picks); $now = @($c.picks)
      foreach($p in @($now | ? { $was -notcontains $_ })){ $diffs.Add("NBA $d new pick: $p") }
      foreach($p in @($was | ? { $now -notcontains $_ })){ $diffs.Add("NBA $d dropped pick: $p") } } }
  Say ("NBA {0} nights: {1}-{2} {3:+0.00;-0.00}u staked" -f $Nights.Count, $tw, $tl, $ts) }

if($Update){
  $out = if($base){ $base } else { [pscustomobject]@{} }
  $out | Add-Member -Force made (Get-Date).ToUniversalTime().ToString("o")
  if($cur.nfl){ $out | Add-Member -Force nfl $cur.nfl }; if($cur.nba){ $out | Add-Member -Force nba $cur.nba }
  [IO.File]::WriteAllText($baseF, ($out | ConvertTo-Json -Depth 8), $utf8); Say "baseline written: $baseF"; exit 0 }
if(-not $base){ Say "no baseline yet: run with -Update to make one"; exit 1 }
if($diffs.Count){ "MOVED ({0}):" -f $diffs.Count; $diffs | Select-Object -First 60 | % { "  $_" }; if($diffs.Count -gt 60){ "  ... and $($diffs.Count - 60) more" }; exit 1 }
"PASS: the models match the baseline ($($base.made))"
