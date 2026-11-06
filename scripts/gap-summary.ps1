param([string]$Tag = "gap")
# Sums tracking\harness-<date>-<tag>.json files (from harness.js __PK) across nights: record, flat units and staked units per variant
$ErrorActionPreference = "Stop"
$trk = Join-Path (Split-Path $PSScriptRoot -Parent) "tracking"
$tot = [ordered]@{}; $nights = @()
foreach($f in Get-ChildItem $trk -Filter "harness-*-$Tag.json" | Sort-Object Name){
  # (Windows PowerShell hands a JSON array down the pipeline as one object; unroll it)
  $r = @(Get-Content $f.FullName -Raw -Encoding UTF8 | ConvertFrom-Json | ForEach-Object { $_ })
  if($r[0].PSObject.Properties.Name -contains 'error'){ "$($f.Name): ERROR $($r[0].error)"; continue }
  $nights += $f.Name.Split('-')[1]
  foreach($v in $r){ if(-not $tot[$v.v]){ $tot[$v.v] = @{ w=0; l=0; u=0.0; s=0.0; k=0.0; drop=@() } }
    $t = $tot[$v.v]; $t.w += $v.w; $t.l += $v.l; $t.u += $v.units; $t.s += $v.staked; $t.k += $v.risked
    foreach($d in @($v.dropped)){ if($d){ $t.drop += "$($f.Name.Split('-')[1]) $d" } } } }
"nights: $($nights -join ', ')"
foreach($k in $tot.Keys){ $t = $tot[$k]; "{0,-5} {1,3}-{2,-3} flat {3,7:+0.00;-0.00}u   staked {4,7:+0.00;-0.00}u of {5,5:0.0}u" -f $k, $t.w, $t.l, $t.u, $t.s, $t.k }
foreach($k in $tot.Keys){ if($tot[$k].drop.Count){ "--- $k drops:"; $tot[$k].drop } }
