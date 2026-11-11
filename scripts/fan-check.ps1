# Lists every Fanatics (Action Network book 2988) entry for one player across the cached prop files of a date,
# alt markets included, so a card line can be checked against what the feed actually posted.
#   .\scripts\fan-check.ps1 -Date 20261111 -Player Burries
param([string]$Date, [string]$Player)
$root = Split-Path $PSScriptRoot
Get-ChildItem (Join-Path $root "raw") -Filter "an_props_${Date}_*.json" | ForEach-Object {
  $t = $_.BaseName -replace "^an_props_${Date}_", ""
  $j = Get-Content $_.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
  $ids = @($j.players | Where-Object { $_.full_name -like "*$Player*" })
  foreach($p in $ids){
    $rows = @($j.markets.'2988'.event.$t | Where-Object { $_.player_id -eq $p.id })
    foreach($r in ($rows | Sort-Object is_alt_market, value, side)){
      "{0,-40} {1,-22} {2,-5} {3,5} {4,6} alt={5} status={6} file={7:HH:mm}" -f $t, $p.full_name, $r.side, $r.value, $r.odds, $r.is_alt_market, $r.line_status, $_.LastWriteTime
    }
  }
}
