param([string]$Out = "site/season.json")
# Every graded recommended pick this season in one file, for the phone view's record screen.
# Reads tracking\results-<date>.json (grade.ps1's output) and the running totals in tracking\ledger.json.
# Run it after each grade.ps1; publish the output as season.json.
$ErrorActionPreference = "Stop"
$root = Split-Path $PSScriptRoot -Parent; $trk = Join-Path $root "tracking"
$bets = New-Object Collections.ArrayList
# closing lines from clv.ps1 (run it first): cLine/cOdds = Fanatics' close for our side, clv = no-vig move toward us in points,
# cEv = expected profit at our price if the close is right, fav = line points the close moved in our favour
$cf = Join-Path $trk "clv.json"; $clv = if(Test-Path $cf){ [IO.File]::ReadAllText($cf) | ConvertFrom-Json } else { $null }
foreach($f in (Get-ChildItem $trk -Filter "results-*.json" | ? { $_.Name -match '^results-(\d{8})\.json$' } | Sort-Object Name)){
  if($f.Name -notmatch '^results-(\d{8})\.json$'){ continue }; $d = $matches[1]
  $j = [IO.File]::ReadAllText($f.FullName) | ConvertFrom-Json
  foreach($b in @($j.bets | ? { $_.set -eq 'recommended' })){
    $stat = $null; $side = $null
    $line = $null; if($b.bet -match ' (over|under) ([\d.]+) ([A-Z0-9]+)$'){ $side = $matches[1]; $line = [double]$matches[2]; $stat = $matches[3] }
    elseif($b.bet -match ' double-double$'){ $side = 'over'; $line = 1.5; $stat = 'DD' }  # priced as "categories with 10+" over 1.5
    $row = [ordered]@{ date=$d; game=$b.game; bet=$b.bet; stat=$stat; side=$side; line=$line; book=$b.book; odds=$b.odds;
      p=[math]::Round([double]$b.pBlend,4); stake=$b.stake; result=$b.result; actual=$b.actual; units=$b.units; staked=$b.staked }
    $c = if($clv){ $clv."$d|$($b.bet)" } else { $null }
    if($c){ $row.cLine = $c.cLine; $row.cOdds = $c.cOdds; $row.clv = $c.clv; $row.cEv = $c.cEv; $row.fav = $c.fav }
    [void]$bets.Add($row)
  }
}
$led = [IO.File]::ReadAllText((Join-Path $trk "ledger.json")) | ConvertFrom-Json
$doc = [ordered]@{ updated=(Get-Date).ToUniversalTime().ToString("o"); toDate=$led.toDate.recommended; bets=@($bets) }
[IO.File]::WriteAllText((Join-Path $root $Out), ($doc | ConvertTo-Json -Depth 6 -Compress))
"$($bets.Count) graded picks -> $Out"
# Final box lines for every player on every graded night, so the phone view can grade the bets you track yourself
# (any player, line and price): boxes.json = { "<date>": { "<name>": [MIN, PTS, REB, AST, 3PM, STL, BLK] } }, final games only.
$boxes = [ordered]@{}
foreach($f in (Get-ChildItem $trk -Filter "finals-*.json" | Sort-Object Name)){
  if($f.Name -notmatch '^finals-(\d{8})\.json$'){ continue }; $d = $matches[1]
  $j = [IO.File]::ReadAllText($f.FullName) | ConvertFrom-Json; $m = [ordered]@{}
  foreach($g in @($j.games | ? { $_.state -eq 'post' })){ foreach($t in $g.teams){ foreach($r in $t.players){
    if($r.dnp -or -not ($r.MIN -gt 0)){ $m[$r.name] = @(0,0,0,0,0,0,0); continue }
    $m[$r.name] = @([int]$r.MIN, [int]$r.PTS, [int]$r.REB, [int]$r.AST, [int]$r.'3PTM', [int]$r.STL, [int]$r.BLK) } } }
  if($m.Count){ $boxes[$d] = $m }
}
$bx = Join-Path (Split-Path (Join-Path $root $Out)) "boxes.json"
[IO.File]::WriteAllText($bx, ($boxes | ConvertTo-Json -Depth 4 -Compress))
"$($boxes.Count) nights of box scores -> $bx ($([math]::Round((Get-Item $bx).Length/1KB))KB)"
