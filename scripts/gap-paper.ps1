param([string]$Date, [switch]$Log, [switch]$Grade, [switch]$Summary, [string]$Slate)
# PAPER ONLY: tracks the one lead from the Nov 13 prop study (private\reviews\prop-edge-20261113): when Fanatics posts a player's line a
# point or more ABOVE FanDuel's, the Fanatics under won 305-185 (+10.2%) over 13 nights, but it failed as a card rule and the sample
# is small. This logs each night's list without touching the model, the card or any stake, and grades it, so the idea earns its way in
# or out on nights it has never seen. Threes are left out (they lost in the study); unders priced -150..+150 only.
#   -Log      add a snapshot of tonight's list (night.ps1 calls it after each freeze; a gap seen on several snapshots is more real)
#   -Grade    grade a finished night from tracking\finals-<date>.json; adds Fanatics' closing line from clv.ps1's cache when it's
#             there, which answers whether the higher line was still up at tipoff (a real price) or a feed that had fallen behind
#   -Summary  the record so far, by stat, both halves, and split by whether the gap was still there at the close
# Files: tracking/gap-paper-<date>.json (paths use / so the GitHub runners can run it too). Never place or suggest a real bet from this list until the user approves it after a test.
$ErrorActionPreference = "Stop"
$root = Split-Path $PSScriptRoot -Parent; $trk = Join-Path $root "tracking"; $raw = Join-Path $root "raw"
function Norm([string]$s){ (($s.Normalize([Text.NormalizationForm]::FormD) -replace '\p{Mn}','').ToLower() -replace "[.'\-,]"," " -replace '\b(jr|sr|ii|iii|iv)\b','' -replace '\s+',' ').Trim() }
function Pay([double]$o){ if($o -gt 0){ $o/100.0 } else { 100.0/(-$o) } }
$utf8 = New-Object Text.UTF8Encoding $false
$TYPES = [ordered]@{ "core_bet_type_27_points"="PTS"; "core_bet_type_23_rebounds"="REB"; "core_bet_type_26_assists"="AST";
  "core_bet_type_85_points_rebounds_assists"="PRA"; "core_bet_type_86_points_rebounds"="PR"; "core_bet_type_87_points_assists"="PA"; "core_bet_type_88_rebounds_assists"="RA" }
if(-not $Date){ $Date = ([TimeZoneInfo]::ConvertTimeBySystemTimeZoneId([DateTime]::UtcNow, 'Eastern Standard Time')).ToString("yyyyMMdd") }
$pf = Join-Path $trk "gap-paper-$Date.json"
function Save($o){ [IO.File]::WriteAllText($pf, (ConvertTo-Json $o -Depth 8), $utf8) }

if($Log){
  if(-not $Slate){ $Slate = Join-Path $root "site/slate.json"; if(-not (Test-Path $Slate) -or ([IO.File]::ReadAllText($Slate) | ConvertFrom-Json).date -ne $Date){ $Slate = Join-Path $trk "slate-$Date.json" } }
  $s = [IO.File]::ReadAllText($Slate) | ConvertFrom-Json; if("$($s.date)" -ne $Date){ throw "$Slate is for $($s.date), not $Date" }
  $at = "$($s.generated)"; $doc = if(Test-Path $pf){ [IO.File]::ReadAllText($pf) | ConvertFrom-Json } else { [pscustomobject]@{ date=$Date; paperOnly=$true; snapshots=@(); bets=@() } }
  if(@($doc.snapshots | ? { $_.at -eq $at }).Count){ "gap-paper $Date : snapshot $at already logged"; return }
  $bets = @{}; foreach($b in @($doc.bets)){ $bets[$b.key] = $b }; $now = @()
  foreach($g in $s.games){ $fd = @{}; foreach($p in @($g.props | ? { $_ -and $_.player -and $_.over -ne $null -and $_.under -ne $null })){ $fd["$(Norm $p.player)|$($p.stat)"] = $p }
    foreach($p in @($g.fanProps | ? { $_ -and $_.player -and $_.stat -ne '3PM' -and $_.over -ne $null -and $_.under -ne $null })){ $o = $fd["$(Norm $p.player)|$($p.stat)"]; if(-not $o){ continue }
      $gap = [double]$p.line - [double]$o.line; if($gap -lt 1 -or [double]$p.under -lt -150 -or [double]$p.under -gt 150){ continue }
      $k = "$(Norm $p.player)|$($p.stat)"; $now += $k
      $row = [ordered]@{ key=$k; game="$($g.away.abbr) @ $($g.home.abbr)"; gid="$($g.espnId)"; player=$p.player; stat=$p.stat; fanLine=[double]$p.line; fanUnder=[int]$p.under; fanOver=[int]$p.over
        fdLine=[double]$o.line; fdUnder=[int]$o.under; fdOver=[int]$o.over; gap=$gap; firstSeen=$at; lastSeen=$at; seen=1 }
      if($bets[$k]){ $old = $bets[$k]; $row.firstSeen = $old.firstSeen; $row.seen = [int]$old.seen + 1 }
      $bets[$k] = [pscustomobject]$row } }
  $doc.snapshots = @(@($doc.snapshots) + [pscustomobject]@{ at=$at; n=$now.Count })
  $doc.bets = @($bets.Values | Sort-Object game, player, stat); Save $doc
  "gap-paper $Date : $($now.Count) Fanatics unders above FanDuel's line in this snapshot ($(@($doc.bets).Count) logged tonight, $(@($doc.snapshots).Count) snapshots). Paper only."
  return }

