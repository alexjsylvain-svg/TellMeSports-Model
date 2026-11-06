param([string]$Date, [string]$Slate, [string]$SeasonStart = "20261020")
# This season's box scores so far ("the openers"), attached to each slate player as "cur": games, starts, minutes and
# production per game, from every game played before $Date. Rotations and roles change from last season (new teams,
# rookies, promotions), so the page blends these into minutes and per-minute rates.
# Final box scores are cached as tracking\finals-<date>.json (fetched with live.ps1 when missing).
$ErrorActionPreference = "Stop"
$root = Split-Path $PSScriptRoot -Parent
$trk = Join-Path $root "tracking"
$day = [DateTime]::ParseExact($SeasonStart,'yyyyMMdd',$null); $end = [DateTime]::ParseExact($Date,'yyyyMMdd',$null)
$agg = @{}
# team defense this season: what each team's opponents did against it (points, possessions, turnovers, free throws, threes)
$def = @{}
# team passing this season: assists and made field goals, so the page can aim each team's share of assisted baskets at its real one
$off = @{}
while($day -lt $end){
  $d = $day.ToString('yyyyMMdd'); $f = Join-Path $trk "finals-$d.json"
  if(-not (Test-Path $f)){ & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "live.ps1") -Date $d -Out "tracking\finals-$d.json" | Out-Null }
  if(Test-Path $f){
    $fin = Get-Content $f -Raw -Encoding UTF8 | ConvertFrom-Json
    foreach($g in @($fin.games | ? { $_.state -eq 'post' })){
      $tot = @($g.teams | % { $o=@{ ab=$_.abbr; pts=0.0; fga=0.0; fta=0.0; oreb=0.0; tov=0.0; fg3a=0.0; fgm=0.0; ast=0.0 }
        foreach($r in $_.players){ if($r.MIN -gt 0){ $o.pts+=$r.PTS; $o.fga+=$r.FGA; $o.fta+=$r.FTA; $o.oreb+=$r.OREB; $o.tov+=$r.TO; $o.fg3a+=$r.'3PTA'; $o.fgm+=$r.FGM; $o.ast+=$r.AST } }; $o })
      foreach($x in $tot){ if(-not $off[$x.ab]){ $off[$x.ab] = @{ g=0; ast=0.0; fgm=0.0 } }; $off[$x.ab].g++; $off[$x.ab].ast+=$x.ast; $off[$x.ab].fgm+=$x.fgm }
      if($tot.Count -eq 2){ $poss = (($tot | % { $_.fga + 0.44*$_.fta - $_.oreb + $_.tov }) | Measure-Object -Average).Average
        for($k=0; $k -lt 2; $k++){ $me=$tot[$k].ab; $op=$tot[1-$k]
          if(-not $def[$me]){ $def[$me] = @{ g=0; poss=0.0; pts=0.0; tov=0.0; fga=0.0; fta=0.0; fg3a=0.0 } }
          $x=$def[$me]; $x.g++; $x.poss+=$poss; $x.pts+=$op.pts; $x.tov+=$op.tov; $x.fga+=$op.fga; $x.fta+=$op.fta; $x.fg3a+=$op.fg3a } }
      foreach($t in $g.teams){ $opp = @($g.teams | ? { $_.abbr -ne $t.abbr })[0].abbr; foreach($r in $t.players){
        if(-not ($r.MIN -gt 0)){ continue }
        $k = "$($t.abbr)|$($r.name)"
        if(-not $agg[$k]){ $agg[$k] = @{ g=0; gs=0; min=0.0; pts=0.0; reb=0.0; ast=0.0; fg3=0.0; fga=0.0; fta=0.0; tov=0.0; last=$null; log=@() } }
        $a = $agg[$k]; $a.g++; if($r.starter){ $a.gs++ }; $a.min += $r.MIN; $a.pts += $r.PTS; $a.reb += $r.REB; $a.ast += $r.AST
        $a.fg3 += $r.'3PTM'; $a.fga += $r.FGA; $a.fta += $r.FTA; $a.tov += $r.TO; $a.last = $d
        # game log, so the page can show how often he has cleared tonight's line this season (and against tonight's opponent)
        $a.log += ,([ordered]@{ d=$d; opp=$opp; min=$r.MIN; pts=$r.PTS; reb=$r.REB; ast=$r.AST; fg3=$r.'3PTM'; pf=$r.PF }) } } } }
  $day = $day.AddDays(1)
}
$s = Get-Content $Slate -Raw -Encoding UTF8 | ConvertFrom-Json
$n = 0
foreach($ab in $s.teams.PSObject.Properties.Name){
  foreach($p in $s.teams.$ab.players){
    $a = $agg["$ab|$($p.name)"]
    $cur = if($a){ [ordered]@{ g=$a.g; gs=$a.gs; min=[math]::Round($a.min/$a.g,1); pts=[math]::Round($a.pts/$a.g,2); reb=[math]::Round($a.reb/$a.g,2); ast=[math]::Round($a.ast/$a.g,2); fg3=[math]::Round($a.fg3/$a.g,2); fga=[math]::Round($a.fga/$a.g,2); fta=[math]::Round($a.fta/$a.g,2); tov=[math]::Round($a.tov/$a.g,2); last=$a.last; log=@($a.log) } } else { $null }
    $p | Add-Member -NotePropertyName cur -NotePropertyValue $cur -Force; if($a){ $n++ } } }
# curDef per slate team and curLeague (every team this season), on the same scales as last season's rt: points allowed per 100
# possessions, opponent turnovers per 100 possessions, opponent FTA/FGA, opponent share of shots that are threes
$rate = { param($x) [ordered]@{ g=$x.g; drtg=[math]::Round(100*$x.pts/$x.poss,1); oppTov=[math]::Round(100*$x.tov/$x.poss,1); oppFtr=[math]::Round($x.fta/$x.fga,3); opp3=[math]::Round($x.fg3a/$x.fga,3) } }
if($def.Count){ $L=@{ g=0; poss=0.0; pts=0.0; tov=0.0; fga=0.0; fta=0.0; fg3a=0.0 }; foreach($x in $def.Values){ foreach($k in @($L.Keys)){ $L[$k]+=$x[$k] } }
  $s | Add-Member -NotePropertyName curLeague -NotePropertyValue (& $rate $L) -Force }
foreach($ab in $s.teams.PSObject.Properties.Name){ $cd = if($def[$ab]){ & $rate $def[$ab] } else { $null }; $s.teams.$ab | Add-Member -NotePropertyName curDef -NotePropertyValue $cd -Force
  $co = if($off[$ab] -and $off[$ab].fgm -gt 0){ $x=$off[$ab]; [ordered]@{ g=$x.g; ast=[math]::Round($x.ast/$x.g,1); fgm=[math]::Round($x.fgm/$x.g,1); astRate=[math]::Round($x.ast/$x.fgm,3) } } else { $null }
  $s.teams.$ab | Add-Member -NotePropertyName curOff -NotePropertyValue $co -Force }
$s | Add-Member -NotePropertyName curThrough -NotePropertyValue $end.AddDays(-1).ToString('yyyyMMdd') -Force
[IO.File]::WriteAllText($Slate, ($s | ConvertTo-Json -Depth 20 -Compress))
"season-to-date: $($agg.Count) player-teams from games before $Date; attached to $n slate players; team defense for $($def.Count) teams; team passing for $($off.Count)"
