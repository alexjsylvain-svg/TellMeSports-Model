param([int]$MinG = 3, [double]$MaxStartShare = 0.5)
# Offline screen for a "listed starter who has been coming off the bench" minutes cap (Nov 8, after Caruso on Nov 7:
# RotoWire listed him starting, 0 starts in 6 games, the model gave him 27.2 minutes, he came off the bench for 13).
# For every archived night (tracking\slate-D.json + finals-D.json): players RotoWire lists as starters who have played
# MinG+ games this season but started under MaxStartShare of them. Did they start? Minutes vs this season's average and
# vs the model's projection (board-D.json rows' min, when the night has a board).
$ErrorActionPreference = "Stop"
$root = Split-Path $PSScriptRoot -Parent; $trk = Join-Path $root "tracking"
function NormN($n){ ($n -replace '[^A-Za-z ]','' -replace '\s+(Jr|Sr|II|III|IV)$','').ToLower().Trim() }
$rows = @()
foreach($sf in Get-ChildItem $trk -Filter 'slate-2026????.json' | Sort-Object Name){
  $D = $sf.BaseName.Substring(6); $ff = Join-Path $trk "finals-$D.json"; if(-not (Test-Path $ff)){ continue }
  $s = Get-Content $sf.FullName -Raw | ConvertFrom-Json; $f = Get-Content $ff -Raw | ConvertFrom-Json
  $bf = Join-Path $trk "board-$D.json"; $bmin = @{}
  if(Test-Path $bf){ foreach($r in (Get-Content $bf -Raw | ConvertFrom-Json).rows){ if($r.min -ne $null){ $bmin["$($r.team)|$(NormN $r.player)"] = $r.min } } }
  $box = @{}; foreach($g in $f.games){ foreach($t in $g.teams){ foreach($p in $t.players){ $box["$($t.abbr)|$(NormN $p.name)"] = $p } } }
  foreach($ab in $s.teams.PSObject.Properties.Name){ foreach($p in $s.teams.$ab.players){
    $c = $p.cur; if(-not $p.rwStarter -or -not $c -or $c.g -lt $MinG){ continue }
    if(($c.gs / $c.g) -ge $MaxStartShare){ continue }
    if($p.rwInj -match 'Out'){ continue }
    $k = "$ab|$(NormN $p.name)"; $b = $box[$k]
    # the page's projMin(p, starter=true) before the openers blend and team scaling (G.stPlus 0, stKnee 99)
    $sm = $p.s; $base = if($sm -and $sm.mpg -ne $null){ $rel=[math]::Min(1,($sm.g)/30); $sm.mpg*$rel + 28*(1-$rel) } else { 27 }
    $base = [math]::Min(37.5,[math]::Max(26,$base)); if($sm -and $sm.yr -eq '2024-25'){ $base = [math]::Min($base,32) }
    $rows += [pscustomobject]@{ date=$D; team=$ab; name=$p.name; g=$c.g; gs=$c.gs; curMin=[math]::Round($c.min,1); lastMpg=$p.s.mpg; projMin=$bmin[$k]; baseStart=[math]::Round($base,1)
      played=[bool]($b -and -not $b.dnp); started=[bool]($b -and $b.starter); min=$(if($b -and -not $b.dnp){ $b.MIN } else { $null }) }
  } }
}
$rows | Format-Table date,team,name,g,gs,curMin,lastMpg,projMin,started,min -AutoSize | Out-String -Width 200
$pl = @($rows | ? played)
"listed-starter-but-bench cases: $($rows.Count) ($($pl.Count) played)"
if($pl.Count){
  $st = @($pl | ? started); "actually started: $($st.Count) of $($pl.Count)"
  $avg = { param($a,$f) if($a.Count){ [math]::Round((($a | % { [double](& $f $_) }) | Measure-Object -Average).Average,1) } }
  "avg minutes played: $(& $avg $pl { param($x) $x.min }) | avg this-season minutes: $(& $avg $pl { param($x) $x.curMin })"
  $pj = @($pl | ? { $_.projMin -ne $null })
  if($pj.Count){ "with a model projection ($($pj.Count)): projected $(& $avg $pj { param($x) $x.projMin }) | played $(& $avg $pj { param($x) $x.min }) | season avg $(& $avg $pj { param($x) $x.curMin })"
    "  abs error, model projection: $(& $avg $pj { param($x) [math]::Abs($x.projMin-$x.min) }) | season avg + 3: $(& $avg $pj { param($x) [math]::Abs([math]::Min($x.projMin,$x.curMin+3)-$x.min) })" }
  if($st.Count){ "  of those who did start: played $(& $avg $st { param($x) $x.min }) vs season avg $(& $avg $st { param($x) $x.curMin })" }
  $bn = @($pl | ? { -not $_.started }); if($bn.Count){ "  of those who came off the bench: played $(& $avg $bn { param($x) $x.min }) vs season avg $(& $avg $bn { param($x) $x.curMin })" }
  # candidate rules for this group's minutes, scored against what they played (mean abs error and mean signed error)
  $rules = [ordered]@{
    "now: starter minutes"           = { param($x) $x.baseStart }
    "hard cap: season avg + 3"       = { param($x) [math]::Min($x.baseStart, $x.curMin+3) }
    "78/22 start-chance mix"         = { param($x) 0.78*$x.baseStart + 0.22*[math]::Min($x.baseStart,$x.curMin+1.5) }
    "halfway to season avg"          = { param($x) ($x.baseStart + $x.curMin)/2 }
  }
  foreach($n in $rules.Keys){ $fn = $rules[$n]; $e = @($pl | % { (& $fn $_) - $_.min })
    "{0,-32} MAE {1,4:N1}  bias {2,5:N1}  | started MAE {3,4:N1} | bench MAE {4,4:N1}" -f $n, (($e | % { [math]::Abs($_) }) | Measure-Object -Average).Average, ($e | Measure-Object -Average).Average,
      ((@($st | % { [math]::Abs((& $fn $_) - $_.min) })) | Measure-Object -Average).Average, ((@($bn | % { [math]::Abs((& $fn $_) - $_.min) })) | Measure-Object -Average).Average }
}
