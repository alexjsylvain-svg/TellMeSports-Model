param([string]$Date = "20261021")
# Rebuilds tracking\picks-<date>.json from tracking\results-<date>.json (which keeps every graded bet's set, game, market,
# bet text, book and price) after the frozen file was overwritten by mistake on 2026-10-22.
$ErrorActionPreference = "Stop"
$root = Split-Path $PSScriptRoot -Parent
$trk = Join-Path $root "tracking"
$res = Get-Content (Join-Path $trk "results-$Date.json") -Raw -Encoding UTF8 | ConvertFrom-Json
$bets = @()
foreach($b in $res.bets){
  $parts = $b.game -split ' @ '; $aw = $parts[0]; $hm = $parts[1]
  $o = [ordered]@{ set=$b.set; gid=$b.gid; game=$b.game; mkt=$b.mkt; bet=$b.bet; book=$b.book; odds=$b.odds; side=$null; hl=$null; tl=$null; player=$null; stat=$null; line=$null; thr=$null; pSim=$null; pBlend=$b.pBlend; ev=$null }
  switch($b.mkt){
    'Spread'   { if($b.bet -match '^(\S+) ([+-]?[\d.]+)$'){ $n=[double]$matches[2]; if($matches[1] -eq $hm){ $o.side='H'; $o.hl=$n } else { $o.side='A'; $o.hl=-$n } } }
    'Moneyline'{ if($b.bet -match '^(\S+) ML$'){ $o.side = if($matches[1] -eq $hm){ 'H' } else { 'A' } } }
    'Total'    { if($b.bet -match '^(Over|Under) ([\d.]+)$'){ $o.side = if($matches[1] -eq 'Over'){ 'O' } else { 'U' }; $o.tl=[double]$matches[2] } }
    'Prop'     { if($b.bet -match '^(.+) (over|under) ([\d.]+) (PTS|REB|AST|3PM|PRA|PR|PA|RA)$'){ $o.player=$matches[1]; $o.side=(Get-Culture).TextInfo.ToTitleCase($matches[2]); $o.line=[double]$matches[3]; $o.stat=$matches[4] } }
    'Milestone'{ if($b.bet -match '^(.+) (\d+)\+ (PTS|REB|AST|3PM)$'){ $o.player=$matches[1]; $o.thr=[int]$matches[2]; $o.stat=$matches[3] } }
  }
  $bets += $o
}
$calls = @()
foreach($c in $res.gameCalls){
  $parts = $c.game -split ' @ '; $aw=$parts[0]; $hm=$parts[1]
  $atsPick = if($c.ats -like "$hm *"){ 'H' } else { 'A' }; $num = [double](($c.ats -split ' ')[-1])
  $spread = if($atsPick -eq 'H'){ $num } else { -$num }
  $calls += [ordered]@{ gid=$c.gid; away=$aw; home=$hm; lineBook="DK"; winner=$c.winnerPick; winProb=$c.winnerProb; atsPick=$atsPick; atsProb=$c.atsProb; spread=$spread; fairSpread=$c.fairSpread;
    totalPick=$(if($c.totalCall -like 'Over*'){'O'}else{'U'}); total=[double](($c.totalCall -split ' ')[-1]); totalProb=$c.totalProb; fairTotal=$c.fairTotal }
}
$doc = [ordered]@{ date=$Date; frozenAt="2026-10-21T23:5x (original); reconstructed 2026-10-22 from results-$Date.json"; stake="1 unit flat per bet";
  notes="Reconstructed after the original frozen file was overwritten by mistake on 2026-10-22. Every bet's set, game, market, text, book, price and blended probability come from the graded results written at 3 AM from the original file."; bets=$bets; calls=$calls }
[IO.File]::WriteAllText((Join-Path $trk "picks-$Date.json"), ($doc | ConvertTo-Json -Depth 6))
"restored $($bets.Count) bets, $($calls.Count) calls; unparsed: " + (($bets | ? { -not $_.side -and $_.mkt -ne 'Milestone' } | % bet) -join ' | ')
