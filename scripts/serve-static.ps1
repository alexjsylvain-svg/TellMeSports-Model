# Plain static file server for checking the viewer build locally (viewer\ as Cloudflare Pages would serve it).
#   powershell -File scripts\serve-static.ps1 -Dir viewer -Port 8766
param([string]$Dir = "viewer", [int]$Port = 8766)
$root = Split-Path $PSScriptRoot -Parent
if(-not [IO.Path]::IsPathRooted($Dir)){ $Dir = Join-Path $root $Dir }
$types = @{ ".html"="text/html; charset=utf-8"; ".json"="application/json"; ".svg"="image/svg+xml"; ".png"="image/png"; ".webmanifest"="application/manifest+json"; ".js"="text/javascript"; ".css"="text/css" }
$l = New-Object Net.HttpListener; $l.Prefixes.Add("http://localhost:$Port/"); $l.Start(); "serving $Dir on http://localhost:$Port/"
while($l.IsListening){ $c = $l.GetContext(); try{
  $p = [Uri]::UnescapeDataString($c.Request.Url.AbsolutePath).TrimStart('/'); if(-not $p -or $p.EndsWith('/')){ $p += "index.html" }
  $f = [IO.Path]::GetFullPath((Join-Path $Dir $p))
  if(-not $f.StartsWith([IO.Path]::GetFullPath($Dir)) -or -not (Test-Path $f -PathType Leaf) -or (Split-Path $f -Leaf) -eq '_headers'){ $c.Response.StatusCode = 404; $c.Response.Close(); continue }
  $b = [IO.File]::ReadAllBytes($f); $ext = [IO.Path]::GetExtension($f).ToLower()
  $c.Response.ContentType = if($types[$ext]){ $types[$ext] } else { "application/octet-stream" }
  $c.Response.Headers.Add("Cache-Control","no-store"); $c.Response.OutputStream.Write($b,0,$b.Length); $c.Response.Close()
} catch { try{ $c.Response.StatusCode = 500; $c.Response.Close() }catch{} } }
