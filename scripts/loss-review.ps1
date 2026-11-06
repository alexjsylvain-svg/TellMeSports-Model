param([string]$Out = "tracking\loss-review.csv")
# Every graded recommended prop with its final line: miss size, minutes played, the game's final margin, the player's last-season
# and this-season averages, and how often he had cleared the line this season before the pick. Writes a CSV and prints a summary.
$ErrorActionPreference = "Stop"
$root = Split-Path $PSScriptRoot -Parent; $trk = Join-Path $root "tracking"
$stOf = { param($o,$st,$ln) if(-not $o){ return $null }; switch($st){ 'PTS'{$o.pts} 'REB'{ if($ln){$o.reb}else{$o.trb} } 'AST'{$o.ast} 'PRA'{ $o.pts + $(if($ln){$o.reb}else{$o.trb}) + $o.ast } 'PR'{ $o.pts + $(if($ln){$o.reb}else{$o.trb}) } 'PA'{ $o.pts + $o.ast } 'RA'{ $(if($ln){$o.reb}else{$o.trb}) + $o.ast } default{$null} } }
$rows = @(); $seen = @{}
foreach($f in Get-ChildItem $trk -Filter 'results-2026????.json' | Sort-Object Name){
  $r = Get-Content $f.FullName -Raw -Encoding UTF8 | ConvertFrom-Json; $d = $r.date
  $pk = if(Test-Path "$trk\picks-$d.json"){ Get-Content "$trk\picks-$d.json" -Raw -Encoding UTF8 | ConvertFrom-Json } else { $null }
  $sl = if(Test-Path "$trk\slate-$d.json"){ Get-Content "$trk\slate-$d.json" -Raw -Encoding UTF8 | ConvertFrom-Json } else { $null }
  $fn = if(Test-Path "$trk\finals-$d.json"){ Get-Content "$trk\finals-$d.json" -Raw -Encoding UTF8 | ConvertFrom-Json } else { $null }
  foreach($b in @($r.bets | Where-Object { $_.set -eq 'recommended' -and $_.mkt -eq 'Prop' -and $_.result -in 'WIN','LOSS' })){
    $k = "$d|$($b.bet)"; if($seen[$k]){ continue }; $seen[$k] = 1
    $fb = if($pk){ $pk.bets | Where-Object { $_.bet -eq $b.bet -and $_.gid -eq $b.gid } | Select-Object -First 1 } else { $null }
    $m = [regex]::Match($b.bet, '^(.*) (over|under) ([\d.]+) (\w+)$'); $name = $m.Groups[1].Value; $side = $m.Groups[2].Value; $line = [double]$m.Groups[3].Value; $st = $m.Groups[4].Value
    $act = [double](($b.actual -split ' ')[0])
    $pl = $null; if($sl){ foreach($ab in $sl.teams.PSObject.Properties.Name){ $x = $sl.teams.$ab.players | Where-Object { $_.name -eq $name }; if($x){ $pl = $x; break } } }
    $box = $null; $marg = $null
    if($fn){ $g = $fn.games | Where-Object { $_.espnId -eq $b.gid }; if($g){ $marg = [math]::Abs($g.home - $g.away); foreach($t in $g.teams){ $y = $t.players | Where-Object { $_.name -eq $name }; if($y){ $box = $y } } } }
    $last = & $stOf $pl.s $st $false; $cur = & $stOf $pl.cur $st $true
    $sh = if($fb -and $fb.season){ "$($fb.season.hit)/$($fb.season.n)" } elseif($pl -and $pl.cur -and $pl.cur.log){ $v = @($pl.cur.log | ForEach-Object { & $stOf $_ $st $true }); "$(@($v | Where-Object { if($side -eq 'under'){ $_ -lt $line } else { $_ -gt $line } }).Count)/$($v.Count)" } else { "" }
    $rows += [pscustomobject]@{ date=$d; bet=$b.bet; stat=$st; side=$side; line=$line; odds=$b.odds; p=[math]::Round([double]$b.pBlend,3)
      pSim=$(if($fb){[math]::Round([double]$fb.pSim,3)}else{$null}); simMean=$(if($fb -and $fb.mean -ne $null){[math]::Round([double]$fb.mean,1)}else{$null})
      lastAvg=$(if($last -ne $null){[math]::Round($last,1)}else{$null}); lastMin=$(if($pl.s){$pl.s.mpg}else{$null}); curAvg=$(if($cur -ne $null){[math]::Round($cur,1)}else{$null}); curMin=$(if($pl.cur){$pl.cur.min}else{$null}); curG=$(if($pl.cur){$pl.cur.g}else{0})
      season=$sh; moved=$(if($pl.s -and $pl.s.team){ $true }else{ $false }); act=$act; miss=$(if($side -eq 'under'){ $act - $line }else{ $line - $act })
      actMin=$(if($box){$box.MIN}else{$null}); pf=$(if($box){$box.PF}else{$null}); margin=$marg; result=$b.result; units=[double]$b.units; stake=$b.stake }
  } }
$rows | Export-Csv (Join-Path $root $Out) -NoTypeInformation -Encoding UTF8
"picks: $($rows.Count)  ($(@($rows | ? result -eq 'WIN').Count)-$(@($rows | ? result -eq 'LOSS').Count))"
