param([string]$Message = "", [switch]$NoPush)
# Publishes the dashboard to GitHub Pages: copies the page and the current data files into docs\ (the folder Pages serves),
# commits them with the tracking records, and pushes. Replaces the claude.ai artifact publish in the scheduled tasks.
# docs\ holds: index.html (nba-matchup-sim.html), slate.json, live.json, picks.json, board.json, results.json, season.json, boxes.json.
# picks.json and board.json are the current slate night's (site\slate.json "date"). Files that don't exist yet are skipped.
$ErrorActionPreference = "Stop"
$root = Split-Path $PSScriptRoot -Parent; Set-Location $root
$docs = Join-Path $root "docs"; New-Item -ItemType Directory -Force $docs | Out-Null
if(-not (Test-Path (Join-Path $docs ".nojekyll"))){ New-Item -ItemType File (Join-Path $docs ".nojekyll") | Out-Null }
$slate = [IO.File]::ReadAllText((Join-Path $root "site/slate.json")) | ConvertFrom-Json; $D = "$($slate.date)"
$map = [ordered]@{
  "index.html"   = "nba-matchup-sim.html"
  "slate.json"   = "site/slate.json"
  "live.json"    = "site/live.json"
  "picks.json"   = "tracking/picks-$D.json"
  "board.json"   = "tracking/board-$D.json"
  "results.json" = "site/results.json"
  "season.json"  = "site/season.json"
  "boxes.json"   = "site/boxes.json"
  "creates.json" = "site/creates.json"   # "How he gets it" panel data (scripts/creates.ps1), loaded only when a player's panel is opened
}
# the NFL panel data follows the frozen NFL cards; rebuilt only when a card or the play-by-play is newer (needs tracking/nfl/plays.json, so PC only)
$ncf = Join-Path $docs "nfl/creates.json"; $nsrc = @("tracking/nfl/plays.json","tracking/nfl/card.json","tracking/nfl/tonight.json","tracking/nfl/mnf.json") | % { Join-Path $root $_ } | ? { Test-Path $_ }
if((Test-Path (Join-Path $root "tracking/nfl/plays.json")) -and (-not (Test-Path $ncf) -or @($nsrc | ? { (Get-Item $_).LastWriteTime -gt (Get-Item $ncf).LastWriteTime }).Count)){ try { & "$PSScriptRoot/nfl-creates.ps1" } catch { Write-Warning "nfl-creates failed: $_" } }
$picksBefore = if(Test-Path (Join-Path $docs "picks.json")){ [IO.File]::ReadAllText((Join-Path $docs "picks.json")) } else { "" }   # for the phone alert
$copied = @()
foreach($k in $map.Keys){ $src = Join-Path $root $map[$k]; if(Test-Path $src){ Copy-Item $src (Join-Path $docs $k) -Force; $copied += $k } }
"copied for $D : $($copied -join ', ')"
# the invite-only viewer (viewer\, served by Cloudflare Pages behind Access): the phone app and the data, no model.
# A failed build leaves the last good viewer in place and never blocks the publish.
try { & "$PSScriptRoot/build-viewer.ps1" } catch { Write-Warning "viewer build failed, viewer\ not updated: $_" }
# git writes progress and line-ending notes to stderr; in Windows PowerShell that must not count as a failure
$ErrorActionPreference = "Continue"
git -c core.autocrlf=false -c core.safecrlf=false add -A docs viewer scripts tracking site brand nba-matchup-sim.html .gitignore 2>$null
if($LASTEXITCODE -ne 0){ throw "git add failed (exit $LASTEXITCODE)" }
$staged = @(git diff --cached --name-only)
if(-not $staged.Count){ "nothing changed; no commit"; exit 0 }
if(-not $Message){ $Message = "Update $D ($((Get-Date).ToUniversalTime().ToString('yyyy-MM-dd HH:mm')) UTC)" }
git commit -q -m $Message 2>$null
if($LASTEXITCODE -ne 0){ throw "git commit failed (exit $LASTEXITCODE)" }
"committed $($staged.Count) files: $(($Message -split "`n")[0])"
if($NoPush){ "not pushed (-NoPush)"; exit 0 }
# GitHub Actions and the PC both commit here (picks refreshes, lineup re-freezes, grading), so take GitHub's commits first and
# put ours on top. Two freezes can clash in the data files: on Nov 7 GitHub's 7:05 PM refresh and the PC's 7:06 lineup re-freeze
# both rewrote tonight's card, the refresh couldn't push, and a Re-run (same old checkout) failed the same way.
# A clash only in the generated data files is settled by keeping our files when that is safe: our card was frozen on top of
# GitHub's (its previousFreeze is GitHub's frozenAt), GitHub's card isn't locked, and every bet placed on GitHub's card is still
# placed on ours. Otherwise our commit is set aside on a branch and local main is matched to GitHub, so the next run starts clean.
function Get-Card($rev){ $t = (git show "${rev}:tracking/picks-$D.json" 2>$null) -join "`n"; if($LASTEXITCODE -ne 0 -or -not $t){ return $null }; $t | ConvertFrom-Json }
function Set-Aside([string]$why, [switch]$Fail){
  git rebase --abort 2>$null
  $b = "unpushed/$D-$(Get-Date -Format HHmmss)"; git branch -f $b HEAD 2>$null
  if(@(git status --porcelain --untracked-files=no).Count){ git stash push -q -m "push-site: changes left when setting aside $b" 2>$null }
  git reset -q --hard origin/main 2>$null
  $msg = "$why. Our commit is kept on branch $b, not pushed; local main now matches GitHub."
  if($Fail){ throw $msg }; $msg; exit 0
}
$out = git -c core.autocrlf=false pull --rebase --autostash -q origin main 2>&1 | % { "$_" }
if($LASTEXITCODE -ne 0){
  $out
  $conf = @(git diff --name-only --diff-filter=U)
  # not a content clash (network, sign-in): keep our commit here for the next try, as before
  if(-not $conf.Count){ git rebase --abort 2>$null; throw "git pull --rebase failed; local commit kept, not pushed" }
  $gen = '^(docs/[^/]+\.json|viewer/([^/]+|nfl/[^/]+)\.json|site/(slate|live|creates)\.json|tracking/(board|picks)-\d{8}\.json|tracking/live-state-\d{8}\.json)$'
  $other = @($conf | ? { $_ -notmatch $gen })
  if($other.Count){ Set-Aside "git pull --rebase clashed in $($other -join ', '), which isn't generated data" -Fail }
  $gh = Get-Card "HEAD"; $mine = Get-Card "REBASE_HEAD"   # mid-rebase, HEAD is GitHub's tip and REBASE_HEAD is our commit
  if($gh.final){ Set-Aside "tonight's card was locked on GitHub meanwhile, and a locked card never changes" }
  if($gh -and $mine){
    if("$($mine.previousFreeze)" -ne "$($gh.frozenAt)" -and "$($mine.frozenAt)" -ne "$($gh.frozenAt)"){
      Set-Aside "GitHub has a newer card (frozen $($gh.frozenAt)) than the one ours was built on ($($mine.previousFreeze))" -Fail }
    $lost = @($gh.bets | ? { $_.placed } | ? { $p = $_; -not @($mine.bets | ? { $_.placed -and $_.gid -eq $p.gid -and $_.bet -eq $p.bet }).Count } | % { $_.bet })
    if($lost.Count){ Set-Aside "our card would drop placed bets ($($lost -join '; '))" -Fail }
  }
  foreach($f in $conf){ git checkout --theirs -- $f 2>$null; git add -- $f 2>$null }
  $env:GIT_EDITOR = "true"
  $out = git -c core.autocrlf=false -c core.safecrlf=false rebase --continue 2>&1 | % { "$_" }
  if($LASTEXITCODE -ne 0){ $out; Set-Aside "couldn't finish the rebase after settling $($conf -join ', ')" -Fail }
  "settled a clash in $($conf -join ', '): our card was frozen on top of GitHub's newest, so ours is kept"
}
$out = git push origin main 2>&1 | % { "$_" }
if($LASTEXITCODE -ne 0){ $out; throw "git push failed (exit $LASTEXITCODE)" }
"pushed to GitHub"
# phone alert (scripts\notify.ps1): only when the card is new, changed or locked; never fails the publish
if($staged -contains "docs/picks.json"){ & "$PSScriptRoot/notify.ps1" -Kind card -Before $picksBefore }
