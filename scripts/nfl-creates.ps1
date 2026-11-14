param([int]$Season = 2026)
# NFL "How he gets it" panel data (Nov 14), PAPER PILOT, CONTEXT ONLY: nothing here feeds the model, a projection or the card.
# Reads tracking/nfl/plays.json (scripts/nfl-pbp.ps1) and the cards in tracking/nfl (card, tonight, mnf), writes nfl/creates.json to tracking/nfl (local server) and docs/nfl (site):
# for every carded player, this season's role (targets, air yards, YAC, carries by box count, red zone), splits by blitz and pressure,
# his man vs zone split and the opponent's man rate from 2025 (nflverse hasn't published 2026 coverage), the opponent's defense
# against the league, and a week-by-week log of the bet's stat. Run it after a freeze (push-site.ps1 runs it when plays.json is here).
$ErrorActionPreference = "Stop"
$root = Split-Path $PSScriptRoot -Parent; $nfl = Join-Path $root "tracking/nfl"; $docs = Join-Path $root "docs/nfl"
$pf = Join-Path $nfl "plays.json"; if(-not (Test-Path $pf)){ "nfl-creates: no tracking/nfl/plays.json here (run scripts/nfl-pbp.ps1); skipped"; return }
$PL = [IO.File]::ReadAllText($pf) | ConvertFrom-Json
$CI = @{}; for($i=0; $i -lt $PL.cols.Count; $i++){ $CI[$PL.cols[$i]] = $i }
$cS=$CI.season; $cW=$CI.week; $cO=$CI.off; $cD=$CI.def; $cK=$CI.kind; $cP=$CI.passer; $cT=$CI.target; $cR=$CI.rusher; $cY=$CI.yds; $cC=$CI.cmp; $cTD=$CI.td; $cYL=$CI.yl; $cA=$CI.air; $cB=$CI.blitz; $cX=$CI.box; $cM=$CI.mz; $cPr=$CI.press
$idx = @{}; for($i=0; $i -lt $PL.ids.Count; $i++){ $idx[$PL.ids[$i]] = $i }
# the carded players (week card, game-day card, Monday card)
$picks = @(); foreach($f in 'card.json','tonight.json','mnf.json'){ $p = Join-Path $nfl $f; if(-not (Test-Path $p)){ $p = Join-Path $docs $f }; if(Test-Path $p){ $c = [IO.File]::ReadAllText($p) | ConvertFrom-Json; $picks += @($c.picks) + @($c.alts) | ? { $_ -and $_.pid } } }
$want = @{}; foreach($r in $picks){ $o = (($r.game -split ' @ ') | ? { $_ -ne $r.team } | Select-Object -First 1); $want[$r.pid] = @{ team=$r.team; opp=$o; pos=$r.pos; wk=[int]$r.w } }
$wk = ($want.Values | % { $_.wk } | Measure-Object -Maximum).Maximum
function D(){ @{ n=0; y=0.0 } }
$PX = @{}; foreach($id in $want.Keys){ if($idx.ContainsKey($id)){ $PX[$idx[$id]] = @{ id=$id; tgt=0; rec=0; ryd=0.0; airT=0.0; airN=0; yac=0.0; yacN=0; rz=0; deep=0; car=0; rush=0.0; r10=0; rzc=0; i5=0; td=0
  db=0; att=0; cmp=0; pyd=0.0; pair=0.0; pairN=0; bl=@{y=(D);n=(D)}; pr=@{y=(D);n=(D)}; box=@{lt7=(D);b7=(D);ge8=(D)}; mz=@{man=(D);zone=(D)}; wk=@{} } } }
