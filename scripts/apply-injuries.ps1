param([string]$Slate, [string]$List, [switch]$DryRun)
# Applies a hand-made injury report (lines like "ATL: Jalen Johnson=Q; Jock Landale=O", O/D/Q/P, ESPN team abbreviations) to
# a built slate where it disagrees with ESPN/RotoWire, the same fields the page's statusOf reads. Reports what changed, names it
# couldn't find, and players the slate has out or questionable that the report doesn't mention.
$ErrorActionPreference = "Stop"
$norm = { param($n) (($n.ToLower() -replace '[^a-z ]','') -replace '\s+(jr|sr|ii|iii|iv)$','').Trim() }
function St($p){ $inj = "$($p.espnInj)".ToLower(); $rw = "$($p.rwInj)".ToUpper()
  if($rw -in 'OUT','OFS' -or $inj -in 'out','suspension'){ return 'O' }
  if($inj -eq 'doubtful' -or $rw -eq 'DOUBT'){ return 'D' }
  if($rw -in 'GTD','QUES' -or $inj -in 'day-to-day','questionable'){ return 'Q' }
  if($rw -eq 'PROB' -or $inj -eq 'probable'){ return 'P' }
  'A' }
$s = Get-Content $Slate -Raw -Encoding UTF8 | ConvertFrom-Json
$want = @{}
foreach($ln in Get-Content $List){ if($ln -notmatch '^\s*([A-Z]+):\s*(.+)$'){ continue }; $ab = $Matches[1]
  foreach($it in $Matches[2] -split ';'){ if($it -match '^\s*(.+?)\s*=\s*([ODQP])\s*$'){ $want["$ab|$(& $norm $Matches[1])"] = @{ name=$Matches[1]; st=$Matches[2] } } } }
$seen = @{}; $out = @()
foreach($ab in $s.teams.PSObject.Properties.Name){ foreach($p in $s.teams.$ab.players){ $k = "$ab|$(& $norm $p.name)"; $now = St $p
  if($want.ContainsKey($k)){ $seen[$k] = 1; $w = $want[$k].st
    if($now -ne $w){ $out += "{0} {1}: {2} -> {3}" -f $ab,$p.name,$now,$w
      if(-not $DryRun){ switch($w){ 'O' { $p.espnInj = 'Out'; $p.rwInj = 'OUT' } 'D' { $p.espnInj = 'Doubtful'; $p.rwInj = 'DOUBT' }
          'Q' { $p.espnInj = 'Questionable'; $p.rwInj = 'QUES'; if($p.rwPct -eq 0 -or $p.rwPct -eq 100){ $p.rwPct = $null } }
          'P' { $p.espnInj = 'Probable'; $p.rwInj = 'PROB'; if($p.rwPct -eq 0){ $p.rwPct = $null } } } } } }
  elseif($now -in 'O','D','Q' -and $p.s){ $out += "  (not in report) {0} {1}: {2} [{3}/{4}]" -f $ab,$p.name,$now,$p.espnInj,$p.rwInj } } }
foreach($k in $want.Keys){ if(-not $seen[$k]){ $out += "  NOT FOUND: $k" } }
if(-not $DryRun){ [IO.File]::WriteAllText($Slate, ($s | ConvertTo-Json -Depth 20 -Compress)) }
$out
