param([string]$Tag = "dd", [string]$Dir = "tracking\btdd", [double]$Hold = -1)
# Double-double backtest. Joins harness __PX "D" rows (tracking\px-<date>-<tag>.json: the sim's chance of a double-double
# for every player who played) with FanDuel's cached "Player Double Double" Yes prices (raw\fd_<fdId>_player-combos.json,
# the last pregame build's fetch) and the actual result, then:
#   1. fits the market's hold (FanDuel posts only the Yes side, so the no-vig chance has to assume a margin),
#   2. fits the sim/market log-odds blend weight leave-one-night-out, the same way fit-blend.ps1 does for props,
#   3. grades the bets the card rules would have taken under a few rule sets, each night priced with weights from the others.
# Writes tracking\dd-eval-<tag>.json (every matched row with its blended chance) and prints the summary.
$ErrorActionPreference = "Stop"
$root = Split-Path $PSScriptRoot -Parent; $trk = Join-Path $root "tracking"; $raw = Join-Path $root "raw"; $dd = Join-Path $root $Dir
function Norm([string]$s){ ($s.Normalize([Text.NormalizationForm]::FormD) -replace '\p{Mn}','').ToLower() -replace "[.'\-,]"," " -replace '\b(jr|sr|ii|iii|iv)\b','' -replace '\s+',' ' | % { $_.Trim() } }
function Impl([double]$o){ if($o -gt 0){ 100/($o+100) } else { -$o/(-$o+100) } }
function Dec([double]$o){ if($o -gt 0){ 1+$o/100 } else { 1+100/(-$o) } }
function Lgt([double]$p){ $p=[math]::Min(.998,[math]::Max(.002,$p)); [math]::Log($p/(1-$p)) }
function Sgm([double]$x){ 1/(1+[math]::Exp(-$x)) }
$rows = New-Object Collections.ArrayList
foreach($f in Get-ChildItem $trk -Filter "px-*-$Tag.json" | Sort-Object Name){
  if($f.Name -notmatch '^px-(\d{8})-'){ continue }; $d = $matches[1]
  $s = [IO.File]::ReadAllText((Join-Path $dd "slate-$d.json")) | ConvertFrom-Json
  $fd = @{}
  foreach($g in $s.games){ $ff = Join-Path $raw "fd_$($g.fdId)_player-combos.json"; if(-not $g.fdId -or -not (Test-Path $ff)){ continue }
    $j = [IO.File]::ReadAllText($ff) | ConvertFrom-Json
    foreach($m in $j.attachments.markets.PSObject.Properties.Value){ if($m.marketType -ne 'TO_RECORD_A_DOUBLE_DOUBLE'){ continue }
      foreach($ru in $m.runners){ if($ru.runnerStatus -ne 'ACTIVE'){ continue }; $o = $ru.winRunnerOdds.americanDisplayOdds.americanOdds
        if($o -ne $null){ $fd["$($g.espnId)|$(Norm $ru.runnerName)"] = [double]$o } } } }
  # (PowerShell 5's ConvertFrom-Json emits a JSON array as ONE object, so filter inside the loop, not with a pipeline)
  $arr = [IO.File]::ReadAllText($f.FullName) | ConvertFrom-Json
  foreach($x in $arr){ if($x.k -ne 'D'){ continue }
    $o = $fd["$($x.gid)|$(Norm $x.player)"]; if($o -eq $null){ continue }
    [void]$rows.Add([pscustomobject]@{ d=$d; gid=$x.gid; player=$x.player; odds=$o; q=(Impl $o); pS=[double]$x.pSim; a=[int]$x.a; min=[double]$x.min; start=$x.start
      shaky=($x.why.q -or $x.why.prior -or $x.why.y24); curG=[int]$x.curG; curDD=[int]$x.curDD; pts=$x.pts; reb=$x.reb; ast=$x.ast; line=$x.line }) }
}
$n = $rows.Count; $nights = @($rows | % d | Sort-Object -Unique)
"Matched $n FanDuel double-double prices over $($nights.Count) nights; $(@($rows | ? a -eq 1).Count) hit ($([math]::Round(100*@($rows | ? a -eq 1).Count/[math]::Max(1,$n),1))%)."
function LL($set,[double]$h,[double]$w){ $s=0.0; foreach($r in $set){ $pm=$r.q/(1+$h); $p=Sgm ((1-$w)*(Lgt $pm) + $w*(Lgt $r.pS)); $s -= if($r.a){ [math]::Log($p) } else { [math]::Log(1-$p) } }; $s/[math]::Max(1,@($set).Count) }
# 1. the market's hold: the margin that makes FanDuel's Yes prices best predict what happened
if($Hold -lt 0){ $best=1e9; foreach($h in 0..80 | % { $_/100 }){ $v = LL $rows $h 0; if($v -lt $best){ $best=$v; $Hold=$h } } }
$avgQ = ($rows | measure q -Average).Average; $rate = @($rows | ? a -eq 1).Count/$n
"Market: average Yes price implies $([math]::Round(100*$avgQ,1))%, actual $([math]::Round(100*$rate,1))%; best-fit hold $([math]::Round(100*$Hold))%."
# 2. blend weight, all nights and leave-one-night-out
$Wgrid = 0..20 | % { $_/20 }  # (not $W: PowerShell names are case-insensitive, so $W and $w would be one variable)
$fit = foreach($w in $Wgrid){ [pscustomobject]@{ w=$w; ll=(LL $rows $Hold $w) } }
$wAll = ($fit | Sort-Object ll | Select-Object -First 1).w
"Log loss: market only $([math]::Round(($fit | ? w -eq 0).ll,4)), sim only $([math]::Round(($fit | ? w -eq 1).ll,4)), best blend w=$wAll $([math]::Round(($fit | Sort-Object ll | Select-Object -First 1).ll,4))."
$wOf = @{}; foreach($d in $nights){ $tr = @($rows | ? d -ne $d); $b=1e9; foreach($w in $Wgrid){ $v = LL $tr $Hold $w; if($v -lt $b){ $b=$v; $wOf[$d]=$w } } }
"Leave-one-night-out weights: " + (($nights | % { "$($_.Substring(4)):$($wOf[$_])" }) -join " ")
$oos = 0.0; $mk = 0.0
foreach($r in $rows){ $w = $wOf[$r.d]; $pm=$r.q/(1+$Hold); $p = Sgm ((1-$w)*(Lgt $pm) + $w*(Lgt $r.pS))
  $r | Add-Member p $p -Force; $r | Add-Member pm $pm -Force; $r | Add-Member ev ($p*(Dec $r.odds)-1) -Force
  $oos -= if($r.a){ [math]::Log($p) } else { [math]::Log(1-$p) }; $mk -= if($r.a){ [math]::Log($pm) } else { [math]::Log(1-$pm) } }
