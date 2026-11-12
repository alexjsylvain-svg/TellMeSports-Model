param(
  [ValidateSet("card","results","test")][string]$Kind = "card",
  [string]$Date,
  [string]$Before = "",     # card: the previous docs\picks.json text (push-site passes it), to tell new / changed / locked apart
  [switch]$DryRun,          # print the alerts instead of sending them
  [switch]$DiscordOnly      # skip the phone alert (e.g. -Kind test to check the Discord channels without pinging phones)
)
# Alerts after a publish (card, from push-site.ps1) and after grading (results, from the grading workflow):
#  - Phone: ntfy (https://ntfy.sh). Friends install the free ntfy app and subscribe to the channel in docs\alerts.json.
#  - Discord: webhooks into two channels of the members' server (Nov 12, 2026):
#      paid  the members' picks channel: the full card when it's posted, changed or locked, and the results
#      free  the public channel: a teaser when the night's card is first posted (count and units, no plays), and the results
#    The webhook URLs are secrets (anyone holding one can post in that channel), so they are never committed:
#      on this PC   private\discord.json  {"paid":"https://discord.com/api/webhooks/...","free":"https://discord.com/api/webhooks/..."}
#      on GitHub    repository secrets DISCORD_WEBHOOK_PAID and DISCORD_WEBHOOK_FREE (passed in as environment variables)
#    Either one may be left out; a channel with no webhook is skipped. docs\alerts.json "join" (optional) is the sign-up link
#    shown under the free teaser.
# Sends only when something a bettor cares about changed: a new night's card, plays added or dropped, the card locked, or results.
# Never fails the caller: any error is printed and ignored.
$ErrorActionPreference = "Stop"
try {
$root = Split-Path $PSScriptRoot -Parent
$cfg = Get-Content (Join-Path $root "docs/alerts.json") -Raw | ConvertFrom-Json
$odds = { param($o) if($o -gt 0){ "+$o" } else { "$o" } }
$day = { param($d) ([datetime]::ParseExact("$d","yyyyMMdd",$null)).ToString("ddd MMM d") }
function Line($b){ "{0}u {1} {2}" -f $b.stake, $b.bet, (& $odds $b.odds) }
# symbols as code points: Windows PowerShell 5.1 reads this file as ANSI, so no literal non-ASCII characters here
$U = { param($c) [char]::ConvertFromUtf32($c) }
$DOT = & $U 0xB7; $ELL = & $U 0x2026
$SYM = @{ WIN = (& $U 0x2705); LOSS = (& $U 0x274C); PUSH = (& $U 0x2796); OPEN = (& $U 0x23F3); ADD = (& $U 0x2795); DROP = (& $U 0x2796) }
# Discord line: stake, the bet, price and book, game, model win chance
function DLine($b){
  $pct = if($b.pBlend){ " $DOT {0:0}%" -f (100 * [double]$b.pBlend) } else { "" }
  "**{0}u** {1} **{2}**{3} $DOT {4}{5}" -f $b.stake, $b.bet, (& $odds $b.odds), $(if($b.book){ " $($b.book)" }else{ "" }), $b.game, $pct }

$title = $null; $msg = $null; $tags = @("basketball")
$dPaid = $null; $dFree = $null; $color = 0x2B6CB0   # Discord posts: @{ title; text } per channel, $null = nothing for that channel
if($Kind -eq "test"){
  $title = "TellMe alerts are on"; $msg = "You'll get a note when the NBA card is posted, changes or locks, and when results are in."
  $dPaid = @{ title = "TellMe picks channel is connected"; text = "The NBA card will post here when it's up, when it changes or locks, and the results the next morning." }
  $dFree = @{ title = "TellMe results channel is connected"; text = "Each night's results and the season record will post here." }
}
elseif($Kind -eq "card"){
  $p = Get-Content (Join-Path $root "docs/picks.json") -Raw | ConvertFrom-Json; $D = "$($p.date)"
  $card = @($p.bets | ? { $_.set -eq "recommended" }); $risk = ($card | Measure-Object stake -Sum).Sum
  $old = $null; if($Before){ try{ $old = $Before | ConvertFrom-Json }catch{} }
  if($old -and "$($old.date)" -ne $D){ $old = $null }
  $key = { param($b) "$($b.gid)|$($b.bet)" }
  $was = if($old){ @($old.bets | ? { $_.set -eq "recommended" }) } else { @() }
  $wasK = @($was | % { & $key $_ }); $nowK = @($card | % { & $key $_ })
  $added = @($card | ? { $wasK -notcontains (& $key $_) }); $dropped = @($was | ? { $nowK -notcontains (& $key $_) })
  $top = ($card | Sort-Object @{e='stake';Descending=$true},@{e='pBlend';Descending=$true} | Select-Object -First 6 | % { Line $_ }) -join "`n"
  $more = if($card.Count -gt 6){ "`n+$($card.Count-6) more" } else { "" }
  $full = if($card.Count){ ($card | Sort-Object game,@{e='stake';Descending=$true},@{e='pBlend';Descending=$true} | % { DLine $_ }) -join "`n" } else { "No plays tonight." }
  $games = @($card | % { $_.game } | Sort-Object -Unique).Count
  $plays = "$($card.Count) play$(if($card.Count -ne 1){'s'})"
  if(-not $old){ $title = "NBA card is up: $($card.Count) plays, $($risk)u ($(& $day $D))"; $msg = "$top$more"
    $dPaid = @{ title = "NBA card: $(& $day $D)"; text = "$full`n`n$plays, $($risk)u at risk. Not final until it's locked; changes post here." }
    $dFree = @{ title = "Tonight's NBA card is up ($(& $day $D))"; text = "$plays across $games game$(if($games -ne 1){'s'}), $($risk)u at risk. Members get the plays in the picks channel." + $(if($cfg.join){ "`nJoin: $($cfg.join)" } else { "" }) } }
  elseif($p.final -and -not $old.final){ $title = "NBA card locked: $($card.Count) plays, $($risk)u"; $msg = "Final for tonight.`n$top$more"; $tags += "lock"
    $dPaid = @{ title = "NBA card locked: $(& $day $D)"; text = "Final for tonight.`n`n$full`n`n$plays, $($risk)u at risk." }; $color = 0x2F855A }
  elseif($added.Count -or $dropped.Count){ $title = "NBA card updated: $($card.Count) plays, $($risk)u"
    $msg = (@($added | % { "Added: " + (Line $_) }) + @($dropped | % { "Dropped: $($_.bet)" }) -join "`n")
    $chg = (@($added | % { "$($SYM.ADD) Added: " + (DLine $_) }) + @($dropped | % { "$($SYM.DROP) Dropped: $($_.bet)" }) -join "`n")
    $dPaid = @{ title = "NBA card updated: $(& $day $D)"; text = "$chg`n`n**Card now**`n$full`n`n$plays, $($risk)u at risk." }; $color = 0xC05621 }
  else { "alerts: card unchanged, nothing sent"; exit 0 }
}
else {
  if(-not $Date){ $Date = ([TimeZoneInfo]::ConvertTimeBySystemTimeZoneId([DateTime]::UtcNow,'Eastern Standard Time')).AddDays(-1).ToString("yyyyMMdd") }
  $r = Get-Content (Join-Path $root "tracking/results-$Date.json") -Raw | ConvertFrom-Json; $s = $r.sets.recommended
  if(($s.w + $s.l + $s.p) -eq 0){ "alerts: nothing graded for $Date"; exit 0 }
  $u = if($s.staked -ne $null){ $s.staked } else { $s.units }; $sg = if($u -ge 0){ "+" } else { "" }
  $title = "NBA results $(& $day $Date): $($s.w)-$($s.l)$(if($s.p){"-$($s.p)"}), $sg$($u)u"
  $rb = @($r.bets | ? { $_.set -eq "recommended" })
  $msg = (@($rb | % { "{0} {1}" -f $(switch($_.result){ "WIN"{"W"} "LOSS"{"L"} "PUSH"{"P"} default{"-"} }), $_.bet }) -join "`n")
  $dText = (@($rb | % { "{0} {1}u {2} {3}{4}" -f $(if($SYM["$($_.result)"]){ $SYM["$($_.result)"] }else{ $SYM.OPEN }), $_.stake, $_.bet, (& $odds $_.odds), $(if($_.actual){ " ($($_.actual))" }else{ "" }) }) -join "`n")
  try{ $t = (Get-Content (Join-Path $root "tracking/ledger.json") -Raw | ConvertFrom-Json).toDate.recommended
    $season = "Season: $($t.w)-$($t.l), $(if($t.staked -ne $null){ "{0:+0.00;-0.00}u" -f $t.staked } else { "{0:+0.00;-0.00}u flat" -f $t.units })"
    $msg += "`n$season"; $dText += "`n`n**$season**" }catch{}
  $tags += $(if($u -ge 0){ "white_check_mark" } else { "x" })
  $color = if($u -ge 0){ 0x2F855A } else { 0xC53030 }
  $dPaid = @{ title = $title; text = $dText }; $dFree = $dPaid
}

# Discord webhooks: environment (GitHub secrets) first, then private\discord.json on this PC. Only Discord webhook URLs are used.
$hooks = @{ paid = $env:DISCORD_WEBHOOK_PAID; free = $env:DISCORD_WEBHOOK_FREE }
$pf = Join-Path $root "private/discord.json"
if(Test-Path $pf){ try{ $pj = Get-Content $pf -Raw | ConvertFrom-Json; foreach($k in 'paid','free'){ if(-not $hooks[$k] -and $pj.$k){ $hooks[$k] = "$($pj.$k)" } } }catch{ "discord: private\discord.json unreadable ($($_.Exception.Message))" } }
foreach($k in @($hooks.Keys)){ if($hooks[$k] -and $hooks[$k] -notmatch '^https://(canary\.|ptb\.)?discord(app)?\.com/api/webhooks/\d+/[\w-]+$'){ "discord: the $k webhook isn't a Discord webhook URL; skipped"; $hooks[$k] = $null } }
$foot = "For entertainment only. No result is guaranteed. 21+. Gambling problem? Call 1-800-GAMBLER."
function DBody($post){
  $txt = "$($post.text)"; if($txt.Length -gt 4000){ $txt = $txt.Substring(0, 3990) + "`n$ELL" }
  [ordered]@{ username = "TellMe Sports"; allowed_mentions = @{ parse = @() }
    embeds = @([ordered]@{ title = $post.title; description = $txt; color = $color; url = $cfg.site; footer = @{ text = $foot }; timestamp = (Get-Date).ToUniversalTime().ToString("o") }) } }

if($DryRun){
  if(-not $DiscordOnly){ "alerts (dry run) to $($cfg.ntfy):"; "  $title"; ($msg -split "`n" | % { "  $_" }) }
  foreach($k in 'paid','free'){ $post = if($k -eq 'paid'){ $dPaid } else { $dFree }
    if(-not $post){ "discord $k (dry run): nothing to post"; continue }
    "discord $k (dry run, webhook $(if($hooks[$k]){'set'}else{'not set'})):"; "  $($post.title)"; ("$($post.text)" -split "`n" | % { "  $_" }) }
  exit 0 }

if(-not $DiscordOnly){
  if($cfg.ntfy){ try{
    $body = [ordered]@{ topic = $cfg.ntfy; title = $title; message = $msg; tags = $tags; click = $cfg.site }
    $bytes = [Text.Encoding]::UTF8.GetBytes(($body | ConvertTo-Json -Depth 4))
    Invoke-RestMethod -Method Post -Uri "https://ntfy.sh/" -Body $bytes -ContentType "application/json; charset=utf-8" -TimeoutSec 20 | Out-Null
    "alerts: sent '$title'" } catch { "alerts: not sent ($($_.Exception.Message))" } }
  else { "alerts: no phone channel set" } }
foreach($k in 'paid','free'){ $post = if($k -eq 'paid'){ $dPaid } else { $dFree }
  if(-not $post -or -not $hooks[$k]){ continue }
  try{ $bytes = [Text.Encoding]::UTF8.GetBytes(((DBody $post) | ConvertTo-Json -Depth 6))
    Invoke-RestMethod -Method Post -Uri $hooks[$k] -Body $bytes -ContentType "application/json; charset=utf-8" -TimeoutSec 20 | Out-Null
    "discord: posted '$($post.title)' to the $k channel" }
  catch { "discord: not posted to the $k channel ($($_.Exception.Message -replace 'https://\S+','(webhook)'))" } }
} catch { "alerts: not sent ($($_.Exception.Message))" }
