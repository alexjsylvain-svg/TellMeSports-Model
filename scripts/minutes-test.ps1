# Offline minutes-projection screen (Nov 11, after Zubac U25.5 PRA: projected 23 min, played 31).
# Rebuilds the page's pregame minutes for every player who played on every archived night (projMin from last season,
# then buildPlayer's this-season blend w = g/(g+1.5) for a player in the same role), tries alternatives, and scores each
# against actual minutes. No team-total rescaling, so compare variants with each other, not with board minutes.
# Variants:
#   current      the page's formula (K = 1.5)
#   K3 / K6      this season counts less: w = g/(g+3), g/(g+6)
#   last3/last5  this season's minutes = average of his last 3 / 5 games instead of the season average
#   noShort      season average without games under 50% of his median (injury exits, ejections)
#   mkt50        50/50 with the minutes the market's PRA (else PTS) line implies at his per-minute rate
#   mkt          the market-implied minutes alone (where a line exists)
# Halves: A = through Nov 1, B = after. Read-only.
param([string]$Trk = "tracking")
$root = Split-Path $PSScriptRoot -Parent; if(-not [IO.Path]::IsPathRooted($Trk)){ $Trk = Join-Path $root $Trk }
function Nrm([string]$x){ ($x.Normalize([Text.NormalizationForm]::FormD) -replace '\p{Mn}','').ToLower() -replace "[.'\-,]"," " -replace '\b(jr|sr|ii|iii|iv)\b','' -replace '\s+',' ' | % { $_.Trim() } }
function ClampV($x,$a,$b){ [math]::Min($b,[math]::Max($a,$x)) }
function Med($a){ $q=@($a | Sort-Object); if(!$q.Count){ return $null }; $n=$q.Count; if($n%2){ $q[($n-1)/2] } else { ($q[$n/2-1]+$q[$n/2])/2 } }
$pairs = @()
foreach($dir in @((Join-Path $Trk "btc"), $Trk)){ foreach($sf in Get-ChildItem $dir -Filter "slate-2026????.json"){ $d = $sf.BaseName -replace 'slate-',''
  $ff = Join-Path $dir "finals-$d.json"; if((Test-Path $ff) -and -not ($pairs | ? { $_.d -eq $d })){ $pairs += [pscustomobject]@{ d=$d; s=$sf.FullName; f=$ff } } } }
