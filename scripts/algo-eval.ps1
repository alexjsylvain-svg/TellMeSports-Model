param([string]$Tag = "nov9", [string]$Trk = "tracking")
# Nov 11 card-level replay of model ideas, from every priced side dumped by harness __PXB (tracking\px-<date>-<Tag>.json, 17 nights).
# Rebuilds the card with the page's rules (rule flag = no 3PM / AST overs / PRA overs / gap / loss rules; no questionable,
# role-mismatch or unproven players; -150..+150, 60%+, 5%+ edge; two a game, one per player; stakes 2/1.5/0.5u), then:
#   1 dropping stats (PRA, all scoring combos, everything with points, AST only)
#   2 per-stat sim weights refit on one half of the nights and tested on the other (both ways)
#   3 bench / low-line scoring unders as an extra 0.5u tier, judged per half
#   4 rest days (back-to-backs) from each player's game log in that night's slate
#   5 how often two picks in one game win or lose together (what same-game parlay pricing would need)
# Read-only: prints a report.
$root = Split-Path $PSScriptRoot -Parent; if(-not [IO.Path]::IsPathRooted($Trk)){ $Trk = Join-Path $root $Trk }
function cl($x){ [math]::Min(.99,[math]::Max(.01,$x)) }
function lg($x){ $x=cl $x; [math]::Log($x/(1-$x)) }
function sg($x){ 1/(1+[math]::Exp(-$x)) }
function dec($o){ if($o -gt 0){ 1+$o/100 } else { 1+100/(-$o) } }
function stake($p){ if($p -ge .66){2} elseif($p -ge .64){1.5} else {.5} }
function Norm([string]$s){ ($s.Normalize([Text.NormalizationForm]::FormD) -replace '\p{Mn}','').ToLower() -replace "[.'\-,]"," " -replace '\b(jr|sr|ii|iii|iv)\b','' -replace '\s+',' ' | % { $_.Trim() } }
$SW0 = @{ PTS=.05; REB=0; AST=.65; "3PM"=.75; PRA=.50; PR=0; PA=.15; RA=.20; DD=.15 }

# ---- load priced player props
$rows = New-Object System.Collections.ArrayList
foreach($f in Get-ChildItem $Trk -Filter "px-*-$Tag.json" | Sort-Object Name){ foreach($r in (Get-Content $f.FullName -Raw | ConvertFrom-Json)){ if($r.k -eq "P" -and $r.u -ne $null){ [void]$rows.Add($r) } } }
$nights = @($rows | % d | Sort-Object -Unique); $mid = "20261029"
# ---- rest days: the player's last game before tonight, from that night's slate logs
$rest = @{}
foreach($d in $nights){ $sf = @((Join-Path $Trk "btc\slate-$d.json"), (Join-Path $Trk "slate-$d.json")) | ? { Test-Path $_ } | Select-Object -First 1
  if(-not $sf){ continue }; $s = Get-Content $sf -Raw | ConvertFrom-Json
  $dt = [datetime]::ParseExact($d,"yyyyMMdd",$null)
  foreach($tm in $s.teams.PSObject.Properties){ $teamLast = $null
    foreach($p in $tm.Value.players){ $lg = @($p.cur.log | ? { $_.d -lt $d } | % d | Sort-Object); if($lg.Count){ $l=$lg[-1]; if(-not $teamLast -or $l -gt $teamLast){ $teamLast=$l } } }
    foreach($p in $tm.Value.players){ if($teamLast){ $rest["$d|$(Norm $p.name)"] = ($dt - [datetime]::ParseExact($teamLast,"yyyyMMdd",$null)).Days } } } }
