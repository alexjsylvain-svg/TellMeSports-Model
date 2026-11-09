param([string]$Tag = "nov9", [string]$Trk = "tracking")
# Price-range backtest (Nov 9): would plus-money bets past +150 (up to +1000) have paid? Reads every priced side dumped by harness
# __PXB (tracking\px-<date>-<Tag>.json), prices it with the page's blend, applies the card's player rules (rule flag, no PRA overs,
# no questionable/role-mismatch players, rookie games), and grades bands of price and edge bars. Game lines (k "G") are included.
$root = Split-Path $PSScriptRoot -Parent; if(-not [IO.Path]::IsPathRooted($Trk)){ $Trk = Join-Path $root $Trk }
$rows = New-Object System.Collections.ArrayList
foreach($f in Get-ChildItem $Trk -Filter "px-*-$Tag.json" | Sort-Object Name){ foreach($r in (Get-Content $f.FullName -Raw | ConvertFrom-Json)){ [void]$rows.Add($r) } }
function cl($x){ [math]::Min(.99,[math]::Max(.01,$x)) }
function lg($x){ $x=cl $x; [math]::Log($x/(1-$x)) }
function sg($x){ 1/(1+[math]::Exp(-$x)) }
function dec($o){ if($o -gt 0){ 1+$o/100 } else { 1+100/(-$o) } }
function stake($p){ if($p -ge .66){2} elseif($p -ge .64){1.5} else {.5} }
$SW = @{ PTS=.05; REB=0; AST=.65; "3PM"=.75; PRA=.50; PR=0; PA=.15; RA=.20; DD=.15 }
$c = New-Object System.Collections.ArrayList
foreach($r in $rows){
  if($r.u -eq $null){ continue }
  if($r.k -eq "P"){
    if(-not $r.rule -or $r.why.mis -or $r.why.q -or (($r.why.prior -or $r.why.y24) -and $r.curG -lt 3)){ continue }
    if($r.side -eq "Over" -and $r.stat -eq "PRA"){ continue }
    $w=[math]::Min(1.0,$SW[$r.stat]*$(if($r.bench){.8}else{1})); $p=(sg ((1-$w)*(lg $r.pm)+$w*(lg $r.pSim)))*(1-$r.push); $pl=[math]::Max(0.0,1-$p-$r.push)
    [void]$c.Add([pscustomobject]@{ d=$r.d; gid=$r.gid; k="P"; stat=$r.stat; side=$r.side; odds=$r.odds; p=$p; pm=$r.pm; ev=$p*((dec $r.odds)-1)-$pl; u=$r.u; player=$r.player; bet="$($r.player) $($r.side) $($r.line) $($r.stat)" }) }
  elseif($r.k -eq "G"){ [void]$c.Add([pscustomobject]@{ d=$r.d; gid=$r.gid; k="G"; stat=$r.mkt; side=""; odds=$r.odds; p=$r.p; pm=$r.pm; ev=$r.ev; u=$r.u; player=$null; bet=$r.bet }) } }
$nights = @($c | % d | Sort-Object -Unique)
"nights: $($nights.Count) ($($nights[0])-$($nights[-1]))   graded sides: $($c.Count)"
function sum($name,$a,[switch]$Tier){ $a=@($a); $w=@($a|?{$_.u -gt 0}).Count; $l=@($a|?{$_.u -lt 0}).Count; $fl=($a|%{$_.u}|Measure-Object -Sum).Sum
  $ex=($a|%{$_.p}|Measure-Object -Average).Average; $ev=($a|%{$_.ev}|Measure-Object -Average).Average
  "{0,-46} {1,4} bets {2,3}-{3,-4} flat {4,7:N2}u ({5,6:P1})  model said win {6,5:P0}, edge {7,5:P0}" -f $name,$a.Count,$w,$l,$fl,$(if($a.Count){$fl/$a.Count}else{0}),$ex,$ev }
"`nAll sides by price band (no win-chance floor), 1u each:"
foreach($b in @(@(-150,-101),@(100,150),@(151,250),@(251,400),@(401,1000))){
  foreach($e in .05,.10,.15,.20,.30){ $a=@($c|?{ $_.odds -ge $b[0] -and $_.odds -le $b[1] -and $_.ev -ge $e })
    if($a.Count){ sum ("{0}..{1}, edge {2:P0}+" -f $b[0],$b[1],$e) $a } } }
"`nSame, props only (no game lines):"
foreach($b in @(@(151,250),@(251,400),@(401,1000))){ foreach($e in .05,.10,.20){ $a=@($c|?{ $_.k -eq "P" -and $_.odds -ge $b[0] -and $_.odds -le $b[1] -and $_.ev -ge $e }); if($a.Count){ sum ("props {0}..{1}, edge {2:P0}+" -f $b[0],$b[1],$e) $a } } }
"`nGame lines only:"
foreach($b in @(@(151,250),@(251,400),@(401,1000))){ foreach($e in .05,.10,.20){ $a=@($c|?{ $_.k -eq "G" -and $_.odds -ge $b[0] -and $_.odds -le $b[1] -and $_.ev -ge $e }); if($a.Count){ sum ("games {0}..{1}, edge {2:P0}+" -f $b[0],$b[1],$e) $a } } }
"`nPlus money +100..+150 below the 60% floor:"
foreach($m in .50,.55){ foreach($e in .05,.10,.15){ $a=@($c|?{ $_.odds -ge 100 -and $_.odds -le 150 -and $_.p -ge $m -and $_.p -lt .60 -and $_.ev -ge $e }); if($a.Count){ sum ("+100..+150, win {0:P0}-60%, edge {1:P0}+" -f $m,$e) $a } } }

