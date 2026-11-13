param([int]$Season = 2026, [int]$Week, [switch]$Refetch, [switch]$DryRun, [switch]$VoidDNP)
# NFL pilot: grade a week's paper card(s) from nflverse box scores (tracking\nfl\data.json) into tracking\nfl\results.json.
#   card-<S>-w<NN>.json          the card frozen before the games ("card")
#   card-<S>-w<NN>-shadow.json   the same week priced by a candidate model, if there is one ("shadow"): graded and kept
#                                separately so the two can be compared before anything goes live
#   gameday-<S>-w<NN>-<date>.json  a locked game-day card at Fanatics prices (archived nfl/tonight.json): picks, plus-money
#                                alternatives and the parlay ("gameday"), kept out of the card's record and totalled on its own
# -DryRun prints the rows and totals without writing results.json.
# Paper only: nothing here is a bet. A player with no box score that week (didn't play) is graded a LOSS (actual 0):
# the model chose someone who never took the field, and the record should show it. A book would have refunded it, so the row
# carries a note saying so. -VoidDNP grades those as VOID (0u) instead, the way the books do.
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
$keep = @($R.picks | Where-Object { -not ($_.season -eq $Season -and $_.week -eq $Week -and (-not $_.set -or $_.set -in @('card','shadow','gameday'))) })
$new = @(); $sum = [ordered]@{}
# one prop against the box score: result, actual, units (no final yet = OPEN; no box score = didn't play: LOSS, or VOID with -VoidDNP)
function Grade($b){ $line = [double]$b.line; $r = $box[[string]$b.pid]; $fin = $finals[[string]$b.game]
  if(-not $fin){ return @('OPEN', $null, 0.0) }
  if(-not $r){ if($VoidDNP){ return @('VOID', $null, 0.0) }; return @('LOSS', 0, -[double]$b.stake, 'dnp') }
  $act = Val $r $b.st; $d = if($b.side -eq 'Over'){ $act - $line } else { $line - $act }
  if($d -gt 0){ return @('WIN', $act, [math]::Round($b.stake * ((Dec $b.odds) - 1), 2)) }
  if($d -lt 0){ return @('LOSS', $act, -[double]$b.stake) }
  return @('PUSH', $act, 0.0) }
function Tally($set, $res, $stake, $u){ if(-not $sum.Contains($set)){ $sum[$set] = [ordered]@{ w=0; l=0; p=0; v=0; staked=0.0; units=0.0; open=0 } }; $s = $sum[$set]
  switch($res){ 'WIN' { $s.w++ } 'LOSS' { $s.l++ } 'PUSH' { $s.p++ } 'VOID' { $s.v++ } 'OPEN' { $s.open++ } }
  if($res -in 'WIN','LOSS'){ $s.staked += $stake; $s.units += $u } }
$srcs = @()
foreach($set in 'card','shadow'){
  $cf = Join-Path $nfl ("card-{0}-w{1:D2}{2}.json" -f $Season,$Week,$(if($set -eq 'shadow'){'-shadow'}else{''}))
  if(Test-Path $cf){ $srcs += ,@($set, ([IO.File]::ReadAllText($cf) | ConvertFrom-Json)) } }
