param([int]$Season = 2026, [int]$Week, [switch]$Refetch)
# NFL pilot: grade a week's paper card(s) from nflverse box scores (tracking\nfl\data.json) into tracking\nfl\results.json.
#   card-<S>-w<NN>.json          the card frozen before the games ("card")
#   card-<S>-w<NN>-shadow.json   the same week priced by a candidate model, if there is one ("shadow"): graded and kept
#                                separately so the two can be compared before anything goes live
# Paper only: nothing here is a bet. A player with no box score that week (inactive) is VOID (0u), as the books do.
# Stakes in units; a win pays stake x (decimal odds - 1). Re-running replaces that week's rows.
#   ./scripts/nfl-grade.ps1 -Week 10 [-Refetch]   (-Refetch first refreshes data.json from nflverse)
$ErrorActionPreference = "Stop"
$root = Split-Path $PSScriptRoot -Parent
$nfl = Join-Path $root "tracking\nfl"
if($Refetch){ & (Join-Path $PSScriptRoot "nfl-data.ps1") -Refetch -Season $Season | Select-Object -Last 1 }
$D = [IO.File]::ReadAllText((Join-Path $nfl "data.json")) | ConvertFrom-Json
$ci = @{}; for($i=0; $i -lt $D.rowCols.Count; $i++){ $ci[$D.rowCols[$i]] = $i }
$box = @{}; foreach($r in $D.rows){ if($r[$ci.season] -eq $Season -and $r[$ci.week] -eq $Week){ $box[[string]$r[$ci.pid]] = $r } }
if(-not $box.Count){ throw "no box scores for $Season week $Week in data.json yet (run with -Refetch after the games)" }
$gi = @{}; for($i=0; $i -lt $D.gameCols.Count; $i++){ $gi[$D.gameCols[$i]] = $i }
$finals = @{}; foreach($g in $D.games){ if($g[$gi.season] -eq $Season -and $g[$gi.week] -eq $Week -and $g[$gi.homeScore] -ne $null){
  $a = $g[$gi.away]; $h = $g[$gi.home]; $finals["$a @ $h"] = "$a $($g[$gi.awayScore]), $h $($g[$gi.homeScore])" } }
$F = @{ REC='rec'; REC_YDS='recyds'; RUSH_ATT='car'; RUSH_YDS='ryds'; PASS_YDS='pyds'; PASS_ATT='att'; PASS_CMP='cmp'; PASS_TD='ptd' }
$LBL = @{ REC='receptions'; REC_YDS='rec yds'; RUSH_ATT='rush att'; RUSH_YDS='rush yds'; PASS_YDS='pass yds'; PASS_ATT='pass att'; PASS_CMP='completions'; PASS_TD='pass TDs'; RR_YDS='rush+rec yds'; ATD='anytime TD' }
function Dec([int]$o){ if($o -gt 0){ 1 + $o/100 } else { 1 + 100/(-$o) } }
function Val($r, [string]$st){
  if($st -eq 'ATD'){ return [int]$r[$ci.rtd] + [int]$r[$ci.rectd] }
  if($st -eq 'RR_YDS'){ return [int]$r[$ci.ryds] + [int]$r[$ci.recyds] }
  return [double]$r[$ci[$F[$st]]] }