$out = New-Object System.Collections.ArrayList
foreach($pr in ($pairs | Sort-Object d)){
  $d = $pr.d; $sl = Get-Content $pr.s -Raw -Encoding UTF8 | ConvertFrom-Json; $fn = Get-Content $pr.f -Raw -Encoding UTF8 | ConvertFrom-Json
  $act = @{}; foreach($g in $fn.games){ if($g.state -ne 'post'){ continue }; foreach($t in $g.teams){ foreach($p in $t.players){ if(-not $p.dnp -and $p.MIN -gt 0){ $act[(Nrm $p.name)] = [double]$p.MIN } } } }
  $mline = @{}
  foreach($g in $sl.games){ foreach($src in @($g.props) + @($g.fanProps)){ if(-not $src){ continue }; $k = Nrm $src.player
    if($src.stat -eq 'PRA'){ $mline["$k|PRA"] = [double]$src.line } elseif($src.stat -eq 'PTS'){ $mline["$k|PTS"] = [double]$src.line } } }
  foreach($tm in $sl.teams.PSObject.Properties){ foreach($p in $tm.Value.players){
    $k = Nrm $p.name; if(-not $act.ContainsKey($k)){ continue }
    $s = $p.s; $c = $p.cur; $st = [bool]$p.rwStarter
    # projMin on the merged seasons
    $mpg=$null; $gg=0; $yr=$null
    if($s -and $s.mpg -ne $null){ $mpg=[double]$s.mpg; $gg=[double]$s.g; $yr=$s.yr
      if($s.prev -and $s.prev.mpg){ $wa=$gg*$mpg; $wb=.7*[double]$s.prev.g*[double]$s.prev.mpg; if($wa+$wb -gt 0){ $mpg=($mpg*$wa+[double]$s.prev.mpg*$wb)/($wa+$wb) }; $gg=$gg+.7*[double]$s.prev.g; $yr="mix" } }
    if($mpg -ne $null){ $rel=[math]::Min(1.0,$gg/30); $m=$mpg*$rel+$(if($st){28}else{11})*(1-$rel) } else { $m=$(if($st){27}else{9}) }
    $m = if($st){ ClampV $m 26 37.5 } else { ClampV $m 0 30 }
    if($yr -eq "2024-25"){ $m=[math]::Min($m,$(if($st){32}else{20})) }
    $base = $m
    $logs = @($c.log | ? { $_ -and $_.d -lt $d -and $_.min -ne $null } | Sort-Object d)
    $cg = if($c){ [double]$c.g } else { 0 }
    $same = $cg -gt 0 -and $(if($st){ [double]$c.gs/$cg -ge .5 } else { [double]$c.gs/$cg -lt .5 })
    $lo = if($st){20}else{0}; $hi = if($st){38}else{32}
    $blend = { param($cm,$n,$K) if($same -and $n -gt 0 -and $cm -ne $null){ $w=$n/($n+$K); ClampV ($w*$cm+(1-$w)*$base) $lo $hi } else { $base } }
    $mins = @($logs | % { [double]$_.min }); $md = Med $mins
    $l3 = if($mins.Count){ ($mins | Select-Object -Last 3 | Measure-Object -Average).Average } else { $null }
    $l5 = if($mins.Count){ ($mins | Select-Object -Last 5 | Measure-Object -Average).Average } else { $null }
    $keep = @($mins | ? { -not $md -or $_ -ge .5*$md }); $ns = if($keep.Count){ ($keep | Measure-Object -Average).Average } else { $null }
    $cur = & $blend $(if($c){[double]$c.min}else{$null}) $cg 1.5
    # market-implied minutes: line / per-minute rate (last season blended with this season by minutes, like the page)
    $impl = $null
    if($s -and $s.mpg -ge 8){ $rL = ([double]$s.pts+[double]$s.trb+[double]$s.ast)/[double]$s.mpg; $rP = [double]$s.pts/[double]$s.mpg
      $cm = if($c){ [double]$c.min*$cg } else { 0 }
      if($cm -ge 20){ $wr=$cm/($cm+150); $rL = $wr*(([double]$c.pts+[double]$c.reb+[double]$c.ast)/[double]$c.min)+(1-$wr)*$rL; $rP = $wr*([double]$c.pts/[double]$c.min)+(1-$wr)*$rP }
      if($mline["$k|PRA"] -and $rL -gt 0){ $impl = $mline["$k|PRA"]/$rL } elseif($mline["$k|PTS"] -and $rP -gt 0){ $impl = $mline["$k|PTS"]/$rP }
      if($impl){ $impl = ClampV $impl 4 42 } }
    [void]$out.Add([pscustomobject]@{ d=$d; half=$(if($d -le "20261101"){"A"}else{"B"}); player=$p.name; st=$st; act=$act[$k]; g=$cg; hasMkt=($impl -ne $null)
      current=$cur; K3=(& $blend $(if($c){[double]$c.min}else{$null}) $cg 3); K6=(& $blend $(if($c){[double]$c.min}else{$null}) $cg 6)
      last3=(& $blend $l3 $cg 1.5); last5=(& $blend $l5 $cg 1.5); noShort=(& $blend $ns $keep.Count 1.5)
      mkt50=$(if($impl){ .5*$cur+.5*$impl }else{ $cur }); mkt=$(if($impl){ $impl }else{ $cur }) }) } } }
$V = "current","K3","K6","last3","last5","noShort","mkt50","mkt"
function Score($set,$label){ $q=@($set); if(!$q.Count){ return }
  "{0,-44} n={1,5}" -f $label,$q.Count
  foreach($v in $V){ $res = foreach($h in "all","A","B"){ $z=@($q | ? { $h -eq "all" -or $_.half -eq $h }); if($z.Count){ $mae=($z | % { [math]::Abs($_.act-$_.$v) } | Measure-Object -Average).Average; $big=@($z | ? { [math]::Abs($_.act-$_.$v) -ge 6 }).Count/$z.Count; "{0,4:0.00} ({1,3:P0})" -f $mae,$big } else { "   -      " } }
    $bias=($q | % { $_.act-$_.$v } | Measure-Object -Average).Average
    "    {0,-9} avg miss all {1}  | A {2}  | B {3}   actual-proj {4,5:+0.0;-0.0}" -f $v,$res[0],$res[1],$res[2],$bias } }
"Nights: $(@($out | % d | Sort-Object -Unique).Count) ($(@($out|% d|Sort-Object)[0])-$(@($out|% d|Sort-Object)[-1])). Avg miss in minutes (share missed by 6+ in brackets).`n"
Score ($out | ? { $_.st -and $_.g -ge 3 }) "STARTERS with 3+ games this season"
""
Score ($out | ? { $_.st -and $_.g -ge 3 -and $_.hasMkt }) "  same, only players with a market PRA/PTS line"
""
Score ($out | ? { -not $_.st -and $_.g -ge 3 -and $_.hasMkt }) "BENCH with 3+ games and a market line"
$out | Export-Csv (Join-Path $Trk "minutes-test.csv") -NoTypeInformation
