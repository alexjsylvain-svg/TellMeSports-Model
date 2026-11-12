param([string]$Tag = "nov9", [string]$Trk = "tracking")
# Nov 11 card-level backtest of two fixes proposed after Zubac U25.5 PRA lost (projected 23 min, played 31):
#   A. injury-return flag: the player sat out a run of his team's games recently and has played only a few since, so his
#      this-season minutes include the injury exit / minutes-limit games. Variants: keep his unders off the card.
#   B. a lower sim weight for PRA (now .50), and a cap on how far the sim may sit above the market on PRA unders.
# Same card rebuild as algo-eval.ps1 (rule flag incl. no PRA overs; no questionable / role-mismatch / unproven players;
# -150..+150, 60%+, 5%+ edge; two a game, one per player; stakes 2/1.5/0.5u). Halves: A = Oct 21-29, B = Oct 30-Nov 8.
# Flag definitions were fixed before looking at results. Read-only: prints a report.
$root = Split-Path $PSScriptRoot -Parent; if(-not [IO.Path]::IsPathRooted($Trk)){ $Trk = Join-Path $root $Trk }
function cl($x){ [math]::Min(.99,[math]::Max(.01,$x)) }
function lgt($x){ $x=cl $x; [math]::Log($x/(1-$x)) }
function sg($x){ 1/(1+[math]::Exp(-$x)) }
function dec($o){ if($o -gt 0){ 1+$o/100 } else { 1+100/(-$o) } }
function stake($p){ if($p -ge .66){2} elseif($p -ge .64){1.5} else {.5} }
function Norm([string]$s){ ($s.Normalize([Text.NormalizationForm]::FormD) -replace '\p{Mn}','').ToLower() -replace "[.'\-,]"," " -replace '\b(jr|sr|ii|iii|iv)\b','' -replace '\s+',' ' | % { $_.Trim() } }
$SW0 = @{ PTS=.05; REB=0; AST=.65; "3PM"=.75; PRA=.50; PR=0; PA=.15; RA=.20; DD=.15 }

$rows = New-Object System.Collections.ArrayList
foreach($f in Get-ChildItem $Trk -Filter "px-*-$Tag.json" | Sort-Object Name){ foreach($r in (Get-Content $f.FullName -Raw | ConvertFrom-Json)){ if($r.k -eq "P" -and $r.u -ne $null){ [void]$rows.Add($r) } } }
$nights = @($rows | % d | Sort-Object -Unique); $mid = "20261029"

# ---- injury-return info per night and player, from that night's slate logs (games before tonight only)
# team game dates = every date any teammate logged; a "missed run" = consecutive team games he did not log, after his
# first logged game or from opening night. ret = { run length of his latest missed run, games he has played since it }
$ret = @{}
foreach($d in $nights){ $sf = @((Join-Path $Trk "btc\slate-$d.json"), (Join-Path $Trk "slate-$d.json")) | ? { Test-Path $_ } | Select-Object -First 1
  if(-not $sf){ continue }; $s = Get-Content $sf -Raw | ConvertFrom-Json
  foreach($tm in $s.teams.PSObject.Properties){
    $tdates = @($tm.Value.players | % { @($_.cur.log) } | ? { $_ -and $_.d -lt $d } | % d | Sort-Object -Unique)
    foreach($p in $tm.Value.players){
      $mine = @{}; foreach($g in @($p.cur.log)){ if($g -and $g.d -lt $d){ $mine[$g.d] = $true } }
      $run=0; $since=0; $lastRun=0; $sinceLast=0
      foreach($td in $tdates){ if($mine[$td]){ if($run -gt 0){ $lastRun=$run; $sinceLast=0; $run=0 }; $sinceLast++ } else { $run++ } }
      # $run > 0 at the end means he is still out (not playing tonight anyway)
      $ret["$d|$(Norm $p.name)"] = [pscustomobject]@{ run=$lastRun; since=$sinceLast; g=$mine.Count } } } }

$c = New-Object System.Collections.ArrayList
foreach($r in $rows){
  $ok = $r.rule -and -not ($r.stat -eq "PRA" -and $r.side -eq "Over") -and -not $r.why.mis -and -not $r.why.q -and -not (($r.why.prior -or $r.why.y24) -and $r.curG -lt 3)
  $rt = $ret["$($r.d)|$(Norm $r.player)"]
  [void]$c.Add([pscustomobject]@{ d=$r.d; half=$(if($r.d -le $mid){"A"}else{"B"}); gid=$r.gid; stat=$r.stat; side=$r.side; line=[double]$r.line; odds=[double]$r.odds
    pm=[double]$r.pm; pSim=[double]$r.pSim; push=[double]$r.push; bench=[bool]$r.bench; u=[double]$r.u; player=$r.player; ok=$ok
    run=$(if($rt){$rt.run}else{$null}); since=$(if($rt){$rt.since}else{$null}); p=0.0; ev=0.0 }) }
