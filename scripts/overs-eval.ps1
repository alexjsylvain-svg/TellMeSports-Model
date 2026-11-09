param([string]$Tag = "nov9", [string]$Trk = "tracking")
# Over-side rules backtest (Nov 9). Reads every priced prop side dumped by harness __PXB (tracking\px-<date>-<Tag>.json),
# re-prices the sides under each variant and picks the card with gamePicks' rules (rule flag: no 3PM / AST overs / own-gap /
# loss rule; no questionable or role-mismatch players; rookies and 2024-25 players only at 3+ games; -150..+150, 60%+, 5%+ EV,
# two a game, one per player, same stat allowed twice, at most one game line). Stakes 2u at 66%+, 1.5u at 64-66%, 0.5u below.
$root = Split-Path $PSScriptRoot -Parent; if(-not [IO.Path]::IsPathRooted($Trk)){ $Trk = Join-Path $root $Trk }
$rows = New-Object System.Collections.ArrayList
foreach($f in Get-ChildItem $Trk -Filter "px-*-$Tag.json" | Sort-Object Name){ foreach($r in (Get-Content $f.FullName -Raw | ConvertFrom-Json)){ [void]$rows.Add($r) } }
$nights = @($rows | % d | Sort-Object -Unique)
function cl($x){ [math]::Min(.99,[math]::Max(.01,$x)) }
function lg($x){ $x=cl $x; [math]::Log($x/(1-$x)) }
function sg($x){ 1/(1+[math]::Exp(-$x)) }
function dec($o){ if($o -gt 0){ 1+$o/100 } else { 1+100/(-$o) } }
function stake($p){ if($p -ge .66){2} elseif($p -ge .64){1.5} else {.5} }
$SW = @{ PTS=.05; REB=0; AST=.65; "3PM"=.75; PRA=.50; PR=0; PA=.15; RA=.20; DD=.15 }
$props = @($rows | ? { $_.k -eq "P" -and $_.rule -and -not $_.why.mis -and -not $_.why.q -and -not (($_.why.prior -or $_.why.y24) -and $_.curG -lt 3) })
$games = @($rows | ? k -eq "G")
"nights: $($nights.Count) ($($nights[0])-$($nights[-1]))   prop sides allowed by the card rules: $($props.Count)"
# the dump's p is the page's blended chance: check the re-pricing reproduces it
$chk = ($props | % { $w=[math]::Min(1.0,($SW[$_.stat])*$(if($_.bench){.8}else{1})); [math]::Abs((sg ((1-$w)*(lg $_.pm)+$w*(lg $_.pSim)))*(1-$_.push) - $_.p) } | Measure-Object -Maximum).Maximum
"re-pricing check, largest gap to the page's chance: {0:N5}" -f $chk
""
# v: overMult (scales the sim weight on over sides), overMinP, noOver (stats with no overs)
function price($r, $v){ $m = if($r.side -eq "Over"){ $v.overMult } else { 1 }
  $sw0=$SW[$r.stat]; if($r.stat -eq "PRA" -and $v.praW -ne $null){ $sw0=$v.praW }; $w=[math]::Min(1.0,$sw0*$(if($r.bench){.8}else{1})*$m); $p=(sg ((1-$w)*(lg $r.pm)+$w*(lg $r.pSim)))*(1-$r.push)
  $pl=[math]::Max(0.0,1-$p-$r.push); [pscustomobject]@{ p=$p; ev=$p*((dec $r.odds)-1)-$pl } }
function card($v, $nset){
  $all=@()
  foreach($grp in ($props | ? { $nset -contains $_.d } | Group-Object d,gid)){
    $c=@()
    foreach($r in $grp.Group){
      if($r.side -eq "Over" -and ($v.noOver -contains $r.stat -or $v.noOver -contains "*")){ continue }
      $q = price $r $v; $min = if($r.side -eq "Over"){ $v.overMinP } else { .60 }
      if($r.odds -lt -150 -or $r.odds -gt 150 -or $q.ev -lt .05 -or $q.p -lt $min){ continue }
      $c += [pscustomobject]@{ p=$q.p; ev=$q.ev; player=$r.player; stat=$r.stat; side=$r.side; u=$r.u; d=$r.d; bet="$($r.player) $($r.side) $($r.line) $($r.stat)" } }
    $d0=$grp.Group[0].d; $g0=$grp.Group[0].gid
    foreach($g in ($games | ? { $_.d -eq $d0 -and $_.gid -eq $g0 -and $_.odds -ge -150 -and $_.odds -le 150 -and $_.ev -ge .05 -and $_.p -ge .60 })){
      $c += [pscustomobject]@{ p=$g.p; ev=$g.ev; player=$null; stat=$g.mkt; side="game"; u=$g.u; d=$g.d; bet=$g.bet } }
    $pk=@()
    foreach($b in ($c | Sort-Object @{e={$_.p};Descending=$true},@{e={$_.ev};Descending=$true})){
      if($pk.Count -ge 2){ break }
      if(@($pk | ? { $_.bet -eq $b.bet -or ($b.player -and $_.player -eq $b.player) -or (-not $b.player -and -not $_.player) }).Count){ continue }
      $pk += $b }
    $all += $pk }
  $all }
