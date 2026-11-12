param([int]$Season = 2026, [switch]$Refetch)
# NFL pilot: play-level matchup data, tracking\nfl\plays.json, from nflverse play-by-play (2025-<Season>), FTN charting
# (blitzers, pass rushers, defenders in the box; 2025-<Season>) and pbp participation (man/zone and coverage shell; 2025 only,
# nflverse hasn't published 2026). One row per regular-season pass dropback or designed run:
#   [season, week, off, def, kind (1 dropback, 2 run), passer, target, rusher, yards, complete, tdPlayer, yardline100,
#    airYards, blitzers (-1 unknown), box (-1 unknown), manZone (0 unknown, 1 man, 2 zone), coverage ("" unknown)]
# Player ids are indexes into ids[] (gsis ids, the same ids as the weekly stats).
$ErrorActionPreference = "Stop"
$root = Split-Path $PSScriptRoot -Parent; $raw = Join-Path $root "raw/nfl"; $out = Join-Path $root "tracking/nfl"
$UA = @{"User-Agent"="Mozilla/5.0"}; $base = "https://github.com/nflverse/nflverse-data/releases/download"
function Get-File($rel, [bool]$cur){ $f = Join-Path $raw (Split-Path $rel -Leaf); if(-not (Test-Path $f) -or ($cur -and $Refetch)){ Invoke-WebRequest -UseBasicParsing "$base/$rel" -Headers $UA -OutFile $f -TimeoutSec 600 }; $f }
Add-Type -ReferencedAssemblies Microsoft.VisualBasic -TypeDefinition @"
using System; using System.IO; using System.IO.Compression; using System.Collections.Generic; using Microsoft.VisualBasic.FileIO;
public static class CsvPick {
  // streams a CSV (optionally .gz) and returns only the named columns of every row
  public static List<string[]> Read(string path, string[] cols){
    Stream s = File.OpenRead(path); if(path.EndsWith(".gz")) s = new GZipStream(s, CompressionMode.Decompress);
    var res = new List<string[]>();
    using(var p = new TextFieldParser(s)){ p.TextFieldType = FieldType.Delimited; p.SetDelimiters(","); p.HasFieldsEnclosedInQuotes = true;
      string[] head = p.ReadFields(); int[] ix = new int[cols.Length];
      for(int i=0;i<cols.Length;i++){ ix[i] = Array.IndexOf(head, cols[i]); if(ix[i] < 0) throw new Exception("no column " + cols[i] + " in " + path); }
      while(!p.EndOfData){ string[] f = p.ReadFields(); var r = new string[cols.Length]; for(int i=0;i<cols.Length;i++) r[i] = ix[i] < f.Length ? f[ix[i]] : ""; res.Add(r); } }
    return res; } }
"@
function N($x){ if($x -eq '' -or $x -eq 'NA' -or $x -eq $null){ $null } else { [double]$x } }
$ids = New-Object System.Collections.Generic.List[string]; $idx = @{}
function Id($g){ if(-not $g -or $g -eq 'NA'){ return -1 }; if(-not $idx.ContainsKey($g)){ $idx[$g] = $ids.Count; $ids.Add($g) }; $idx[$g] }
$rows = New-Object System.Collections.ArrayList
foreach($s in 2025..$Season){
  $cur = ($s -eq $Season)
  $ftn = @{}
  foreach($r in [CsvPick]::Read((Get-File "ftn_charting/ftn_charting_$s.csv" $cur), @("nflverse_game_id","nflverse_play_id","n_blitzers","n_defense_box"))){ $ftn["$($r[0])|$($r[1])"] = $r }
  $par = @{}; $pf = Join-Path $raw "pbp_participation_$s.csv"
  if($s -eq 2025){ $pf = Get-File "pbp_participation/pbp_participation_$s.csv" $false }
  if(Test-Path $pf){ foreach($r in [CsvPick]::Read($pf, @("nflverse_game_id","play_id","defense_man_zone_type","defense_coverage_type"))){ $par["$($r[0])|$($r[1])"] = $r } }
  $cols = @("game_id","play_id","season","week","season_type","posteam","defteam","play_type","qb_dropback","rush_attempt","two_point_attempt","passer_player_id","receiver_player_id","rusher_player_id","yards_gained","complete_pass","td_player_id","yardline_100","air_yards","qb_scramble","qb_hit","sack")
  $n0 = $rows.Count; $nb = 0; $nc = 0
  foreach($r in [CsvPick]::Read((Get-File "pbp/play_by_play_$s.csv.gz" $cur), $cols)){
    if($r[4] -ne 'REG' -or $r[10] -eq '1' -or -not $r[5]){ continue }
    $drop = ($r[8] -eq '1'); $run = ($r[9] -eq '1' -and $r[19] -ne '1')
    if(-not $drop -and -not $run){ continue }
    $k = "$($r[0])|$([int][double]$r[1])"; $f = $ftn[$k]; $p = $par[$k]
    $bl = if($f -and $f[2] -ne ''){ [int]$f[2] } else { -1 }; $bx = if($f -and $f[3] -ne ''){ [int]$f[3] } else { -1 }
    $mz = if($p){ switch($p[2]){ 'MAN_COVERAGE' { 1 } 'ZONE_COVERAGE' { 2 } default { 0 } } } else { 0 }
    $cv = if($p -and $p[3] -and $p[3] -ne 'NA'){ $p[3] } else { "" }
    if($bl -ge 0){ $nb++ }; if($mz){ $nc++ }
    $yd = N $r[14]; $ay = N $r[18]
    [void]$rows.Add(@([int]$r[2], [int]$r[3], $r[5], $r[6], $(if($drop){1}else{2}), (Id $r[11]), (Id $r[12]), (Id $r[13]), $(if($yd -ne $null){[int]$yd}else{0}), [int]($r[15] -eq '1'), (Id $r[16]), [int](N $r[17]), $(if($ay -ne $null){[int]$ay}else{$null}), $bl, $bx, $mz, $cv,
      # pressure (Nov 12): a dropback that ended in a sack, a QB hit or a scramble
      [int]($drop -and ($r[19] -eq '1' -or $r[20] -eq '1' -or $r[21] -eq '1')))) }
  "$s : $($rows.Count - $n0) plays, $nb with FTN blitz/box, $nc with man/zone coverage"
}
$obj = [ordered]@{ built=(Get-Date).ToUniversalTime().ToString("o"); cols=@("season","week","off","def","kind","passer","target","rusher","yds","cmp","td","yl","air","blitz","box","mz","cov","press"); ids=$ids; plays=$rows }
$of = Join-Path $out "plays.json"; [IO.File]::WriteAllText($of, ($obj | ConvertTo-Json -Depth 4 -Compress))
"wrote $of $((Get-Item $of).Length) bytes"
