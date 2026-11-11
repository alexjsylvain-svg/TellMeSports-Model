param(
  [ValidateSet("card","results","test")][string]$Kind = "card",
  [string]$Date,
  [string]$Before = "",     # card: the previous docs\picks.json text (push-site passes it), to tell new / changed / locked apart
  [switch]$DryRun           # print the alert instead of sending it
)
# Phone alerts through ntfy (https://ntfy.sh): friends install the free ntfy app and subscribe to the channel in docs\alerts.json
# (the page's "Get alerts" button links to it). Called by push-site.ps1 after a publish (card) and by the grading workflow (results).
# Sends only when something a bettor cares about changed: a new night's card, plays added or dropped, the card locked, or results.
# Never fails the caller: any error is printed and ignored.
$ErrorActionPreference = "Stop"
try {
$root = Split-Path $PSScriptRoot -Parent
$cfg = Get-Content (Join-Path $root "docs/alerts.json") -Raw | ConvertFrom-Json
if(-not $cfg.ntfy){ "alerts: no channel set"; exit 0 }
$odds = { param($o) if($o -gt 0){ "+$o" } else { "$o" } }
$day = { param($d) ([datetime]::ParseExact("$d","yyyyMMdd",$null)).ToString("ddd MMM d") }
function Line($b){ "{0}u {1} {2}" -f $b.stake, $b.bet, (& $odds $b.odds) }

$title = $null; $msg = $null; $tags = @("basketball")
if($Kind -eq "test"){ $title = "TellMe alerts are on"; $msg = "You'll get a note when the NBA card is posted, changes or locks, and when results are in." }
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
  if(-not $old){ $title = "NBA card is up: $($card.Count) plays, $($risk)u ($(& $day $D))"; $msg = "$top$more" }
  elseif($p.final -and -not $old.final){ $title = "NBA card locked: $($card.Count) plays, $($risk)u"; $msg = "Final for tonight.`n$top$more"; $tags += "lock" }
  elseif($added.Count -or $dropped.Count){ $title = "NBA card updated: $($card.Count) plays, $($risk)u"
    $msg = (@($added | % { "Added: " + (Line $_) }) + @($dropped | % { "Dropped: $($_.bet)" }) -join "`n") }
  else { "alerts: card unchanged, nothing sent"; exit 0 }
}
else {
  if(-not $Date){ $Date = ([TimeZoneInfo]::ConvertTimeBySystemTimeZoneId([DateTime]::UtcNow,'Eastern Standard Time')).AddDays(-1).ToString("yyyyMMdd") }
  $r = Get-Content (Join-Path $root "tracking/results-$Date.json") -Raw | ConvertFrom-Json; $s = $r.sets.recommended
  if(($s.w + $s.l + $s.p) -eq 0){ "alerts: nothing graded for $Date"; exit 0 }
  $u = if($s.staked -ne $null){ $s.staked } else { $s.units }; $sg = if($u -ge 0){ "+" } else { "" }
  $title = "NBA results $(& $day $Date): $($s.w)-$($s.l)$(if($s.p){"-$($s.p)"}), $sg$($u)u"
  $msg = (@($r.bets | ? { $_.set -eq "recommended" } | % { "{0} {1}" -f $(switch($_.result){ "WIN"{"W"} "LOSS"{"L"} "PUSH"{"P"} default{"-"} }), $_.bet }) -join "`n")
  try{ $t = (Get-Content (Join-Path $root "tracking/ledger.json") -Raw | ConvertFrom-Json).toDate.recommended
    $msg += "`nSeason: $($t.w)-$($t.l), $(if($t.staked -ne $null){ "{0:+0.00;-0.00}u" -f $t.staked } else { "{0:+0.00;-0.00}u flat" -f $t.units })" }catch{}
  $tags += $(if($u -ge 0){ "white_check_mark" } else { "x" })
}
$body = [ordered]@{ topic = $cfg.ntfy; title = $title; message = $msg; tags = $tags; click = $cfg.site }
if($DryRun){ "alerts (dry run) to $($cfg.ntfy):"; "  $title"; ($msg -split "`n" | % { "  $_" }); exit 0 }
$bytes = [Text.Encoding]::UTF8.GetBytes(($body | ConvertTo-Json -Depth 4))
Invoke-RestMethod -Method Post -Uri "https://ntfy.sh/" -Body $bytes -ContentType "application/json; charset=utf-8" -TimeoutSec 20 | Out-Null
"alerts: sent '$title'"
} catch { "alerts: not sent ($($_.Exception.Message))" }
