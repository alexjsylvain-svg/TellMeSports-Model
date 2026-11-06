param([string[]]$Dates, [switch]$Refetch)
# Closing-line value for every graded recommended pick: how the price we took compares with Fanatics' last pregame line.
# Closing lines: Action Network's feed for a past date (book 2988 = Fanatics), which serves each prop's last pregame
# price once the night is over. Cached as raw\an_close_<date>.json, fetched only for nights already graded, so the cache
# is the close, never a mid-day line (the build's own raw\an_props_<date>.json is a mid-day snapshot and isn't used).
# Writes tracking\clv.json: { "<date>|<bet>": { cLine, cOdds, cOther, clv, cEv, fav } } where (same line only, else null)
#   clv = fair (no-vig) closing chance of our side minus the fair chance at the price we took, in points: positive means
#         the market moved toward our side after we bet. The fair chance at our price uses that night's archived slate
#         pair (tracking\slate-<date>.json or the bt folder) when it has our exact line and price, else the closing hold.
#   cEv = expected profit per unit staked if the fair closing chance is the truth (the price we got against the close).
#   fav = how many points the line moved in our favour (over: close line - our line; under: our line - close line).
# season.ps1 merges this into season.json.
$ErrorActionPreference = "Stop"
$root = Split-Path $PSScriptRoot -Parent; $trk = Join-Path $root "tracking"; $raw = Join-Path $root "raw"
$UA = @{"User-Agent"="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/130.0 Safari/537.36"}
$TYPES = [ordered]@{ "core_bet_type_27_points"="PTS"; "core_bet_type_23_rebounds"="REB"; "core_bet_type_26_assists"="AST"; "core_bet_type_21_3fgm"="3PM";
  "core_bet_type_85_points_rebounds_assists"="PRA"; "core_bet_type_86_points_rebounds"="PR"; "core_bet_type_87_points_assists"="PA"; "core_bet_type_88_rebounds_assists"="RA" }
function Norm([string]$s){ ($s.Normalize([Text.NormalizationForm]::FormD) -replace '\p{Mn}','').ToLower() -replace "[.'\-,]"," " -replace '\b(jr|sr|ii|iii|iv)\b','' -replace '\s+',' ' | % { $_.Trim() } }
function Impl([double]$o){ if($o -gt 0){ 100/($o+100) } else { -$o/(-$o+100) } }
$today = (Get-Date).ToString("yyyyMMdd")
if(-not $Dates){ $Dates = Get-ChildItem $trk -Filter "results-*.json" | ? { $_.Name -match '^results-(\d{8})\.json$' } | % { $matches[1] } | Sort-Object }
$cf = Join-Path $trk "clv.json"
$out = [ordered]@{}; if(Test-Path $cf){ $old = [IO.File]::ReadAllText($cf) | ConvertFrom-Json; foreach($p in $old.PSObject.Properties){ $out[$p.Name] = $p.Value } }
foreach($d in $Dates){
  if($d -ge $today){ Write-Warning "$d : not over yet, no closing lines"; continue }
  $rf = Join-Path $trk "results-$d.json"; if(-not (Test-Path $rf)){ continue }
  $anf = Join-Path $raw "an_close_$d.json"
  if($Refetch -or -not (Test-Path $anf)){
    $rq = Invoke-WebRequest -UseBasicParsing "https://api.actionnetwork.com/web/v2/scoreboard/nba/markets?bookIds=2988&customPickTypes=$($TYPES.Keys -join ',')&date=$d" -Headers $UA -TimeoutSec 60
    [IO.File]::WriteAllText($anf, [Text.Encoding]::UTF8.GetString($rq.RawContentStream.ToArray())); Start-Sleep -Milliseconds 600 }
  $an = [IO.File]::ReadAllText($anf) | ConvertFrom-Json
  $nm = @{}; foreach($p in $an.players){ $nm[[string]$p.id] = Norm $p.full_name }
  $close = @{}
  foreach($t in $TYPES.Keys){
    $os = @($an.markets.'2988'.event.$t | ? { $_ -and -not $_.is_alt_market })
    foreach($grp in ($os | Group-Object player_id)){
      $o = $grp.Group | ? side -eq 'over' | Select-Object -First 1; $u = $grp.Group | ? side -eq 'under' | Select-Object -First 1; $pn = $nm[[string]$grp.Name]
      if($pn -and $o -and $u -and $o.value -eq $u.value){ $close["$pn|$($TYPES[$t])"] = @{ line=[double]$o.value; over=[double]$o.odds; under=[double]$u.odds } } } }
  $bt = Join-Path $trk ("bt" + $d.Substring(6,2))
  $sl = if($d -le "20261028" -and (Test-Path (Join-Path $bt "slate.json"))){ Join-Path $bt "slate.json" } else { Join-Path $trk "slate-$d.json" }
  $open = @{}; if(Test-Path $sl){ foreach($g in ([IO.File]::ReadAllText($sl) | ConvertFrom-Json).games){ foreach($q in @($g.fanProps | ? { $_ })){ $open["$(Norm $q.player)|$($q.stat)|$($q.line)"] = $q } } }
  $j = [IO.File]::ReadAllText($rf) | ConvertFrom-Json; $n = 0; $hit = 0; $paired = 0
  foreach($b in @($j.bets | ? { $_.set -eq 'recommended' })){
    if($b.bet -notmatch '^(.+) (over|under) ([\d.]+) ([A-Z0-9]+)$'){ continue }
    $pl = $matches[1]; $side = $matches[2]; $line = [double]$matches[3]; $stat = $matches[4]; $n++
    $c = $close["$(Norm $pl)|$stat"]; if(-not $c){ continue }; $hit++
    $mine = if($side -eq 'over'){ $c.over } else { $c.under }; $oth = if($side -eq 'over'){ $c.under } else { $c.over }
    $fav = if($side -eq 'over'){ $c.line - $line } else { $line - $c.line }
    $clv = $null; $cEv = $null
    if($c.line -eq $line){ $pm = Impl $mine; $po = Impl $oth; $fc = $pm/($pm+$po); $o = [double]$b.odds; $sum = $pm+$po
      $q = $open["$(Norm $pl)|$stat|$line"]
      if($q){ $qm = if($side -eq 'over'){ [double]$q.over } else { [double]$q.under }; $qo = if($side -eq 'over'){ [double]$q.under } else { [double]$q.over }
        if($qm -eq $o){ $sum = (Impl $qm) + (Impl $qo); $paired++ } }
      $clv = [math]::Round(100*($fc - (Impl $o)/$sum), 2)
      $dec = if($o -gt 0){ 1 + $o/100 } else { 1 + 100/(-$o) }; $cEv = [math]::Round($fc*$dec - 1, 4) }
    $out["$d|$($b.bet)"] = [ordered]@{ cLine=$c.line; cOdds=$mine; cOther=$oth; clv=$clv; cEv=$cEv; fav=$fav }
  }
  "$d : $hit of $n picks matched to a Fanatics close ($paired with the archived price pair)"
}
[IO.File]::WriteAllText($cf, ($out | ConvertTo-Json -Depth 4 -Compress))
"$($out.Count) picks with a close -> $cf"