$team = @{}; $def = @{}; $lg = @{ db=0; bl=0; pr=0; tgt=0; tyd=0.0; air=0.0; airN=0; cmp=0; yac=0.0; yacN=0; car=0; rush=0.0; ge8=0; mzN=0; man=0 }
function DefOf($t){ if(-not $def[$t]){ $def[$t] = @{ db=0; bl=0; pr=0; tgt=0; tyd=0.0; air=0.0; airN=0; cmp=0; yac=0.0; yacN=0; car=0; rush=0.0; ge8=0; mzN=0; man=0 } }; $def[$t] }
function WkOf($q, $w){ if(-not $q.wk["$w"]){ $q.wk["$w"] = @{ REC=0; REC_YDS=0.0; RUSH_YDS=0.0; RUSH_ATT=0; PASS_YDS=0.0; PASS_CMP=0; PASS_ATT=0; TD=0 } }; $q.wk["$w"] }
foreach($p in $PL.plays){ $s = $p[$cS]; $kind = $p[$cK]; $y = if($p[$cY] -ne $null){ [double]$p[$cY] } else { 0.0 }; $air = $p[$cA]
  if($s -eq 2025){ # man/zone only exists for 2025
    if($kind -eq 1 -and $p[$cM]){ $dd = DefOf "25|$($p[$cD])"; $dd.mzN++; if($p[$cM] -eq 1){ $dd.man++ }; $lg.mzN++; if($p[$cM] -eq 1){ $lg.man++ }
      $t = $p[$cT]; if($t -ge 0 -and $PX[$t]){ $b = $PX[$t].mz[$(if($p[$cM] -eq 1){'man'}else{'zone'})]; $b.n++; if($p[$cC]){ $b.y += $y } } }
    continue }
  if($s -ne $Season -or $p[$cW] -ge $wk){ continue }
  $dd = DefOf $p[$cD]; $tm = $p[$cO]; if(-not $team[$tm]){ $team[$tm] = @{ tgt=0; car=0 } }
  if($kind -eq 1){ $dd.db++; $lg.db++; if($p[$cB] -gt 0){ $dd.bl++; $lg.bl++ }; if($p[$cPr]){ $dd.pr++; $lg.pr++ }
    $t = $p[$cT]
    if($t -ge 0){ $team[$tm].tgt++; $dd.tgt++; $lg.tgt++; if($p[$cC]){ $dd.tyd += $y; $lg.tyd += $y; $dd.cmp++; $lg.cmp++ }
      if($air -ne $null){ $dd.air += $air; $dd.airN++; $lg.air += $air; $lg.airN++; if($p[$cC]){ $dd.yac += $y - $air; $dd.yacN++; $lg.yac += $y - $air; $lg.yacN++ } } }
    if($t -ge 0 -and $PX[$t]){ $q = $PX[$t]; $w = WkOf $q $p[$cW]; $q.tgt++; if($p[$cYL] -le 20){ $q.rz++ }; if($air -ne $null){ $q.airT += $air; $q.airN++; if($air -ge 20){ $q.deep++ } }
      if($p[$cC]){ $q.rec++; $q.ryd += $y; $w.REC++; $w.REC_YDS += $y; if($air -ne $null){ $q.yac += $y - $air; $q.yacN++ } }
      $b = $q.bl[$(if($p[$cB] -gt 0){'y'}else{'n'})]; $b.n++; if($p[$cC]){ $b.y += $y } }
    $qb = $p[$cP]
    if($qb -ge 0 -and $PX[$qb]){ $q = $PX[$qb]; $w = WkOf $q $p[$cW]; $q.db++
      if($t -ge 0){ $q.att++; $w.PASS_ATT++; if($p[$cC]){ $q.cmp++; $q.pyd += $y; $w.PASS_CMP++; $w.PASS_YDS += $y }; if($air -ne $null){ $q.pair += $air; $q.pairN++ } }
      $b = $q.bl[$(if($p[$cB] -gt 0){'y'}else{'n'})]; $b.n++; if($t -ge 0 -and $p[$cC]){ $b.y += $y }
      $b = $q.pr[$(if($p[$cPr]){'y'}else{'n'})]; $b.n++; if($t -ge 0 -and $p[$cC]){ $b.y += $y } } }
  elseif($kind -eq 2){ $dd.car++; $dd.rush += $y; $lg.car++; $lg.rush += $y; if($p[$cX] -ge 8){ $dd.ge8++; $lg.ge8++ }; $team[$tm].car++
    $rr = $p[$cR]; if($rr -ge 0 -and $PX[$rr]){ $q = $PX[$rr]; $w = WkOf $q $p[$cW]; $q.car++; $q.rush += $y; $w.RUSH_ATT++; $w.RUSH_YDS += $y; if($y -ge 10){ $q.r10++ }; if($p[$cYL] -le 20){ $q.rzc++ }; if($p[$cYL] -le 5){ $q.i5++ }
      if($p[$cX] -ge 0){ $bk = if($p[$cX] -le 6){'lt7'}elseif($p[$cX] -eq 7){'b7'}else{'ge8'}; $q.box[$bk].n++; $q.box[$bk].y += $y } } }
  $td = $p[$cTD]; if($td -ge 0 -and $PX[$td]){ $PX[$td].td++; (WkOf $PX[$td] $p[$cW]).TD++ } }