function line($name, $pk){
  $w=@($pk|?{$_.u -gt 0}).Count; $l=@($pk|?{$_.u -lt 0}).Count; $fl=($pk|%{$_.u}|Measure-Object -Sum).Sum; $st=($pk|%{$_.u*(stake $_.p)}|Measure-Object -Sum).Sum
  $rk=($pk|%{stake $_.p}|Measure-Object -Sum).Sum; $ov=@($pk|? side -eq "Over")
  "{0,-40} {1,3}-{2,-3} flat {3,6:N2}u  staked {4,6:N2}u on {5,5:N1}u ({6,5:P1})   overs {7}-{8}" -f $name,$w,$l,$fl,$st,$rk,$(if($rk){$st/$rk}else{0}),@($ov|?{$_.u -gt 0}).Count,@($ov|?{$_.u -lt 0}).Count }
$V = [ordered]@{
  "now"                          = @{ overMult=1;   overMinP=.60; noOver=@() }
  "overs need 62%"               = @{ overMult=1;   overMinP=.62; noOver=@() }
  "overs need 64%"               = @{ overMult=1;   overMinP=.64; noOver=@() }
  "overs need 66%"               = @{ overMult=1;   overMinP=.66; noOver=@() }
  "no PRA overs"                 = @{ overMult=1;   overMinP=.60; noOver=@("PRA") }
  "over sim weight x0.75"        = @{ overMult=.75; overMinP=.60; noOver=@() }
  "over sim weight x0.5"         = @{ overMult=.5;  overMinP=.60; noOver=@() }
  "no overs at all"              = @{ overMult=1;   overMinP=.60; noOver=@("*") }
  "PRA sim weight .35 (both sides)" = @{ overMult=1; overMinP=.60; noOver=@(); praW=.35 }
  "PRA sim weight .25 (both sides)" = @{ overMult=1; overMinP=.60; noOver=@(); praW=.25 }
  "PRA weight .25 + no PRA overs"   = @{ overMult=1; overMinP=.60; noOver=@("PRA"); praW=.25 } }
$half1 = @($nights | ? { $_ -le "20261028" }); $half2 = @($nights | ? { $_ -gt "20261028" })
foreach($set in @(@{n="all $($nights.Count) nights"; d=$nights}, @{n="Oct 21-28 ($($half1.Count) nights)"; d=$half1}, @{n="Oct 30-Nov 8 ($($half2.Count) nights)"; d=$half2})){
  "== $($set.n)"; foreach($k in $V.Keys){ line $k (card $V[$k] $set.d) }; "" }
# calibration on every side that clears 60% / 5% EV under today's pricing (before the two-a-game cap): bigger sample than the card
"== every side clearing 60% and 5% EV today (no per-game cap): model chance vs hit rate"
$q = @($props | % { $x = price $_ $V["now"]; if($_.odds -ge -150 -and $_.odds -le 150 -and $x.ev -ge .05 -and $x.p -ge .60 -and $_.u -ne 0){ [pscustomobject]@{ stat=$_.stat; side=$_.side; p=$x.p; y=[int]($_.u -gt 0); u=$_.u } } })
foreach($g in ($q | Group-Object { "$($_.stat) $($_.side)" } | Sort-Object Count -Descending)){
  "{0,-12} n={1,4}  model {2:P1}  hit {3:P1}  flat {4,7:N2}u" -f $g.Name,$g.Count,($g.Group|Measure-Object p -Average).Average,($g.Group|Measure-Object y -Average).Average,($g.Group|Measure-Object u -Sum).Sum }
foreach($g in ($q | Group-Object side)){ "{0,-12} n={1,4}  model {2:P1}  hit {3:P1}  flat {4,7:N2}u" -f "ALL $($g.Name)",$g.Count,($g.Group|Measure-Object p -Average).Average,($g.Group|Measure-Object y -Average).Average,($g.Group|Measure-Object u -Sum).Sum }
