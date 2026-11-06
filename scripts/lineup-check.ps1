param([string]$Date, [switch]$Due, [switch]$All, [int]$MinLead = 15, [int]$MaxLead = 70, [switch]$Backfill)
# Pre-tip lineup check. Compares each game's projected starters in site\slate.json (RotoWire, after a fresh build) with the
# starters its frozen picks were made with (tracking\picks-<date>.json "starters").
#   -Due       only list the games tipping MinLead..MaxLead minutes from now (no comparison; run this before building)
#   -All       compare every game that hasn't tipped, not just the ones due
#   -Backfill  add "starters" to a picks file frozen before freezePicks recorded them, from the current slate.json
# The last line printed is "RESULT {json}": due = game ids in the window, changed = game ids whose starters changed.
$ErrorActionPreference = "Stop"
$root = Split-Path $PSScriptRoot -Parent
$slatePath = Join-Path $root "site/slate.json"
$picksPath = Join-Path $root "tracking/picks-$Date.json"
$slate = Get-Content $slatePath -Raw -Encoding UTF8 | ConvertFrom-Json
if($slate.date -ne $Date){ throw "site\slate.json is for $($slate.date), not $Date" }
$now = [DateTime]::UtcNow

function StartersOf($abbr){ @($slate.teams.$abbr.players | ? { $_.rwStarter } | % { [ordered]@{ name=$_.name; inj=$(if($_.rwInj){ $_.rwInj } else { $null }) } }) }

$games = @($slate.games | % { $tip = ([DateTime]$_.time).ToUniversalTime(); [pscustomobject]@{ gid=$_.espnId; label="$($_.away.abbr)@$($_.home.abbr)"; away=$_.away.abbr; home=$_.home.abbr; tip=$tip; lead=($tip-$now).TotalMinutes } })
$dueGames = @($games | ? { $_.lead -ge $MinLead -and $_.lead -le $MaxLead })

if($Backfill){
  $doc = Get-Content $picksPath -Raw -Encoding UTF8 | ConvertFrom-Json
  if($doc.starters){ "picks-$Date.json already has starters; nothing changed"; return }
  $st = [ordered]@{}; foreach($g in $games){ $st[$g.gid] = [ordered]@{ $g.away = (StartersOf $g.away); $g.home = (StartersOf $g.home) } }
  $doc | Add-Member -NotePropertyName starters -NotePropertyValue $st
  [IO.File]::WriteAllText($picksPath, ($doc | ConvertTo-Json -Depth 8))
  "backfilled starters for $($games.Count) games from slate generated $($slate.generated)"; return
}

if((Test-Path $picksPath) -and (Get-Content $picksPath -Raw -Encoding UTF8 | ConvertFrom-Json).final){
  "picks-$Date.json is marked final: nothing to check or re-freeze tonight"
  "RESULT " + (@{ due=@(); changed=@() } | ConvertTo-Json -Compress); return
}

if($Due){
  $dueGames | % { "{0} tips {1:HH:mm} UTC ({2:N0} min)" -f $_.label, $_.tip, $_.lead }
  "RESULT " + (@{ due=@($dueGames | % gid); changed=@() } | ConvertTo-Json -Compress); return
}

$doc = Get-Content $picksPath -Raw -Encoding UTF8 | ConvertFrom-Json
$check = if($All){ @($games | ? { $_.lead -gt 10 }) } else { $dueGames }
$changed = @()
foreach($g in $check){
  $frozen = $doc.starters.($g.gid)
  $notes = @()
  foreach($ab in $g.away, $g.home){
    $was = @($frozen.$ab); $now2 = @(StartersOf $ab)
    $wasN = @($was | % name); $nowN = @($now2 | % { $_.name })
    $out = @($wasN | ? { $nowN -notcontains $_ }); $in = @($nowN | ? { $wasN -notcontains $_ })
    if($out.Count -or $in.Count){ $notes += "$ab starters: out $($out -join ', ') / in $($in -join ', ')" }
    foreach($p in $now2){ $w = $was | ? { $_.name -eq $p.name }; if($w -and "$($w.inj)" -ne "$($p.inj)"){ $notes += "$ab $($p.name): '$($w.inj)' -> '$($p.inj)'" } }
    $conf = $slate.teams.$ab.rwConfirmed
    "{0} {1}: {2}{3}" -f $g.label, $ab, ($nowN -join ', '), $(if($conf){ " (confirmed)" } else { " (projected)" })
  }
  if(-not $frozen){ $notes += "no starters recorded with the frozen picks" }
  if($notes.Count){ $changed += $g.gid; "  CHANGED " + ($notes -join '; ') } else { "  unchanged" }
}
"RESULT " + (@{ due=@($check | % gid); changed=@($changed) } | ConvertTo-Json -Compress)