function Rt($a, $b, $d=1){ if($b){ [math]::Round($a/$b, $d) } else { $null } }
function Dsum($d){ [ordered]@{ db=$d.db; blitz=(Rt $d.bl $d.db 3); press=(Rt $d.pr $d.db 3); ydsTgt=(Rt $d.tyd $d.tgt 2); adot=(Rt $d.air $d.airN 1); yac=(Rt $d.yac $d.yacN 1); ypc=(Rt $d.rush $d.car 2); stack=(Rt $d.ge8 $d.car 3) } }
# official weekly box scores (tracking/nfl/data.json): totals and the week log come from these, because play-by-play counts only
# designed runs as carries (a QB's scrambles are dropbacks); play-by-play is kept for the splits
$off = @{}; $dj = Join-Path $nfl "data.json"
if(Test-Path $dj){ $DJ = [IO.File]::ReadAllText($dj) | ConvertFrom-Json; $rc = @{}; for($i=0; $i -lt $DJ.rowCols.Count; $i++){ $rc[$DJ.rowCols[$i]] = $i }
  foreach($row in $DJ.rows){ $id = $row[$rc.pid]; if(-not $want.ContainsKey($id) -or [int]$row[$rc.season] -ne $Season -or [int]$row[$rc.week] -ge $wk){ continue }
    if(-not $off[$id]){ $off[$id] = @() }; $off[$id] += ,$row } }
