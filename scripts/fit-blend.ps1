param([string]$Trk = "tracking", [string]$W = "", [string]$Tag = "", [switch]$StatRule)
# -StatRule: grade today's card rules (no 3PM, no AST overs) with and without "one pick per stat per game"
# Refit the blend's sim weight per stat (blend() STAT_W) on every night dumped by __PX (tracking\px-<date>.json), and
# grade the picks each weight set would have made. -W "PTS=.4,REB=.25,AST=.65,3PM=.75,PRA=.5" adds a set to grade.
$root = Split-Path $PSScriptRoot -Parent; if(-not [IO.Path]::IsPathRooted($Trk)){ $Trk = Join-Path $root $Trk }
$rows = @(); $pxf = if($Tag){ Get-ChildItem $Trk -Filter "px-*-$Tag.json" } else { Get-ChildItem $Trk -Filter "px-*.json" | ? { $_.Name -match "^px-\d{8}\.json$" } }
foreach($f in $pxf | Sort-Object Name){ foreach($r in (Get-Content $f.FullName -Raw | ConvertFrom-Json)){ $rows += $r } }
$nights = @($rows | % d | Sort-Object -Unique)
function cl($x){ [math]::Min(.99,[math]::Max(.01,$x)) }
function lg($x){ $x=cl $x; [math]::Log($x/(1-$x)) }
function sg($x){ 1/(1+[math]::Exp(-$x)) }
function dec($o){ if($o -gt 0){ 1+$o/100 } else { 1+100/(-$o) } }
$stats = "PTS","REB","AST","3PM","PRA","PR","PA","RA"
$cur = @{ PTS=.05; REB=0; AST=.65; "3PM"=.75; PRA=.50; PR=.50; PA=.50; RA=.50 }
# fitting rows: one per prop (the over side), no push, no role-mismatch players
$fit = @($rows | ? { $_.k -eq "P" -and $_.side -eq "Over" -and $_.a -ne $_.line -and -not $_.why.mis } | % {
  [pscustomobject]@{ d=$_.d; stat=$_.stat; lm=(lg $_.pm); ls=(lg $_.pSim); b=$(if($_.bench){.8}else{1}); y=$(if($_.a -gt $_.line){1}else{0}) } })
function loss($set, $w){ $s=0.0; foreach($r in $set){ $p=sg ((1-$w*$r.b)*$r.lm + $w*$r.b*$r.ls); $p=cl $p; $s += -($r.y*[math]::Log($p) + (1-$r.y)*[math]::Log(1-$p)) }; $s }
$grid = 0..20 | % { $_/20 }
function best($set){ $bw=0; $bl=1e18; foreach($w in $grid){ $l=loss $set $w; if($l -lt $bl){ $bl=$l; $bw=$w } }; $bw }
"nights: $($nights -join ', ')   props fitted: $($fit.Count)"
""
"stat  props  now   fit-all  log loss per prop: market / now / fit-all   held-out (fit on the other nights): now / refit   refit weights by held-out night"
$fitW = @{}
foreach($st in $stats){ $set=@($fit | ? stat -eq $st); if(-not $set.Count){ continue }
  $wa = best $set; $fitW[$st]=$wa
  $ln=0.0; $lr=0.0; $ws=@()
  foreach($d in $nights){ $te=@($set | ? d -eq $d); if(-not $te.Count){ continue }; $tr=@($set | ? d -ne $d); $wd = best $tr; $ws += $wd; $ln += loss $te $cur[$st]; $lr += loss $te $wd }
  $n=$set.Count
  "{0,-4} {1,6}  {2,4:N2}  {3,6:N2}    {4:N4} / {5:N4} / {6:N4}                         {7:N4} / {8:N4}            {9}" -f $st,$n,$cur[$st],$wa,((loss $set 0)/$n),((loss $set $cur[$st])/$n),((loss $set $wa)/$n),($ln/$n),($lr/$n),(($ws|%{"{0:N2}" -f $_}) -join " ") }
""
# pick backtest: re-price every prop side under a weight set, then gamePicks' rules (60%+, 5%+ EV, -150..+150, two a game, one per player and stat)
$side = @($rows | ? k -eq "P" | % { [pscustomobject]@{ d=$_.d; gid=$_.gid; player=$_.player; stat=$_.stat; side=$_.side; odds=$_.odds; lm=(lg $_.pm); ls=(lg $_.pSim); push=$_.push; b=$(if($_.bench){.8}else{1});
  rule=$_.rule; why=$_.why; curG=$_.curG; u=$_.u; bet="$($_.player) $($_.side.ToLower()) $($_.line) $($_.stat)" } })
