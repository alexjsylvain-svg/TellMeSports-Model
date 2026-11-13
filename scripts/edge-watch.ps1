param([int]$Last = 30, [double]$Watch = 0.65, [double]$Alarm = 0.58, [switch]$NoSave)
# Early warning for the card's one proven edge (Nov 13 sweep): assist unders carried the season (66-18 through Nov 12) while
# everything else was about break-even, and the closing line never moved toward them, so the edge is a standing habit in
# how books price assists, not news the market absorbs. This watches for that habit ending. Read-only for the model: it changes no picks or settings.
#   1. Results: assist unders over the last $Last decided picks against the season (docs\season.json).
#      WATCH below $Watch, ALARM below $Alarm (about break-even at the usual -130 to -150 prices).
#   2. Prices: tonight's Fanatics assist lines against FanDuel's on the same player and line (site\slate.json): the no-vig
#      chance each book gives the under. First run (Nov 13): +0.4 points on 57 lines, so the two books agree and the edge is
#      not a Fanatics quirk. A gap that opens up means one book has repriced assists: worth a look at which.
#   Each run adds a row to tracking\edge-watch.json (unless -NoSave) so the trend can be read back.
#   ./scripts/edge-watch.ps1
$ErrorActionPreference = "Stop"
$root = Split-Path $PSScriptRoot -Parent
function Impl([double]$o){ if($o -gt 0){ 100/($o+100) } else { -$o/(-$o+100) } }
function Norm([string]$s){ ($s.Normalize([Text.NormalizationForm]::FormD) -replace '\p{Mn}','').ToLower() -replace "[.'\-,]"," " -replace '\b(jr|sr|ii|iii|iv)\b','' -replace '\s+',' ' | % { $_.Trim() } }
$rec = { param($a) $w = @($a | ? result -eq 'WIN').Count; $n = @($a).Count; [pscustomobject]@{ w = $w; l = $n - $w; n = $n; rate = $(if($n){ $w/$n } else { $null }); said = $(if($n){ ($a | % p | Measure-Object -Average).Average } else { $null }) } }

# ---- 1. results
$bets = @(([IO.File]::ReadAllText((Join-Path $root "docs\season.json")) | ConvertFrom-Json).bets | ? { $_.result -in 'WIN','LOSS' })
$ast = @($bets | ? { $_.stat -eq 'AST' -and $_.side -eq 'under' } | Sort-Object date)
$rest = @($bets | ? { -not ($_.stat -eq 'AST' -and $_.side -eq 'under') })
$all = & $rec $ast; $recent = & $rec @($ast | Select-Object -Last $Last); $other = & $rec $rest
$state = if($recent.n -lt 15){ 'TOO FEW' } elseif($recent.rate -lt $Alarm){ 'ALARM' } elseif($recent.rate -lt $Watch){ 'WATCH' } else { 'OK' }
"Assist unders, season:      {0}-{1}  won {2:P1}  (model said {3:P1})" -f $all.w, $all.l, $all.rate, $all.said
"Assist unders, last {0,-3}:    {1}-{2}  won {3:P1}  -> {4}" -f $recent.n, $recent.w, $recent.l, $recent.rate, $state
"Everything else, season:    {0}-{1}  won {2:P1}  (model said {3:P1})" -f $other.w, $other.l, $other.rate, $other.said
if($all.n){ "Share of all picks that are assist unders: {0:P0}" -f ($all.n / $bets.Count) }

# ---- 2. prices: Fanatics against FanDuel, same player and line
$gap = $null; $nPair = 0; $date = $null
$sf = Join-Path $root "site\slate.json"
if(Test-Path $sf){ $s = [IO.File]::ReadAllText($sf) | ConvertFrom-Json; $date = "$($s.date)"; $d = @()
  foreach($g in $s.games){ $fd = @{}; foreach($p in @($g.props | ? { $_.stat -eq 'AST' -and $_.book -eq 'FD' -and $_.over -and $_.under })){ $fd["$(Norm $p.player)|$($p.line)"] = $p }
    foreach($p in @($g.fanProps | ? { $_.stat -eq 'AST' -and $_.over -and $_.under })){ $o = $fd["$(Norm $p.player)|$($p.line)"]; if(-not $o){ continue }
      $fan = (Impl $p.under) / ((Impl $p.under) + (Impl $p.over)); $oth = (Impl $o.under) / ((Impl $o.under) + (Impl $o.over)); $d += ($oth - $fan) } }
  $nPair = $d.Count
  if($nPair){ $gap = ($d | Measure-Object -Average).Average
    "Prices, slate {0}: on {1} matching assist lines FanDuel gives the under {2:+0.0;-0.0} points more chance than Fanatics" -f $date, $nPair, ($gap*100)
    "  (near zero = the books agree. A gap opening up means one of them has repriced assists.)" }
  else { "Prices, slate $date`: no assist lines priced at both books" } }
else { "Prices: no site\slate.json to compare" }

# ---- history
if(-not $NoSave){ $hf = Join-Path $root "tracking\edge-watch.json"
  $hist = @(if(Test-Path $hf){ [IO.File]::ReadAllText($hf) | ConvertFrom-Json })
  $row = [pscustomobject][ordered]@{ run = (Get-Date).ToUniversalTime().ToString("o"); through = $(if($ast.Count){ $ast[-1].date }); seasonW = $all.w; seasonL = $all.l
    lastN = $recent.n; lastW = $recent.w; lastRate = $(if($recent.rate -ne $null){ [math]::Round($recent.rate, 3) }); state = $state
    slate = $date; pairs = $nPair; gapPts = $(if($gap -ne $null){ [math]::Round($gap*100, 2) }) }
  $hist = @($hist | ? { -not ($_.through -eq $row.through -and $_.slate -eq $row.slate) }) + $row
  [IO.File]::WriteAllText($hf, (ConvertTo-Json @($hist) -Depth 4), (New-Object Text.UTF8Encoding $false))
  if($hist.Count -gt 1){ "Trend (last runs): " + ((@($hist | Select-Object -Last 6) | % { "$($_.through) $([math]::Round(100*$_.lastRate))%" + $(if($_.gapPts -ne $null){ " gap $($_.gapPts)" }) }) -join "  |  ") } }
if($state -in 'WATCH','ALARM'){ "`n$state`: assist unders have cooled. Tell the user before the next card, and consider smaller stakes until it recovers."; exit 2 }