foreach($gf in @(Get-ChildItem $nfl -Filter ("gameday-{0}-w{1:D2}-*.json" -f $Season,$Week) | Sort-Object Name)){ $srcs += ,@('gameday', ([IO.File]::ReadAllText($gf.FullName) | ConvertFrom-Json)) }
foreach($src in $srcs){ $set = $src[0]; $C = $src[1]
  $bets = @(@($C.picks) + $(if($set -eq 'gameday'){ @($C.alts) } else { @() }) | Where-Object { $_ })
  foreach($b in $bets){
    $g = Grade $b; $res = $g[0]; $act = $g[1]; $u = $g[2]; Tally $set $res ([double]$b.stake) $u; $dnp = $g.Count -gt 3
    $bet = if($b.st -eq 'ATD'){ "$($b.player) anytime TD" } else { "$($b.player) $($b.side) $($b.line) $($LBL[$b.st])" }
    $new += [pscustomobject][ordered]@{ season=$Season; week=$Week; set=$set; game=$b.game; final=$finals[[string]$b.game]; bet=$bet; tier=$b.tier; book=$b.book; odds=[int]$b.odds; stake=[double]$b.stake; p=[math]::Round([double]$b.p,3); actual=$act; result=$res; units=$u }
    if($dnp){ $new[-1] | Add-Member note "Didn't play (no box score). Counted as a loss; a sportsbook would have refunded it." } }
  # a game-day parlay: every leg must win; a pushed or void leg drops out (its price with it); graded at the legs multiplied,
  # which is longer than the same-game price Fanatics would actually offer
  if($set -eq 'gameday' -and $C.parlay -and @($C.parlay.legs).Count){
    $rows = @(@($C.board) + @($C.picks) + @($C.alts) | Where-Object { $_ })
    $legs = @(foreach($l in $C.parlay.legs){ $m = $rows | Where-Object { $_.player -eq $l.player -and $_.st -eq $l.st -and $_.side -eq $l.side -and [double]$_.line -eq [double]$l.line } | Select-Object -First 1
      $g = Grade ([pscustomobject]@{ pid=$m.pid; game=$m.game; st=$l.st; side=$l.side; line=$l.line; stake=1; odds=$l.odds })
      [pscustomobject]@{ l=$l; game=$m.game; res=$g[0]; act=$(if($g.Count -gt 3){ 'DNP' } else { $g[1] }) } })
    $rs = @($legs | ForEach-Object { $_.res }); $won = @($legs | Where-Object { $_.res -eq 'WIN' })
    $res = if($rs -contains 'OPEN'){ 'OPEN' } elseif($rs -contains 'LOSS'){ 'LOSS' } elseif(-not $won.Count){ 'PUSH' } else { 'WIN' }
    $dec = 1.0; foreach($x in $won){ $dec *= (Dec $x.l.odds) }; $stk = [double]$(if($C.parlay.stake){ $C.parlay.stake } else { 0.25 })
    $u = switch($res){ 'WIN' { [math]::Round($stk * ($dec - 1), 2) } 'LOSS' { -$stk } default { 0.0 } }
    Tally $set $res $stk $u
    $new += [pscustomobject][ordered]@{ season=$Season; week=$Week; set=$set; game=$legs[0].game; final=$finals[[string]$legs[0].game]
      bet=("Parlay: " + (($legs | ForEach-Object { "$($_.l.player) $($_.l.side) $($_.l.line) $($LBL[$_.l.st])" }) -join " + ")); tier='parlay'; book='FAN'; odds=[int]$C.parlay.odds; stake=$stk
      p=[math]::Round([double]$C.parlay.p,3); actual=(($legs | ForEach-Object { if($_.act -ne $null){ $_.act } else { $_.res } }) -join " / "); result=$res; units=$u
      note="Graded at the legs multiplied; Fanatics' same-game price is usually shorter." } }
}
foreach($k in $sum.Keys){ $s = $sum[$k]; $s.staked = [math]::Round($s.staked,2); $s.units = [math]::Round($s.units,2)
  "{0,-7} week {1}: {2}-{3}{4}{5}, {6:+0.00;-0.00}u on {7}u staked{8}" -f $k,$Week,$s.w,$s.l,$(if($s.p){"-$($s.p)"}),$(if($s.v){", $($s.v) void"}),$s.units,$s.staked,$(if($s.open){", $($s.open) not final yet"}) }
$all = @($keep + $new)
# running totals: the live card (set "card", plus the older rows from before sets existed) and the shadow model separately
$tot = { param($rows) $w=@($rows | ? result -eq 'WIN').Count; $l=@($rows | ? result -eq 'LOSS').Count; $p=@($rows | ? result -eq 'PUSH').Count
  $st=($rows | ? { $_.result -in 'WIN','LOSS' } | Measure-Object stake -Sum).Sum; $un=($rows | Measure-Object units -Sum).Sum
  [ordered]@{ w=$w; l=$l; p=$p; staked=[math]::Round([double]$st,2); units=[math]::Round([double]$un,2) } }
$cardRows = @($all | ? { -not $_.set -or $_.set -eq 'card' }); $shRows = @($all | ? { $_.set -eq 'shadow' }); $gdRows = @($all | ? { $_.set -eq 'gameday' })
$out = [ordered]@{ note=$R.note; graded=(Get-Date).ToUniversalTime().ToString("o"); picks=$all; toDate=(& $tot $cardRows) }
if($shRows.Count){ $out.shadowToDate = (& $tot $shRows) }
if($gdRows.Count){ $out.gamedayToDate = (& $tot $gdRows) }
if($DryRun){ $new | Format-Table set,bet,odds,stake,actual,result,units -AutoSize | Out-String -Width 200; "dry run: results.json not written" }
else { [IO.File]::WriteAllText($rf, ($out | ConvertTo-Json -Depth 5), (New-Object Text.UTF8Encoding($false))) }
"to date (card): $($out.toDate.w)-$($out.toDate.l), $($out.toDate.units)u on $($out.toDate.staked)u staked"
if($out.shadowToDate){ "to date (shadow): $($out.shadowToDate.w)-$($out.shadowToDate.l), $($out.shadowToDate.units)u on $($out.shadowToDate.staked)u staked" }
if($out.gamedayToDate){ "to date (game day): $($out.gamedayToDate.w)-$($out.gamedayToDate.l), $($out.gamedayToDate.units)u on $($out.gamedayToDate.staked)u staked" }
"RESULT " + ($sum | ConvertTo-Json -Compress)
