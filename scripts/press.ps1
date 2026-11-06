param([string]$Date, [string]$Slate, [string]$SeasonStart = "20261020", [double]$HandlerA36 = 5.0, [int]$MinMin = 20, [double]$MaxA36 = 99, [string]$EvalFile = "press-eval.json", [switch]$Eval)
# Ball-handler pressure by defense (Nov 4: proxy for pick-and-roll blitz/hedge rates, which aren't public). For every game an
# opponent's handler (5+ assists per 36 in his other games this season) played 20+ minutes against a team, his assists and points
# are compared with his own per-minute rates from his other games times that night's minutes. Each team gets the sums
# (curPress: n, aAct, aExp, pAct, pExp); the page shrinks the ratios (G.pressK) and applies them to handlers facing that team.
# -MaxA36 caps the group instead (e.g. -HandlerA36 0 -MaxA36 2.5: low-assist forwards/bigs, Nov 5 Hachimura review).
# -Eval: for each night, builds the table from earlier games only and checks whether it predicted that night's handlers.
$ErrorActionPreference = "Stop"
$trk = Join-Path (Split-Path $PSScriptRoot -Parent) "tracking"
function Load-Rows([string]$from, [string]$to){
  # one row per player-game: team, name, opponent, date, minutes, assists, points
  $rows = New-Object System.Collections.ArrayList
  $day = [DateTime]::ParseExact($from,'yyyyMMdd',$null); $end = [DateTime]::ParseExact($to,'yyyyMMdd',$null)
  while($day -lt $end){ $d = $day.ToString('yyyyMMdd'); $f = Join-Path $trk "finals-$d.json"
    if(Test-Path $f){ $fin = Get-Content $f -Raw -Encoding UTF8 | ConvertFrom-Json
      foreach($g in @($fin.games | ? { $_.state -eq 'post' })){ foreach($t in $g.teams){ $opp = @($g.teams | ? { $_.abbr -ne $t.abbr })[0].abbr
        foreach($r in $t.players){ if($r.MIN -gt 0){ [void]$rows.Add([pscustomobject]@{ k="$($t.abbr)|$($r.name)"; opp=$opp; d=$d; min=[double]$r.MIN; ast=[double]$r.AST; pts=[double]$r.PTS }) } } } } }
    $day = $day.AddDays(1) }
  ,$rows }
function Press-Table($rows){
  # leave-one-out: a handler's expected line in each game comes from his other games
  $byP = @{}; foreach($r in $rows){ if(-not $byP[$r.k]){ $byP[$r.k] = New-Object System.Collections.ArrayList }; [void]$byP[$r.k].Add($r) }
  $tab = @{}
  foreach($k in $byP.Keys){ $gs = $byP[$k]; $tm = ($gs | Measure-Object min -Sum).Sum; $ta = ($gs | Measure-Object ast -Sum).Sum; $tp = ($gs | Measure-Object pts -Sum).Sum
    foreach($r in $gs){ if($r.min -lt $MinMin){ continue }; $om = $tm - $r.min; if($gs.Count -lt 3 -or $om -lt 40){ continue }
      $apm = ($ta - $r.ast)/$om; if($apm*36 -lt $HandlerA36 -or $apm*36 -gt $MaxA36){ continue }; $ppm = ($tp - $r.pts)/$om
      if(-not $tab[$r.opp]){ $tab[$r.opp] = @{ n=0; aAct=0.0; aExp=0.0; pAct=0.0; pExp=0.0 } }
      $x = $tab[$r.opp]; $x.n++; $x.aAct += $r.ast; $x.aExp += $apm*$r.min; $x.pAct += $r.pts; $x.pExp += $ppm*$r.min } }
  $tab }
if($Eval){
  # out of sample: table from games before night d; handlers' expected lines on night d from their games before d
  $all = Load-Rows $SeasonStart $Date; $out = @()
  $nights = @($all | % d | Sort-Object -Unique | ? { $_ -ge "20261024" })
  foreach($d in $nights){ $prior = @($all | ? { $_.d -lt $d }); $tab = Press-Table $prior
    $hist = @{}; foreach($r in $prior){ if(-not $hist[$r.k]){ $hist[$r.k]=@{ g=0; min=0.0; ast=0.0; pts=0.0 } }; $h=$hist[$r.k]; $h.g++; $h.min+=$r.min; $h.ast+=$r.ast; $h.pts+=$r.pts }
    foreach($r in @($all | ? { $_.d -eq $d -and $_.min -ge $MinMin })){ $h = $hist[$r.k]; if(-not $h -or $h.g -lt 2 -or $h.min -lt 40){ continue }
      $apm = $h.ast/$h.min; if($apm*36 -lt $HandlerA36 -or $apm*36 -gt $MaxA36){ continue }; $x = $tab[$r.opp]; if(-not $x){ continue }
      $out += [pscustomobject]@{ d=$d; k=$r.k; opp=$r.opp; n=$x.n; aAct=$r.ast; aExp=$apm*$r.min; pAct=$r.pts; pExp=$h.pts/$h.min*$r.min; tA=$x.aAct; tAE=$x.aExp; tP=$x.pAct; tPE=$x.pExp } } }
  $out | ConvertTo-Json -Depth 3 | Set-Content (Join-Path $trk $EvalFile) -Encoding UTF8
  "press-eval: $($out.Count) handler games over $($nights.Count) nights -> tracking\$EvalFile"; return }
$tab = Press-Table (Load-Rows $SeasonStart $Date)
$s = Get-Content $Slate -Raw -Encoding UTF8 | ConvertFrom-Json
foreach($ab in $s.teams.PSObject.Properties.Name){ $x = $tab[$ab]
  $cp = if($x){ [ordered]@{ n=$x.n; aAct=$x.aAct; aExp=[math]::Round($x.aExp,1); pAct=$x.pAct; pExp=[math]::Round($x.pExp,1) } } else { $null }
  $s.teams.$ab | Add-Member -NotePropertyName curPress -NotePropertyValue $cp -Force }
[IO.File]::WriteAllText($Slate, ($s | ConvertTo-Json -Depth 20 -Compress))
"press: handler games against $($tab.Count) defenses"
