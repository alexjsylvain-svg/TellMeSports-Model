param([string]$Date = "20261021", [string]$Out = "site\slate.json", [switch]$Refetch)
$ErrorActionPreference = "Stop"
. "$PSScriptRoot\lib.ps1"
$root = Split-Path $PSScriptRoot -Parent
$raw = Join-Path $root "raw"; New-Item -ItemType Directory -Force $raw | Out-Null
$UA = @{"User-Agent"="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/130.0 Safari/537.36"}
function Fetch($name, $url){
  $p = Join-Path $raw $name
  if($Refetch -or -not (Test-Path $p)){
    $r = Invoke-WebRequest -UseBasicParsing $url -Headers $UA -TimeoutSec 60
    [IO.File]::WriteAllText($p, [Text.Encoding]::UTF8.GetString($r.RawContentStream.ToArray()))
  }
  return [IO.File]::ReadAllText($p)
}

# ---- 1. Schedule (ESPN) ----
$sb = (Fetch "espn_sb_$Date.json" "https://site.api.espn.com/apis/site/v2/sports/basketball/nba/scoreboard?dates=$Date") | ConvertFrom-Json
$games = @()
foreach($e in $sb.events){
  $c = $e.competitions[0]
  $hc = $c.competitors | ? { $_.homeAway -eq 'home' }; $ac = $c.competitors | ? { $_.homeAway -eq 'away' }
  $games += [ordered]@{ espnId=$e.id; time=$e.date; venue=$c.venue.fullName; broadcast=(($c.broadcasts | % { $_.names }) -join ', ')
    away=[ordered]@{ id=$ac.team.id; abbr=$ac.team.abbreviation; name=$ac.team.displayName; short=$ac.team.shortDisplayName }
    home=[ordered]@{ id=$hc.team.id; abbr=$hc.team.abbreviation; name=$hc.team.displayName; short=$hc.team.shortDisplayName } }
}
Write-Host "games: $($games.Count)"

# ---- 2. Last-season player stats (Basketball-Reference 2025-26) ----
$pg  = Parse-BbrefRows (Fetch "bbref_pg.html"  "https://www.basketball-reference.com/leagues/NBA_2026_per_game.html") "per_game_stats"
$adv = Parse-BbrefRows (Fetch "bbref_adv.html" "https://www.basketball-reference.com/leagues/NBA_2026_advanced.html") "advanced"
$sh  = Parse-BbrefRows (Fetch "bbref_shooting.html" "https://www.basketball-reference.com/leagues/NBA_2026_shooting.html") "shooting"
$pbp = Parse-BbrefRows (Fetch "bbref_play-by-play.html" "https://www.basketball-reference.com/leagues/NBA_2026_play-by-play.html") "pbp_stats"
function Index($rows){ $h=@{}; foreach($r in $rows){ $k = Norm-Name $r['name_display']; if($k -and -not $h.ContainsKey($k)){ $h[$k]=$r } }; return $h }
$PG = Index $pg; $ADV = Index $adv; $SH = Index $sh; $PBP = Index $pbp
# 2024-25 fallback for players who missed last season (injury returns)
$PG25 = Index (Parse-BbrefRows (Fetch "bbref25_pg.html" "https://www.basketball-reference.com/leagues/NBA_2025_per_game.html") "per_game_stats")
$ADV25 = Index (Parse-BbrefRows (Fetch "bbref25_adv.html" "https://www.basketball-reference.com/leagues/NBA_2025_advanced.html") "advanced")
$SH25 = Index (Parse-BbrefRows (Fetch "bbref25_shooting.html" "https://www.basketball-reference.com/leagues/NBA_2025_shooting.html") "shooting")
$PBP25 = Index (Parse-BbrefRows (Fetch "bbref25_play-by-play.html" "https://www.basketball-reference.com/leagues/NBA_2025_play-by-play.html") "pbp_stats")
Write-Host "bbref players: $($PG.Count) (+$($PG25.Count) 2024-25)"
function Pct($x){ $v = F ($x -replace '%',''); if($v -eq $null){ return $null }; if($v -gt 1.0){ return $v/100 }; return $v }

