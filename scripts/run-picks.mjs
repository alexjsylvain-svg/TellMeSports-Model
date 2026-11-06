// Headless picks run (GitHub Actions): the same steps the PC's tasks do in the browser pane.
// Loads the page from serve.ps1 (http://localhost:8765) at 50,000 sims a game; freezePicks and exportBoard save through
// serve.ps1 into tracking/.
//   node scripts/run-picks.mjs <YYYYMMDD> [report.md]                 full refresh: every game, freeze all games not yet tipped
//   node scripts/run-picks.mjs <YYYYMMDD> [report.md] --only=ID,ID   lineup change: re-sim those games first (then the other
//                                                                    games still ahead, for the board) and re-freeze only them
// Writes a markdown report to report.md, and picks-changed.txt = a one-line "added …; dropped …" when the card changed.
import fs from "node:fs";
import puppeteer from "puppeteer-core";

const args = process.argv.slice(2), D = args[0], OUT = args[1] && !args[1].startsWith("--") ? args[1] : "picks-report.md";
const ONLY = (args.find(a => a.startsWith("--only=")) || "").slice(7).split(",").filter(Boolean);
const NOTE = (args.find(a => a.startsWith("--note=")) || "").slice(7);
if (!/^\d{8}$/.test(D)) { console.error("date YYYYMMDD required"); process.exit(2); }
fs.writeFileSync("picks-changed.txt", "");
const chrome = process.env.CHROME_PATH || "/usr/bin/google-chrome";
const browser = await puppeteer.launch({ executablePath: chrome, headless: true, protocolTimeout: 15 * 60000,
  args: ["--no-sandbox", "--disable-background-timer-throttling", "--disable-renderer-backgrounding", "--disable-backgrounding-occluded-windows"] });
const page = await browser.newPage();
await page.setViewport({ width: 1440, height: 1000 });
page.on("pageerror", e => console.log("page error:", e.message));
page.on("console", m => { if (m.type() === "error") console.log("console error:", m.text()); });
const fail = async msg => { console.error(msg); fs.writeFileSync(OUT, `### Picks run ${D} failed\n\n${msg}\n`); await browser.close(); process.exit(1); };
const wait = ms => new Promise(r => setTimeout(r, ms));
const t0 = Date.now(), secs = () => Math.round((Date.now() - t0) / 1000);
const picksOf = doc => (doc?.bets || []).filter(b => b.set === "recommended");