# card-level test: the card's rules (two a game, one per player, at most one game line, best chance first) plus extra tiers at 0.5u
function card2($tiers, [int]$extra){
  $all=@()
  foreach($grp in ($c | Group-Object d,gid)){
    $cand=@()
    foreach($r in $grp.Group){ $t=$null
      if($r.odds -ge -150 -and $r.odds -le 150 -and $r.p -ge .60 -and $r.ev -ge .05){ $t="A" }
      else { foreach($tr in $tiers){ if($r.odds -ge $tr.lo -and $r.odds -le $tr.hi -and $r.p -ge $tr.minP -and $r.ev -ge $tr.ev){ $t="B"; break } } }
      if($t){ $cand += [pscustomobject]@{ r=$r; t=$t; s=$(if($t -eq "A"){ stake $r.p } else { .5 }) } } }
    $pk=@()
    foreach($x in ($cand | Sort-Object @{e={$_.t};Ascending=$true},@{e={$_.r.p};Descending=$true})){
      $cap = if($x.t -eq "A"){ 2 } else { 2 + $extra }
      if($pk.Count -ge $cap){ continue }
      if(@($pk | ? { ($x.r.player -and $_.r.player -eq $x.r.player) -or (-not $x.r.player -and -not $_.r.player) }).Count){ continue }
      $pk += $x }
    $all += $pk }
  $all }
function line2($name,$pk){ $w=@($pk|?{$_.r.u -gt 0}).Count; $l=@($pk|?{$_.r.u -lt 0}).Count; $st=($pk|%{$_.r.u*$_.s}|Measure-Object -Sum).Sum; $rk=($pk|%{$_.s}|Measure-Object -Sum).Sum
  $b=@($pk|?{$_.t -eq "B"}); $bs=($b|%{$_.r.u*$_.s}|Measure-Object -Sum).Sum
  "{0,-44} {1,3}-{2,-3} staked {3,6:N2}u on {4,5:N1}u ({5,5:P1})   tier {6}-{7} {8:N2}u" -f $name,$w,$l,$st,$rk,$(if($rk){$st/$rk}else{0}),@($b|?{$_.r.u -gt 0}).Count,@($b|?{$_.r.u -lt 0}).Count,$bs }
"`nCard-level (17 nights):"
line2 "now" (card2 @() 0)
line2 "+ long +151..+1000 edge 5%" (card2 @(@{lo=151;hi=1000;minP=0;ev=.05}) 0)
line2 "+ long +151..+250 edge 5%, 3rd slot" (card2 @(@{lo=151;hi=250;minP=0;ev=.05}) 1)
line2 "+ value +100..+150 50%+ edge 10%" (card2 @(@{lo=100;hi=150;minP=.5;ev=.10}) 0)
line2 "+ value +100..+150 50%+ edge 10%, 3rd slot" (card2 @(@{lo=100;hi=150;minP=.5;ev=.10}) 1)
line2 "+ value +100..+150 55%+ edge 10%" (card2 @(@{lo=100;hi=150;minP=.55;ev=.10}) 0)

# parlays: each night's card legs (main tier), best chance first, one per game; a push drops the leg; 1u a parlay
function parlay($pk, [int]$n, [string]$by){
  $out=@()
  foreach($night in ($pk | ? { $_.t -eq "A" } | Group-Object { $_.r.d })){
    $legs=@(); foreach($x in ($night.Group | Sort-Object @{e={ if($by -eq "ev"){ $_.r.ev } else { $_.r.p } };Descending=$true})){ if($legs.Count -ge $n){ break }; if(@($legs|?{ $_.r.gid -eq $x.r.gid }).Count){ continue }; $legs += $x }
    if($legs.Count -lt $n){ continue }
    $dec=1.0; $p=1.0; $lost=$false; foreach($l in $legs){ $p*=$l.r.p; if($l.r.u -lt 0){ $lost=$true } elseif($l.r.u -gt 0){ $dec*=(dec $l.r.odds) } }
    $out += [pscustomobject]@{ d=$night.Name; p=$p; u=$(if($lost){-1}else{$dec-1}); price=$(($legs|%{ dec $_.r.odds })|% -Begin {$m=1.0} -Process {$m*=$_} -End {$m}) } }
  $out }
"`nParlays (1u each, legs from the main card tier):"
$base = card2 @(@{lo=100;hi=150;minP=.5;ev=.10}) 1
foreach($v in @(@(2,"p"),@(3,"p"),@(2,"ev"),@(3,"ev"))){ $pp=parlay $base $v[0] $v[1]; $w=@($pp|?{$_.u -gt 0}).Count; $u=($pp|%{$_.u}|Measure-Object -Sum).Sum
  "{0} legs by {1,-3}: {2,2}-{3,-2} {4,6:N2}u ({5,6:P1})  avg price {6:N2}x, model chance {7:P0}" -f $v[0],$v[1],$w,($pp.Count-$w),$u,$(if($pp.Count){$u/$pp.Count}else{0}),($pp|%{$_.price}|Measure-Object -Average).Average,($pp|%{$_.p}|Measure-Object -Average).Average }
