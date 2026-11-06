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
}
$copied = @()
foreach($k in $map.Keys){ $src = Join-Path $root $map[$k]; if(Test-Path $src){ Copy-Item $src (Join-Path $docs $k) -Force; $copied += $k } }
"copied for $D : $($copied -join ', ')"
# git writes progress and line-ending notes to stderr; in Windows PowerShell that must not count as a failure
$ErrorActionPreference = "Continue"
git -c core.autocrlf=false -c core.safecrlf=false add -A docs scripts tracking site brand nba-matchup-sim.html .gitignore 2>$null
if($LASTEXITCODE -ne 0){ throw "git add failed (exit $LASTEXITCODE)" }
$staged = @(git diff --cached --name-only)
if(-not $staged.Count){ "nothing changed; no commit"; exit 0 }
if(-not $Message){ $Message = "Update $D ($((Get-Date).ToUniversalTime().ToString('yyyy-MM-dd HH:mm')) UTC)" }
git commit -q -m $Message 2>$null
if($LASTEXITCODE -ne 0){ throw "git commit failed (exit $LASTEXITCODE)" }
"committed $($staged.Count) files: $(($Message -split "`n")[0])"
if($NoPush){ "not pushed (-NoPush)"; exit 0 }
# GitHub Actions also commits here (nightly grading), so take its commits first and put ours on top
$out = git -c core.autocrlf=false pull --rebase --autostash -q origin main 2>&1 | % { "$_" }
if($LASTEXITCODE -ne 0){ git rebase --abort 2>$null; $out; throw "git pull --rebase failed (exit $LASTEXITCODE); local commit kept, not pushed" }
$out = git push origin main 2>&1 | % { "$_" }
if($LASTEXITCODE -ne 0){ $out; throw "git push failed (exit $LASTEXITCODE)" }
"pushed to GitHub"