function Stats-For($name){
  $k = Norm-Name $name
  $cur = $null; $prev = $null
  if($PG.ContainsKey($k)){ $cur = Make-Stats $PG[$k] $ADV[$k] $SH[$k] $PBP[$k] "2025-26" }
  if($PG25.ContainsKey($k)){ $prev = Make-Stats $PG25[$k] $ADV25[$k] $SH25[$k] $PBP25[$k] "2024-25" }
  if($cur -and $cur.g -ge 5){ if($prev -and $cur.g -lt 40){ $cur['prev'] = $prev }; return $cur }
  if($prev){ return $prev }
  return $cur
}
function Make-Stats($a, $b, $s, $p, $yr){
  $pos = $null
  if($p){ $w=0; $t=0; for($i=1;$i -le 5;$i++){ $v = Pct $p["pct_$i"]; if($v){ $w += $i*$v; $t += $v } }; if($t -gt 0){ $pos = [math]::Round($w/$t,2) } }
  return [ordered]@{
    yr=$yr; team=$a['team_name_abbr']; g=(F $a['games']); gs=(F $a['games_started']); mpg=(F $a['mp_per_g'])
    pts=(F $a['pts_per_g']); trb=(F $a['trb_per_g']); ast=(F $a['ast_per_g']); fg3=(F $a['fg3_per_g']); stl=(F $a['stl_per_g']); blk=(F $a['blk_per_g']); tov=(F $a['tov_per_g']); pf=(F $a['pf_per_g'])
    fga=(F $a['fga_per_g']); fta=(F $a['fta_per_g']); ftp=(F $a['ft_pct']); fg3p=(F $a['fg3_pct']); fg2p=(F $a['fg2_pct'])
    usg=(F $b['usg_pct']); astp=(F $b['ast_pct']); tovp=(F $b['tov_pct']); orbp=(F $b['orb_pct']); drbp=(F $b['drb_pct']); stlp=(F $b['stl_pct']); blkp=(F $b['blk_pct']); dbpm=(F $b['dbpm']); obpm=(F $b['obpm']); ftr=(F $b['fta_per_fga_pct']); ts=(F $b['ts_pct'])
    z=@( (F $s['pct_fga_00_03']), (F $s['pct_fga_03_10']), ((F $s['pct_fga_10_16']) + (F $s['pct_fga_16_xx'])), (F $s['pct_fga_fg3a']) )
    zfg=@( (F $s['fg_pct_00_03']), (F $s['fg_pct_03_10']), $null, (F $s['fg_pct_fg3a']) )
    zfgMid=@( (F $s['fg_pct_10_16']), (F $s['fg_pct_16_xx']) )
    astd2=(F $s['pct_ast_fg2']); astd3=(F $s['pct_ast_fg3']); and1=(F $p['and1s']); drawnShoot=(F $p['drawn_shooting']); posEst=$pos
  }
}

# ---- 3. Expected lineups and injury status (RotoWire) ----
$rw = Fetch "roto_lineups.html" "https://www.rotowire.com/basketball/nba-lineups.php"
$LINEUPS = @{}
foreach($game in ($rw -split '<div class="lineup is-nba') | Select-Object -Skip 1){
 $abbrs = @([regex]::Matches($game, '<div class="lineup__abbr">([A-Z]+)</div>') | % { $_.Groups[1].Value })
 if($abbrs.Count -lt 2){ continue }
 foreach($blk in [regex]::Matches($game, '<ul class="lineup__list is-(visit|home)"[^>]*>(.*?)</ul>', 'Singleline')){
  $html = $blk.Groups[2].Value
  $teamAbbr = if($blk.Groups[1].Value -eq 'visit'){ $abbrs[0] } else { $abbrs[1] }
  $mayNot = $html.IndexOf('MAY NOT PLAY')
  $plist = @()
  foreach($m in [regex]::Matches($html, '<li class="lineup__player is-pct-play-(\d+)([^"]*)"[^>]*>.*?<div class="lineup__pos"[^>]*>([A-Z]+)</div>\s*<a title="([^"]+)".*?</a>\s*(?:<span class="lineup__inj">([^<]+)</span>)?', 'Singleline')){
    $plist += [ordered]@{ name=$m.Groups[4].Value; pos=$m.Groups[3].Value; pct=[int]$m.Groups[1].Value; inj=$m.Groups[5].Value; starter=($mayNot -lt 0 -or $m.Index -lt $mayNot); hidden=($m.Groups[2].Value -match 'hide') }
  }
  $confirmed = $html -match 'is-confirmed'
  if($teamAbbr){ $LINEUPS[$teamAbbr] = @{ players=$plist; confirmed=$confirmed } }
 }
}
Write-Host "rotowire teams: $($LINEUPS.Keys -join ',')"
$LUMAP = @{ GS='GSW'; NO='NOP'; NY='NYK'; SA='SAS'; UTAH='UTA'; WSH='WAS'; PHX='PHO' }
function RW-For($abbr){ foreach($k in @($abbr, $LUMAP[$abbr], ($abbr -replace 'WSH','WAS'))){ if($k -and $LINEUPS.ContainsKey($k)){ return $LINEUPS[$k] } }; return $null }