const url = ONLY.length ? `http://localhost:8765/?view=full&sims=50000&norun=1&lineups=${D}` : `http://localhost:8765/?view=full&sims=50000&run=${D}`;
await page.goto(url, { waitUntil: "load", timeout: 120000 });
const prevDoc = await page.evaluate(async d => await fetch(`/tracking/picks-${d}.json?x=` + Date.now()).then(r => r.ok ? r.json() : null), D);
let fr;
if (!ONLY.length) {
  let last = "";
  for (;;) {
    const s = await page.evaluate(d => ({
      ready: typeof SLATE !== "undefined" && SLATE && SLATE.date === d && Object.keys(PRICED).length === SLATE.games.length && !$("runAll").disabled,
      date: typeof SLATE !== "undefined" && SLATE ? SLATE.date : null, status: $("status") ? $("status").textContent : "" }), D);
    if (s.ready) break;
    if (s.status !== last) { console.log(`${secs()}s ${s.status}`); last = s.status; }
    if (s.date && s.date !== D) await fail(`the server answered with the ${s.date} slate, not ${D}`);
    if (Date.now() - t0 > 55 * 60000) await fail(`sims didn't finish in 55 minutes (last status: ${s.status})`);
    await wait(5000);
  }
  console.log(`sims done in ${secs()}s`);
  fr = await page.evaluate(() => freezePicks({ overwrite: true }));
} else {
  for (;;) { const d = await page.evaluate(() => typeof SLATE !== "undefined" && SLATE ? SLATE.date : null); if (d === D) break;
    if (d && d !== D) await fail(`the server answered with the ${d} slate, not ${D}`); if (secs() > 120) await fail("the page didn't load the slate"); await wait(1000); }
  if (!prevDoc) await fail(`no frozen picks for ${D} to re-freeze from`);
  // changed games first, then every other game that hasn't tipped (so the board covers them)
  const order = await page.evaluate(only => [...only, ...SLATE.games.filter(g => !only.includes(g.espnId) && new Date(g.time).getTime() > Date.now() + 10 * 60000).map(g => g.espnId)], ONLY);
  for (const id of order) { await page.evaluate(id => runOne(SLATE.games.find(g => g.espnId === id)).then(() => true), id); console.log(`${secs()}s simulated ${id}`); }
  fr = await page.evaluate(only => freezePicks({ overwrite: true, only }), ONLY);
}
console.log("freezePicks:", JSON.stringify(fr));
if (!fr.ok || fr.date !== D) await fail(`freezePicks: ${fr.error || JSON.stringify(fr)}`);
const bd = await page.evaluate(() => exportBoard());
console.log("exportBoard:", JSON.stringify(bd));
// every frozen pick should show on the board as a pick, except placed bets: the board lists tonight's current line, so a bet
// placed at a line that has since moved isn't a board row
const nPlaced = picksOf(JSON.parse(fs.readFileSync(`tracking/picks-${D}.json`, "utf8"))).filter(b => b.placed).length;
if (!bd.ok || (!ONLY.length && (bd.picks > bd.picksFrozen || bd.picks < bd.picksFrozen - nPlaced))) await fail(`exportBoard: ${JSON.stringify(bd)} (${nPlaced} placed)`);

const games = await page.evaluate(only => SLATE.games.filter(g => !only.length || only.includes(g.espnId)).map(g => ({ gid: g.espnId,
  line: `${g.away.abbr} @ ${g.home.abbr} ${etTime(g.time)}: ` + (gamePicks(g.espnId).map(b => `${b.bet} ${oddsTxt(b.odds)} ${b.book} (${(b.p * 100).toFixed(0)}%, ${b.stake}u${b.top ? ", top" : ""}${b.season ? `, ${b.season.hit} of ${b.season.n} this season` : ""}${b.def ? `, guarded by ${b.def}` : ""})`).join("; ") || "none (nothing clears 60%)") })), ONLY);
const key = b => `${b.bet} ${b.odds}`;
const inScope = b => !ONLY.length || ONLY.includes(b.gid);
const prev = prevDoc ? picksOf(prevDoc).filter(inScope).map(key) : null;
const cur = picksOf(JSON.parse(fs.readFileSync(`tracking/picks-${D}.json`, "utf8"))).filter(inScope).map(key);
const added = prev ? cur.filter(x => !prev.includes(x)) : [], dropped = prev ? prev.filter(x => !cur.includes(x)) : [];
const changedCard = prev && (added.length || dropped.length);
const head = ONLY.length ? `### Lineup change ${D}: re-froze ${games.map(g => g.line.split(" ").slice(0, 3).join(" ")).join(", ")}` : `### Picks ${D}: ${cur.length} picks, ${fr.lockedGames} game(s) locked (already tipped)`;
const md = [head, "", ...(NOTE ? [NOTE, ""] : []), ...games.map(g => `- ${g.line}`), "",
  prev ? (changedCard ? `**Card changed**: added ${added.join(", ") || "none"}; dropped ${dropped.join(", ") || "none"}` : "Same picks as before.") : "First freeze of the day."];
fs.writeFileSync(OUT, md.join("\n") + "\n");
if (changedCard) fs.writeFileSync("picks-changed.txt", `added: ${added.join(", ") || "none"}; dropped: ${dropped.join(", ") || "none"}`);
console.log(md.join("\n"));
await browser.close();