$out = [ordered]@{}
foreach($q in $PX.Values){ $m = $want[$q.id]; $tt = $team[$m.team]; $d25 = $def["25|$($m.opp)"]
  $weeks = @($q.wk.Keys | Sort-Object { [int]$_ } | % { $w = $q.wk[$_]; [ordered]@{ w=[int]$_; REC=$w.REC; REC_YDS=$w.REC_YDS; RUSH_YDS=$w.RUSH_YDS; RUSH_ATT=$w.RUSH_ATT; PASS_YDS=$w.PASS_YDS; PASS_CMP=$w.PASS_CMP; PASS_ATT=$w.PASS_ATT; RR_YDS=$w.REC_YDS+$w.RUSH_YDS; TD=$w.TD } })
  $pbTgt = $q.tgt; $pbCar = $q.car; $rows = @($off[$q.id] | ? { $_ } | Sort-Object { [int]$_[$rc.week] })
  if($rows.Count){ $weeks = @($rows | % { $x = $_; [ordered]@{ w=[int]$x[$rc.week]; REC=[int]$x[$rc.rec]; REC_YDS=[double]$x[$rc.recyds]; RUSH_YDS=[double]$x[$rc.ryds]; RUSH_ATT=[int]$x[$rc.car]
      PASS_YDS=[double]$x[$rc.pyds]; PASS_CMP=[int]$x[$rc.cmp]; PASS_ATT=[int]$x[$rc.att]; RR_YDS=[double]$x[$rc.recyds]+[double]$x[$rc.ryds]; TD=[int]$x[$rc.rtd]+[int]$x[$rc.rectd] } })
    $sum = { param($c) ($rows | % { [double]$_[$rc[$c]] } | Measure-Object -Sum).Sum }
    $q.tgt = [int](& $sum 'tgt'); $q.rec = [int](& $sum 'rec'); $q.ryd = & $sum 'recyds'; $q.car = [int](& $sum 'car'); $q.rush = & $sum 'ryds'
    $q.att = [int](& $sum 'att'); $q.cmp = [int](& $sum 'cmp'); $q.pyd = & $sum 'pyds'; $q.td = [int]((& $sum 'rtd') + (& $sum 'rectd')) }
  $out[$q.id] = [ordered]@{ team=$m.team; opp=$m.opp; pos=$m.pos; games=$weeks.Count
    rec=[ordered]@{ tgt=$q.tgt; rec=$q.rec; yds=$q.ryd; share=$(if($tt){ Rt $pbTgt $tt.tgt 3 } else { $null }); adot=(Rt $q.airT $q.airN 1); yac=(Rt $q.yac $q.yacN 1); rz=$q.rz; deep=$q.deep
      blitz=[ordered]@{ y=@($q.bl.y.n, (Rt $q.bl.y.y $q.bl.y.n 2)); n=@($q.bl.n.n, (Rt $q.bl.n.y $q.bl.n.n 2)) } }
    rush=[ordered]@{ car=$q.car; yds=$q.rush; share=$(if($tt){ Rt $pbCar $tt.car 3 } else { $null }); designed=$pbCar; r10=$q.r10; rz=$q.rzc; i5=$q.i5
      box=[ordered]@{ lt7=@($q.box.lt7.n, (Rt $q.box.lt7.y $q.box.lt7.n 2)); b7=@($q.box.b7.n, (Rt $q.box.b7.y $q.box.b7.n 2)); ge8=@($q.box.ge8.n, (Rt $q.box.ge8.y $q.box.ge8.n 2)) } }
    pass=[ordered]@{ db=$q.db; att=$q.att; cmp=$q.cmp; yds=$q.pyd; adot=(Rt $q.pair $q.pairN 1)
      blitz=[ordered]@{ y=@($q.bl.y.n, (Rt $q.bl.y.y $q.bl.y.n 2)); n=@($q.bl.n.n, (Rt $q.bl.n.y $q.bl.n.n 2)) }; press=[ordered]@{ y=@($q.pr.y.n, (Rt $q.pr.y.y $q.pr.y.n 2)); n=@($q.pr.n.n, (Rt $q.pr.n.y $q.pr.n.n 2)) } }
    td=$q.td
    mz25=[ordered]@{ man=@($q.mz.man.n, (Rt $q.mz.man.y $q.mz.man.n 2)); zone=@($q.mz.zone.n, (Rt $q.mz.zone.y $q.mz.zone.n 2)) }
    oppMan25=$(if($d25){ Rt $d25.man $d25.mzN 3 } else { $null })
    weeks=$weeks } }
$defOut = [ordered]@{}; foreach($t in ($def.Keys | ? { $_ -notlike '25|*' } | Sort-Object)){ $defOut[$t] = Dsum $def[$t] }
$doc = [ordered]@{ season=$Season; throughWeek=$wk-1; built=(Get-Date).ToUniversalTime().ToString("o"); league=(Dsum $lg); leagueMan25=(Rt $lg.man $lg.mzN 3); def=$defOut; players=$out }
$js = ConvertTo-Json $doc -Depth 8 -Compress; $of = Join-Path $docs "creates.json"; foreach($o in @((Join-Path $nfl "creates.json"), $of)){ [IO.File]::WriteAllText($o, $js, (New-Object Text.UTF8Encoding $false)) }
"nfl-creates: $($out.Count) carded players through week $($wk-1), $([math]::Round((Get-Item $of).Length/1KB))KB"
