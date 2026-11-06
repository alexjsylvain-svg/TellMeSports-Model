param([string]$Date = "20261021", [switch]$DryRunLive)
# -DryRunLive grades in-progress games as if they ended now and writes nothing (for testing only).
# Grades a night's frozen picks (tracking\picks-<date>.json) against ESPN final scores and box scores.
# Writes tracking\results-<date>.json, updates the running record in tracking\ledger.json,
# and copies the night's results (with the season-to-date record) to site\results.json for the page.
$ErrorActionPreference = "Stop"
. "$PSScriptRoot/lib.ps1"
$root = Split-Path $PSScriptRoot -Parent
$trk = Join-Path $root "tracking"
$picks = Get-Content (Join-Path $trk "picks-$Date.json") -Raw -Encoding UTF8 | ConvertFrom-Json

# ---- finals ----
$sb = Get-Json "https://site.api.espn.com/apis/site/v2/sports/basketball/nba/scoreboard?dates=$Date"
$GAMES = @{}
foreach($e in $sb.events){
  $c = $e.competitions[0]; $h = $c.competitors | ? { $_.homeAway -eq 'home' }; $a = $c.competitors | ? { $_.homeAway -eq 'away' }
  $g = [ordered]@{ gid=$e.id; state=$c.status.type.state; detail=$c.status.type.shortDetail; away=$a.team.abbreviation; home=$h.team.abbreviation; as=[int]$a.score; hs=[int]$h.score; players=@{} }
  if($DryRunLive -and $g.state -eq 'in'){ $g.state = 'post' }
  if($g.state -eq 'post'){
    $s = Get-Json "https://site.api.espn.com/apis/site/v2/sports/basketball/nba/summary?event=$($e.id)"
    foreach($tp in $s.boxscore.players){ $labels = $tp.statistics[0].labels
      foreach($ath in $tp.statistics[0].athletes){
        $row = @{ dnp=[bool]$ath.didNotPlay; name=$ath.athlete.displayName }
        for($k=0; $k -lt $labels.Count -and $k -lt $ath.stats.Count; $k++){ $v=$ath.stats[$k]
          if($v -match '^(\d+)-(\d+)$'){ $row[$labels[$k]+'M']=[int]$matches[1] } elseif($v -match '^[+-]?\d+$'){ $row[$labels[$k]]=[int]$v } }
        $g.players[(Norm-Name $ath.athlete.displayName)] = $row } } }
  $GAMES[$e.id] = $g
}
function StatOf($row, $stat){
  switch($stat){ 'DD'{ return @($row.PTS,$row.REB,$row.AST,$row.STL,$row.BLK | ? { [int]$_ -ge 10 }).Count } 'PTS'{ return $row.PTS } 'REB'{ return $row.REB } 'AST'{ return $row.AST } '3PM'{ return $row['3PTM'] } 'PRA'{ return ($row.PTS + $row.REB + $row.AST) } 'PR'{ return ($row.PTS + $row.REB) } 'PA'{ return ($row.PTS + $row.AST) } 'RA'{ return ($row.REB + $row.AST) } }
}
function Profit($odds){ if($odds -gt 0){ return $odds/100 } return 100/[math]::Abs($odds) }
function FindRow($g, $name){
  $k = Norm-Name $name; if($g.players.ContainsKey($k)){ return $g.players[$k] }
  $last = ($k -split ' ')[-1]; $first = $k.Substring(0,1)
  foreach($key in $g.players.Keys){ $p = $key -split ' '; if($p[-1] -eq $last -and $key.Substring(0,1) -eq $first){ return $g.players[$key] } }
  return $null
}

