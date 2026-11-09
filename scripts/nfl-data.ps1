param([switch]$Refetch, [int]$Season = 2026)
# NFL pilot: the model's data bundle, tracking\nfl\data.json, from nflverse (github.com/nflverse/nflverse-data releases):
#   games: schedule with the closing spread/total, scores, roof and wind (nfldata games.csv)
#   rows:  regular-season offensive player games 2024-<Season> (QB/RB/FB/WR/TE) with passing, rushing and receiving
#          volume and yards, joined to the offensive snap share (snap_counts, matched on name + team + week)
#   inj:   this season's latest injury report per player (status and week), for the upcoming card
# -Refetch re-downloads this season's files (stats, snaps, injuries, schedule); past seasons are fetched once.
$ErrorActionPreference = "Stop"
$root = Split-Path $PSScriptRoot -Parent; $raw = Join-Path $root "raw/nfl"; $out = Join-Path $root "tracking/nfl"
New-Item -ItemType Directory -Force $raw, $out | Out-Null
$UA = @{"User-Agent"="Mozilla/5.0"}; $base = "https://github.com/nflverse/nflverse-data/releases/download"
function Get-File($tag, $name, [bool]$cur){ $f = Join-Path $raw $name
  if(-not (Test-Path $f) -or ($cur -and $Refetch)){ Invoke-WebRequest -UseBasicParsing "$base/$tag/$name" -Headers $UA -OutFile $f -TimeoutSec 180 }; $f }
$seasons = ($Season-2)..$Season
$sched = Join-Path $raw "games.csv"
if(-not (Test-Path $sched) -or $Refetch){ Invoke-WebRequest -UseBasicParsing "https://raw.githubusercontent.com/nflverse/nfldata/master/data/games.csv" -Headers $UA -OutFile $sched -TimeoutSec 180 }
function Num($x){ if($x -eq $null -or $x -eq '' -or $x -eq 'NA'){ $null } else { [double]$x } }
$games = @(Import-Csv $sched | ? { [int]$_.season -ge $seasons[0] -and $_.game_type -eq 'REG' } | % {
  ,@($_.game_id, [int]$_.season, [int]$_.week, $_.gameday, $_.away_team, $_.home_team, (Num $_.spread_line), (Num $_.total_line), (Num $_.away_score), (Num $_.home_score), $_.roof, (Num $_.wind)) })
function Norm([string]$s){ ($s.Normalize([Text.NormalizationForm]::FormD) -replace '\p{Mn}','').ToLower() -replace "[.'\-,]"," " -replace '\b(jr|sr|ii|iii|iv|v)\b','' -replace '\s+',' ' | % { $_.Trim() } }
$rows = New-Object System.Collections.ArrayList
foreach($s in $seasons){
  $cur = ($s -eq $Season)
  $snap = @{}
  foreach($r in (Import-Csv (Get-File "snap_counts" "snap_counts_$s.csv" $cur))){ if($r.game_type -ne 'REG'){ continue }; $snap["$(Norm $r.player)|$($r.team)|$($r.week)"] = [double]$r.offense_pct }
  $nsnap = 0
  foreach($r in (Import-Csv (Get-File "stats_player" "stats_player_week_$s.csv" $cur))){
    if($r.season_type -ne 'REG' -or $r.position -notin 'QB','RB','FB','WR','TE'){ continue }
    $sp = $snap["$(Norm $r.player_display_name)|$($r.team)|$($r.week)"]; if($sp -ne $null){ $nsnap++ }
    [void]$rows.Add(@($r.player_id, $r.player_display_name, $r.position, [int]$r.season, [int]$r.week, $r.team, $r.opponent_team,
      [int](Num $r.attempts), [int](Num $r.completions), [int](Num $r.passing_yards), [int](Num $r.carries), [int](Num $r.rushing_yards),
      [int](Num $r.targets), [int](Num $r.receptions), [int](Num $r.receiving_yards), $sp)) }
  "$s : player games so far $($rows.Count), with snap share $nsnap"
}
$inj = @{}
foreach($r in (Import-Csv (Get-File "injuries" "injuries_$Season.csv" $true))){ if($r.game_type -ne 'REG'){ continue }
  $k = "$($r.full_name)|$($r.team)"; if(-not $inj[$k] -or [int]$inj[$k][1] -le [int]$r.week){ $inj[$k] = @($r.report_status, [int]$r.week, $r.report_primary_injury) } }
$obj = [ordered]@{ built=(Get-Date).ToUniversalTime().ToString("o"); season=$Season
  gameCols=@("id","season","week","date","away","home","spread","total","awayScore","homeScore","roof","wind"); games=$games
  rowCols=@("pid","name","pos","season","week","team","opp","att","cmp","pyds","car","ryds","tgt","rec","recyds","snap"); rows=$rows
  inj=$inj }
$of = Join-Path $out "data.json"; [IO.File]::WriteAllText($of, ($obj | ConvertTo-Json -Depth 5 -Compress))
"wrote $of $((Get-Item $of).Length) bytes: $($games.Count) games, $($rows.Count) player games, $($inj.Count) injury entries"
