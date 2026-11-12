param([int]$Season = 2026, [string]$Weeks = "", [switch]$Refetch)
# NFL pilot: player prop lines by week from Action Network's feed (book 2988 = Fanatics, 68 = DraftKings, 69 = FanDuel, 30 = opening line).
# For a past week the feed serves each prop's last pregame line, so a backtest bets at roughly the close.
# Raw responses cached in raw\nfl\an_<season>_w<NN>.json; writes tracking\nfl\lines-<season>-w<NN>.json:
#   { season, week, fetched, games:[{ anId, away, home, start, props:[{ player, stat, line, over, under, book }] }] }
$ErrorActionPreference = "Stop"
$root = Split-Path $PSScriptRoot -Parent; $raw = Join-Path $root "raw/nfl"; $out = Join-Path $root "tracking/nfl"
New-Item -ItemType Directory -Force $raw, $out | Out-Null
$UA = @{"User-Agent"="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/130.0 Safari/537.36"}
$TYPES = [ordered]@{ "core_bet_type_9_passing_yards"="PASS_YDS"; "core_bet_type_10_pass_completions"="PASS_CMP"; "core_bet_type_30_passing_attempts"="PASS_ATT";
  "core_bet_type_12_rushing_yards"="RUSH_YDS"; "core_bet_type_18_rushing_attempts"="RUSH_ATT"; "core_bet_type_16_receiving_yards"="REC_YDS"; "core_bet_type_15_receptions"="REC";
  "core_bet_type_66_rushing_receiving_yards"="RR_YDS"; "core_bet_type_62_anytime_touchdown_scorer"="ATD" }
# types the old combined files (an_<season>_w<NN>.json) hold; anything added later is fetched on its own
$OLD = @($TYPES.Keys)
$TYPES["core_bet_type_11_passing_tds"] = "PASS_TD"   # Nov 12, 2026
$BOOKS = [ordered]@{ "2988"="FAN"; "68"="DK"; "69"="FD"; "30"="OPEN" }
# Action Network team abbreviations that differ from nflverse's
$TEAM = @{ "LAR"="LA"; "JAC"="JAX"; "WSH"="WAS"; "LVR"="LV" }
$WK = if($Weeks){ @($Weeks -split "[, ]+" | ? { $_ } | % { if($_ -match "^(\d+)-(\d+)$"){ [int]$matches[1]..[int]$matches[2] } else { [int]$_ } }) } else { 1..18 }
foreach($w in $WK){
  # Since Nov 10, 2026 the feed answers 400 INVALID_DATA to several customPickTypes at once, so each prop type is its own request
  # (raw\nfl\an_<season>_w<NN>_<type>.json). An older combined file (an_<season>_w<NN>.json) is still read when there's no refetch.
  $rf = Join-Path $raw ("an_{0}_w{1:D2}.json" -f $Season,$w)
  $J = @{}   # type -> parsed response
  $one = if(-not $Refetch -and (Test-Path $rf)){ [IO.File]::ReadAllText($rf) | ConvertFrom-Json } else { $null }
  # a per-type file (newer) beats the old combined one; the combined one only fills old types that have no file of their own
  & { foreach($tp in $TYPES.Keys){ $rt = Join-Path $raw ("an_{0}_w{1:D2}_{2}.json" -f $Season,$w,$TYPES[$tp])
      if($one -and $OLD -contains $tp -and -not (Test-Path $rt)){ $J[$tp] = $one; continue }
      if($Refetch -or -not (Test-Path $rt)){
        $u = "https://api.actionnetwork.com/web/v2/scoreboard/nfl/markets?bookIds=$($BOOKS.Keys -join ',')&customPickTypes=$tp&week=$w&season=$Season&seasonType=reg"
        $rq = Invoke-WebRequest -UseBasicParsing $u -Headers $UA -TimeoutSec 90
        [IO.File]::WriteAllText($rt, [Text.Encoding]::UTF8.GetString($rq.RawContentStream.ToArray())); Start-Sleep -Milliseconds 800 }
      $J[$tp] = [IO.File]::ReadAllText($rt) | ConvertFrom-Json } }
  $nm = @{}; $gm = [ordered]@{}
  foreach($r in $J.Values){ foreach($p in $r.players){ $nm[[string]$p.id] = $p.full_name }; foreach($g in $r.games){ if(-not $gm.Contains([string]$g.id)){ $gm[[string]$g.id] = $g } } }
  $games = @()
  foreach($g in $gm.Values){
    $ht = $g.home_team; $at = $g.away_team
    $h = if($TEAM[$ht.abbr]){ $TEAM[$ht.abbr] } else { $ht.abbr }; $a = if($TEAM[$at.abbr]){ $TEAM[$at.abbr] } else { $at.abbr }
    $props = @()
    foreach($bk in $BOOKS.Keys){
      foreach($t in $TYPES.Keys){ $ev = $J[$t].markets.$bk.event; if(-not $ev){ continue }
        $os = @($ev.$t | ? { $_ -and $_.event_id -eq $g.id -and -not $_.is_alt_market })
        foreach($grp in ($os | Group-Object player_id)){
          $o = $grp.Group | ? side -eq 'over' | Select-Object -First 1; $un = $grp.Group | ? side -eq 'under' | Select-Object -First 1; $pn = $nm[[string]$grp.Name]
          if($pn -and $o -and $un -and $o.value -eq $un.value){ $props += [ordered]@{ player=$pn; stat=$TYPES[$t]; line=[double]$o.value; over=[int]$o.odds; under=[int]$un.odds; book=$BOOKS[$bk] } }
          # anytime TD: a Yes price only ("noside"), kept as an over 0.5 with no under
          elseif($pn -and $TYPES[$t] -eq "ATD"){ $y = $grp.Group | Select-Object -First 1; if($y.odds -ne $null){ $props += [ordered]@{ player=$pn; stat="ATD"; line=0.5; over=[int]$y.odds; under=$null; book=$BOOKS[$bk] } } } } } }
    $games += [ordered]@{ anId=$g.id; away=$a; home=$h; start=$g.start_time; props=$props }
  }
  $of = Join-Path $out ("lines-{0}-w{1:D2}.json" -f $Season,$w)
  [IO.File]::WriteAllText($of, ([ordered]@{ season=$Season; week=$w; fetched=(Get-Date).ToUniversalTime().ToString("o"); games=$games } | ConvertTo-Json -Depth 6 -Compress))
  $fan = @($games | % { $_.props } | ? { $_.book -eq 'FAN' }).Count
  "{0} week {1}: {2} games, {3} Fanatics props, {4} all books" -f $Season,$w,$games.Count,$fan,@($games | % { $_.props }).Count
}
