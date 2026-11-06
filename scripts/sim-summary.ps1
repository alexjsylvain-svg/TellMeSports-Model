param([string]$Tag = "tast")
# Sums tracking\harness-<date>-<tag>.json files from harness.js __PKS across nights: picks (flat and staked), assist-prop Brier and
# bias (sim mean minus real assists), and team assist totals (mean absolute error and bias against the real box score)
$ErrorActionPreference = "Stop"
$trk = Join-Path (Split-Path $PSScriptRoot -Parent) "tracking"
$tot = [ordered]@{}; $nights = @()
foreach($f in Get-ChildItem $trk -Filter "harness-*-$Tag.json" | Sort-Object Name){
  $r = @(Get-Content $f.FullName -Raw -Encoding UTF8 | ConvertFrom-Json | ForEach-Object { $_ })
  if($r[0].PSObject.Properties.Name -contains 'error'){ "$($f.Name): ERROR $($r[0].error)"; continue }
  $nights += $f.Name.Split('-')[1]
  foreach($v in $r){ if(-not $tot[$v.v]){ $tot[$v.v] = @{ w=0; l=0; u=0.0; s=0.0; k=0.0; br=0.0; bias=0.0; na=0; te=0.0; tb=0.0; nt=0 } }
    $t = $tot[$v.v]; $t.w += $v.w; $t.l += $v.l; $t.u += $v.units; $t.s += $v.staked; $t.k += $v.risked
    if($v.astN){ $t.br += $v.astBrier*$v.astN; $t.bias += $v.astBias*$v.astN; $t.na += $v.astN }
    if($v.teams){ $t.te += $v.teamAstMAE*$v.teams; $t.tb += $v.teamAstBias*$v.teams; $t.nt += $v.teams } } }
"nights: $($nights -join ', ')"
foreach($k in $tot.Keys){ $t = $tot[$k]
  "{0,-5} picks {1,3}-{2,-3} flat {3,7:+0.00;-0.00}u staked {4,7:+0.00;-0.00}u of {5,5:0.0}u | AST props n={6} Brier {7:0.0000} bias {8:+0.00;-0.00} | team AST MAE {9:0.0} bias {10:+0.0;-0.0}" -f $k, $t.w, $t.l, $t.u, $t.s, $t.k, $t.na, ($t.br/[math]::Max(1,$t.na)), ($t.bias/[math]::Max(1,$t.na)), ($t.te/[math]::Max(1,$t.nt)), ($t.tb/[math]::Max(1,$t.nt)) }