"Out-of-sample log loss: blend $([math]::Round($oos/$n,4)) vs market $([math]::Round($mk/$n,4)) (lower is better)."
# Recalibrated blend: logistic regression on [1, logit(FanDuel's raw Yes chance), logit(sim)], fitted by Newton's method,
# leave-one-night-out. It corrects the market's margin and the sim's overconfidence at once. Uses fields pc (chance) and evc.
function FitLR($set){ $b=@(0.0,1.0,0.0)
  for($it=0;$it -lt 30;$it++){ $g=@(0.0,0.0,0.0); $H=New-Object 'double[,]' 3,3
    foreach($r in $set){ $x=@(1.0,(Lgt $r.q),(Lgt $r.pS)); $p=Sgm ($b[0]*$x[0]+$b[1]*$x[1]+$b[2]*$x[2]); $e=$r.a-$p; $v=$p*(1-$p)
      for($i=0;$i -lt 3;$i++){ $g[$i]+=$e*$x[$i]; for($k=0;$k -lt 3;$k++){ $H[$i,$k]+=$v*$x[$i]*$x[$k] } } }
    for($i=0;$i -lt 3;$i++){ $H[$i,$i]+=1e-6 }
    # solve H d = g (3x3, Gaussian elimination)
    $A=New-Object 'double[,]' 3,4; for($i=0;$i -lt 3;$i++){ for($k=0;$k -lt 3;$k++){ $A[$i,$k]=$H[$i,$k] }; $A[$i,3]=$g[$i] }
    for($c=0;$c -lt 3;$c++){ for($i=$c+1;$i -lt 3;$i++){ $fct=$A[$i,$c]/$A[$c,$c]; for($k=$c;$k -lt 4;$k++){ $A[$i,$k]-=$fct*$A[$c,$k] } } }
    $dl=@(0.0,0.0,0.0); for($i=2;$i -ge 0;$i--){ $s=$A[$i,3]; for($k=$i+1;$k -lt 3;$k++){ $s-=$A[$i,$k]*$dl[$k] }; $dl[$i]=$s/$A[$i,$i] }
    for($i=0;$i -lt 3;$i++){ $b[$i]+=$dl[$i] }
    if([math]::Abs($dl[0])+[math]::Abs($dl[1])+[math]::Abs($dl[2]) -lt 1e-7){ break } }
  ,$b }
function FitMk($set){ # market alone, recalibrated: [1, logit(q)]  (sim coefficient pinned at 0 by fitting on pS = 0.5)
  ,(FitLR @($set | % { [pscustomobject]@{ q=$_.q; pS=0.5; a=$_.a } })) }
