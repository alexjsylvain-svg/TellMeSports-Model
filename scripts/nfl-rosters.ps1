# NFL pilot: current rosters and depth charts, tracking\nfl\rosters.json, so the card and the game sims only use players who are
# on a team today (nflverse stats alone kept retired or released players, and players under their old team after a trade).
#   nfl.com  www.nfl.com/teams/<slug>/roster : name, position, roster status (ACT active, RES reserve/IR, PUP, NON, SUS, ...)
#   ESPN     site.api.espn.com .../teams/<id>/roster      : name, position, group (offense / injuredReserveOrOut / ...), injury status
#            site.api.espn.com .../teams/<id>/depthcharts : offensive depth chart (qb, rb, wr1, wr2, wr3, te) in order
# Team codes follow nflverse (ESPN WSH -> WAS, LAR -> LA).
$ErrorActionPreference = "Stop"
$root = Split-Path $PSScriptRoot -Parent; $out = Join-Path $root "tracking/nfl"
$UA = @{"User-Agent"="Mozilla/5.0"}; $api = "https://site.api.espn.com/apis/site/v2/sports/football/nfl"
$fix = @{ WSH="WAS"; LAR="LA" }
$teams = (Invoke-RestMethod "$api/teams" -Headers $UA -TimeoutSec 60).sports[0].leagues[0].teams | % { $_.team }
$res = [ordered]@{}; $miss = @()
foreach($t in $teams){
  $code = if($fix[$t.abbreviation]){ $fix[$t.abbreviation] } else { $t.abbreviation }
  $o = [ordered]@{ espn=@(); nfl=@(); depth=[ordered]@{} }
  try{
    $r = Invoke-RestMethod "$api/teams/$($t.id)/roster" -Headers $UA -TimeoutSec 60
    $o.espn = @(foreach($g in $r.athletes){ foreach($a in $g.items){ [ordered]@{ name=$a.displayName; id=$a.id; pos=$a.position.abbreviation; group=$g.position; status=$a.status.name; inj=(@($a.injuries | % { $_.status }) -join ",") } } })
  } catch { $miss += "$code espn roster" }
  try{
    $d = Invoke-RestMethod "$api/teams/$($t.id)/depthcharts" -Headers $UA -TimeoutSec 60
    $off = $d.depthchart | ? { $_.positions.PSObject.Properties.Name -contains "qb" } | Select-Object -First 1
    foreach($p in "qb","rb","wr1","wr2","wr3","te"){ if($off.positions.$p){ $o.depth[$p] = @($off.positions.$p.athletes | % { [ordered]@{ name=$_.displayName; inj=(@($_.injuries | % { $_.status }) -join ",") } }) } }
  } catch { $miss += "$code espn depth" }
  try{
    $h = (Invoke-WebRequest -UseBasicParsing "https://www.nfl.com/teams/$($t.slug)/roster" -Headers $UA -TimeoutSec 60).Content
    $o.nfl = @(foreach($row in [regex]::Matches($h,'(?s)<tr>.*?</tr>')){
      $c = @([regex]::Matches($row.Value,'(?s)<td[^>]*>(.*?)</td>') | % { (($_.Groups[1].Value -replace '(?s)<picture.*?</picture>','' -replace '<[^>]+>',' ') -replace '\s+',' ').Trim() })
      if($c.Count -ge 4 -and $c[0]){ [ordered]@{ name=[Net.WebUtility]::HtmlDecode($c[0]); pos=$c[2]; status=$c[3] } } })
  } catch { $miss += "$code nfl.com roster" }
  $res[$code] = $o
}
$obj = [ordered]@{ fetched=(Get-Date).ToUniversalTime().ToString("o"); sources="nfl.com team rosters; ESPN rosters, injuries and depth charts"; teams=$res }
$of = Join-Path $out "rosters.json"; [IO.File]::WriteAllText($of, ($obj | ConvertTo-Json -Depth 6 -Compress))
# ids.json: team -> normalized name -> ESPN athlete id, so the phone page can show headshots (same key as nfNm in the page)
$ids = [ordered]@{}; foreach($k in $res.Keys){ $m = [ordered]@{}; foreach($a in $res[$k].espn){ if($a.id){ $n = (($a.name.ToLower() -replace '[^a-z]','') -replace '(jr|sr|ii|iii|iv)$',''); if(-not $m.Contains($n)){ $m[$n] = "$($a.id)" } } }; $ids[$k] = $m }
[IO.File]::WriteAllText((Join-Path $out "ids.json"), ($ids | ConvertTo-Json -Depth 3 -Compress))
$n = ($res.Values | % { $_.nfl.Count }) | Measure-Object -Sum; $e = ($res.Values | % { $_.espn.Count }) | Measure-Object -Sum
"wrote $of : $($res.Count) teams, nfl.com $($n.Sum) players, ESPN $($e.Sum) players$(if($miss){"; missing: $($miss -join ', ')"})"
