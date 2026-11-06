param([string]$Root = (Split-Path $PSScriptRoot -Parent))
# Pools bt-props for every archived night with each game's pregame spread, then compares sim and actual minutes and prop
# results by spread size and by actual final margin: does the sim see blowouts (and the minutes starters lose in them) coming?
$rows = @()
foreach($f in Get-ChildItem (Join-Path $Root "tracking\bt-props-*.json")){
  $d = $f.BaseName -replace 'bt-props-',''
  $slPath = Join-Path $Root "tracking\slate-$d.json"; if(-not (Test-Path $slPath)){ continue }
  $sl = Get-Content $slPath -Raw -Encoding UTF8 | ConvertFrom-Json
  $sp = @{}; foreach($g in $sl.games){ $l = if($g.lines.DK){ $g.lines.DK } elseif($g.lines.FD){ $g.lines.FD } else { $g.lines.FAN }; $sp[$g.espnId] = [math]::Abs([double]$l.spread) }
  foreach($x in (Get-Content $f.FullName -Raw -Encoding UTF8 | ConvertFrom-Json)){
    if($x.mkt -ne 'Prop' -or $null -eq $x.act -or $x.act -eq $x.line -or -not $x.actMin){ continue }
    $x | Add-Member -NotePropertyName spread -NotePropertyValue $sp[$x.gid] -Force; $rows += $x } }
function B($v,$cuts){ for($i=0;$i -lt $cuts.Count;$i++){ if($v -lt $cuts[$i]){ return $i } }; return $cuts.Count }
function Avg($a){ $a=@($a); if($a.Count){ ($a | Measure-Object -Average).Average } else { [double]::NaN } }
function Line($label,$s){ $u=@($s | Sort-Object player,gid -Unique)
  "{0,-7} players {1,4}  simMin {2,5:N1}  actMin {3,5:N1}  over hit {4,4:P0}  sim said {5,4:P0}  market said {6,4:P0}" -f $label, $u.Count, (Avg ($u|%{$_.simMin})), (Avg ($u|%{$_.actMin})), (Avg ($s|%{ [int]($_.act -gt $_.line) })), (Avg ($s|%{$_.pSim})), (Avg ($s|%{$_.pm})) }
"props graded: $($rows.Count)"
$st = @($rows | ? start); $bn = @($rows | ? { -not $_.start })
"`nSTARTERS by actual final margin"
foreach($k in 0..2){ Line @('0-9','10-19','20+')[$k] @($st | ? { (B $_.absMargin @(10,20)) -eq $k }) }
"`nSTARTERS by pregame spread (games with a 20+ margin in brackets)"
foreach($k in 0..3){ $s=@($st | ? { (B $_.spread @(4,8,12)) -eq $k }); $gm=@($s | Sort-Object date,gid -Unique)
  (Line @('<4','4-8','8-12','12+')[$k] $s) + ("  [{0}/{1}]" -f @($gm | ? { $_.absMargin -ge 20 }).Count, $gm.Count) }
"`nBENCH by pregame spread"
foreach($k in 0..3){ Line @('<4','4-8','8-12','12+')[$k] @($bn | ? { (B $_.spread @(4,8,12)) -eq $k }) }
"`nBENCH by actual final margin"
foreach($k in 0..2){ Line @('0-9','10-19','20+')[$k] @($bn | ? { (B $_.absMargin @(10,20)) -eq $k }) }