if($Grade){
  if(-not (Test-Path $pf)){ "gap-paper $Date : nothing logged"; return }
  $doc = [IO.File]::ReadAllText($pf) | ConvertFrom-Json; $ff = Join-Path $trk "finals-$Date.json"; if(-not (Test-Path $ff)){ throw "no tracking\finals-$Date.json yet" }
  $box = @{}; foreach($gm in ([IO.File]::ReadAllText($ff) | ConvertFrom-Json).games){ foreach($t in $gm.teams){ foreach($p in $t.players){ $box[(Norm $p.name)] = $p } } }
  $close = @{}
  foreach($t in $TYPES.Keys){ $cf = Join-Path $raw "an_close_${Date}_$t.json"; if(-not (Test-Path $cf)){ $cf = Join-Path $raw "an_close_$Date.json" }; if(-not (Test-Path $cf)){ continue }
    $an = [IO.File]::ReadAllText($cf) | ConvertFrom-Json; $nm = @{}; foreach($p in $an.players){ $nm[[string]$p.id] = Norm $p.full_name }
    foreach($grp in (@($an.markets.'2988'.event.$t | ? { $_ -and -not $_.is_alt_market }) | Group-Object player_id)){ $o = $grp.Group | ? side -eq 'over' | Select-Object -First 1; $u = $grp.Group | ? side -eq 'under' | Select-Object -First 1
      if($nm[[string]$grp.Name] -and $o -and $u -and $o.value -eq $u.value){ $close["$($nm[[string]$grp.Name])|$($TYPES[$t])"] = @{ line=[double]$o.value; under=[double]$u.odds } } } }
  $lastAt = (@($doc.snapshots) | Select-Object -Last 1).at
  foreach($b in $doc.bets){ $p = $box[($b.key -split '\|')[0]]
    $res = 'DNP'; $act = $null; $u = 0.0
    if($p -and -not $p.dnp -and [double]$p.MIN -gt 0){ $v = @{ PTS=[double]$p.PTS; REB=[double]$p.REB; AST=[double]$p.AST }; $act = 0.0; foreach($c in ($b.stat -replace 'PRA','PTS,REB,AST' -replace '^PR$','PTS,REB' -replace '^PA$','PTS,AST' -replace '^RA$','REB,AST') -split ','){ $act += $v[$c] }
      if($act -lt $b.fanLine){ $res = 'WIN'; $u = Pay $b.fanUnder } elseif($act -gt $b.fanLine){ $res = 'LOSS'; $u = -1.0 } else { $res = 'PUSH' } }
    $c = $close[$b.key]
    $b | Add-Member -Force actual $act; $b | Add-Member -Force result $res; $b | Add-Member -Force units ([math]::Round($u,3)); $b | Add-Member -Force atLast ([bool]($b.lastSeen -eq $lastAt))
    $b | Add-Member -Force closeLine $(if($c){ $c.line } else { $null }); $b | Add-Member -Force closeUnder $(if($c){ $c.under } else { $null })
    $b | Add-Member -Force heldToClose $(if($c){ [bool]($c.line -ge $b.fanLine) } else { $null }) }
  $doc | Add-Member -Force gradedAt ((Get-Date).ToUniversalTime().ToString("o")); Save $doc
  $g = @($doc.bets | ? { $_.result -in 'WIN','LOSS' }); $w = @($g | ? result -eq 'WIN').Count
  "gap-paper $Date (paper): {0}-{1}, {2:+0.00;-0.00}u flat 1u; {3} with a closing line, {4} of them still at the higher number at the close" -f $w, ($g.Count-$w), (($g | % units | Measure-Object -Sum).Sum), @($doc.bets | ? { $_.closeLine -ne $null }).Count, @($doc.bets | ? { $_.heldToClose }).Count
  return }

if($Summary){
  $all = @(); foreach($f in (Get-ChildItem $trk -Filter "gap-paper-*.json" | Sort-Object Name)){ $d = [IO.File]::ReadAllText($f.FullName) | ConvertFrom-Json; foreach($b in @($d.bets | ? { $_.result -in 'WIN','LOSS','PUSH' })){ $b | Add-Member -Force d $d.date; $b | Add-Member -Force backfill ([bool]$d.backfill); $all += $b } }
  if(-not $all.Count){ "gap-paper: nothing graded yet"; return }
  function Rec($lab, $set){ $set = @($set); if(-not $set.Count){ return }; $w = @($set | ? result -eq 'WIN').Count; $l = @($set | ? result -eq 'LOSS').Count; $u = ($set | % units | Measure-Object -Sum).Sum
    "  {0,-40} {1,4}-{2,-4} {3,7:+0.00;-0.00}u  {4,6:P1} a bet  ({5} nights)" -f $lab, $w, $l, $u, ($u/$set.Count), @($set | % d | Sort-Object -Unique).Count }
  $live = @($all | ? { -not $_.backfill }); $back = @($all | ? { $_.backfill })
  "Line-gap unders, PAPER ONLY (Fanatics line 1+ above FanDuel's, no threes, -150..+150, flat 1u)"
  Rec 'backfill (nights before tracking began)' $back
  Rec 'tracked live' $live
  foreach($set in @(@('tracked live', $live), @('all', $all))){ if(-not @($set[1]).Count){ continue }; "-- $($set[0]) by stat"; foreach($st in 'PTS','REB','AST','PRA','PR','PA','RA'){ Rec "    $st" ($set[1] | ? stat -eq $st) }
    "-- $($set[0]): was the higher line still up at Fanatics' close?"; Rec '    yes (a real price)' ($set[1] | ? { $_.heldToClose -eq $true }); Rec '    no (Fanatics came down)' ($set[1] | ? { $_.heldToClose -eq $false }); Rec '    no closing line' ($set[1] | ? { $_.heldToClose -eq $null }) }
  return }
"use -Log, -Grade or -Summary"