# ---- candidate sides with the card's player rules applied
$c = New-Object System.Collections.ArrayList
foreach($r in $rows){
  $ok = $r.rule -and -not ($r.stat -eq "PRA" -and $r.side -eq "Over") -and -not $r.why.mis -and -not $r.why.q -and -not (($r.why.prior -or $r.why.y24) -and $r.curG -lt 3)
  [void]$c.Add([pscustomobject]@{ d=$r.d; half=$(if($r.d -le $mid){"A"}else{"B"}); gid=$r.gid; stat=$r.stat; side=$r.side; line=[double]$r.line; odds=[double]$r.odds
    pm=[double]$r.pm; pSim=[double]$r.pSim; push=[double]$r.push; bench=[bool]$r.bench; u=[double]$r.u; player=$r.player; ok=$ok; rest=$rest["$($r.d)|$(Norm $r.player)"]; p=0.0; ev=0.0 }) }
function price($sw){ foreach($x in $c){ $w=[math]::Min(1.0,$sw[$x.stat]*$(if($x.bench){.8}else{1})); $p=(sg ((1-$w)*(lg $x.pm)+$w*(lg $x.pSim)))*(1-$x.push); $pl=[math]::Max(0.0,1-$p-$x.push); $x.p=$p; $x.ev=$p*((dec $x.odds)-1)-$pl } }
function card($filter, $extra){
  $all=@()
  foreach($grp in ($c | ? { $_.ok } | Group-Object d,gid)){
    $cand=@(); foreach($r in $grp.Group){ if(& $filter $r){ if($r.odds -ge -150 -and $r.odds -le 150 -and $r.p -ge .60 -and $r.ev -ge .05){ $cand += [pscustomobject]@{ r=$r; t="A"; s=(stake $r.p) } } elseif($extra -and (& $extra $r)){ $cand += [pscustomobject]@{ r=$r; t="B"; s=.5 } } } }
    $pk=@(); foreach($x in ($cand | Sort-Object @{e={$_.t}},@{e={$_.r.p};Descending=$true})){ if($pk.Count -ge $(if($x.t -eq "A"){2}else{3})){ continue }; if(@($pk|?{ $_.r.player -eq $x.r.player }).Count){ continue }; $pk += $x }
    $all += $pk }
  $all }
function line($name,$pk){ $pk=@($pk); $o=foreach($h in "all","A","B"){ $q=@($pk | ? { $h -eq "all" -or $_.r.half -eq $h }); $w=@($q|?{$_.r.u -gt 0}).Count; $l=@($q|?{$_.r.u -lt 0}).Count; $st=($q|%{$_.r.u*$_.s}|Measure-Object -Sum).Sum; $rk=($q|%{$_.s}|Measure-Object -Sum).Sum
    "{0,3}-{1,-3} {2,6:+0.0;-0.0}u {3,6:P0}" -f $w,$l,$st,$(if($rk){$st/$rk}else{0}) }
  "{0,-40} {1}  | Oct21-29 {2}  | Oct30-Nov8 {3}" -f $name,$o[0],$o[1],$o[2] }
$any = { param($r) $true }
"Nights: $($nights.Count) ($($nights[0])-$($nights[-1])); priced sides $($c.Count); rest days known for $(@($c|?{$_.rest -ne $null}).Count)"
"Columns: record, staked units, return on stake. Halves: A = Oct 21-29, B = Oct 30-Nov 8.`n"

# ---- 1 dropping stats
price $SW0
"== 1. Card with stats dropped =="
line "current card" (card $any $null)
line "no PRA at all" (card { param($r) $r.stat -ne "PRA" } $null)
line "no scoring combos (PRA/PR/PA/RA)" (card { param($r) $r.stat -notin "PRA","PR","PA","RA" } $null)
line "nothing with points (PTS/PRA/PR/PA)" (card { param($r) $r.stat -notin "PTS","PRA","PR","PA" } $null)
line "assists only" (card { param($r) $r.stat -eq "AST" } $null)
$base = card $any $null
"`nCurrent card by stat:"; foreach($g in ($base | Group-Object { "$($_.r.stat) $($_.r.side)" } | Sort-Object Count -Descending)){ line ("  "+$g.Name) $g.Group }
"`nCurrent card, model chance vs result:"; foreach($g in ($base | Group-Object { if($_.r.stat -eq "AST"){"AST"}else{"other"} })){ $q=$g.Group; "  {0,-6} {1,3} picks, model said {2:P1}, won {3:P1}" -f $g.Name,$q.Count,(($q|%{$_.r.p}|Measure-Object -Average).Average),(@($q|?{$_.r.u -gt 0}).Count/@($q|?{$_.r.u -ne 0}).Count) }