# ---- 4. Team context (2025-26 ratings) ----
$season = (Fetch "bbref_season.html" "https://www.basketball-reference.com/leagues/NBA_2026.html") -replace '<!--','' -replace '-->',''
$tadv = Parse-BbrefRows $season "advanced-team"; $tosh = Parse-BbrefRows $season "shooting-opponent"
$OSH = @{}; foreach($r in $tosh){ $OSH[(Norm-Name ($r['team'] -replace '\*',''))] = $r }
$TEAMRT = @{}
foreach($r in $tadv){ $k = Norm-Name ($r['team'] -replace '\*',''); if(-not $k -or $k -eq 'league average'){ continue }
  $o = $OSH[$k]; $oz = $null
  if($o){ $oz = @( (F $o['opp_pct_fga_00_03']), (F $o['opp_pct_fga_03_10']), ((F $o['opp_pct_fga_10_16']) + (F $o['opp_pct_fga_16_xx'])), (F $o['opp_pct_fga_fg3a']) ) }
  $TEAMRT[$k] = [ordered]@{ pace=(F $r['pace']); ortg=(F $r['off_rtg']); drtg=(F $r['def_rtg']); oppEfg=(F $r['opp_efg_pct']); oppTov=(F $r['opp_tov_pct']); oppFtr=(F $r['opp_ft_rate']); drb=(F $r['drb_pct']); oppZone=$oz } }
if($OSH.Count){ Write-Host ("opp shooting keys: " + (($tosh[0].Keys | ? { $_ -match 'pct_fga' }) -join ',')) }

# ---- 5. Rosters (ESPN) merged with stats + lineups ----
$teams = [ordered]@{}
foreach($g in $games){ foreach($side in 'away','home'){
  $t = $g[$side]
  $ro = (Fetch "espn_roster_$($t.abbr).json" "https://site.api.espn.com/apis/site/v2/sports/basketball/nba/teams/$($t.id)/roster") | ConvertFrom-Json
  $rwt = RW-For $t.abbr
  $players = @()
  foreach($a in $ro.athletes){
    $nm = $a.displayName; $nk = Norm-Name $nm
    $inj = if($a.injuries -and $a.injuries.Count){ $a.injuries[0].status } else { "" }
    $rp = $null; if($rwt){ $rp = $rwt.players | ? { (Norm-Name $_.name) -eq $nk } | Select-Object -First 1 }
    $players += [ordered]@{ name=$nm; espnId=$a.id; pos=$a.position.abbreviation; exp=$a.experience.years; espnInj=$inj
      rwStarter=[bool]($rp -and $rp.starter); rwPct=$(if($rp){ $rp.pct } else { $null }); rwInj=$(if($rp){ $rp.inj } else { "" })
      s=(Stats-For $nm) }
  }
  $rt = $TEAMRT[(Norm-Name $t.name)]
  if(-not $rt){ $rt = $TEAMRT[(Norm-Name ($t.name -replace 'LA Clippers','Los Angeles Clippers'))] }
  $teams[$t.abbr] = [ordered]@{ abbr=$t.abbr; name=$t.name; rt=$rt; rwConfirmed=$(if($rwt){ $rwt.confirmed } else { $false }); rwFound=[bool]$rwt; players=$players }
}}

