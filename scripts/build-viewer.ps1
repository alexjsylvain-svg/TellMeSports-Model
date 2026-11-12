# Builds the invite-only viewer site in viewer\ (Nov 12, 2026): the phone app and the published data files, WITHOUT the model.
# Cloudflare Pages serves this folder behind Cloudflare Access; the full model (nba-matchup-sim.html), the NFL model page,
# slate.json (the model's inputs), the scripts and the tracking history never go into it.
#   viewer\index.html      the phone app from nba-matchup-sim.html: page head and styles, the #phoneApp markup and the phone
#                          script, with the model script replaced by the few helpers the phone app uses (copied from the model
#                          so they stay in sync). Always the phone layout; no "Open the full model" button.
#   viewer\*.json          picks, board, live, results, season, boxes, alerts (from docs\), nfl\*.json (not nfl\index.html)
#   viewer\icons, manifest the home-screen app files
# Runs in Windows PowerShell and in pwsh on GitHub's Linux runners. Called by push-site.ps1 and the nightly-grading workflow.
#   ./scripts/build-viewer.ps1
$ErrorActionPreference = "Stop"
$root = Split-Path $PSScriptRoot -Parent
$src  = Join-Path $root "nba-matchup-sim.html"
$docs = Join-Path $root "docs"
$out  = Join-Path $root "viewer"
New-Item -ItemType Directory -Force $out | Out-Null

$L = [IO.File]::ReadAllLines($src, [Text.Encoding]::UTF8)
function Find([string]$pattern, [int]$from = 0){ for($i=$from; $i -lt $L.Count; $i++){ if($L[$i] -match $pattern){ return $i } }; throw "build-viewer: '$pattern' not found in nba-matchup-sim.html" }
$iStyleEnd = Find '^</style>'
$iWrap     = Find '^<div class="wrap">'
$iPhone    = Find '^<div id="phoneApp"'
$iScript1  = Find '^<script>' $iPhone
$iEnd1     = Find '^</script>' $iScript1
$iScript2  = Find '^<script>' ($iEnd1 + 1)
$iEnd2     = Find '^</script>' $iScript2

# the helpers the phone script uses from the model script (top-level names checked Nov 12: $, esc, norm, dec, impl, oddsTxt,
# DD_HOLD; the rest are guarded by PHONE or only in text)
$HELP = 'clamp','esc','fmt','pctf','norm','dec','impl','amer','oddsTxt','DD_HOLD'
$helpers = foreach($h in $HELP){ $i = Find ('^const ' + [regex]::Escape($h) + '=') $iScript1; if($i -gt $iEnd1){ throw "build-viewer: helper $h is outside the model script" }; $L[$i] }

$head = @($L[0..$iStyleEnd] | Where-Object { $_ -notmatch 'mp4-muxer' })
# keep search engines out and say where this copy comes from
$head = @($head | ForEach-Object { if($_ -match '^<meta name="viewport"'){ $_; '<meta name="robots" content="noindex,nofollow">' } else { $_ } })
$phoneHtml = $L[$iPhone..($iScript1 - 1)]
$shim = @(
  '<script>'
  '"use strict";'
  '// Viewer build (scripts/build-viewer.ps1): the phone app only. The model is not part of this page.'
  'const $=id=>document.getElementById(id);'
  'const PHONE=true; document.body.classList.add("phone");'
) + $helpers + @(
  'let SLATE=null, FROZEN=null; const PRICED={}, LIVE={data:null, res:{}};'
  'function rosterOf(){ return {}; }'
  'function renderLive(){} async function runLive(){}'
  '</script>'
)
$phoneJs = [string]::Join("`n", $L[$iScript2..$iEnd2])
$btn = '<button class="pa-btn" data-act="full">Open the full model</button>'
if(-not $phoneJs.Contains($btn)){ throw "build-viewer: the 'Open the full model' button changed; update build-viewer.ps1" }
$phoneJs = $phoneJs.Replace($btn, '')

