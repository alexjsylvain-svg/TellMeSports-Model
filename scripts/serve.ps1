param([string]$Page, [string]$Data, [string]$VideoDir, [int]$Port = 8765)
# Local preview server: serves the page and slate.json, and saves recorded videos POSTed to /upload?name=...
New-Item -ItemType Directory -Force $VideoDir | Out-Null
$l = New-Object System.Net.HttpListener
$l.Prefixes.Add("http://localhost:$Port/")
$l.Start()
while ($l.IsListening) {
  $c = $l.GetContext()
  $path = $c.Request.Url.AbsolutePath
  # Other websites must not drive this server (Nov 12, 2026 security review). Browsers label every request with where it
  # came from: a write must come from this page itself, and the autopilot (?auto, ?lock, ?placed, ?ovr, ?run) only starts
  # from a typed or scripted address (night.ps1, the preview pane), never from a link or form on another site.
  # Local scripts (Invoke-WebRequest) send neither header and are allowed.
  $site = $c.Request.Headers["Sec-Fetch-Site"]; $origin = $c.Request.Headers["Origin"]
  $foreign = ($site -and $site -ne "same-origin" -and $site -ne "none") -or ($origin -and $origin -ne "http://localhost:$Port")
  $pilot = [Uri]::UnescapeDataString($c.Request.Url.Query) -match '[?&](auto|lock|placed|ovr|run)(=|&|$)'
  if ($foreign -and ($c.Request.HttpMethod -ne "GET" -or $pilot)) {
    $c.Response.StatusCode = 403; $b = [Text.Encoding]::UTF8.GetBytes("blocked: request from another site")
    $c.Response.OutputStream.Write($b, 0, $b.Length); $c.Response.Close(); continue
  }
  if ($c.Request.HttpMethod -eq "POST" -and $path -eq "/upload") {
    $name = [IO.Path]::GetFileName($c.Request.QueryString["name"])
    if ($name -notmatch '^[\w\-.]+\.(mp4|webm|json)$') { $c.Response.StatusCode = 400; $c.Response.Close(); continue }
    # videos go to the video folder; JSON records (frozen picks) go to tracking\ next to the project
    $dir = if ($name -like "*.json") { Join-Path (Split-Path $VideoDir) "tracking" } else { $VideoDir }
    New-Item -ItemType Directory -Force $dir | Out-Null
    $dest = Join-Path $dir $name
    # a frozen picks file is a record: never replaced unless the caller asks explicitly (?overwrite=1)
    if ($name -like "picks-*.json" -and (Test-Path $dest) -and $c.Request.QueryString["overwrite"] -ne "1") { $c.Response.StatusCode = 409; $c.Response.Close(); continue }
    $fs = [IO.File]::Create($dest); $c.Request.InputStream.CopyTo($fs); $fs.Close()
    $b = [Text.Encoding]::UTF8.GetBytes("ok"); $c.Response.ContentType = "text/plain"
  } elseif ($path -match '^/tracking/((picks|bt-props|results)-\d{8}\.json)$') {
    # read-only access to a frozen picks file, so a re-freeze can keep locked (already tipped) games' picks
    $f = Join-Path (Join-Path (Split-Path $VideoDir) "tracking") $matches[1]
    if (-not (Test-Path $f)) { $c.Response.StatusCode = 404; $c.Response.Close(); continue }
    $b = [IO.File]::ReadAllBytes($f); $c.Response.ContentType = "application/json"
  } elseif ($path -eq '/next') {
    # preview copy of the dashboard (dashboard-next.html), never published by push-site.ps1
    $f = Join-Path (Split-Path $Page) "dashboard-next.html"
    if (-not (Test-Path $f)) { $c.Response.StatusCode = 404; $c.Response.Close(); continue }
    $b = [IO.File]::ReadAllBytes($f); $c.Response.ContentType = "text/html; charset=utf-8"
  } elseif ($path -eq '/nfl' -or $path -eq '/nfl/') {
    # NFL pilot page (nfl.html next to the NBA page) and its data files (tracking\nfl)
    $b = [IO.File]::ReadAllBytes((Join-Path (Split-Path $Page) "nfl.html")); $c.Response.ContentType = "text/html; charset=utf-8"
  } elseif ($path -match '^/nfl/([\w\-.]+\.json)$') {
    $f = Join-Path (Join-Path (Join-Path (Split-Path $VideoDir) "tracking") "nfl") $matches[1]
    if (-not (Test-Path $f)) { $c.Response.StatusCode = 404; $c.Response.Close(); continue }
    $b = [IO.File]::ReadAllBytes($f); $c.Response.ContentType = "application/json"
  } elseif ($path -eq '/harness.js') {
    # backtest harness for the local preview (scripts\harness.js)
    $b = [IO.File]::ReadAllBytes((Join-Path $PSScriptRoot "harness.js")); $c.Response.ContentType = "text/javascript"
  } elseif ($path -match '^/(slate|live|results|finals|picks|board|season|boxes|alerts|creates)\.json$') {
    # picks, board, season and boxes are the phone view's files; they're only there when the -Data folder holds them
    $f = Join-Path (Split-Path $Data) ($matches[1] + ".json")
    # the /next preview falls back to the published copy (docs\) so its NBA side shows the current card
    if (-not (Test-Path $f) -and (($c.Request.UrlReferrer -and $c.Request.UrlReferrer.AbsolutePath -eq '/next') -or $matches[1] -eq 'alerts')) { $f = Join-Path (Join-Path (Split-Path $PSScriptRoot) "docs") ($matches[1] + ".json") }
    if (-not (Test-Path $f)) { $c.Response.StatusCode = 404; $c.Response.Close(); continue }
    $b = [IO.File]::ReadAllBytes($f); $c.Response.ContentType = "application/json"
  } else {
    $body = "<!doctype html><html><head><meta charset=`"utf-8`"><meta name=`"viewport`" content=`"width=device-width,initial-scale=1`"></head><body>" + [IO.File]::ReadAllText($Page) + "</body></html>"
    $b = [Text.Encoding]::UTF8.GetBytes($body); $c.Response.ContentType = "text/html; charset=utf-8"
  }
  $c.Response.OutputStream.Write($b, 0, $b.Length)
  $c.Response.Close()
}