# ---- 6. Game lines by book (Action Network feed: Open, DraftKings, FanDuel, Fanatics, Caesars, Consensus) ----
$BOOKS = [ordered]@{ "30"="OPEN"; "68"="DK"; "69"="FD"; "2988"="FAN"; "123"="CZR"; "15"="CONS" }
$an = (Fetch "an_sb_$Date.json" "https://api.actionnetwork.com/web/v2/scoreboard/nba?bookIds=$($BOOKS.Keys -join ',')&date=$Date&periods=event") | ConvertFrom-Json
foreach($ag in $an.games){
  $ha = $ag.teams | ? { $_.id -eq $ag.home_team_id }; $aa = $ag.teams | ? { $_.id -eq $ag.away_team_id }
  $g = $games | ? { (Norm-Name $_.home.name) -eq (Norm-Name $ha.full_name) -or $_.home.short -eq $ha.display_name } | Select-Object -First 1
  if(-not $g){ Write-Warning "no ESPN match for $($ha.full_name)"; continue }
  $lines = [ordered]@{}
  foreach($bk in $BOOKS.Keys){
    $e = $ag.markets.$bk.event; if(-not $e){ continue }
    $sh_ = $e.spread | ? { $_.side -eq 'home' } | Select-Object -First 1; $sa_ = $e.spread | ? { $_.side -eq 'away' } | Select-Object -First 1
    $ov = $e.total | ? { $_.side -eq 'over' } | Select-Object -First 1; $un = $e.total | ? { $_.side -eq 'under' } | Select-Object -First 1
    $mh = $e.moneyline | ? { $_.side -eq 'home' } | Select-Object -First 1; $ma = $e.moneyline | ? { $_.side -eq 'away' } | Select-Object -First 1
    $lines[$BOOKS[$bk]] = [ordered]@{ spread=$sh_.value; spreadHome=$sh_.odds; spreadAway=$sa_.odds; total=$ov.value; over=$ov.odds; under=$un.odds; mlHome=$mh.odds; mlAway=$ma.odds }
  }
  $g['lines'] = $lines; $g['anId'] = $ag.id
}

# ---- 7. FanDuel player props ----
$fd = (Fetch "fd_nba.json" "https://sbapi.nj.sportsbook.fanduel.com/api/content-managed-page?page=CUSTOM&customPageId=nba&pbHorizontal=false&_ak=FhMFpcPWXMeyZxOx&timezone=America%2FNew_York") | ConvertFrom-Json
$fdEvents = $fd.attachments.events.PSObject.Properties.Value | ? { $_.name -match ' @ ' -and $_.name -notmatch '\(' }
$STATMAP = @{ 'Points'='PTS'; 'Rebounds'='REB'; 'Assists'='AST'; 'Made Threes'='3PM'; 'Pts + Reb + Ast'='PRA'; 'Points + Rebounds + Assists'='PRA'; 'Pts + Reb'='PR'; 'Pts + Ast'='PA'; 'Reb + Ast'='RA' }
$MILE = @( @('^To Score (\d+)\+ Points$','PTS'), @('^To Record (\d+)\+ Rebounds$','REB'), @('^To Record (\d+)\+ Assists$','AST'), @('^(\d+)\+ Made Threes$','3PM') )
foreach($g in $games){
  $ev = $fdEvents | ? { $_.name -eq "$($g.away.name) @ $($g.home.name)" -or ($_.name -match [regex]::Escape($g.home.short) -and $_.name -match [regex]::Escape($g.away.short)) } | Select-Object -First 1
  if(-not $ev){ Write-Warning "no FD event for $($g.away.abbr)@$($g.home.abbr)"; $g['props']=@(); continue }
  $g['fdId'] = $ev.eventId
  $props = @{}; $miles = @(); $dds = @{}
  foreach($tab in 'player-points','player-rebounds','player-assists','player-threes','player-combos'){
    $j = (Fetch "fd_$($ev.eventId)_$tab.json" "https://sbapi.nj.sportsbook.fanduel.com/api/event-page?_ak=FhMFpcPWXMeyZxOx&eventId=$($ev.eventId)&tab=$tab") | ConvertFrom-Json
    foreach($m in $j.attachments.markets.PSObject.Properties.Value){
      # "Player Double Double": Yes prices only (the page prices them as categories with 10+ over 1.5)
      if($m.marketType -eq 'TO_RECORD_A_DOUBLE_DOUBLE'){ foreach($rn in $m.runners){ $o = $rn.winRunnerOdds.americanDisplayOdds.americanOdds
          if(($rn.runnerStatus -eq 'ACTIVE' -or -not $rn.runnerStatus) -and $o -ne $null){ $dds[$rn.runnerName] = [ordered]@{ player=$rn.runnerName; odds=$o; book='FD' } } }; continue }
      if($m.marketName -match '^(.+?) - (Points|Rebounds|Assists|Made Threes|Pts \+ Reb \+ Ast|Points \+ Rebounds \+ Assists|Pts \+ Reb|Pts \+ Ast|Reb \+ Ast)$'){
        $pn = $matches[1]; $st = $STATMAP[$matches[2]]
        $o = $m.runners | ? { $_.runnerName -match 'Over$' } | Select-Object -First 1; $u = $m.runners | ? { $_.runnerName -match 'Under$' } | Select-Object -First 1
        if($o -and $u){ $props["$pn|$st"] = [ordered]@{ player=$pn; stat=$st; line=$o.handicap; over=$o.winRunnerOdds.americanDisplayOdds.americanOdds; under=$u.winRunnerOdds.americanDisplayOdds.americanOdds; book='FD' } }
        continue
      }
      foreach($mm in $MILE){ if($m.marketName -match $mm[0]){ $thr=[int]$matches[1]
        foreach($rn in $m.runners){ if($rn.runnerStatus -eq 'ACTIVE' -or -not $rn.runnerStatus){ $miles += [ordered]@{ player=$rn.runnerName; stat=$mm[1]; thr=$thr; odds=$rn.winRunnerOdds.americanDisplayOdds.americanOdds; book='FD' } } } } }
    }
  }
  $g['props'] = @($props.Values); $g['milestones'] = $miles; $g['dd'] = @($dds.Values)
  Write-Host "$($g.away.abbr)@$($g.home.abbr): props $($props.Count), milestones $($miles.Count), double-doubles $($dds.Count)"
}