$rf = Join-Path $nfl "results.json"
$R = if(Test-Path $rf){ [IO.File]::ReadAllText($rf) | ConvertFrom-Json } else { [pscustomobject]@{ note="NFL pilot paper picks, graded after the games (paper only, not bets)."; picks=@() } }
# older hand-graded rows have no "set": they count as the card's and are replaced too
$keep = @($R.picks | Where-Object { -not ($_.season -eq $Season -and $_.week -eq $Week -and (-not $_.set -or $_.set -in @('card','shadow'))) })
$new = @(); $sum = [ordered]@{}
foreach($set in 'card','shadow'){
  $cf = Join-Path $nfl ("card-{0}-w{1:D2}{2}.json" -f $Season,$Week,$(if($set -eq 'shadow'){'-shadow'}else{''}))
  if(-not (Test-Path $cf)){ continue }
  $C = [IO.File]::ReadAllText($cf) | ConvertFrom-Json
  $s = [ordered]@{ w=0; l=0; p=0; v=0; staked=0.0; units=0.0; open=0 }
  foreach($b in $C.picks){
    $line = [double]$b.line; $r = $box[[string]$b.pid]; $fin = $finals[$b.game]
    $res = $null; $act = $null; $u = 0.0
    if(-not $fin){ $res = 'OPEN'; $s.open++ }
    elseif(-not $r){ $res = 'VOID' }
    else { $act = Val $r $b.st; $d = if($b.side -eq 'Over'){ $act - $line } else { $line - $act }
      if($d -gt 0){ $res = 'WIN'; $u = [math]::Round($b.stake * ((Dec $b.odds) - 1), 2) } elseif($d -lt 0){ $res = 'LOSS'; $u = -[double]$b.stake } else { $res = 'PUSH' } }
    switch($res){ 'WIN' { $s.w++ } 'LOSS' { $s.l++ } 'PUSH' { $s.p++ } 'VOID' { $s.v++ } }
    if($res -in 'WIN','LOSS'){ $s.staked += $b.stake; $s.units += $u }
    $bet = if($b.st -eq 'ATD'){ "$($b.player) anytime TD" } else { "$($b.player) $($b.side) $($b.line) $($LBL[$b.st])" }
    $new += [pscustomobject][ordered]@{ season=$Season; week=$Week; set=$set; game=$b.game; final=$fin; bet=$bet; tier=$b.tier; book=$b.book; odds=[int]$b.odds; stake=[double]$b.stake; p=[math]::Round([double]$b.p,3); actual=$act; result=$res; units=$u } }
  $s.staked = [math]::Round($s.staked,2); $s.units = [math]::Round($s.units,2); $sum[$set] = $s
  "{0,-6} week {1}: {2}-{3}{4}{5}, {6:+0.00;-0.00}u on {7}u staked{8}" -f $set,$Week,$s.w,$s.l,$(if($s.p){"-$($s.p)"}),$(if($s.v){", $($s.v) void"}),$s.units,$s.staked,$(if($s.open){", $($s.open) not final yet"}) }
$all = @($keep + $new)
# running totals: the live card (set "card", plus the older rows from before sets existed) and the shadow model separately
$tot = { param($rows) $w=@($rows | ? result -eq 'WIN').Count; $l=@($rows | ? result -eq 'LOSS').Count; $p=@($rows | ? result -eq 'PUSH').Count
  $st=($rows | ? { $_.result -in 'WIN','LOSS' } | Measure-Object stake -Sum).Sum; $un=($rows | Measure-Object units -Sum).Sum
  [ordered]@{ w=$w; l=$l; p=$p; staked=[math]::Round([double]$st,2); units=[math]::Round([double]$un,2) } }
$cardRows = @($all | ? { -not $_.set -or $_.set -eq 'card' }); $shRows = @($all | ? { $_.set -eq 'shadow' })
$out = [ordered]@{ note=$R.note; graded=(Get-Date).ToUniversalTime().ToString("o"); picks=$all; toDate=(& $tot $cardRows) }
if($shRows.Count){ $out.shadowToDate = (& $tot $shRows) }
[IO.File]::WriteAllText($rf, ($out | ConvertTo-Json -Depth 5), (New-Object Text.UTF8Encoding($false)))
"to date (card): $($out.toDate.w)-$($out.toDate.l), $($out.toDate.units)u on $($out.toDate.staked)u staked"
if($out.shadowToDate){ "to date (shadow): $($out.shadowToDate.w)-$($out.shadowToDate.l), $($out.shadowToDate.units)u on $($out.shadowToDate.staked)u staked" }
"RESULT " + ($sum | ConvertTo-Json -Compress)