# ---- grade bets ----
$graded = @()
foreach($b in $picks.bets){
  $g = $GAMES[$b.gid]; $res = "PENDING"; $actual = $null
  if($g -and $g.state -eq 'post'){
    $m = $g.hs - $g.as; $t = $g.hs + $g.as; $x = $null
    switch($b.mkt){
      'Spread'   { $x = if($b.side -eq 'H'){ $m + $b.hl } else { -($m + $b.hl) }; $actual = "$($g.away) $($g.as) - $($g.hs) $($g.home)" }
      'Moneyline'{ $x = if($b.side -eq 'H'){ $m } else { -$m }; $actual = "$($g.away) $($g.as) - $($g.hs) $($g.home)" }
      'Total'    { $x = if($b.side -eq 'O'){ $t - $b.tl } else { $b.tl - $t }; $actual = "total $t" }
      default {
        $row = FindRow $g $b.player
        if(-not $row -or $row.dnp -or -not $row.MIN){ $res = "VOID"; $actual = "did not play" }
        else { $v = StatOf $row $b.stat; $actual = "$v $($b.stat)"
          if($b.mkt -eq 'Milestone'){ $x = if($v -ge $b.thr){ 1 } else { -1 } }
          else { $x = if($b.side -eq 'Over'){ $v - $b.line } else { $b.line - $v } } } }
    }
    if($x -ne $null){ $res = if($x -gt 0){ "WIN" } elseif($x -lt 0){ "LOSS" } else { "PUSH" } }
  }
  $units = switch($res){ "WIN" { [math]::Round((Profit $b.odds),3) } "LOSS" { -1 } default { 0 } }
  # picks frozen from Oct 27 on carry a stake (units by win chance); the flat 1-unit record above stays for comparison
  $stake = if($b.PSObject.Properties['stake'] -and $b.stake -ne $null){ [double]$b.stake } else { $null }
  $staked = if($stake -ne $null){ [math]::Round($units*$stake,3) } else { $null }
  $graded += [ordered]@{ set=$b.set; game=$b.game; gid=$b.gid; mkt=$b.mkt; bet=$b.bet; book=$b.book; odds=$b.odds; pBlend=$b.pBlend; result=$res; actual=$actual; units=$units; stake=$stake; staked=$staked }
}

# ---- grade game calls ----
$calls = @()
foreach($c in $picks.calls){
  $g = $GAMES[$c.gid]; $row = [ordered]@{ gid=$c.gid; game="$($c.away) @ $($c.home)"; final=$null; winnerPick=$c.winner; winnerProb=$c.winProb; winner="PENDING";
    ats="$(if($c.atsPick -eq 'H'){ "$($c.home) $($c.spread)" } else { "$($c.away) $(if(-$c.spread -gt 0){'+'})$(-$c.spread)" })"; atsProb=$c.atsProb; atsResult="PENDING";
    totalCall="$(if($c.totalPick -eq 'O'){'Over'}else{'Under'}) $($c.total)"; totalProb=$c.totalProb; totalResult="PENDING"; fairSpread=$c.fairSpread; fairTotal=$c.fairTotal }
  if($g -and $g.state -eq 'post'){
    $m = $g.hs - $g.as; $t = $g.hs + $g.as; $row.final = "$($g.away) $($g.as) - $($g.hs) $($g.home)"
    $actualWinner = if($m -gt 0){ $g.home } else { $g.away }
    $row.winner = if($actualWinner -eq $c.winner){ "WIN" } else { "LOSS" }
    $xa = if($c.atsPick -eq 'H'){ $m + $c.spread } else { -($m + $c.spread) }
    $row.atsResult = if($xa -gt 0){ "WIN" } elseif($xa -lt 0){ "LOSS" } else { "PUSH" }
    $xt = if($c.totalPick -eq 'O'){ $t - $c.total } else { $c.total - $t }
    $row.totalResult = if($xt -gt 0){ "WIN" } elseif($xt -lt 0){ "LOSS" } else { "PUSH" }
    $row.marginError = [math]::Round($m - (-$c.fairSpread),1); $row.totalError = [math]::Round($t - $c.fairTotal,1) }
  $calls += $row
}

function Summ($rows, $field){
  $w=@($rows | ? { $_[$field] -eq 'WIN' }).Count; $l=@($rows | ? { $_[$field] -eq 'LOSS' }).Count; $p=@($rows | ? { $_[$field] -eq 'PUSH' }).Count
  $v=@($rows | ? { $_[$field] -eq 'VOID' }).Count; $pd=@($rows | ? { $_[$field] -eq 'PENDING' }).Count
  return [ordered]@{ w=$w; l=$l; p=$p; void=$v; pending=$pd }
}
$sets = [ordered]@{}
foreach($name in 'recommended','page','board'){
  $rows = @($graded | ? { $_.set -eq $name }); $s = Summ $rows 'result'
  $risked = $s.w + $s.l; $units = 0.0; foreach($r in $rows){ $units += $r.units }; $units = [math]::Round($units,2)
  $s['units'] = $units; $s['roi'] = if($risked){ [math]::Round($units/$risked,3) } else { $null }
  $sr = @($rows | ? { $_.stake -ne $null -and $_.result -in 'WIN','LOSS' })
  if($sr.Count){ $st=0.0; $rk=0.0; foreach($r in $sr){ $st += $r.staked; $rk += $r.stake }; $s['staked'] = [math]::Round($st,2); $s['risked'] = [math]::Round($rk,2) }
  $sets[$name] = $s }
