param([string[]]$Dates, [string]$OutDir = "tracking\btc")
# Backtest copies of archived nights with the combo props (PR, PA, RA) added, for the Nov 5 combo-market test.
# FanDuel: the night's cached raw\fd_<eventId>_player-combos.json (the last pregame build's fetch).
# Fanatics: Action Network's feed for that date (book 2988), which still serves past nights' last pregame lines.
# Each night's existing props are left as they were. Writes <OutDir>\slate-<date>.json and finals-<date>.json.
$ErrorActionPreference = "Stop"
$root = Split-Path $PSScriptRoot -Parent; $trk = Join-Path $root "tracking"; $raw = Join-Path $root "raw"
$out = Join-Path $root $OutDir; New-Item -ItemType Directory -Force $out | Out-Null
$UA = @{"User-Agent"="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/130.0 Safari/537.36"}
$FDST = @{ 'Pts + Reb'='PR'; 'Pts + Ast'='PA'; 'Reb + Ast'='RA' }
$ANST = [ordered]@{ "core_bet_type_86_points_rebounds"="PR"; "core_bet_type_87_points_assists"="PA"; "core_bet_type_88_rebounds_assists"="RA" }
foreach($d in $Dates){
  $bt = Join-Path $trk ("bt" + $d.Substring(6,2))
  if($d -le "20261028" -and (Test-Path (Join-Path $bt "slate.json"))){ $sl = Join-Path $bt "slate.json"; $fn = Join-Path $bt "finals.json" }
  else { $sl = Join-Path $trk "slate-$d.json"; $fn = Join-Path $trk "finals-$d.json" }
  if(-not (Test-Path $sl) -or -not (Test-Path $fn)){ Write-Warning "$d : no archived slate/finals"; continue }
  $s = [IO.File]::ReadAllText($sl) | ConvertFrom-Json
  $anf = Join-Path $raw "an_combos_$d.json"
  if(-not (Test-Path $anf)){ $rq = Invoke-WebRequest -UseBasicParsing "https://api.actionnetwork.com/web/v2/scoreboard/nba/markets?bookIds=2988&customPickTypes=$($ANST.Keys -join ',')&date=$d" -Headers $UA -TimeoutSec 60
    [IO.File]::WriteAllText($anf, [Text.Encoding]::UTF8.GetString($rq.RawContentStream.ToArray())) }
  $an = [IO.File]::ReadAllText($anf) | ConvertFrom-Json
  $anName = @{}; foreach($p in $an.players){ $anName[[string]$p.id] = $p.full_name }
  $nfd = 0; $nfan = 0
  foreach($g in $s.games){
    $props = [Collections.ArrayList]@(@($g.props)); $have = @{}; foreach($p in $props){ $have["$($p.player)|$($p.stat)"] = 1 }
    $ff = Join-Path $raw "fd_$($g.fdId)_player-combos.json"
    if($g.fdId -and (Test-Path $ff)){ $j = [IO.File]::ReadAllText($ff) | ConvertFrom-Json
      foreach($m in $j.attachments.markets.PSObject.Properties.Value){
        if($m.marketName -match '^(.+?) - (Pts \+ Reb|Pts \+ Ast|Reb \+ Ast)$'){ $pn = $matches[1]; $st = $FDST[$matches[2]]
          $o = $m.runners | ? { $_.runnerName -match 'Over$' } | Select-Object -First 1; $u = $m.runners | ? { $_.runnerName -match 'Under$' } | Select-Object -First 1
          if($o -and $u -and -not $have["$pn|$st"]){ [void]$props.Add([pscustomobject][ordered]@{ player=$pn; stat=$st; line=$o.handicap; over=$o.winRunnerOdds.americanDisplayOdds.americanOdds; under=$u.winRunnerOdds.americanDisplayOdds.americanOdds; book='FD' }); $have["$pn|$st"]=1; $nfd++ } } } }
    $g.props = @($props)
    $fan = [Collections.ArrayList]@(@($g.fanProps | ? { $_ }))
    if($g.anId){ foreach($t in $ANST.Keys){
      $os = @($an.markets.'2988'.event.$t | ? { $_.event_id -eq $g.anId -and -not $_.is_alt_market -and $_.line_status -ne 'suspended' })
      foreach($grp in ($os | Group-Object player_id)){
        $o = $grp.Group | ? side -eq 'over' | Select-Object -First 1; $u = $grp.Group | ? side -eq 'under' | Select-Object -First 1; $pn = $anName[[string]$grp.Name]
        if($pn -and $o -and $u -and $o.value -eq $u.value){ [void]$fan.Add([pscustomobject][ordered]@{ player=$pn; stat=$ANST[$t]; line=$o.value; over=$o.odds; under=$u.odds; book='FAN' }); $nfan++ } } } }
    if($g.PSObject.Properties['fanProps']){ $g.fanProps = @($fan) } else { $g | Add-Member fanProps @($fan) }
  }
  [IO.File]::WriteAllText((Join-Path $out "slate-$d.json"), ($s | ConvertTo-Json -Depth 12 -Compress))
  Copy-Item $fn (Join-Path $out "finals-$d.json") -Force
  "$d : games $(@($s.games).Count), FD combos $nfd, FAN combos $nfan"
}
