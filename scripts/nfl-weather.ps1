param([int]$Season = 2026, [Parameter(Mandatory)][int]$Week)
# NFL pilot: game-time wind forecast for a week, tracking\nfl\weather-<S>-w<NN>.json, read by the card freeze (nfl.html).
# Venue, city and roof from ESPN's scoreboard (retractable roofs count as indoor, as ESPN marks them); the city's coordinates
# from Open-Meteo's geocoder; wind from Open-Meteo's forecast: 10 m wind in mph averaged over kickoff to +3 hours (gusts,
# temperature and rain kept for reference). Open-Meteo is free and needs no account. Forecasts go out 16 days but are only
# good a couple of days ahead, so re-run it on game day before a game-day freeze.
# Why: QBs threw ~85-88% of their usual yards in 15+ mph wind (2024, 2025); the model takes passing projections down past
# 14 mph (P0.windF, Nov 13). nflverse only records wind after the game, so live cards need this forecast.
#   ./scripts/nfl-weather.ps1 -Week 11
$ErrorActionPreference = "Stop"
$root = Split-Path $PSScriptRoot -Parent
$out = Join-Path $root ("tracking\nfl\weather-{0}-w{1:D2}.json" -f $Season, $Week)
$TEAM = @{ WSH = 'WAS'; LAR = 'LA' }                      # ESPN abbreviations -> the model's (nflverse)
$CC = @{ USA = 'US'; Germany = 'DE'; England = 'GB'; 'United Kingdom' = 'GB'; Mexico = 'MX'; Brazil = 'BR'; Spain = 'ES'; Ireland = 'IE'; Australia = 'AU'; France = 'FR'; Canada = 'CA' }
# states with an NFL venue (ESPN gives the abbreviation, the geocoder the name; PowerShell names are case-blind, hence no $cc)
$STATE = @{ AZ='Arizona'; CA='California'; CO='Colorado'; FL='Florida'; GA='Georgia'; IL='Illinois'; IN='Indiana'; LA='Louisiana'; MA='Massachusetts'
  MD='Maryland'; MI='Michigan'; MN='Minnesota'; MO='Missouri'; NC='North Carolina'; NJ='New Jersey'; NV='Nevada'; NY='New York'; OH='Ohio'
  PA='Pennsylvania'; TN='Tennessee'; TX='Texas'; WA='Washington'; WI='Wisconsin' }
$ab = { param($a) $x = [string]$a; if($TEAM[$x]){ $TEAM[$x] } else { $x } }
$sb = Invoke-RestMethod "https://site.api.espn.com/apis/site/v2/sports/football/nfl/scoreboard?seasontype=2&week=$Week&dates=$Season"
$geo = @{}; $games = @()
foreach($e in $sb.events){ $c = $e.competitions[0]; $v = $c.venue
  $hm = & $ab (($c.competitors | ? homeAway -eq 'home').team.abbreviation); $away = & $ab (($c.competitors | ? homeAway -eq 'away').team.abbreviation)
  $start = [datetime]::Parse($e.date, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::AdjustToUniversal)
  $g = [ordered]@{ game = "$away @ $hm"; start = $start.ToString("yyyy-MM-ddTHH:mm:ssZ"); venue = $v.fullName; city = ($v.address.city, $v.address.state, $v.address.country | ? { $_ }) -join ', '; indoor = [bool]$v.indoor; wind = $null }
  if($g.indoor){ $g.wind = 0; $games += [pscustomobject]$g; continue }
  # coordinates: the venue's city in its country (state checked when there are several)
  $key = $g.city; if(-not $geo.ContainsKey($key)){
    $code = $CC[[string]$v.address.country]; $q = "https://geocoding-api.open-meteo.com/v1/search?name=$([uri]::EscapeDataString($v.address.city))&count=10&language=en&format=json" + $(if($code){ "&countryCode=$code" })
    $hits = @((Invoke-RestMethod $q).results | ? { $_ }); $st = [string]$v.address.state; $stName = if($STATE[$st]){ $STATE[$st] } else { $st }
    $pick = if($st -and $hits.Count -gt 1){ $m = @($hits | ? { $_.admin1 -eq $stName }); if($m.Count){ $m[0] } else { $hits[0] } } elseif($hits.Count){ $hits[0] } else { $null }
    $geo[$key] = $pick }
  $p = $geo[$key]; if(-not $p){ Write-Warning "no coordinates for $($g.game) ($key)"; $games += [pscustomobject]$g; continue }
  $g.lat = [math]::Round($p.latitude, 3); $g.lon = [math]::Round($p.longitude, 3)
  $d0 = $start.ToString('yyyy-MM-dd'); $d1 = $start.AddHours(4).ToString('yyyy-MM-dd')
  $u = "https://api.open-meteo.com/v1/forecast?latitude=$($g.lat)&longitude=$($g.lon)&hourly=wind_speed_10m,wind_gusts_10m,temperature_2m,precipitation&wind_speed_unit=mph&temperature_unit=fahrenheit&precipitation_unit=inch&timezone=GMT&start_date=$d0&end_date=$d1"
  try { $f = (Invoke-RestMethod $u).hourly } catch { Write-Warning "no forecast for $($g.game): $($_.Exception.Message)"; $games += [pscustomobject]$g; continue }
  $k0 = $start.ToString('yyyy-MM-ddTHH:00'); $i0 = [array]::IndexOf([string[]]$f.time, $k0)
  if($i0 -lt 0){ Write-Warning "kickoff hour not in the forecast for $($g.game)"; $games += [pscustomobject]$g; continue }
  $ix = $i0..([math]::Min($i0 + 3, $f.time.Count - 1)); $avg = { param($a) $x = @($ix | % { $a[$_] } | ? { $_ -ne $null }); if($x.Count){ ($x | Measure-Object -Average).Average } else { $null } }
  # wind: put on nflverse's scale, which the model was tested on. Open-Meteo's modeled wind against nflverse's recorded wind,
  # 40 outdoor 2025 games (weeks 7, 11, 13, 16): correlation .83, nflverse = 1.8 + 0.92 x Open-Meteo (it reads low in wind)
  $w = & $avg $f.wind_speed_10m; if($w -ne $null){ $g.windRaw = [math]::Round($w, 1); $g.wind = [math]::Round(1.8 + 0.92 * $w, 1) }
  $gu = & $avg $f.wind_gusts_10m; if($gu -ne $null){ $g.gust = [math]::Round($gu, 1) }
  $t = & $avg $f.temperature_2m; if($t -ne $null){ $g.temp = [math]::Round($t) }
  $g.rain = [math]::Round((@($ix | % { [double]$f.precipitation[$_] }) | Measure-Object -Sum).Sum, 2)
  $games += [pscustomobject]$g }
$doc = [ordered]@{ season = $Season; week = $Week; fetched = (Get-Date).ToUniversalTime().ToString("o")
  source = "ESPN venue and roof; Open-Meteo forecast, 10 m wind in mph averaged kickoff to +3 h (windRaw), on nflverse's scale (wind = 1.8 + 0.92 x windRaw)"; games = $games }
[IO.File]::WriteAllText($out, ($doc | ConvertTo-Json -Depth 4), (New-Object Text.UTF8Encoding $false))
$games | % { "{0,-11} {1,-28} {2}" -f $_.game, $_.venue, $(if($_.indoor){ 'indoors' } elseif($_.wind -eq $null){ 'no forecast' } else { "wind $($_.wind) mph (gusts $($_.gust)), $($_.temp)F, rain $($_.rain) in" + $(if($_.wind -gt 14){ '  <- passing projections lowered' }) }) }
"wrote $out"
