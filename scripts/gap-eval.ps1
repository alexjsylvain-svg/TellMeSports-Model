param([string]$Tag = "nov9", [string]$Trk = "tracking")
# Nov 11 (after Zubac U25.5 PRA lost at 33): when the sim disagrees with the market by a lot on a points-type under, is
# the sim right or is it missing something (minutes, role)? Reads the priced sides dumped by harness __PXB
# (tracking\px-<date>-<Tag>.json), prices them with the page's blend, applies the card's player rules, and splits
# results by the gap between the sim's and the market's win chance. Read-only.
$root = Split-Path $PSScriptRoot -Parent; if(-not [IO.Path]::IsPathRooted($Trk)){ $Trk = Join-Path $root $Trk }
function cl($x){ [math]::Min(.99,[math]::Max(.01,$x)) }
function lgt($x){ $x=cl $x; [math]::Log($x/(1-$x)) }
function sg($x){ 1/(1+[math]::Exp(-$x)) }
function dec($o){ if($o -gt 0){ 1+$o/100 } else { 1+100/(-$o) } }
function stake($p){ if($p -ge .66){2} elseif($p -ge .64){1.5} else {.5} }
$SWT = @{ PTS=.05; REB=0; AST=.65; "3PM"=.75; PRA=.50; PR=0; PA=.15; RA=.20; DD=.15 }
$mid = "20261029"
$all = New-Object System.Collections.ArrayList
foreach($f in Get-ChildItem $Trk -Filter "px-*-$Tag.json" | Sort-Object Name){ foreach($r in (Get-Content $f.FullName -Raw | ConvertFrom-Json)){
  if($r.k -ne "P" -or $r.u -eq $null){ continue }
  $ok = $r.rule -and -not ($r.stat -eq "PRA" -and $r.side -eq "Over") -and -not $r.why.mis -and -not $r.why.q -and -not (($r.why.prior -or $r.why.y24) -and $r.curG -lt 3)
  $wt = [math]::Min(1.0, $SWT[[string]$r.stat]*$(if($r.bench){.8}else{1}))
  $p = (sg ((1-$wt)*(lgt $r.pm)+$wt*(lgt $r.pSim)))*(1-[double]$r.push); $pl=[math]::Max(0.0,1-$p-[double]$r.push)
  $ev = $p*((dec ([double]$r.odds))-1)-$pl
  [void]$all.Add([pscustomobject]@{ d=$r.d; half=$(if($r.d -le $mid){"A"}else{"B"}); gid=$r.gid; player=$r.player; stat=[string]$r.stat; side=$r.side; line=[double]$r.line; odds=[double]$r.odds
    pm=[double]$r.pm; pSim=[double]$r.pSim; gap=[double]$r.pSim-[double]$r.pm; p=$p; ev=$ev; u=[double]$r.u; ok=$ok
    card=($ok -and $r.odds -ge -150 -and $r.odds -le 150 -and $p -ge .60 -and $ev -ge .05) }) } }
$nights = @($all | ForEach-Object d | Sort-Object -Unique)
"Nights: $($nights.Count) ($($nights[0])-$($nights[-1])). Halves: A = Oct 21-29, B = Oct 30-Nov 8."
""
function rec($set){ $s=@($set | Where-Object { $_.u -ne 0 }); if(!$s.Count){ return "n=0" }; $w=@($s|Where-Object{$_.u -gt 0}).Count
  "{0,3}-{1,-3} won {2,4:P0} | market said {3,4:P0}, sim {4,4:P0}, blend {5,4:P0}" -f $w,($s.Count-$w),($w/$s.Count),(($s|Measure-Object pm -Average).Average),(($s|Measure-Object pSim -Average).Average),(($s|Measure-Object p -Average).Average) }
$BK = @(@(-1.0,.10,"under 10 pts"),@(.10,.20,"10-20 pts"),@(.20,.30,"20-30 pts"),@(.30,1.0,"30+ pts"))
foreach($grp in @(@("PRA unders","PRA"),@("PR/PA/RA unders","PR","PA","RA"),@("PTS unders","PTS"),@("AST unders (for comparison)","AST"))){
  $name=$grp[0]; $stats=$grp[1..($grp.Count-1)]
  "== $name, every priced side with the card's player rules, by how far the sim sat above the market =="
  foreach($b in $BK){ $s=@($all | Where-Object { $_.ok -and $_.side -eq 'Under' -and $_.stat -in $stats -and $_.gap -ge $b[0] -and $_.gap -lt $b[1] })
    "  sim above market by {0,-12} {1}" -f $b[2],(rec $s) }
  "" }
"== PRA unders that cleared the card's bar (60%+, 5%+ edge, -150..+150), by gap and half =="
foreach($b in $BK){ foreach($h in "A","B"){ $s=@($all | Where-Object { $_.card -and $_.side -eq 'Under' -and $_.stat -eq 'PRA' -and $_.half -eq $h -and $_.gap -ge $b[0] -and $_.gap -lt $b[1] })
  $st = ($s | ForEach-Object { $_.u*(stake $_.p) } | Measure-Object -Sum).Sum
  "  gap {0,-12} half {1}: {2}  staked {3,5:+0.0;-0.0}u" -f $b[2],$h,(rec $s),$st } }
""
"PRA-under card picks with the sim 20+ points above the market:"
$all | Where-Object { $_.card -and $_.side -eq 'Under' -and $_.stat -eq 'PRA' -and $_.gap -ge .20 } | Sort-Object d | ForEach-Object {
  "  {0} {1,-24} U{2,-5} {3,5}  market {4:P0} sim {5:P0} blend {6:P0}  {7}" -f $_.d,$_.player,$_.line,$_.odds,$_.pm,$_.pSim,$_.p,$(if($_.u -gt 0){"won"}elseif($_.u -lt 0){"LOST"}else{"push/void"}) }
