param([string]$Root = (Split-Path $PSScriptRoot -Parent), [double]$W = 0.24)
# Game lines (moneyline, spread, total) as pick candidates, over every graded night: the sim's raw call record, and what the
# props pick rule (blend the sim with the no-vig market at weight $W, 60%+ win chance, 5%+ edge, -150..+150) would have done.
# Spreads and totals are priced at the book's own odds from the archived slate (DraftKings, else FanDuel).
function Impl($o){ $o=[double]$o; if($o -lt 0){ -$o/(-$o+100) } else { 100/($o+100) } }
function Dec($o){ $o=[double]$o; if($o -lt 0){ 1+100/-$o } else { 1+$o/100 } }
function Lg($p){ $p=[math]::Min(0.99,[math]::Max(0.01,$p)); [math]::Log($p/(1-$p)) }
function Sg($x){ 1/(1+[math]::Exp(-$x)) }
$rows=@()
foreach($f in Get-ChildItem (Join-Path $Root "tracking\results-*.json")){
  $d = $f.BaseName -replace 'results-',''
  $pk = Join-Path $Root "tracking\picks-$d.json"; $sl = Join-Path $Root "tracking\slate-$d.json"
  if(-not (Test-Path $pk) -or -not (Test-Path $sl)){ continue }
  $res = Get-Content $f.FullName -Raw | ConvertFrom-Json; $calls = (Get-Content $pk -Raw | ConvertFrom-Json).calls; $slate = Get-Content $sl -Raw -Encoding UTF8 | ConvertFrom-Json
  foreach($c in $calls){
    $r = $res.gameCalls | ? gid -eq $c.gid; if(-not $r -or -not $r.final){ continue }
    $g = $slate.games | ? espnId -eq $c.gid; $l = if($g.lines.DK){ $g.lines.DK } else { $g.lines.FD }
    if($r.final -notmatch '(\d+)\s*-\s*(\d+)\s+\S+$'){ continue }; $as=[int]$matches[1]; $hs=[int]$matches[2]; $m=$hs-$as; $t=$hs+$as
    $simH = if($c.homeWinProb -ne $null){ [double]$c.homeWinProb } elseif($c.winner -eq $c.home){ [double]$c.winProb } else { 1-[double]$c.winProb }
    $simHc = if($c.atsPick -eq 'H'){ [double]$c.atsProb } else { 1-[double]$c.atsProb }
    $simO = if($c.totalPick -eq 'O'){ [double]$c.totalProb } else { 1-[double]$c.totalProb }
    $cands = @(
      @{ k='ML'; side='H'; pS=$simH; o=$l.mlHome; oo=$l.mlAway; win=($m -gt 0); push=$false },
      @{ k='ML'; side='A'; pS=1-$simH; o=$l.mlAway; oo=$l.mlHome; win=($m -lt 0); push=$false },
      @{ k='ATS'; side='H'; pS=$simHc; o=$l.spreadHome; oo=$l.spreadAway; win=(($m+[double]$l.spread) -gt 0); push=(($m+[double]$l.spread) -eq 0) },
      @{ k='ATS'; side='A'; pS=1-$simHc; o=$l.spreadAway; oo=$l.spreadHome; win=(($m+[double]$l.spread) -lt 0); push=(($m+[double]$l.spread) -eq 0) },
      @{ k='TOT'; side='O'; pS=$simO; o=$l.over; oo=$l.under; win=($t -gt [double]$l.total); push=($t -eq [double]$l.total) },
      @{ k='TOT'; side='U'; pS=1-$simO; o=$l.under; oo=$l.over; win=($t -lt [double]$l.total); push=($t -eq [double]$l.total) })
    foreach($x in $cands){ if($null -eq $x.o -or $null -eq $x.oo -or $x.push){ continue }
      $pm = (Impl $x.o)/((Impl $x.o)+(Impl $x.oo)); $p = Sg((1-$W)*(Lg $pm)+$W*(Lg $x.pS)); $ev = $p*(Dec $x.o)-1
      $rows += [pscustomobject]@{ d=$d; game="$($c.away)@$($c.home)"; k=$x.k; side=$x.side; o=[double]$x.o; pS=$x.pS; pm=$pm; p=$p; ev=$ev; win=$x.win; u=$(if($x.win){ (Dec $x.o)-1 } else { -1 }) } }
  } }
function Rec($s){ $s=@($s); $w=@($s|?{$_.win}).Count; $u=($s|measure u -Sum).Sum; "{0}-{1} ({2:P0}) {3:+0.00;-0.00}u" -f $w, ($s.Count-$w), $(if($s.Count){$w/$s.Count}else{0}), $u }
"games: $(@($rows | Sort-Object d,game -Unique).Count)"
"`nRAW SIM SIDE (whichever side the sim favors, at the book's price)"
foreach($k in 'ML','ATS','TOT'){ "{0,-4} {1}" -f $k, (Rec ($rows | ? { $_.k -eq $k -and $_.pS -gt 0.5 })) }
"`nSIM SIDE when the sim disagrees with the market by 10+ points of probability"
foreach($k in 'ML','ATS','TOT'){ "{0,-4} {1}" -f $k, (Rec ($rows | ? { $_.k -eq $k -and ($_.pS - $_.pm) -ge 0.10 })) }
"`nPROPS RULE (blend w=$W, 60%+, EV 5%+, -150..+150)"
foreach($k in 'ML','ATS','TOT'){ $s=@($rows | ? { $_.k -eq $k -and $_.p -ge 0.6 -and $_.ev -ge 0.05 -and $_.o -ge -150 -and $_.o -le 150 }); "{0,-4} n{1} {2}" -f $k, $s.Count, (Rec $s) }
"`nEDGE RULE ONLY (blend w=$W, EV 5%+, -150..+150)"
foreach($k in 'ML','ATS','TOT'){ $s=@($rows | ? { $_.k -eq $k -and $_.ev -ge 0.05 -and $_.o -ge -150 -and $_.o -le 150 }); "{0,-4} n{1} {2}" -f $k, $s.Count, (Rec $s) }
