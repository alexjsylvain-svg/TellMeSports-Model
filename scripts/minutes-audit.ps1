# Minutes audit (Nov 11): how far the page's projected minutes (board-<date>.json rows' min) missed actual minutes
# (finals-<date>.json, or ESPN for a date without a finals file), and whether short games in a player's season log
# (injury exits, minutes limits on return) drag projections down. Read-only.
#   .\scripts\minutes-audit.ps1 [-Short 0.6]
param([double]$Short = 0.6)   # a log game counts as "short" when its minutes are under this share of his log's median
$root = Split-Path $PSScriptRoot
function Median($a){ $s=@($a | Sort-Object); if(!$s.Count){ return $null }; $n=$s.Count; if($n%2){ $s[($n-1)/2] } else { ($s[$n/2-1]+$s[$n/2])/2 } }
$rows = @()
foreach($bf in Get-ChildItem (Join-Path $root "tracking") -Filter "board-*.json"){
  $d = $bf.BaseName -replace 'board-',''
  $ff = Join-Path $root "tracking\finals-$d.json"
  $act = @{}
  if(Test-Path $ff){ $fin = Get-Content $ff -Raw -Encoding UTF8 | ConvertFrom-Json
    foreach($g in $fin.games){ if($g.state -ne 'post'){ continue }; foreach($t in $g.teams){ foreach($p in $t.players){ if(-not $p.dnp -and $p.MIN -ne $null){ $act["$($t.abbr)|$($p.name)"] = [double]$p.MIN } } } } }
  else {
    $sb = Invoke-RestMethod "https://site.api.espn.com/apis/site/v2/sports/basketball/nba/scoreboard?dates=$d"
    foreach($e in $sb.events){ if($e.status.type.state -ne 'post'){ continue }
      $s = Invoke-RestMethod "https://site.api.espn.com/apis/site/v2/sports/basketball/nba/summary?event=$($e.id)"
      foreach($t in $s.boxscore.players){ $st=$t.statistics[0]; $mi=[array]::IndexOf($st.labels,'MIN')
        foreach($a in $st.athletes){ if($a.stats.Count -and $a.stats[$mi] -match '^\d+$'){ $act["$($t.team.abbreviation)|$($a.athlete.displayName)"] = [double]$a.stats[$mi] } } } } }
  if(!$act.Count){ continue }
  $b = Get-Content $bf.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
  $seen = @{}
  foreach($r in $b.rows){
    $k = "$($r.team)|$($r.player)"; if($seen[$k] -or $r.min -eq $null){ continue }; $seen[$k]=1
    if(-not $act.ContainsKey($k)){ continue }
    $lg0 = if($b.logs){ $b.logs.($r.player) } else { $r.log }; $log = @($lg0 | Where-Object { $_.min -ne $null })
    $mins = @($log | ForEach-Object { [double]$_.min }); $med = Median $mins
    $nShort = if($med){ @($mins | Where-Object { $_ -lt $Short*$med }).Count } else { 0 }
    $last = if($mins.Count){ $mins[-1] } else { $null }
    $rows += [pscustomobject]@{ d=$d; player=$r.player; team=$r.team; start=[bool]$r.start; proj=[double]$r.min; act=$act[$k]; err=$act[$k]-[double]$r.min
      g=$mins.Count; seasonMin=$r.seasonMin; med=$med; short=$nShort; last=$last; up=($last -ne $null -and $r.seasonMin -ne $null -and $last -ge $r.seasonMin+4) }
  }
}
function Sum($set,$label){ $s=@($set); if(!$s.Count){ "{0,-62} n=0" -f $label; return }
  "{0,-62} n={1,4}  avg actual-proj {2,5:+0.0;-0.0}  avg |miss| {3,4:0.0}  played 4+ more than projected {4,4:P0}" -f $label,$s.Count,(($s|Measure-Object err -Average).Average),(($s|ForEach-Object{[math]::Abs($_.err)}|Measure-Object -Average).Average),(@($s|Where-Object{$_.err -ge 4}).Count/$s.Count) }
"Nights: " + ((@($rows | Select-Object -ExpandProperty d -Unique) | Sort-Object) -join ', ')
""
"STARTERS (projected to start, 3+ games this season)"
$st = @($rows | Where-Object { $_.start -and $_.g -ge 3 })
Sum $st "all starters"
Sum ($st | Where-Object { $_.short -eq 0 }) "no short game in his log"
Sum ($st | Where-Object { $_.short -ge 1 }) "1+ short game in his log (<$([int]($Short*100))% of his median)"
Sum ($st | Where-Object { $_.short -ge 1 -and $_.up }) "  ...and his last game was 4+ min above his season average"
Sum ($st | Where-Object { $_.proj -le $_.med - 3 }) "projected 3+ min under the median of his log"
""
"What a median-based projection would have done for those with a short game (model min shifted by w*(median-mean), w=g/(g+1.5)):"
$sh = @($st | Where-Object { $_.short -ge 1 -and $_.seasonMin -ne $null })
foreach($x in $sh){ $w=$x.g/($x.g+1.5); $x | Add-Member alt ($x.proj + $w*($x.med-$x.seasonMin)) }
if($sh.Count){
  "  model:  avg |miss| {0:0.0}, avg actual-proj {1:+0.0;-0.0}" -f (($sh|ForEach-Object{[math]::Abs($_.err)}|Measure-Object -Average).Average),(($sh|Measure-Object err -Average).Average)
  "  median: avg |miss| {0:0.0}, avg actual-proj {1:+0.0;-0.0}" -f (($sh|ForEach-Object{[math]::Abs($_.act-$_.alt)}|Measure-Object -Average).Average),(($sh|ForEach-Object{$_.act-$_.alt}|Measure-Object -Average).Average) }
""
"Biggest under-projections (starters):"
$st | Sort-Object err -Descending | Select-Object -First 15 | ForEach-Object { "  {0} {1,-24} {2} proj {3,4:0.0} actual {4,3} | season avg {5,4:0.0} median {6,4:0.0} last {7,3} short games {8} | log {9}" -f $_.d,$_.player,$_.team,$_.proj,$_.act,$_.seasonMin,$_.med,$_.last,$_.short,'' }
$rows | Export-Csv (Join-Path $root "tracking\minutes-audit.csv") -NoTypeInformation