# ---- 7b. Fanatics player props (Action Network feed, book 2988): main over/under lines, same shape as the FanDuel props ----
$ANPROP = [ordered]@{ "core_bet_type_27_points"="PTS"; "core_bet_type_23_rebounds"="REB"; "core_bet_type_26_assists"="AST"; "core_bet_type_21_3fgm"="3PM"; "core_bet_type_85_points_rebounds_assists"="PRA"; "core_bet_type_86_points_rebounds"="PR"; "core_bet_type_87_points_assists"="PA"; "core_bet_type_88_rebounds_assists"="RA" }
$anp = (Fetch "an_props_$Date.json" "https://api.actionnetwork.com/web/v2/scoreboard/nba/markets?bookIds=2988&customPickTypes=$($ANPROP.Keys -join ',')&date=$Date") | ConvertFrom-Json
$anName = @{}; foreach($p in $anp.players){ $anName[[string]$p.id] = $p.full_name }
foreach($g in $games){
  $fan = [ordered]@{}
  foreach($t in $ANPROP.Keys){
    $os = @($anp.markets.'2988'.event.$t | ? { $_.event_id -eq $g.anId -and -not $_.is_alt_market -and $_.line_status -ne 'suspended' })
    foreach($grp in ($os | Group-Object player_id)){
      $o = $grp.Group | ? side -eq 'over' | Select-Object -First 1; $u = $grp.Group | ? side -eq 'under' | Select-Object -First 1
      $pn = $anName[[string]$grp.Name]
      if($pn -and $o -and $u -and $o.value -eq $u.value){ $fan["$pn|$($ANPROP[$t])"] = [ordered]@{ player=$pn; stat=$ANPROP[$t]; line=$o.value; over=$o.odds; under=$u.odds; book='FAN' } } } }
  $g['fanProps'] = @($fan.Values)
  Write-Host "$($g.away.abbr)@$($g.home.abbr): Fanatics props $($fan.Count)"
}

$outObj = [ordered]@{ generated=(Get-Date).ToUniversalTime().ToString("o"); date=$Date; season="2026-27"; statSeason="2025-26"; games=$games; teams=$teams }
$outPath = Join-Path $root $Out; New-Item -ItemType Directory -Force (Split-Path $outPath) | Out-Null
# an earlier night's last pregame build is the backtest record for that night: keep it as tracking\slate-<date>.json before
# overwriting (Oct 30: the grading run that archives it was missed, and the morning build replaced Oct 29's)
if(Test-Path $outPath){ try{ $old = (Get-Content $outPath -Raw -Encoding UTF8 | ConvertFrom-Json).date
  $arc = Join-Path $root "tracking\slate-$old.json"
  if($old -and $old -ne $Date -and -not (Test-Path $arc)){ Copy-Item $outPath $arc; Write-Host "archived the $old slate to $arc" } }catch{} }
[IO.File]::WriteAllText($outPath, ($outObj | ConvertTo-Json -Depth 12 -Compress))
Write-Host "wrote $outPath $((Get-Item $outPath).Length) bytes"
# this season's games so far (minutes, starts, per-game production) for every player, from games before $Date
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "season-to-date.ps1") -Date $Date -Slate $outPath | Write-Host