# ---- 2 per-stat weight refit, out of sample
"`n== 2. Sim weight per stat, refit on one half and tested on the other =="
function fitW($half){ $sw=@{}; foreach($st in $SW0.Keys){ $q=@($c | ? { $_.half -eq $half -and $_.stat -eq $st -and $_.u -ne 0 -and $_.side -eq "Over" }); if($q.Count -lt 40){ $sw[$st]=$SW0[$st]; continue }
    $best=$null; foreach($w0 in 0..20){ $w=$w0/20; $ll=0.0; foreach($x in $q){ $ww=[math]::Min(1.0,$w*$(if($x.bench){.8}else{1})); $p=cl (sg ((1-$ww)*(lg $x.pm)+$ww*(lg $x.pSim))); $y=[int]($x.u -gt 0); $ll -= $y*[math]::Log($p)+(1-$y)*[math]::Log(1-$p) }
      if(-not $best -or $ll -lt $best.ll){ $best=@{w=$w;ll=$ll} } }; $sw[$st]=$best.w }; $sw }
$fA = fitW "A"; $fB = fitW "B"
"  weight     now   fit on A   fit on B"; foreach($st in "PTS","REB","AST","3PM","PRA","PR","PA","RA"){ "  {0,-6} {1,6:N2} {2,9:N2} {3,9:N2}" -f $st,$SW0[$st],$fA[$st],$fB[$st] }
price $fA; $tB = @(card $any $null | ? { $_.r.half -eq "B" })
price $fB; $tA = @(card $any $null | ? { $_.r.half -eq "A" })
line "refit, each half priced by the other" (@($tA)+@($tB))
price $SW0; line "current weights (same nights)" (card $any $null)
foreach($st in "PRA","PTS","PR","PA","RA"){ $sw=$SW0.Clone(); $sw[$st]=0; price $sw; line "  $st weight 0" (card $any $null) }
$sw=$SW0.Clone(); foreach($st in "PTS","PRA","PR","PA","RA"){ $sw[$st]=0 }; price $sw; line "  all points stats weight 0" (card $any $null)
price $SW0

# ---- 3 bench / low-line scoring unders
"`n== 3. Scoring unders (PTS/PRA/PR/PA/RA), flat 1u, -150..+150, card player rules =="
function flat($name,$q){ $o=foreach($h in "all","A","B"){ $z=@($q | ? { $h -eq "all" -or $_.half -eq $h }); $w=@($z|?{$_.u -gt 0}).Count; $l=@($z|?{$_.u -lt 0}).Count; $s=($z|%{$_.u}|Measure-Object -Sum).Sum; "{0,4}-{1,-4} {2,6:+0.0;-0.0}u {3,6:P1}" -f $w,$l,$s,$(if($z.Count){$s/$z.Count}else{0}) }
  "{0,-40} {1} | A {2} | B {3}" -f $name,$o[0],$o[1],$o[2] }
