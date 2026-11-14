param([string]$Date, [switch]$NoFetch)
# "How he gets it" panel data (Nov 14). CONTEXT ONLY: nothing here feeds the model, a projection, a win chance or the card.
#  1. Caches each finished game's ESPN play-by-play as a small file, tracking/pbp/<espnId>.json (once per game; finals-*.json lists them):
#       s: shots [shooterId, assisterId or "", x, y, made 0/1, value 2/3, zone 0-4, kind]   zone: 0 rim, 1 paint, 2 mid, 3 corner 3, 4 above-break 3
#       r: rebounds [playerId, offensive 0/1, zone of the miss 0-4 or 5 for a free throw]  kind: d dunk/lob, l layup/tip, j jumper/floater/hook
#     ESPN's x runs 0-50 across the court and y is feet out from the rim (0 = under it).
#  2. Writes site/creates.json for tonight's slate: every player with a prop, his season shot chart, zones, who feeds him, who he feeds,
#     where his rebounds come from, and each team's defense by zone. The page loads it only when the panel is opened.
# Paths use / so the GitHub runners can run it too.
$ErrorActionPreference = "Stop"
$root = Split-Path $PSScriptRoot -Parent; $trk = Join-Path $root "tracking"; $pbpDir = Join-Path $trk "pbp"
New-Item -ItemType Directory -Force $pbpDir | Out-Null
$utf8 = New-Object Text.UTF8Encoding $false
function Norm([string]$s){ (($s.Normalize([Text.NormalizationForm]::FormD) -replace '\p{Mn}','').ToLower() -replace "[.'\-,]"," " -replace '\b(jr|sr|ii|iii|iv)\b','' -replace '\s+',' ').Trim() }
function ZoneOf($x, $y, [string]$txt, [int]$v){ $dx = [double]$x - 25; $dy = [double]$y
  $ft = if($txt -match '(\d+)-foot'){ [int]$matches[1] } else { [math]::Sqrt($dx*$dx + $dy*$dy) }
  if($v -eq 3){ if($dy -le 9 -and [math]::Abs($dx) -ge 20){ 3 } else { 4 } } elseif($ft -le 4){ 0 } elseif([math]::Abs($dx) -le 8 -and $dy -le 19){ 1 } else { 2 } }

# 1. cache finished games
$games = [ordered]@{}
foreach($f in Get-ChildItem $trk -Filter "finals-*.json" | Sort-Object Name){ $d = $f.Name.Substring(7,8)
  foreach($g in ([IO.File]::ReadAllText($f.FullName) | ConvertFrom-Json).games){ if("$($g.state)" -eq 'post' -or "$($g.detail)" -match 'Final'){ $games["$($g.espnId)"] = $d } } }
$new = 0
if(-not $NoFetch){
  foreach($gid in $games.Keys){ $pf = Join-Path $pbpDir "$gid.json"; if(Test-Path $pf){ continue }
    try { $s = Invoke-RestMethod "https://site.api.espn.com/apis/site/v2/sports/basketball/nba/summary?event=$gid" -TimeoutSec 60 } catch { Write-Warning "pbp $gid : $_"; continue }
    if(-not $s.plays){ continue }
    $tm = @{}; foreach($t in $s.boxscore.teams){ $tm["$($t.team.id)"] = "$($t.team.abbreviation)" }
    $ath = [ordered]@{}; foreach($tp in $s.boxscore.players){ foreach($st in $tp.statistics){ foreach($a in $st.athletes){ $ath["$($a.athlete.id)"] = @("$($a.athlete.displayName)", $tm["$($tp.team.id)"]) } } }
    $SH = New-Object System.Collections.ArrayList; $RB = New-Object System.Collections.ArrayList; $lastMiss = $null
    foreach($p in $s.plays){ $ty = "$($p.type.text)"; $txt = "$($p.text)"; $pp = @($p.participants)
      if($p.shootingPlay -and $ty -notmatch 'Free Throw' -and $pp.Count){
        $v = if($txt -match 'three point'){ 3 } else { 2 }; $m = [int][bool]$p.scoringPlay
        $z = ZoneOf $p.coordinate.x $p.coordinate.y $txt $v
        $k = if($ty -match 'Dunk|Alley'){ 'd' } elseif($ty -match 'Layup|Finger|Tip'){ 'l' } else { 'j' }
        $as = if($m -and $pp.Count -ge 2){ "$($pp[1].athlete.id)" } else { "" }
        [void]$SH.Add(@("$($pp[0].athlete.id)", $as, [int]$p.coordinate.x, [int]$p.coordinate.y, $m, $v, $z, $k))
        $lastMiss = if($m){ $null } else { $z } }
      elseif($ty -match 'Free Throw'){ $lastMiss = if($p.scoringPlay){ $null } else { 5 } }
      elseif($ty -match '^(Offensive|Defensive) Rebound$' -and $pp.Count){ [void]$RB.Add(@("$($pp[0].athlete.id)", [int]($ty -like 'Off*'), $(if($lastMiss -ne $null){ $lastMiss } else { -1 }))); $lastMiss = $null } }
    $doc = [ordered]@{ gid=$gid; date=$games[$gid]; ath=$ath; s=$SH; r=$RB }
    [IO.File]::WriteAllText($pf, (ConvertTo-Json $doc -Depth 5 -Compress), $utf8); $new++ } }