$all = FitLR $rows
"Recalibrated fit on all nights: intercept $([math]::Round($all[0],2)), market $([math]::Round($all[1],2)), sim $([math]::Round($all[2],2))."
$llc=0.0; $llm=0.0
foreach($d in $nights){ $tr=@($rows | ? d -ne $d); $b=FitLR $tr; $bm=FitMk $tr
  foreach($r in @($rows | ? d -eq $d)){ $pc=Sgm ($b[0]+$b[1]*(Lgt $r.q)+$b[2]*(Lgt $r.pS)); $pmc=Sgm ($bm[0]+$bm[1]*(Lgt $r.q))
    $r | Add-Member pc $pc -Force; $r | Add-Member pmc $pmc -Force; $r | Add-Member evc ($pc*(Dec $r.odds)-1) -Force
    $llc -= if($r.a){ [math]::Log($pc) } else { [math]::Log(1-$pc) }; $llm -= if($r.a){ [math]::Log($pmc) } else { [math]::Log(1-$pmc) } } }
"Out-of-sample log loss, recalibrated: market + sim $([math]::Round($llc/$n,4)) vs market alone $([math]::Round($llm/$n,4))."
# calibration of the sim alone and the blend
"Calibration (sim alone | blended), by predicted chance:"
foreach($b in @(@(0,.1),@(.1,.25),@(.25,.4),@(.4,.55),@(.55,.7),@(.7,1.01))){
  $s1 = @($rows | ? { $_.pS -ge $b[0] -and $_.pS -lt $b[1] }); $s2 = @($rows | ? { $_.p -ge $b[0] -and $_.p -lt $b[1] })
  $f = { param($s,$k) if(-not $s.Count){ "   -   " } else { "{0,3} said {1,4:P0} won {2,4:P0}" -f $s.Count, (($s | measure $k -Average).Average), (@($s | ? a -eq 1).Count/$s.Count) } }
  "  {0,3:P0}-{1,4:P0}:  {2}  |  {3}" -f $b[0], [math]::Min(1.0,[double]$b[1]), (& $f $s1 'pS'), (& $f $s2 'p') }
# 3. what the card would have bet
function Grade($name,$sel){ $s=@($sel | ? { $_ }); $w=@($s | ? a -eq 1).Count; $u=0.0; foreach($r in $s){ $u += if($r.a){ (Dec $r.odds)-1 } else { -1 } }
  "  {0,-46} {1,3} bets  {2,3}-{3,-3} {4,7:+0.00;-0.00}u  ROI {5,6:+0.0;-0.0}%  avg p {6:P0}, avg price {7}" -f $name, $s.Count, $w, ($s.Count-$w), $u, (100*$u/[math]::Max(1,$s.Count)), (($s | measure p -Average).Average), [math]::Round((($s | measure odds -Average).Average)) }
$band = @($rows | ? { $_.odds -ge -150 -and $_.odds -le 150 -and -not $_.shaky })
"Bets each rule set would have taken (flat 1u, Yes side, FanDuel price, shaky players excluded):"
Grade "Current card rules (60%+, 5%+ edge, -150..+150)" ($band | ? { $_.p -ge .60 -and $_.ev -ge .05 })
Grade "5%+ edge, -150..+150, any chance" ($band | ? { $_.ev -ge .05 })
Grade "10%+ edge, -150..+150" ($band | ? { $_.ev -ge .10 })
Grade "50%+ chance, 5%+ edge, -150..+150" ($band | ? { $_.p -ge .50 -and $_.ev -ge .05 })
Grade "Sim alone 5%+ edge at the price, -150..+150" ($band | ? { $_.pS*(Dec $_.odds)-1 -ge .05 })
Grade "Every Yes in -150..+150 (the market baseline)" $band
Grade "Recalibrated: 5%+ edge, -150..+150" ($band | ? { $_.evc -ge .05 })
Grade "Recalibrated: 5%+ edge, any price (shaky out)" ($rows | ? { -not $_.shaky -and $_.evc -ge .05 })
Grade "Recalibrated: 50%+ chance, 5%+ edge, -150..+150" ($band | ? { $_.pc -ge .50 -and $_.evc -ge .05 })
"If a No side existed at the same margin (FanDuel posts none; this is only a check of the sim's direction):"
Grade "  'No' where the sim is 10+ pts below FanDuel's raw price" ($band | ? { $_.pS -le $_.q - .10 } | % { [pscustomobject]@{ a=1-$_.a; odds=-110; p=1-$_.pS } })
"Top edges taken under '5%+ edge, -150..+150':"
$band | ? { $_.ev -ge .05 } | Sort-Object ev -Descending | Select-Object -First 12 | % { "  {0} {1,-24} {2,5} sim {3:P0} blend {4:P0} edge {5,5:P0}  {6}" -f $_.d, $_.player, $_.odds, $_.pS, $_.p, $_.ev, $(if($_.a){"YES ($($_.line.PTS)/$($_.line.REB)/$($_.line.AST))"}else{"no ($($_.line.PTS)/$($_.line.REB)/$($_.line.AST))"}) }
[IO.File]::WriteAllText((Join-Path $trk "dd-eval-$Tag.json"), (@{ hold=$Hold; wAll=$wAll; wLono=$wOf; rows=@($rows) } | ConvertTo-Json -Depth 6 -Compress))