$su = @($c | ? { $_.ok -and $_.side -eq "Under" -and $_.stat -in "PTS","PRA","PR","PA","RA" -and $_.odds -ge -150 -and $_.odds -le 150 })
flat "all scoring unders" $su
flat "bench" ($su | ? { $_.bench })
flat "starters" ($su | ? { -not $_.bench })
flat "PTS line under 10" ($su | ? { $_.stat -eq "PTS" -and $_.line -lt 10 })
flat "bench, PTS line under 10" ($su | ? { $_.bench -and $_.stat -eq "PTS" -and $_.line -lt 10 })
flat "bench, model edge 0%+" ($su | ? { $_.bench -and $_.ev -ge 0 })
flat "bench, sim leans under (55%+)" ($su | ? { $_.bench -and $_.pSim -ge .55 })
line "card + bench scoring unders 0.5u (edge 0%+)" (card $any { param($r) $r.bench -and $r.side -eq "Under" -and $r.stat -in "PTS","PRA","PR","PA","RA" -and $r.odds -ge -150 -and $r.odds -le 150 -and $r.ev -ge 0 })

# ---- 4 rest days
"`n== 4. Rest: result minus model chance (positive = model too low), card player rules, -150..+150 =="
$rq = @($c | ? { $_.ok -and $_.rest -ne $null -and $_.u -ne 0 -and $_.odds -ge -150 -and $_.odds -le 150 })
foreach($grp in "AST","PTS","REB","PRA/PR/PA/RA"){ foreach($sd in "Over","Under"){
  $q=@($rq | ? { $_.side -eq $sd -and $(if($grp -eq "PRA/PR/PA/RA"){ $_.stat -in "PRA","PR","PA","RA" } else { $_.stat -eq $grp }) })
  $o=foreach($b in @(@(1,1,"b2b"),@(2,2,"1 day"),@(3,99,"2+ days"))){ $z=@($q|?{ $_.rest -ge $b[0] -and $_.rest -le $b[1] }); if($z.Count){ $hit=@($z|?{$_.u -gt 0}).Count/$z.Count; $ex=($z|%{$_.p}|Measure-Object -Average).Average; $mk=($z|%{$_.pm}|Measure-Object -Average).Average; "{0} n={1,4} {2,6:+0.0;-0.0} vs mkt {3,6:+0.0;-0.0}" -f $b[2],$z.Count,(100*($hit-$ex)),(100*($hit-$mk)) } }
  "  {0,-13} {1,-5} {2}" -f $grp,$sd,($o -join "  |  ") } }
"  b2b by half (all stats, unders): " + (("A","B" | % { $h=$_; $z=@($rq|?{ $_.rest -eq 1 -and $_.side -eq "Under" -and $_.half -eq $h }); if($z.Count){ "{0} n={1} {2:+0.0;-0.0} pts vs model" -f $h,$z.Count,(100*(@($z|?{$_.u -gt 0}).Count/$z.Count-($z|%{$_.p}|Measure-Object -Average).Average)) } }) -join "; ")
"  card picks on a b2b: " + $(line "" ($base | ? { $_.r.rest -eq 1 }))

# ---- 5 same-game pairs on the card
"`n== 5. Two card picks in the same game =="
$pairs = @($base | Group-Object { "$($_.r.d)|$($_.r.gid)" } | ? { $_.Count -eq 2 -and -not @($_.Group | ? { $_.r.u -eq 0 }).Count })
$bw=@($pairs|?{ @($_.Group|?{$_.r.u -gt 0}).Count -eq 2 }).Count; $bl=@($pairs|?{ @($_.Group|?{$_.r.u -lt 0}).Count -eq 2 }).Count
$ind=($pairs|%{ $_.Group[0].r.p*$_.Group[1].r.p }|Measure-Object -Sum).Sum; $indL=($pairs|%{ (1-$_.Group[0].r.p)*(1-$_.Group[1].r.p) }|Measure-Object -Sum).Sum
$ss=@($pairs|?{ $_.Group[0].r.stat -eq $_.Group[1].r.stat })
"  {0} games with two picks: both won {1} (independent model says {2:N1}), both lost {3} (model {4:N1}), split {5}; same-stat pairs {6}" -f $pairs.Count,$bw,$ind,$bl,$indL,($pairs.Count-$bw-$bl),$ss.Count
$sw2=@($ss|?{ @($_.Group|?{$_.r.u -gt 0}).Count -eq 2 }).Count; $sl2=@($ss|?{ @($_.Group|?{$_.r.u -lt 0}).Count -eq 2 }).Count
"  same-stat pairs: both won $sw2, both lost $sl2, split $($ss.Count-$sw2-$sl2)"
# outcome correlation across all qualifying same-game unders (not only the card), for a bigger sample
$gq = @($c | ? { $_.ok -and $_.u -ne 0 -and $_.side -eq "Under" -and $_.stat -eq "AST" } | Group-Object d,gid | ? { $_.Count -ge 2 })
$n=0; $agree=0; $exp=0.0; foreach($g in $gq){ $z=$g.Group; for($i=0;$i -lt $z.Count;$i++){ for($j=$i+1;$j -lt $z.Count;$j++){ if($z[$i].player -eq $z[$j].player){continue}; $n++; $a=[int]($z[$i].u -gt 0); $b=[int]($z[$j].u -gt 0); if($a -eq $b){$agree++}; $exp += $z[$i].pm*$z[$j].pm+(1-$z[$i].pm)*(1-$z[$j].pm) } } }
"  all same-game AST under pairs: {0}, same result {1:P1} vs {2:P1} if independent" -f $n,($agree/[math]::Max(1,$n)),($exp/[math]::Max(1,$n))