$html = [string]::Join("`n", @($head + @('<body>') + $phoneHtml + $shim + @($phoneJs) + @('</body>','</html>')))
# guard: none of the model may leak into the viewer
foreach($m in 'function buildPlayer','function projMin','function simGame','function runAll','freezePicks','STOPPERS','mergeSeasons','leagueContext','posPrior'){
  if($html.Contains($m)){ throw "build-viewer: model code '$m' would be published in viewer\index.html" } }
if(-not $html.Contains('id="phoneApp"')){ throw "build-viewer: phone app markup missing" }
[IO.File]::WriteAllText((Join-Path $out "index.html"), $html, (New-Object Text.UTF8Encoding($false)))

# data and app files
$files = 'picks.json','board.json','live.json','results.json','season.json','boxes.json','alerts.json','manifest.webmanifest'
foreach($f in $files){ $p = Join-Path $docs $f; if(Test-Path $p){ Copy-Item $p (Join-Path $out $f) -Force } }
if(Test-Path (Join-Path $docs "icons")){ Copy-Item (Join-Path $docs "icons") $out -Recurse -Force }
$nflOut = Join-Path $out "nfl"; New-Item -ItemType Directory -Force $nflOut | Out-Null
Get-ChildItem (Join-Path $docs "nfl") -Filter *.json -ErrorAction SilentlyContinue | ForEach-Object { Copy-Item $_.FullName (Join-Path $nflOut $_.Name) -Force }
# the model's settings never go to viewers. The phone app doesn't read them (checked Nov 12, 2026):
#   picks.json      model (the ~50 sim settings) and modelWeight (the sim/market blend weight)
#   nfl/backtest    sim (the NFL game-sim fit: sdM, sdT, tdK, slopes), simW, atdHold; its "Game sim settings" card just hides
# The per-prop sim results in board.json (cnt, lo, w, pSim) stay: the bet calculator and the charts are built from them.
function Strip([string]$path, [string[]]$keys){
  if(-not (Test-Path $path)){ return }
  $j = [IO.File]::ReadAllText($path) | ConvertFrom-Json
  $hit = @($keys | Where-Object { $j.PSObject.Properties.Name -contains $_ })
  if(-not $hit.Count){ return }
  foreach($k in $hit){ $j.PSObject.Properties.Remove($k) }
  [IO.File]::WriteAllText($path, (ConvertTo-Json -InputObject $j -Depth 50 -Compress), (New-Object Text.UTF8Encoding($false)))
}
Strip (Join-Path $out "picks.json") 'model','modelWeight'
Strip (Join-Path $nflOut "backtest.json") 'sim','simW','atdHold'
# guard: no model settings in the published data either
Get-ChildItem $out -Recurse -Filter *.json | ForEach-Object {
  $t = [IO.File]::ReadAllText($_.FullName)
  foreach($m in '"modelWeight"','"model":{','"model": {','"slopes"','"simW"'){ if($t.Contains($m)){ throw "build-viewer: model settings $m would be published in viewer\$($_.Name)" } } }
# nothing else may sit in viewer\ (an old copy of a model page, slate.json, ...)
$allowed = @($files + 'index.html','icons','nfl','_headers')
Get-ChildItem $out | Where-Object { $allowed -notcontains $_.Name } | ForEach-Object { Remove-Item $_.FullName -Recurse -Force; "build-viewer: removed $($_.Name)" }
Get-ChildItem $nflOut | Where-Object { $_.Extension -ne '.json' } | ForEach-Object { Remove-Item $_.FullName -Force; "build-viewer: removed nfl/$($_.Name)" }
# Cloudflare Pages headers: no caching of the data files, no framing, no referrer leaks
[IO.File]::WriteAllText((Join-Path $out "_headers"), "/*`n  X-Frame-Options: DENY`n  Referrer-Policy: no-referrer`n  X-Robots-Tag: noindex, nofollow`n/*.json`n  Cache-Control: no-store`n", (New-Object Text.UTF8Encoding($false)))
"viewer built: index.html $([math]::Round((Get-Item (Join-Path $out 'index.html')).Length/1KB))KB (model page $([math]::Round((Get-Item $src).Length/1KB))KB), $(@(Get-ChildItem $out -Recurse -File).Count) files"