# 2. tonight's panel file
if(-not $Date){ $Date = ([TimeZoneInfo]::ConvertTimeBySystemTimeZoneId([DateTime]::UtcNow, 'Eastern Standard Time')).ToString("yyyyMMdd") }
$slF = Join-Path $root "site/slate.json"; $slate = [IO.File]::ReadAllText($slF) | ConvertFrom-Json
if("$($slate.date)" -ne $Date){ $alt = Join-Path $trk "slate-$Date.json"; if(Test-Path $alt){ $slate = [IO.File]::ReadAllText($alt) | ConvertFrom-Json } else { throw "no slate for $Date" } }
# box scores (games, per-game averages) by normalized name|team, from the finals files
$box = @{}
foreach($f in Get-ChildItem $trk -Filter "finals-*.json" | Sort-Object Name){ if($f.Name.Substring(7,8) -ge $Date){ continue }
  foreach($g in ([IO.File]::ReadAllText($f.FullName) | ConvertFrom-Json).games){ foreach($t in $g.teams){ foreach($p in $t.players){ if($p.dnp -or [double]$p.MIN -le 0){ continue }
    $k = "$(Norm $p.name)"; if(-not $box[$k]){ $box[$k] = @{ team=$t.abbr; g=0; MIN=0.0; PTS=0.0; REB=0.0; AST=0.0; OREB=0.0; DREB=0.0; FTA=0.0; FTM=0.0; TPM=0.0; TPA=0.0 } }
    $b = $box[$k]; $b.team = $t.abbr; $b.g++; foreach($c in 'MIN','PTS','REB','AST','OREB','DREB','FTA','FTM'){ $b[$c] += [double]$p.$c }; $b.TPM += [double]$p.'3PTM'; $b.TPA += [double]$p.'3PTA' } } } }
# play-by-play, season to date
$pbp = @(Get-ChildItem $pbpDir -Filter "*.json" | % { [IO.File]::ReadAllText($_.FullName) | ConvertFrom-Json } | ? { $_.date -lt $Date })
$name = @{}; $teamOf = @{}; $idOf = @{}
foreach($g in $pbp){ foreach($pr in $g.ath.PSObject.Properties){ $name[$pr.Name] = $pr.Value[0]; $teamOf[$pr.Name] = $pr.Value[1]; $idOf[(Norm $pr.Value[0])] = $pr.Name } }
# per player and per defending team
$P = @{}; $DEF = @{}; $LG = @(0..4 | % { ,@(0,0) })
function PEnt($id){ if(-not $P[$id]){ $P[$id] = @{ sh=New-Object System.Collections.ArrayList; zf=@(0..4 | % { ,@(0,0) }); asd=0; fgm=0; asd3=0; tpm=0; by=@{}; to=@{}; az=@(0,0,0,0,0); ak=@{d=0;l=0;j=0}; ash=New-Object System.Collections.ArrayList; rz=@(0,0,0,0,0,0); ro=0; rd=0 } }; $P[$id] }
foreach($g in $pbp){ $teams = @($g.ath.PSObject.Properties | % { $_.Value[1] } | Sort-Object -Unique)
  foreach($s in $g.s){ $sid = $s[0]; $q = PEnt $sid; [void]$q.sh.Add(@($s[2], $s[3], $s[4], $s[5])); $q.zf[$s[6]][1]++; if($s[4]){ $q.zf[$s[6]][0]++; $q.fgm++; if($s[5] -eq 3){ $q.tpm++ } }
    $off = $g.ath.$sid; $dt = if($off){ @($teams | ? { $_ -ne $off[1] })[0] } else { $null }
    if($dt){ if(-not $DEF[$dt]){ $DEF[$dt] = @(0..4 | % { ,@(0,0) }) }; $DEF[$dt][$s[6]][1]++; if($s[4]){ $DEF[$dt][$s[6]][0]++ } }
    $LG[$s[6]][1]++; if($s[4]){ $LG[$s[6]][0]++ }
    if($s[1]){ $q.asd++; if($s[5] -eq 3){ $q.asd3++ }; $q.by[$s[1]] = 1 + [int]$q.by[$s[1]]
      $a = PEnt $s[1]; $a.to[$sid] = 1 + [int]$a.to[$sid]; $a.az[$s[6]]++; $a.ak[$s[7]]++; [void]$a.ash.Add(@($s[2], $s[3], $sid)) } }
  foreach($r in $g.r){ $q = PEnt $r[0]; if($r[1]){ $q.ro++ } else { $q.rd++ }; if($r[2] -ge 0){ $q.rz[$r[2]]++ } } }