# ---- 6 assist unders: the model is under-confident there; test the bar, stakes and sim weight
"`n== 6. Assist unders: bar, stakes and sim weight =="
$au = @($base | ? { $_.r.stat -eq "AST" })
foreach($b in @(@(.60,.64,"60-64% (0.5u)"),@(.64,.66,"64-66% (1.5u)"),@(.66,1,"66%+ (2u)"))){ $q=@($au|?{ $_.r.p -ge $b[0] -and $_.r.p -lt $b[1] }); "  {0,-15} {1,3} picks, model said {2:P1}, won {3:P1}, flat {4,6:+0.0;-0.0}u" -f $b[2],$q.Count,(($q|%{$_.r.p}|Measure-Object -Average).Average),(@($q|?{$_.r.u -gt 0}).Count/[math]::Max(1,@($q|?{$_.r.u -ne 0}).Count)),(($q|%{$_.r.u}|Measure-Object -Sum).Sum) }
function cardBar($minP, $minEv, $stk){
  $all=@(); foreach($grp in ($c | ? { $_.ok } | Group-Object d,gid)){
    $cand=@($grp.Group | ? { $_.odds -ge -150 -and $_.odds -le 150 -and $(if($_.stat -eq "AST"){ $_.p -ge $minP -and $_.ev -ge $minEv } else { $_.p -ge .60 -and $_.ev -ge .05 }) } | Sort-Object p -Descending)
    $pk=@(); foreach($r in $cand){ if($pk.Count -ge 2){ break }; if(@($pk|?{ $_.r.player -eq $r.player }).Count){ continue }; $pk += [pscustomobject]@{ r=$r; t="A"; s=(& $stk $r) } }
    $all += $pk }; $all }
