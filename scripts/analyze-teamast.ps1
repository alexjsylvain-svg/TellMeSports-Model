param([string]$Trk = "tracking", [string]$Tag = "", [string[]]$Dates = @())
# Team assists, sim vs real, from tracking\ta-<date>[-tag].json (harness.js __TA): bias, assisted share, whether a team's error
# persists from game to game, and whether it follows how much the lineup passes (creator density = minutes-weighted AST%)
$rows = @()
foreach($f in Get-ChildItem $Trk -Filter "ta-*.json" | ? { if($Tag){ $_.Name -like "*-$Tag.json" } else { $_.Name -match '^ta-\d{8}\.json$' } } | ? { -not $Dates.Count -or $Dates -contains $_.Name.Substring(3,8) } | Sort-Object Name){
  foreach($t in (Get-Content $f.FullName -Raw | ConvertFrom-Json)){
    $pl = @($t.players)
    # creator density: on-floor assist share, minutes-weighted (sum of AST% x min / 240)
    $dens = ($pl | % { $_.astPct * $_.simMin } | Measure-Object -Sum).Sum / 240
    $mvF = ($pl | ? moved | % simFgm | Measure-Object -Sum).Sum / [math]::Max(0.01, $t.simFgm)
    $rows += [pscustomobject]@{ d=$t.d; team=$t.team; sa=$t.simAst; ra=$t.realAst; sf=$t.simFgm; rf=$t.realFgm; ss=$t.simAst/$t.simFgm; rs=$t.realAst/[math]::Max(1,$t.realFgm); dens=$dens; moved=$mvF } } }
"team-games: $($rows.Count)"
$e = $rows | % { $_.sa - $_.ra }; "assists sim-real: mean {0:N2}  MAE {1:N2}" -f ($e|Measure-Object -Average).Average, (($e|%{[math]::Abs($_)})|Measure-Object -Average).Average
$es = $rows | % { $_.ss - $_.rs }; "assisted share sim-real: mean {0:N3}  MAE {1:N3}" -f ($es|Measure-Object -Average).Average, (($es|%{[math]::Abs($_)})|Measure-Object -Average).Average
$ef = $rows | % { $_.sf - $_.rf }; "FGM sim-real: mean {0:N2}" -f ($ef|Measure-Object -Average).Average
function corr($x,$y){ $n=$x.Count; $mx=($x|Measure-Object -Average).Average; $my=($y|Measure-Object -Average).Average; $sxy=0;$sxx=0;$syy=0; for($i=0;$i -lt $n;$i++){ $sxy+=($x[$i]-$mx)*($y[$i]-$my); $sxx+=($x[$i]-$mx)*($x[$i]-$mx); $syy+=($y[$i]-$my)*($y[$i]-$my) }; if($sxx -le 0 -or $syy -le 0){ return 0 }; $sxy/[math]::Sqrt($sxx*$syy) }
# persistence: a team's share error in one game vs its mean share error in its other games (leave one out)
$x=@();$y=@()
foreach($r in $rows){ $o = @($rows | ? { $_.team -eq $r.team -and $_.d -ne $r.d }); if($o.Count -lt 2){ continue }; $x += ($o | % { $_.ss - $_.rs } | Measure-Object -Average).Average; $y += $r.ss - $r.rs }
"persistence (share error vs same team's other games): r={0:N2} over {1} team-games" -f (corr $x $y), $x.Count
"share error vs creator density: r={0:N2}" -f (corr @($rows|%{$_.dens}) @($rows|%{$_.ss-$_.rs}))
"share error vs moved-player share of makes: r={0:N2}" -f (corr @($rows|%{$_.moved}) @($rows|%{$_.ss-$_.rs}))
"assist error vs FGM error: r={0:N2}" -f (corr @($rows|%{$_.sf-$_.rf}) @($rows|%{$_.sa-$_.ra}))
""
"by team (games, sim/real assists, sim/real assisted share, FGM sim/real):"
$rows | Group-Object team | % { $g=$_.Group; [pscustomobject]@{ team=$_.Name; n=$g.Count; simAst=[math]::Round(($g|% sa|Measure-Object -Average).Average,1); realAst=[math]::Round(($g|% ra|Measure-Object -Average).Average,1);
  simShare=[math]::Round(($g|% ss|Measure-Object -Average).Average,3); realShare=[math]::Round(($g|% rs|Measure-Object -Average).Average,3); simFgm=[math]::Round(($g|% sf|Measure-Object -Average).Average,1); realFgm=[math]::Round(($g|% rf|Measure-Object -Average).Average,1); dens=[math]::Round(($g|% dens|Measure-Object -Average).Average,1) } } | Sort-Object { $_.simShare - $_.realShare } | Format-Table -AutoSize | Out-String -Width 200
