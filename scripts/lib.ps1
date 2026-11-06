function Norm-Name([string]$s){
  if(-not $s){ return "" }
  $d = $s.Normalize([Text.NormalizationForm]::FormD)
  $sb = New-Object Text.StringBuilder
  foreach($ch in $d.ToCharArray()){ if([Globalization.CharUnicodeInfo]::GetUnicodeCategory($ch) -ne 'NonSpacingMark'){ [void]$sb.Append($ch) } }
  $n = $sb.ToString().ToLower() -replace "[\.\'\-,]", " " -replace "\b(jr|sr|ii|iii|iv)\b", "" -replace "\s+", " "
  return $n.Trim()
}

# Parse every <tr> in a bbref stats table into hashtables keyed by data-stat.
function Parse-BbrefRows([string]$html, [string]$tableId){
  $start = $html.IndexOf("id=`"$tableId`"")
  if($start -lt 0){ throw "table $tableId not found" }
  $tb = $html.IndexOf("<tbody", $start); $te = $html.IndexOf("</tbody>", $tb)
  if($tb -lt 0 -or $te -lt 0){ throw "tbody for $tableId not found" }
  $body = $html.Substring($tb, $te - $tb)
  $rows = @()
  foreach($m in [regex]::Matches($body, "<tr[^>]*>(.*?)</tr>", 'Singleline')){
    $tr = $m.Groups[1].Value
    if($tr -notmatch 'data-stat="(name_display|team_name|team)"'){ continue }
    $row = @{}
    foreach($c in [regex]::Matches($tr, '<t[dh][^>]*?(?:data-append-csv="([^"]*)")?[^>]*data-stat="([^"]+)"[^>]*>(.*?)</t[dh]>', 'Singleline')){
      $v = ($c.Groups[3].Value -replace '<[^>]+>', '').Trim()
      $row[$c.Groups[2].Value] = $v
      if($c.Groups[1].Value){ $row['bref_id'] = $c.Groups[1].Value }
    }
    $rows += ,$row
  }
  return $rows
}

function Get-Json([string]$url){
  $h = @{"User-Agent"="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/130.0 Safari/537.36"}
  for($i=0;$i -lt 3;$i++){
    try { return (Invoke-WebRequest -UseBasicParsing $url -Headers $h -TimeoutSec 40).Content | ConvertFrom-Json }
    catch { Start-Sleep -Milliseconds 800 }
  }
  Write-Warning "failed $url"; return $null
}

function F($x){ if($x -eq $null -or $x -eq ''){ return $null }; $d=0.0; if([double]::TryParse(($x -replace '^\.', '0.'), [ref]$d)){ return $d }; return $null }
