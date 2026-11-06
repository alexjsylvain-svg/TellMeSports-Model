param([string]$Date = "20261021", [string]$Out = "site/live.json")
# Live game state for in-progress and finished games: score, period, clock, player box scores (ESPN),
# plus current in-game lines by book (Action Network). The page simulates the rest of each game from this state.
# Paths use forward slashes so this also runs on Linux (GitHub Actions); Windows accepts them too.
$ErrorActionPreference = "Stop"
. "$PSScriptRoot/lib.ps1"
$root = Split-Path $PSScriptRoot -Parent
$sb = Get-Json "https://site.api.espn.com/apis/site/v2/sports/basketball/nba/scoreboard?dates=$Date"
$games = @()
foreach($e in $sb.events){
  $st = $e.competitions[0].status
  if($st.type.state -eq 'pre'){ continue }
  $s = Get-Json "https://site.api.espn.com/apis/site/v2/sports/basketball/nba/summary?event=$($e.id)"
  if(-not $s){ continue }
  $comp = $s.header.competitions[0]
  $score = @{}; foreach($c in $comp.competitors){ $score[$c.homeAway] = [int]$c.score }
  $teams = @()
  foreach($tp in $s.boxscore.players){
    $labels = $tp.statistics[0].labels
    $pl = @()
    foreach($a in $tp.statistics[0].athletes){
      $row = [ordered]@{ name=$a.athlete.displayName; starter=[bool]$a.starter; dnp=[bool]$a.didNotPlay; ejected=[bool]$a.ejected; reason=$a.reason }
      for($k=0; $k -lt $labels.Count -and $k -lt $a.stats.Count; $k++){
        $v = $a.stats[$k]; $lab = $labels[$k]
        if($v -match '^(\d+)-(\d+)$'){ $row[$lab+'M']=[int]$matches[1]; $row[$lab+'A']=[int]$matches[2] }
        elseif($v -match '^[+-]?\d+$'){ $row[$lab]=[int]$v }
        else { $row[$lab]=$null }
      }
      $pl += $row
    }
    $teams += [ordered]@{ abbr=$tp.team.abbreviation; players=$pl }
  }
  $games += [ordered]@{ espnId=$e.id; state=$st.type.state; detail=$st.type.shortDetail; period=[int]$st.period; clock=[double]$st.clock; away=$score['away']; home=$score['home']; teams=$teams }
}
# in-game lines (DraftKings, FanDuel, Fanatics, Caesars) when books post them
$an = Get-Json "https://api.actionnetwork.com/web/v2/scoreboard/nba?bookIds=68,69,2988,123&date=$Date&periods=event"
$BOOKS = @{ "68"="DK"; "69"="FD"; "2988"="FAN"; "123"="CZR" }
$liveLines = @{}
if($an){ foreach($ag in $an.games){
  $ha = $ag.teams | ? { $_.id -eq $ag.home_team_id }
  $lines = [ordered]@{}
  if($ag.status -ne 'inprogress'){ continue }
  foreach($bk in $BOOKS.Keys){ $m = $ag.markets.$bk; $ev = if($m.live){ $m.live } elseif($m.event){ $m.event } else { $null }
    if(-not $ev){ continue }
    $sh_ = $ev.spread | ? { $_.side -eq 'home' } | Select-Object -First 1; $sa_ = $ev.spread | ? { $_.side -eq 'away' } | Select-Object -First 1
    $ov = $ev.total | ? { $_.side -eq 'over' } | Select-Object -First 1; $un = $ev.total | ? { $_.side -eq 'under' } | Select-Object -First 1
    $mh = $ev.moneyline | ? { $_.side -eq 'home' } | Select-Object -First 1; $ma = $ev.moneyline | ? { $_.side -eq 'away' } | Select-Object -First 1
    $lines[$BOOKS[$bk]] = [ordered]@{ spread=$sh_.value; spreadHome=$sh_.odds; spreadAway=$sa_.odds; total=$ov.value; over=$ov.odds; under=$un.odds; mlHome=$mh.odds; mlAway=$ma.odds } }
  if($lines.Count){ $liveLines[(Norm-Name $ha.full_name)] = $lines } } }
foreach($g in $games){ $hn = ($sb.events | ? { $_.id -eq $g.espnId }).competitions[0].competitors | ? { $_.homeAway -eq 'home' } | Select-Object -First 1
  $k = Norm-Name $hn.team.displayName; if($liveLines.ContainsKey($k)){ $g['liveLines'] = $liveLines[$k] } }
$outObj = [ordered]@{ generated=(Get-Date).ToUniversalTime().ToString("o"); games=$games }
$outPath = Join-Path $root $Out
[IO.File]::WriteAllText($outPath, ($outObj | ConvertTo-Json -Depth 10 -Compress))
foreach($g in $games){ "{0} {1} {2}-{3} P{4} {5}s players={6} liveLines={7}" -f $g.espnId, $g.state, $g.away, $g.home, $g.period, $g.clock, (($g.teams | % { $_.players.Count }) -join '/'), [bool]$g.liveLines }
"wrote $outPath"
