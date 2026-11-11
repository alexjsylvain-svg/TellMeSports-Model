# Checks every prop on tonight's frozen card (docs\picks.json: card and alternatives) against a fresh pull of
# Fanatics' main lines from the Action Network feed (book 2988), and flags any line or price that moved.
#   .\scripts\card-check.ps1 [-Date 20261111] [-Picks docs\picks.json]
param([string]$Date = "", [string]$Picks = "docs\picks.json")
$root = Split-Path $PSScriptRoot
$pk = Get-Content (Join-Path $root $Picks) -Raw -Encoding UTF8 | ConvertFrom-Json
if(-not $Date){ $Date = $pk.date }
$TYPE = @{ PTS="core_bet_type_27_points"; REB="core_bet_type_23_rebounds"; AST="core_bet_type_26_assists"; "3PM"="core_bet_type_21_3fgm"
           PRA="core_bet_type_85_points_rebounds_assists"; PR="core_bet_type_86_points_rebounds"; PA="core_bet_type_87_points_assists"; RA="core_bet_type_88_rebounds_assists" }
$bets = @($pk.bets | Where-Object { $_.mkt -eq 'Prop' -and $_.set -in @('recommended','alt') -and $TYPE.ContainsKey([string]$_.stat) })
$feed = @{}
foreach($t in @($bets | ForEach-Object { $TYPE[[string]$_.stat] } | Sort-Object -Unique)){
  $url = "https://api.actionnetwork.com/web/v2/scoreboard/nba/markets?bookIds=2988&customPickTypes=$t&date=$Date"
  try { $feed[$t] = Invoke-RestMethod $url -Headers @{ "User-Agent" = "Mozilla/5.0" } -TimeoutSec 30 } catch { Write-Host "fetch failed for ${t}: $_" }
}
$pulled = Get-Date
$bad = 0
"Fanatics main lines pulled {0:h:mm tt} ET; card frozen {1}" -f $pulled, $pk.frozenAt
""
"{0,-5} {1,-40} {2,-4} {3,6} {4,6}   {5}" -f "set","bet","book","price","line","Fanatics now"
foreach($b in $bets){
  $t = $TYPE[[string]$b.stat]; $j = $feed[$t]; $now = "not posted"; $flag = ""
  if($j){
    $pl = @($j.players | Where-Object { $_.full_name -eq $b.player }) | Select-Object -First 1
    $rows = if($pl){ @($j.markets.'2988'.event.$t | Where-Object { $_.player_id -eq $pl.id -and -not $_.is_alt_market -and $_.line_status -ne 'suspended' }) } else { @() }
    $o = $rows | Where-Object side -eq 'over' | Select-Object -First 1; $u = $rows | Where-Object side -eq 'under' | Select-Object -First 1
    if($o -and $u){
      $mine = if($b.side -eq 'Over'){ $o } else { $u }
      $now = "{0} {1}: o{2} / u{3}" -f $b.stat, $o.value, $o.odds, $u.odds
      if($b.book -eq 'FAN'){
        if([double]$mine.value -ne [double]$b.line){ $flag = "  << LINE MOVED to $($mine.value)"; $bad++ }
        elseif([int]$mine.odds -ne [int]$b.odds){ $flag = "  << price now $($mine.odds)"; $bad++ }
        else { $flag = "  ok" }
      } else { $flag = "  (card priced at $($b.book); Fanatics has it)" }
    } elseif($b.book -eq 'FAN'){ $flag = "  << NOT POSTED at Fanatics now"; $bad++ }
  }
  $set = if($b.set -eq 'alt'){ 'alt' } else { 'card' }
  "{0,-5} {1,-40} {2,-4} {3,6} {4,6}   {5}{6}" -f $set, $b.bet, $b.book, $b.odds, $b.line, $now, $flag
}
""
if($bad){ "$bad pick(s) no longer match Fanatics." } else { "Every Fanatics-priced pick matches Fanatics' current main line and price." }