# tonight's status of everyone on the slate's rosters
$stat = @{}; $roster = @{}
foreach($tp in $slate.teams.PSObject.Properties){ $roster[$tp.Name] = @(); foreach($pl in $tp.Value.players){ $st = @(@("$($pl.espnInj)", "$($pl.rwInj)") | ? { $_ }) -join "/"; $stat[(Norm $pl.name)] = $(if($st){ $st } else { "Active" }); $roster[$tp.Name] += $pl.name } }
function Who($id){ $nm = $name[$id]; if(-not $nm){ return $null }; $s0 = $stat[(Norm $nm)]; @($nm, $(if($s0){ $s0 } else { "" })) }
function Top($h, $n){ @($h.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First $n | % { $w = Who $_.Key; if($w){ ,@($w[0], [int]$_.Value, $w[1]) } }) }
$out = [ordered]@{}; $opp = @{}
foreach($g in $slate.games){ $opp[$g.away.abbr] = $g.home.abbr; $opp[$g.home.abbr] = $g.away.abbr
  $pl = @(@($g.props) + @($g.fanProps) | ? { $_ -and $_.player } | % { $_.player } | Sort-Object -Unique)
  foreach($nm in $pl){ $k = Norm $nm; $id = $idOf[$k]; $b = $box[$k]; if(-not $id -or -not $b -or -not $P[$id]){ continue }; $q = $P[$id]; $gp = [double]$b.g
    $avg = [ordered]@{}; foreach($c in 'MIN','PTS','REB','AST','OREB','DREB','FTA','FTM','TPM','TPA'){ $avg[$c] = [math]::Round($b[$c]/$gp, 1) }
    $toIds = @($q.to.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 3 | % { $_.Key })
    # teammates' rebounding, for "who else is on the glass tonight"
    $mates = @($box.GetEnumerator() | ? { $_.Value.team -eq $b.team -and $_.Key -ne $k -and $_.Value.g -ge 3 } | Sort-Object { $_.Value.REB / $_.Value.g } -Descending | Select-Object -First 4 | % { $mn = $name[$idOf[$_.Key]]; if(-not $mn){ $mn = $_.Key }; $s0 = $stat[$_.Key]; ,@($mn, [math]::Round($_.Value.REB/$_.Value.g,1), $(if($s0){ $s0 } else { "" })) })
    $out[$nm] = [ordered]@{ t=$b.team; opp=$opp[$b.team]; g=[int]$gp; avg=$avg
      sh=$q.sh; zf=$q.zf; fgm=$q.fgm; asd=$q.asd; tpm=$q.tpm; asd3=$q.asd3; by=(Top $q.by 4)
      to=(Top $q.to 6); az=$q.az; ak=$q.ak; ash=@($q.ash | % { ,@($_[0], $_[1], [array]::IndexOf($toIds, $_[2])) })
      rz=$q.rz; ro=$q.ro; rd=$q.rd; mates=$mates } } }
$defOut = [ordered]@{}; foreach($t in $DEF.Keys){ $defOut[$t] = $DEF[$t] }
$doc = [ordered]@{ date=$Date; built=(Get-Date).ToUniversalTime().ToString("o"); games=$pbp.Count; league=$LG; def=$defOut; players=$out }
$of = Join-Path $root "site/creates.json"; [IO.File]::WriteAllText($of, (ConvertTo-Json $doc -Depth 6 -Compress), $utf8)
"creates $Date : $new new games cached ($($pbp.Count) in the season file set), $($out.Count) players, $([math]::Round((Get-Item $of).Length/1KB))KB"