$callSum = [ordered]@{ winners=(Summ $calls 'winner'); ats=(Summ $calls 'atsResult'); totals=(Summ $calls 'totalResult') }
$finals = @($GAMES.Values | ? { $_.state -eq 'post' }).Count

$night = [ordered]@{ date=$Date; gradedAt=(Get-Date).ToUniversalTime().ToString("o"); gamesFinal=$finals; gamesTotal=$GAMES.Count; sets=$sets; calls=$callSum; bets=$graded; gameCalls=$calls }
if($DryRunLive){
  "DRY RUN (in-progress games graded as if final; nothing written)"
  $graded | ? { $_.result -ne 'PENDING' } | % { "{0,-11} {1,-42} {2,-5} {3}" -f $_.set, $_.bet, $_.result, $_.actual }
  $calls | ? { $_.final } | % { "{0} {1}: winner {2} {3} | ATS {4} {5} | {6} {7}" -f $_.game, $_.final, $_.winnerPick, $_.winner, $_.ats, $_.atsResult, $_.totalCall, $_.totalResult }
  return }
[IO.File]::WriteAllText((Join-Path $trk "results-$Date.json"), ($night | ConvertTo-Json -Depth 8))

# ---- running record across nights ----
$ledPath = Join-Path $trk "ledger.json"
$ledger = if(Test-Path $ledPath){ Get-Content $ledPath -Raw | ConvertFrom-Json } else { [pscustomobject]@{ nights=@() } }
$nights = @($ledger.nights | ? { $_.date -ne $Date }) + [pscustomobject]@{ date=$Date; gamesFinal=$finals; sets=$sets; calls=$callSum }
$tot = [ordered]@{}
foreach($name in 'recommended','page','board'){ $w=0;$l=0;$p=0;$u=0.0;$st=0.0;$rk=0.0;$hasSt=$false; foreach($n in $nights){ $s=$n.sets.$name; if($s){ $w+=$s.w; $l+=$s.l; $p+=$s.p; $u+=$s.units
      if($s.PSObject.Properties['staked'] -or ($s -is [System.Collections.IDictionary] -and $s.Contains('staked'))){ $st+=$s.staked; $rk+=$s.risked; $hasSt=$true } } }
  $tot[$name] = [ordered]@{ w=$w; l=$l; p=$p; units=[math]::Round($u,2); roi=$(if($w+$l){ [math]::Round($u/($w+$l),3) } else { $null }) }
  if($hasSt){ $tot[$name]['staked'] = [math]::Round($st,2); $tot[$name]['risked'] = [math]::Round($rk,2) } }
foreach($k in 'winners','ats','totals'){ $w=0;$l=0;$p=0; foreach($n in $nights){ $s=$n.calls.$k; if($s){ $w+=$s.w; $l+=$s.l; $p+=$s.p } }; $tot[$k] = [ordered]@{ w=$w; l=$l; p=$p } }
$ledgerOut = [ordered]@{ updated=(Get-Date).ToUniversalTime().ToString("o"); nights=$nights; toDate=$tot }
[IO.File]::WriteAllText($ledPath, ($ledgerOut | ConvertTo-Json -Depth 8))
$night['toDate'] = $tot
[IO.File]::WriteAllText((Join-Path $root "site/results.json"), ($night | ConvertTo-Json -Depth 8 -Compress))

# ---- summary ----
"Games final: $finals / $($GAMES.Count)"
foreach($name in $sets.Keys){ $s=$sets[$name]; "{0,-12} {1}-{2}-{3}  void {4}  pending {5}  units {6:+0.00;-0.00}  ROI {7}{8}" -f $name, $s.w, $s.l, $s.p, $s.void, $s.pending, $s.units, $(if($s.roi -ne $null){ "{0:P1}" -f $s.roi } else { "-" }), $(if($s.Contains('staked')){ "  staked {0:+0.00;-0.00}u of {1}u" -f $s.staked, $s.risked } else { "" }) }
"Winners {0}-{1}  ATS {2}-{3}-{4}  Totals {5}-{6}-{7}" -f $callSum.winners.w, $callSum.winners.l, $callSum.ats.w, $callSum.ats.l, $callSum.ats.p, $callSum.totals.w, $callSum.totals.l, $callSum.totals.p