function price($sw){ foreach($x in $c){ $wt=[math]::Min(1.0,$sw[$x.stat]*$(if($x.bench){.8}else{1})); $p=(sg ((1-$wt)*(lgt $x.pm)+$wt*(lgt $x.pSim)))*(1-$x.push); $pl=[math]::Max(0.0,1-$p-$x.push); $x.p=$p; $x.ev=$p*((dec $x.odds)-1)-$pl } }
function card($filter){
  $all=@()
  foreach($grp in ($c | ? { $_.ok } | Group-Object d,gid)){
    $cand=@(); foreach($r in $grp.Group){ if((& $filter $r) -and $r.odds -ge -150 -and $r.odds -le 150 -and $r.p -ge .60 -and $r.ev -ge .05){ $cand += [pscustomobject]@{ r=$r; s=(stake $r.p) } } }
    $pk=@(); foreach($x in ($cand | Sort-Object @{e={$_.r.p};Descending=$true})){ if($pk.Count -ge 2){ continue }; if(@($pk|?{ $_.r.player -eq $x.r.player }).Count){ continue }; $pk += $x }
    $all += $pk }
  $all }
function line($name,$pk){ $pk=@($pk); $o=foreach($h in "all","A","B"){ $q=@($pk | ? { $h -eq "all" -or $_.r.half -eq $h }); $w=@($q|?{$_.r.u -gt 0}).Count; $l=@($q|?{$_.r.u -lt 0}).Count; $st=($q|%{$_.r.u*$_.s}|Measure-Object -Sum).Sum; $rk=($q|%{$_.s}|Measure-Object -Sum).Sum
    "{0,3}-{1,-3} {2,6:+0.0;-0.0}u {3,5:P0}" -f $w,$l,$st,$(if($rk){$st/$rk}else{0}) }
  "{0,-46} {1}  | Oct21-29 {2}  | Oct30-Nov8 {3}" -f $name,$o[0],$o[1],$o[2] }
$any = { param($r) $true }
$known = @($c | ? { $_.run -ne $null }).Count
"Nights: $($nights.Count) ($($nights[0])-$($nights[-1])); priced sides $($c.Count); injury-return info for $known"
"Columns: record, staked units, return on stake.`n"

price $SW0
$base = card $any
"== A. Injury-return flag (unders only kept off the card) =="
line "current card" $base
$f2 = { param($r) -not ($r.side -eq "Under" -and $r.run -ge 2 -and $r.since -le 3) }
$f3 = { param($r) -not ($r.side -eq "Under" -and $r.run -ge 3 -and $r.since -le 4) }
$f2p = { param($r) -not ($r.side -eq "Under" -and $r.stat -in "PTS","PRA","PR","PA","RA","REB" -and $r.run -ge 2 -and $r.since -le 3) }
line "no unders: missed 2+ games, <=3 back" (card $f2)
line "no unders: missed 3+ games, <=4 back" (card $f3)
line "no points/reb unders: missed 2+, <=3 back" (card $f2p)
"`nCard picks the flag (missed 2+, <=3 back) would touch:"
$base | ? { $_.r.side -eq "Under" -and $_.r.run -ge 2 -and $_.r.since -le 3 } | % { "  {0} {1,-24} {2} U{3,-5} {4,5} {5}u  missed {6}, back {7}  {8}" -f $_.r.d,$_.r.player,$_.r.stat,$_.r.line,$_.r.odds,$_.s,$_.r.run,$_.r.since,$(if($_.r.u -gt 0){"won"}else{"LOST"}) }
"How every rules-passing under did by flag (all priced sides, not just the card):"
foreach($set in @(@("flagged (missed 2+, <=3 back)",{ param($r) $r.run -ge 2 -and $r.since -le 3 }),@("not flagged",{ param($r) -not ($r.run -ge 2 -and $r.since -le 3) -and $r.run -ne $null }))){
  foreach($grp in @(@("points/reb types","PTS","PRA","PR","PA","RA","REB"),@("AST","AST"))){
    $s=@($c | ? { $_.ok -and $_.side -eq "Under" -and $_.u -ne 0 -and $_.stat -in $grp[1..($grp.Count-1)] -and (& $set[1] $_) })
    if($s.Count){ $w=@($s|?{$_.u -gt 0}).Count; "  {0,-32} {1,-18} n={2,5} won {3,4:P0}  sim said {4,4:P0}  market {5,4:P0}" -f $set[0],$grp[0],$s.Count,($w/$s.Count),(($s|Measure-Object pSim -Average).Average),(($s|Measure-Object pm -Average).Average) } } }

""
"== B. PRA sim weight (now .50) =="
foreach($wv in .50,.40,.30,.20,.10,0){ $sw=$SW0.Clone(); $sw.PRA=$wv; price $sw; line ("PRA weight {0:0.00}" -f $wv) (card $any) }
price $SW0
"`n== B2. Cap on the sim-vs-market gap for PRA unders (weight .50) =="
foreach($cap in .30,.25,.20,.15){ line ("PRA unders only when sim - market < {0:P0}" -f $cap) (card ([scriptblock]::Create("param(`$r) -not (`$r.stat -eq 'PRA' -and `$r.side -eq 'Under' -and (`$r.pSim-`$r.pm) -ge $cap)"))) }
line "no PRA at all" (card { param($r) $r.stat -ne "PRA" })
"`nPRA picks on the current card by half:"
foreach($h in "A","B"){ $q=@($base | ? { $_.r.stat -eq "PRA" -and $_.r.half -eq $h }); $w=@($q|?{$_.r.u -gt 0}).Count; "  half {0}: {1}-{2}, staked {3:+0.0;-0.0}u" -f $h,$w,($q.Count-$w),(($q|%{$_.r.u*$_.s}|Measure-Object -Sum).Sum) }
