param([string]$Date, [switch]$Commit)
# For the live-score job: compares site\live.json (just written by live.ps1) with the last published snapshot, and finds
# tonight's recommended picks that have just been decided (an over cleared, an under passed, or the game went final).
# State lives in tracking\live-state-<date>.json: sig = the last published scoreboard, settled = picks already alerted.
# Without -Commit it records newly settled picks only; with -Commit (after a successful publish) it also saves the new sig.
# Last line: RESULT {"publish":bool,"inProgress":n,"final":n,"alerts":[...],"record":"W-L","units":x}
$ErrorActionPreference = "Stop"
$root = Split-Path $PSScriptRoot -Parent; $trk = Join-Path $root "tracking"
$live = [IO.File]::ReadAllText((Join-Path $root "site\live.json")) | ConvertFrom-Json
$pf = Join-Path $trk "picks-$Date.json"
$picks = if(Test-Path $pf){ @(([IO.File]::ReadAllText($pf) | ConvertFrom-Json).bets | ? { $_.set -eq 'recommended' -and $_.player }) } else { @() }
$sf = Join-Path $trk "live-state-$Date.json"
$state = if(Test-Path $sf){ [IO.File]::ReadAllText($sf) | ConvertFrom-Json } else { [pscustomobject]@{ sig=""; settled=@() } }
function Norm([string]$s){ ($s.Normalize([Text.NormalizationForm]::FormD) -replace '\p{Mn}','').ToLower() -replace "[.'\-,]"," " -replace '\b(jr|sr|ii|iii|iv)\b','' -replace '\s+',' ' | % { $_.Trim() } }
function StatOf($r,[string]$st){ $p=[int]$r.PTS; $b=[int]$r.REB; $a=[int]$r.AST
  switch($st){ 'DD'{ @($p,$b,$a,[int]$r.STL,[int]$r.BLK | ? { $_ -ge 10 }).Count } 'PTS'{$p} 'REB'{$b} 'AST'{$a} '3PM'{[int]$r.'3PTM'} 'PRA'{$p+$b+$a} 'PR'{$p+$b} 'PA'{$p+$a} 'RA'{$b+$a} } }
$games = @($live.games)
$sig = ($games | Sort-Object espnId | % { "$($_.espnId):$($_.state):$($_.away)-$($_.home):$($_.period):$([math]::Floor([double]$_.clock/60))" }) -join '|'
$settled = [Collections.ArrayList]@(@($state.settled)); $alerts = @(); $w=0; $l=0; $u=0.0
foreach($b in $picks){
  $g = $games | ? { $_.espnId -eq $b.gid } | Select-Object -First 1; if(-not $g -or $g.state -eq 'pre'){ continue }
  $row = $null; foreach($t in $g.teams){ foreach($r in $t.players){ if((Norm $r.name) -eq (Norm $b.player)){ $row = $r } } }
  $fin = $g.state -eq 'post'; $res = $null; $v = $null
  if(-not $row -or $row.dnp -or -not ($row.MIN -gt 0)){ if($fin){ $res = 'VOID' } }
  else { $v = StatOf $row $b.stat
    if($b.side -eq 'Over'){ if($v -gt $b.line){ $res='WON' } elseif($fin){ $res = if($v -eq $b.line){'PUSH'}else{'LOST'} } }
    else { if($v -gt $b.line){ $res='LOST' } elseif($fin){ $res = if($v -eq $b.line){'PUSH'}else{'WON'} } } }
  if(-not $res){ continue }
  $st = if($b.stake){ [double]$b.stake } else { 1.0 }; $o = [double]$b.odds; $win = if($o -gt 0){ $st*$o/100 } else { $st*100/(-$o) }
  if($res -eq 'WON'){ $w++; $u += $win } elseif($res -eq 'LOST'){ $l++; $u -= $st }
  $key = "$($b.gid)|$($b.bet)"
  if($settled -notcontains $key){ [void]$settled.Add($key)
    $amt = if($res -eq 'WON'){ "+{0:N2}u" -f $win } elseif($res -eq 'LOST'){ "-{0:N2}u" -f $st } else { "0u" }
    $what = if($b.stat -eq 'DD'){ "double-double" } else { "$(if($b.side -eq 'Over'){'o'}else{'u'})$($b.line) $($b.stat)" }
    $alerts += "$($b.player) $what $res $amt ($(if($v -ne $null){"$v"}else{'DNP'}))" }
}
$publish = $sig -ne $state.sig -and $games.Count -gt 0
$newState = [ordered]@{ sig = if($Commit){ $sig } else { $state.sig }; settled = @($settled) }
[IO.File]::WriteAllText($sf, ($newState | ConvertTo-Json -Depth 4 -Compress))
$out = [ordered]@{ publish=$publish; inProgress=@($games | ? state -eq 'in').Count; final=@($games | ? state -eq 'post').Count; alerts=@($alerts); record="$w-$l"; units=[math]::Round($u,2) }
"RESULT " + ($out | ConvertTo-Json -Compress)
