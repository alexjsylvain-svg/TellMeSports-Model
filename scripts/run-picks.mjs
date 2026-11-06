// Headless picks run (GitHub Actions): the same steps the PC's refresh task does in the browser pane.
// Loads the page from serve.ps1 (http://localhost:8765) with 50,000 sims a game, waits for every game to be priced,
// freezes the picks (freezePicks keeps games that have tipped) and exports the board; both are saved by serve.ps1 into tracking/.
// usage: node scripts/run-picks.mjs <YYYYMMDD> [summary.md]
// Writes a markdown report (games, picks, what changed since the previous freeze) to the summary file.
import fs from "node:fs";
import puppeteer from "puppeteer-core";

const D = process.argv[2], OUT = process.argv[3] || "picks-report.md";
if (!/^\d{8}$/.test(D)) { console.error("date YYYYMMDD required"); process.exit(2); }
const chrome = process.env.CHROME_PATH || "/usr/bin/google-chrome";
const browser = await puppeteer.launch({ executablePath: chrome, headless: true,
  args: ["--no-sandbox", "--disable-background-timer-throttling", "--disable-renderer-backgrounding", "--disable-backgrounding-occluded-windows"] });
const page = await browser.newPage();
await page.setViewport({ width: 1440, height: 1000 });
page.on("pageerror", e => console.log("page error:", e.message));
page.on("console", m => { if (m.type() === "error") console.log("console error:", m.text()); });
const fail = async msg => { console.error(msg); fs.writeFileSync(OUT, `### Picks run ${D} failed\n\n${msg}\n`); await browser.close(); process.exit(1); };

await page.goto(`http://localhost:8765/?view=full&sims=50000&run=${D}`, { waitUntil: "load", timeout: 120000 });
const t0 = Date.now(); let last = "";
for (;;) {
  const s = await page.evaluate(d => ({
    ready: typeof SLATE !== "undefined" && SLATE && SLATE.date === d && Object.keys(PRICED).length === SLATE.games.length && !$("runAll").disabled,
    date: typeof SLATE !== "undefined" && SLATE ? SLATE.date : null,
    status: $("status") ? $("status").textContent : "" }), D);
  if (s.ready) break;
  if (s.status !== last) { console.log(`${Math.round((Date.now() - t0) / 1000)}s ${s.status}`); last = s.status; }
  if (s.date && s.date !== D) await fail(`the server answered with the ${s.date} slate, not ${D}`);
  if (Date.now() - t0 > 55 * 60000) await fail(`sims didn't finish in 55 minutes (last status: ${s.status})`);
  await new Promise(r => setTimeout(r, 5000));
}
console.log(`sims done in ${Math.round((Date.now() - t0) / 1000)}s`);

const prev = await page.evaluate(async d => (await fetch(`/tracking/picks-${d}.json?x=` + Date.now()).then(r => r.ok ? r.json() : null))
  ?.bets.filter(b => b.set === "recommended").map(b => b.bet + " " + b.odds) ?? null, D);
const fr = await page.evaluate(() => freezePicks({ overwrite: true }));
console.log("freezePicks:", JSON.stringify(fr));
if (!fr.ok || fr.date !== D) await fail(`freezePicks: ${fr.error || JSON.stringify(fr)}`);
const bd = await page.evaluate(() => exportBoard());
console.log("exportBoard:", JSON.stringify(bd));
if (!bd.ok || bd.picks !== bd.picksFrozen) await fail(`exportBoard: ${JSON.stringify(bd)}`);

const rep = await page.evaluate(() => ({
  games: SLATE.games.map(g => `${g.away.abbr} @ ${g.home.abbr} ${etTime(g.time)}: ` + (gamePicks(g.espnId).map(b => `${b.bet} ${oddsTxt(b.odds)} ${b.book} (${(b.p * 100).toFixed(0)}%, ${b.stake}u${b.top ? ", top" : ""}${b.season ? `, ${b.season.hit} of ${b.season.n} this season` : ""}${b.def ? `, guarded by ${b.def}` : ""})`).join("; ") || "none (nothing clears 60%)")) }));
const cur = JSON.parse(fs.readFileSync(`tracking/picks-${D}.json`, "utf8")).bets.filter(b => b.set === "recommended").map(b => b.bet + " " + b.odds);
const added = prev ? cur.filter(x => !prev.includes(x)) : [], dropped = prev ? prev.filter(x => !cur.includes(x)) : [];
const md = [`### Picks ${D}: ${cur.length} picks, ${fr.lockedGames} game(s) locked (already tipped)`, "",
  ...rep.games.map(x => `- ${x}`), "",
  prev ? (added.length || dropped.length ? `**Changed since the previous freeze**: added ${added.join(", ") || "none"}; dropped ${dropped.join(", ") || "none"}` : "Same picks as the previous freeze.") : "First freeze of the day."];
fs.writeFileSync(OUT, md.join("\n") + "\n");
fs.writeFileSync("picks-changed.txt", prev && (added.length || dropped.length) ? `added: ${added.join(", ") || "none"}; dropped: ${dropped.join(", ") || "none"}` : "");
console.log(md.join("\n"));
await browser.close();