$stk0 = { param($r) stake $r.p }
line "current bar" (cardBar .60 .05 $stk0)
foreach($mp in .58,.56,.55){ line "AST unders from $([int]($mp*100))%" (cardBar $mp .05 $stk0) }
line "AST unders edge 3%+" (cardBar .60 .03 $stk0)
line "AST unders 58%+, edge 3%+" (cardBar .58 .03 $stk0)
line "AST unders min 1u stake" (cardBar .60 .05 { param($r) if($r.stat -eq "AST"){ [math]::Max(1.0,(stake $r.p)) } else { stake $r.p } })
line "AST unders 1.5u flat" (cardBar .60 .05 { param($r) if($r.stat -eq "AST"){ 1.5 } else { stake $r.p } })
foreach($aw in .50,.75,.85,1.0){ $sw=$SW0.Clone(); $sw["AST"]=$aw; price $sw; line "AST sim weight $aw" (cardBar .60 .05 $stk0) }
price $SW0
"  AST unders by line: " + ((@(@(0,2,"0.5-1.5"),@(2,4,"2.5-3.5"),@(4,6,"4.5-5.5"),@(6,99,"6.5+")) | % { $b=$_; $q=@($au|?{ $_.r.line -ge $b[0] -and $_.r.line -lt $b[1] }); if($q.Count){ "{0} {1}-{2}" -f $b[2],@($q|?{$_.r.u -gt 0}).Count,@($q|?{$_.r.u -lt 0}).Count } }) -join ", ")
"  AST unders by odds: " + ((@(@(-150,-131,"-150..-131"),@(-130,-111,"-130..-111"),@(-110,150,"-110..+150")) | % { $b=$_; $q=@($au|?{ $_.r.odds -ge $b[0] -and $_.r.odds -le $b[1] }); if($q.Count){ "{0} {1}-{2} {3:+0.0;-0.0}u" -f $b[2],@($q|?{$_.r.u -gt 0}).Count,@($q|?{$_.r.u -lt 0}).Count,(($q|%{$_.r.u*$_.s}|Measure-Object -Sum).Sum) } }) -join ", ")
"  AST unders by rest: " + ((@(@(1,1,"b2b"),@(2,2,"1 day"),@(3,99,"2+ days")) | % { $b=$_; $q=@($au|?{ $_.r.rest -ge $b[0] -and $_.r.rest -le $b[1] }); if($q.Count){ "{0} {1}-{2}" -f $b[2],@($q|?{$_.r.u -gt 0}).Count,@($q|?{$_.r.u -lt 0}).Count } }) -join ", ")
"`n== 7. AST weight: unders-only fit and flat-stake check =="
foreach($h in "A","B"){ $q=@($c | ? { $_.half -eq $h -and $_.stat -eq "AST" -and $_.side -eq "Under" -and $_.u -ne 0 -and $_.ok })
  $res=foreach($w0 in 8..20){ $w=$w0/20; $ll=0.0; foreach($x in $q){ $ww=[math]::Min(1.0,$w*$(if($x.bench){.8}else{1})); $p=cl (sg ((1-$ww)*(lg $x.pm)+$ww*(lg $x.pSim))); $y=[int]($x.u -gt 0); $ll -= $y*[math]::Log($p)+(1-$y)*[math]::Log(1-$p) }; [pscustomobject]@{w=$w;ll=$ll/$q.Count} }
  $bst=$res | Sort-Object ll | Select-Object -First 1; "  half {0}: {1} AST unders (card player rules), best weight {2:N2} (log loss {3:N4}; at .65 {4:N4})" -f $h,$q.Count,$bst.w,$bst.ll,($res|?{[math]::Abs($_.w-.65) -lt .01}).ll }
$flat1 = { param($r) 1.0 }
foreach($aw in .65,.75,.85,1.0){ $sw=$SW0.Clone(); $sw["AST"]=$aw; price $sw; $pk=cardBar .60 .05 $flat1; line "AST weight $aw, every pick 1u" $pk; $a=@($pk|?{$_.r.stat -eq "AST"}); "      AST picks {0}, model said {1:P1}, won {2:P1}" -f $a.Count,(($a|%{$_.r.p}|Measure-Object -Average).Average),(@($a|?{$_.r.u -gt 0}).Count/[math]::Max(1,@($a|?{$_.r.u -ne 0}).Count)) }
price $SW0

"`n  Rest 2+ days by half (unders, result minus model): " + (("A","B" | % { $h=$_; $z=@($rq|?{ $_.rest -ge 3 -and $_.side -eq "Under" -and $_.half -eq $h }); if($z.Count){ "{0} n={1} {2:+0.0;-0.0} pts" -f $h,$z.Count,(100*(@($z|?{$_.u -gt 0}).Count/$z.Count-($z|%{$_.p}|Measure-Object -Average).Average)) } }) -join "; ")