$games = @($rows | ? k -eq "G")
function picks($w, [int]$minG){
  $all=@()
  foreach($grp in ($side | Group-Object d,gid)){
    $gl = @($games | ? { $_.d -eq $grp.Group[0].d -and $_.gid -eq $grp.Group[0].gid })
    $c = @()
    foreach($r in $grp.Group){ if(-not $r.rule -or $r.why.mis -or $r.why.q -or $w.ContainsKey("skip:"+$r.stat) -or ($w.ContainsKey("noASTo") -and $r.stat -eq "AST" -and $r.side -eq "Over")){ continue }
      if(($r.why.prior -or $r.why.y24) -and ($minG -lt 0 -or $r.curG -lt $minG)){ continue }
      $ww = $w[$r.stat]*$r.b; $p = (sg ((1-$ww)*$r.lm + $ww*$r.ls))*(1-$r.push); $pl=[math]::Max(0.0,1-$p-$r.push); $ev=$p*((dec $r.odds)-1)-$pl
      $c += [pscustomobject]@{ p=$p; ev=$ev; odds=$r.odds; player=$r.player; stat=$r.stat; u=$r.u; bet=$r.bet; d=$r.d; rk=($r.why.prior -or $r.why.y24) } }
    foreach($g in $gl){ $c += [pscustomobject]@{ p=$g.p; ev=$g.ev; odds=$g.odds; player=$null; stat=$g.mkt; u=$g.u; bet=$g.bet; d=$g.d; rk=$false } }
    $pk=@()
    foreach($b in ($c | ? { $_.odds -ge -150 -and $_.odds -le 150 -and $_.ev -ge .05 -and $_.p -ge .60 } | Sort-Object @{e={$_.p};Descending=$true},@{e={$_.ev};Descending=$true})){
      if($pk.Count -ge 2){ break }
      if(@($pk | ? { $_.bet -eq $b.bet -or ($b.player -and ($_.player -eq $b.player -or (-not $w.ContainsKey("anyStat") -and $_.stat -eq $b.stat))) -or (-not $b.player -and -not $_.player) }).Count){ continue }
      $pk += $b }
    $all += $pk }
  $all }
function stake($p){ if($p -ge .66){2} elseif($p -ge .64){1.5} else {.5} }
$global:PK=@{}
function show($name, $w, [int]$minG){
  $pk = @(picks $w $minG); $global:PK[$name]=$pk; $wn=@($pk|?{$_.u -gt 0}).Count; $ls=@($pk|?{$_.u -lt 0}).Count
  $fl=($pk|%{$_.u}|Measure-Object -Sum).Sum; $st=($pk|%{$_.u*(stake $_.p)}|Measure-Object -Sum).Sum
  $by = ($pk | Group-Object { if($_.player){ "$($_.stat) " + $(if($_.bet -match " over "){"o"}else{"u"}) } else { $_.stat } } | Sort-Object Name | % { $g=$_.Group; "{0} {1}-{2}" -f $_.Name,@($g|?{$_.u -gt 0}).Count,@($g|?{$_.u -lt 0}).Count }) -join ", "
  $rk = @($pk | ? rk); $rks = if($rk.Count){ "  rookies/2024-25 players {0}-{1}" -f @($rk|?{$_.u -gt 0}).Count,@($rk|?{$_.u -lt 0}).Count } else { "" }
  "{0,-34} {1,3}-{2,-3} flat {3,6:N2}u  staked {4,6:N2}u   {5}{6}" -f $name,$wn,$ls,$fl,$st,$by,$rks }
$noc = @{}+$cur; foreach($s in "PR","PA","RA"){ $noc["skip:"+$s]=1 }
$sets = [ordered]@{ "no combos" = $noc; "now" = $cur; "refit (all nights)" = $fitW }
if($StatRule){ $c1=@{}+$cur; $c1["skip:3PM"]=1; $c1["noASTo"]=1; $c2=@{}+$c1; $c2["anyStat"]=1; $sets=[ordered]@{ "card now: one pick per stat" = $c1; "card, any stat twice" = $c2 } }
if($W){ $x=@{}; foreach($kv in $W.Split(",")){ $a=$kv.Split("="); $x[$a[0]]=[double]$a[1] }; $sets["custom $W"]=$x }
"refit weights: " + (($stats | % { "$_=$($fitW[$_])" }) -join ", ")
""
foreach($k in $sets.Keys){ $ws=$sets[$k]
  if($Tag){ show "$k (rookies in at 3+ games)" $ws 3 } else { show "$k, rookies out" $ws -1; show "$k, rookies always in" $ws 0
  foreach($m in 2,3,4){ show "$k, rookies in at $m+ games" $ws $m } } }

if($Tag){ foreach($k in $global:PK.Keys){ $global:PK[$k] | Select d,bet,odds,@{n='p';e={[math]::Round($_.p,3)}},u | Export-Csv (Join-Path $Trk ("fit-picks-$Tag-" + ($k -replace '[^\w]+','_') + ".csv")) -NoTypeInformation } }
