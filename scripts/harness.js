// Backtest harness (local preview only). Load the page on a night's archived slate + finals.json, then run
//   await __H([{name:"base", g:{}}, {name:"cur", g:{curOn:true}}])
// Each variant re-runs the slate with those model settings and scores props (Brier) and several pick rules against the finals.
window.__G0 = window.__G0 || {...G};
window.__sleep = ms => new Promise(r=>setTimeout(r,ms));
window.__pickAll = (o={})=>{
  const games=[...SLATE.games].sort((a,b)=>new Date(a.time)-new Date(b.time)||a.espnId.localeCompare(b.espnId));
  const maxU = o.bal ? Math.ceil(o.bal*2*games.length) : 1e9; let nU=0, n3=0; const all=[];
  for(const g of games){ const P=PRICED[g.espnId]; if(!P) continue;
    const shaky=new Set(P.props.filter(b=>b.mismatch||b.prior).map(b=>b.player));
    RESULTS[g.espnId].P.forEach(p=>{ if(p.status==="q"||p.prior||(p.yr&&p.yr.startsWith("2024-25"))) shaky.add(p.name); });
    const c=P.props.filter(b=>!shaky.has(b.player)&&+b.odds>=-150&&+b.odds<=150&&!(o.no3&&b.stat==="3PM")&&!(o.stats&&!o.stats.includes(b.stat))&&!(o.minP&&b.p<o.minP));
    const pk=[];
    [b=>b.ev>=0.05, b=>b.ev>=0, ()=>true].forEach(ok=>{
      for(const b of c.filter(ok).sort((a,b)=>(b.p-a.p)||(b.ev-a.ev))){ if(pk.length>=2) break;
        if(pk.some(p=>p.bet===b.bet||p.player===b.player||((o.oneStat??G.oneStat)&&p.stat===b.stat))) continue;
        if(!o.no3 && b.stat==="3PM" && n3+pk.filter(p=>p.stat==="3PM").length>=(o.max3??3)) continue;
        if(b.side==="Under" && nU+pk.filter(p=>p.side==="Under").length>=maxU) continue;
        pk.push(b); } });
    nU+=pk.filter(p=>p.side==="Under").length; n3+=pk.filter(p=>p.stat==="3PM").length; all.push(...pk); }
  return all; };
window.__H = async (variants, rules)=>{
  rules = rules || {live:{useBest:true}};
  const F=await fetch("finals.json").then(r=>r.json()), row=(gid,n)=>{ const lg=F.games.find(x=>x.espnId===gid); return lg?liveRowFor(lg,n):null; };
  const statOf=(r,st)=>st==="PTS"?r.PTS:st==="REB"?r.REB:st==="AST"?r.AST:st==="3PM"?r["3PTM"]:st==="PR"?r.PTS+r.REB:st==="PA"?r.PTS+r.AST:st==="RA"?r.REB+r.AST:r.PTS+r.REB+r.AST;
  const out=[];
  for(const v of variants){
    Object.assign(G, window.__G0, v.g||{}); $("nSims").value=String(v.n||5000); await runAll(); while($("runAll").disabled) await __sleep(300);
    let bs=0,bb=0,bm=0,n=0, star=[0,0], role=[0,0];
    for(const g of SLATE.games){ const P=PRICED[g.espnId]; if(!P) continue; for(const b of P.props){ if(b.side!=="Over") continue; const r=row(g.espnId,b.player); if(!r||!(r.MIN>0)) continue; const a=statOf(r,b.stat); if(a===b.line) continue; const y=a>b.line?1:0;
      bs+=(b.pSim-y)**2; bb+=(b.p-y)**2; bm+=(b.pm-y)**2; n++; if(b.stat==="PRA"){ if(b.line>=22){ star[0]+=b.mean-a; star[1]++; } else { role[0]+=b.mean-a; role[1]++; } } } }
    // game level: sim mean margin/total vs the final, and vs the market line; starters' foul trouble (5+ PF) sim vs real
    let mErr=0,tErr=0,mMk=0,tMk=0,ng=0, f5s=0,f5r=0,nst=0;
    for(const g of SLATE.games){ const res=RESULTS[g.espnId], lg=F.games.find(x=>x.espnId===g.espnId); if(!res||!lg||lg.state!=="post") continue; const N=res.N, l=cons(g);
      let ms=0,ts=0; for(let s=0;s<N;s++){ ms+=res.score[s*2+1]-res.score[s*2]; ts+=res.score[s*2]+res.score[s*2+1]; } ms/=N; ts/=N;
      const am=lg.home-lg.away, at=lg.home+lg.away; mErr+=Math.abs(ms-am); tErr+=Math.abs(ts-at); mMk+=Math.abs(-l.spread-am); tMk+=Math.abs(l.total-at); ng++;
      for(const p of res.P){ if(!p.start||!res.games[p.g]) continue; const r=row(g.espnId,p.name); if(!r||!(r.MIN>0)) continue; let c=0,k=0; for(let s=0;s<N;s++){ if(!res.played[p.g*N+s]) continue; k++; if(res.pfS[p.g*N+s]>=5) c++; } f5s+=c/k; f5r+=(r.PF>=5?1:0); nst++; } }
    const grade=b=>{ const r=row(b.gid,b.player); if(!r||!(r.MIN>0)) return null; const a=statOf(r,b.stat); const d=b.side==="Over"?a-b.line:b.line-a; return d>0?dec(b.odds)-1:d<0?-1:0; };
    const res={v:v.name, n, brierSim:+(bs/n).toFixed(4), brierBlend:+(bb/n).toFixed(4), brierMkt:+(bm/n).toFixed(4), praStarBias:+(star[0]/star[1]).toFixed(2), praRoleBias:+(role[0]/role[1]).toFixed(2),
      marginMAE:+(mErr/ng).toFixed(1), marginMAEmkt:+(mMk/ng).toFixed(1), totalMAE:+(tErr/ng).toFixed(1), totalMAEmkt:+(tMk/ng).toFixed(1), foul5sim:+(f5s/nst*100).toFixed(1), foul5real:+(f5r/nst*100).toFixed(1)};
    for(const [name,o] of Object.entries(rules)){ const sel = o.useBest ? SLATE.games.flatMap(g=>bestPicks(g.espnId)) : __pickAll(o); const gs=sel.map(grade).filter(x=>x!=null); res[name]=[gs.filter(x=>x>0).length, gs.filter(x=>x<0).length, +gs.reduce((a,b)=>a+b,0).toFixed(2)]; }
    out.push(res); }
  Object.assign(G, window.__G0);
  return out; };
// one call per night: run the standard comparison and save it as tracking\harness-<date>-<tag>.json
window.__HN = (tag, variants)=>{ __H(variants).then(r=>fetch(`/upload?name=harness-${SLATE.date}-${tag}.json`,{method:"POST",body:JSON.stringify(r,null,1)})).catch(e=>fetch(`/upload?name=harness-${SLATE.date}-${tag}.json`,{method:"POST",body:JSON.stringify({error:String(e)})})); return "started"; };
// pick-rule settings only (no re-sim): run the night once at n sims, then grade gamePicks under each variant's G settings,
// flat 1u and at the listed stakes, with the picks each variant drops versus the first. Saved as tracking\harness-<date>-<tag>.json
window.__PK = (tag, variants, n=10000)=>{ (async()=>{
  const F=await fetch("finals.json").then(r=>r.json()), row=(gid,nm)=>{ const lg=F.games.find(x=>x.espnId===gid); return lg?liveRowFor(lg,nm):null; };
  const statOf=(r,st)=>st==="PTS"?r.PTS:st==="REB"?r.REB:st==="AST"?r.AST:st==="3PM"?r["3PTM"]:st==="PR"?r.PTS+r.REB:st==="PA"?r.PTS+r.AST:st==="RA"?r.REB+r.AST:r.PTS+r.REB+r.AST;
  Object.assign(G, window.__G0); $("nSims").value=String(n); await runAll(); while($("runAll").disabled) await __sleep(300);
  const grade=b=>{ if(b.mkt!=="Prop") return null; const r=row(b.gid,b.player); if(!r||!(r.MIN>0)) return null; const a=statOf(r,b.stat); const d=b.side==="Over"?a-b.line:b.line-a; return {a, u:d>0?dec(b.odds)-1:d<0?-1:0}; };
  const out=[]; let base=null;
  for(const v of variants){ Object.assign(G, window.__G0, v.g||{});
    const sel=SLATE.games.flatMap(g=>gamePicks(g.espnId)), gs=sel.map(b=>({b, g:grade(b)})).filter(x=>x.g);
    const res={v:v.name, w:gs.filter(x=>x.g.u>0).length, l:gs.filter(x=>x.g.u<0).length, units:+gs.reduce((a,x)=>a+x.g.u,0).toFixed(2),
      staked:+gs.reduce((a,x)=>a+x.g.u*x.b.stake,0).toFixed(2), risked:+gs.reduce((a,x)=>a+x.b.stake,0).toFixed(2),
      picks:gs.map(x=>`${x.b.bet} ${x.b.odds} p${(x.b.p*100).toFixed(0)} gap${(ownGapOf(x.b)*100).toFixed(0)} -> ${x.g.a} ${x.g.u>0?"W":x.g.u<0?"L":"P"}`)};
    if(base) res.dropped=base.filter(s=>!res.picks.includes(s)), res.added=res.picks.filter(s=>!base.includes(s)); else base=res.picks;
    out.push(res); }
  Object.assign(G, window.__G0);
  await fetch(`/upload?name=harness-${SLATE.date}-${tag}.json`,{method:"POST",body:JSON.stringify(out,null,1)});
})().catch(e=>fetch(`/upload?name=harness-${SLATE.date}-${tag}.json`,{method:"POST",body:JSON.stringify({error:String(e)})})); return "started"; };
// model settings that change the sims: re-run the night for each variant, then grade picks (flat and staked), assist props
// (Brier of the blended win chance and the sim's mean minus the real count, on every priced assist line) and team assist totals
window.__PKS = (tag, variants, n=5000)=>{ window.__PKSp = (async()=>{
  const F=await fetch("finals.json").then(r=>r.json()), row=(gid,nm)=>{ const lg=F.games.find(x=>x.espnId===gid); return lg?liveRowFor(lg,nm):null; };
  const statOf=(r,st)=>st==="PTS"?r.PTS:st==="REB"?r.REB:st==="AST"?r.AST:st==="3PM"?r["3PTM"]:st==="PR"?r.PTS+r.REB:st==="PA"?r.PTS+r.AST:st==="RA"?r.REB+r.AST:r.PTS+r.REB+r.AST;
  const out=[];
  for(const v of variants){ Object.assign(G, window.__G0, v.g||{}); $("nSims").value=String(n); await runAll(); while($("runAll").disabled) await __sleep(300);
    const grade=b=>{ if(b.mkt!=="Prop") return null; const r=row(b.gid,b.player); if(!r||!(r.MIN>0)) return null; const a=statOf(r,b.stat); const d=b.side==="Over"?a-b.line:b.line-a; return {a, u:d>0?dec(b.odds)-1:d<0?-1:0}; };
    const gs=SLATE.games.flatMap(g=>gamePicks(g.espnId)).map(b=>({b,g:grade(b)})).filter(x=>x.g);
    let br=0,bias=0,na=0, tErr=0,tBias=0,nt=0;
    for(const g of SLATE.games){ const P=PRICED[g.espnId], res=RESULTS[g.espnId], lg=F.games.find(x=>x.espnId===g.espnId); if(!P||!res||!lg||lg.state!=="post") continue;
      for(const b of P.props){ if(b.stat!=="AST"||b.side!=="Over") continue; const r=row(g.espnId,b.player); if(!r||!(r.MIN>0)||r.AST===b.line) continue; const y=r.AST>b.line?1:0; br+=(b.p-y)**2; bias+=b.mean-r.AST; na++; }
      for(const T of res.TM){ const lt=lg.teams.find(t=>t.abbr===T.abbr); if(!lt) continue; let s=0; for(const i of T.idx) s+=res.sum[i*NS+S.AST]; s/=res.N; const real=lt.players.reduce((a,p)=>a+(p.MIN>0?p.AST:0),0); tErr+=Math.abs(s-real); tBias+=s-real; nt++; } }
    out.push({v:v.name, w:gs.filter(x=>x.g.u>0).length, l:gs.filter(x=>x.g.u<0).length, units:+gs.reduce((a,x)=>a+x.g.u,0).toFixed(2),
      staked:+gs.reduce((a,x)=>a+x.g.u*x.b.stake,0).toFixed(2), risked:+gs.reduce((a,x)=>a+x.b.stake,0).toFixed(2),
      astN:na, astBrier:+(br/na).toFixed(4), astBias:+(bias/na).toFixed(2), teamAstMAE:+(tErr/nt).toFixed(1), teamAstBias:+(tBias/nt).toFixed(1), teams:nt,
      picks:gs.map(x=>`${x.b.bet} ${x.b.odds} p${(x.b.p*100).toFixed(0)} -> ${x.g.a} ${x.g.u>0?"W":x.g.u<0?"L":"P"}`)}); }
  Object.assign(G, window.__G0);
  await fetch(`/upload?name=harness-${SLATE.date}-${tag}.json`,{method:"POST",body:JSON.stringify(out,null,1)});
})().catch(e=>fetch(`/upload?name=harness-${SLATE.date}-${tag}.json`,{method:"POST",body:JSON.stringify({error:String(e)})})); return "started"; };
// team passing check: run the night once and save each team's sim assists and made baskets beside the real box score, with
// every player's sim and real assists, minutes and assisted rates (astd), as tracking\ta-<date>[-tag].json
window.__TA = (tag="", g={}, n=5000)=>{ window.__TAdone=false; (async()=>{
  const F=await fetch("finals.json").then(r=>r.json());
  Object.assign(G, window.__G0, g); $("nSims").value=String(n); await runAll(); while($("runAll").disabled) await __sleep(300);
  const out=[];
  for(const gm of SLATE.games){ const res=RESULTS[gm.espnId], lg=F.games.find(x=>x.espnId===gm.espnId); if(!res||!lg||lg.state!=="post") continue;
    for(const T of res.TM){ const lt=lg.teams.find(t=>t.abbr===T.abbr); if(!lt) continue; let a=0,m=0; for(const i of T.idx){ a+=res.sum[i*NS+S.AST]; m+=res.sum[i*NS+S.FGM]; }
      const rp=lt.players.filter(p=>p.MIN>0);
      out.push({d:SLATE.date, gid:gm.espnId, team:T.abbr, simAst:+(a/res.N).toFixed(2), simFgm:+(m/res.N).toFixed(2), realAst:rp.reduce((s,p)=>s+p.AST,0), realFgm:rp.reduce((s,p)=>s+p.FGM,0),
        players:res.P.filter(p=>p.t===res.TM.indexOf(T)&&res.games[p.g]).map(p=>{ const r=liveRowFor(lg,p.name), k=res.games[p.g];
          return {n:p.name, start:p.start, moved:p.moved, simMin:+(res.minSum[p.g]/k).toFixed(1), simAst:+(res.sum[p.g*NS+S.AST]/k).toFixed(2), simFgm:+(res.sum[p.g*NS+S.FGM]/k).toFixed(2),
            realMin:r?.MIN??null, realAst:r?.AST??null, realFgm:r?.FGM??null, astPct:+p.ast.toFixed(1), astd:p.astd.map(x=>+x.toFixed(2))}; })}); } }
  Object.assign(G, window.__G0);
  await fetch(`/upload?name=ta-${SLATE.date}${tag?"-"+tag:""}.json`,{method:"POST",body:JSON.stringify(out)}); window.__TAdone=true;
})().catch(e=>{ window.__TAdone="error: "+e; }); return "started"; };
// every priced bet for refitting the blend: run the night once, then save each prop side's market and sim win chances,
// whether gamePicks would allow it, and the result; game lines with their blended chance. Saved as tracking\px-<date>.json
window.__PX = (n=10000, tag="")=>{ window.__PXdone=false; window.__PXp=(async()=>{
  const F=await fetch("finals.json").then(r=>r.json()), row=(gid,nm)=>{ const lg=F.games.find(x=>x.espnId===gid); return lg?liveRowFor(lg,nm):null; };
  const statOf=(r,st)=>st==="PTS"?r.PTS:st==="REB"?r.REB:st==="AST"?r.AST:st==="3PM"?r["3PTM"]:st==="PR"?r.PTS+r.REB:st==="PA"?r.PTS+r.AST:st==="RA"?r.REB+r.AST:r.PTS+r.REB+r.AST;
  Object.assign(G, window.__G0); $("nSims").value=String(n); await runAll(); while($("runAll").disabled) await __sleep(300);
  const out=[];
  for(const g of SLATE.games){ const P=PRICED[g.espnId], res=RESULTS[g.espnId], lg=F.games.find(x=>x.espnId===g.espnId); if(!P||!res||!lg||lg.state!=="post") continue;
    const shaky=new Set(P.props.filter(b=>b.mismatch||b.prior).map(b=>b.player));
    res.P.forEach(p=>{ if(p.status==="q"||p.prior||(p.yr&&p.yr.startsWith("2024-25"))) shaky.add(p.name); });
    const mis=new Set(P.props.filter(b=>b.mismatch).map(b=>b.player));
    for(const b of P.props){ const r=row(g.espnId,b.player); if(!r||!(r.MIN>0)) continue; const a=statOf(r,b.stat), d=b.side==="Over"?a-b.line:b.line-a, pu=Math.max(0,1-b.p-b.pl);
      const pl=findPlayer(res,b.player), raw=pl&&SLATE.teams[pl.team]?.players.find(x=>norm(x.name)===pl.id);
      // why gamePicks would call him shaky, kept apart so each reason can be tested: rookie prior, 2024-25 data, questionable, role mismatch
      const why={prior:!!pl?.prior, y24:!!(pl?.yr&&pl.yr.startsWith("2024-25")), q:pl?.status==="q", mis:mis.has(b.player)};
      out.push({d:SLATE.date, gid:g.espnId, k:"P", player:b.player, stat:b.stat, side:b.side, line:b.line, odds:+b.odds, pm:b.pm, pSim:b.pSim/Math.max(1e-9,1-pu), push:pu, bench:b.bench, churn:b.churn,
        why, curG:raw?.cur?.g||0, moved:!!b.moved, rule:b.stat!=="3PM"&&!(b.stat==="AST"&&b.side==="Over")&&!(b.stat==="PRA"&&b.side==="Over")&&!ownGapHit(b)&&!lossRuleHit(g.espnId,b),
        ok:!shaky.has(b.player)&&b.stat!=="3PM"&&!(b.stat==="AST"&&b.side==="Over")&&!(b.stat==="PRA"&&b.side==="Over")&&!ownGapHit(b)&&!lossRuleHit(g.espnId,b), p:b.p, a, u:d>0?dec(b.odds)-1:d<0?-1:0}); }
    // double-doubles: every player the sim used, with his chance of 10+ in two of PTS/REB/AST/STL/BLK when he plays,
    // the same shaky reasons as props, his season-to-date double-double rate (PTS/REB/AST only; the log has no STL/BLK),
    // and whether he got one. Odds are joined offline from FanDuel's cached "Player Double Double" market (dd-eval.ps1).
    res.P.forEach(p=>{ const i=p.g, gm=res.games[i]; if(!(gm>0)) return; const r=row(g.espnId,p.name); if(!r||!(r.MIN>0)) return;
      const raw=SLATE.teams[p.team]?.players.find(x=>norm(x.name)===p.id), lgc=raw?.cur?.log||[];
      const ddG=lgc.filter(x=>[x.pts,x.reb,x.ast].filter(v=>v>=10).length>=2).length;
      const tens=[r.PTS,r.REB,r.AST,r.STL,r.BLK].filter(v=>v>=10).length;
      out.push({d:SLATE.date, gid:g.espnId, k:"D", player:p.name, team:res.TM[p.t]?.abbr, pSim:res.dd[i]/gm, pTD:res.td[i]/gm, min:res.minSum[i]/gm,
        pts:res.sum[i*NS+S.PTS]/gm, reb:res.sum[i*NS+S.REB]/gm, ast:res.sum[i*NS+S.AST]/gm, start:!!p.start,
        why:{prior:!!p.prior, y24:!!(p.yr&&p.yr.startsWith("2024-25")), q:p.status==="q"}, curG:raw?.cur?.g||0, curDD:ddG,
        a:tens>=2?1:0, line:{MIN:r.MIN,PTS:r.PTS,REB:r.REB,AST:r.AST,STL:r.STL,BLK:r.BLK}}); });
    const am=lg.home-lg.away, at=lg.home+lg.away;
    for(const b of P.game){ let d=0; if(b.mkt==="Spread") d=(b.side==="H"?am+b.hl:-am-b.hl); else if(b.mkt==="Total") d=(b.side==="O"?at-b.tl:b.tl-at); else d=(b.side==="H"?am:-am);
      out.push({d:SLATE.date, gid:g.espnId, k:"G", mkt:b.mkt, bet:b.bet, odds:+b.odds, p:b.p, ev:b.ev, u:d>0?dec(b.odds)-1:d<0?-1:0}); } }
  await fetch(`/upload?name=px-${SLATE.date}${tag?"-"+tag:""}.json`,{method:"POST",body:JSON.stringify(out)}); window.__PXdone=true;
})().catch(e=>{ window.__PXdone="error: "+e; }); return "started"; };
// several nights in one page: for each date, ask scripts\bt-feed.ps1 (via tracking\btreq.json) to copy that night's slate and
// finals into the served folder, wait until slate.json is that night, load it and run __PKS. Progress in window.__BTstate.
window.__BT = (dates, tag, variants, n=5000)=>{ window.__BTstate={done:0, of:dates.length, cur:null, err:null}; (async()=>{
  for(const d of dates){ __BTstate.cur=d;
    await fetch(`/upload?name=btreq.json`,{method:"POST",body:JSON.stringify({want:d})});
    let s=null; for(let k=0;k<120;k++){ s=await fetch("slate.json",{cache:"no-store"}).then(r=>r.json()).catch(()=>null); if(s&&s.date===d) break; await __sleep(500); }
    if(!s||s.date!==d) throw new Error("feed timeout "+d);
    SLATE=s; LG_T=leagueContext(); for(const k of Object.keys(RESULTS)) delete RESULTS[k]; for(const k of Object.keys(PRICED)) delete PRICED[k];
    __PKS(tag, variants, n); await window.__PKSp;
    __BTstate.done++; }
  __BTstate.cur=null; })().catch(e=>{ __BTstate.err=String(e); }); return "started"; };
// __PX over several archived nights in one page (fed by scripts\bt-feed.ps1 like __BT); files px-<date>-<tag>.json
window.__PXB = (dates, tag, n=10000)=>{ window.__PXBstate={done:0, of:dates.length, cur:null, err:null}; (async()=>{
  for(const d of dates){ __PXBstate.cur=d;
    await fetch(`/upload?name=btreq.json`,{method:"POST",body:JSON.stringify({want:d})});
    let s=null; for(let k=0;k<120;k++){ s=await fetch("slate.json",{cache:"no-store"}).then(r=>r.json()).catch(()=>null); if(s&&s.date===d) break; await __sleep(500); }
    if(!s||s.date!==d) throw new Error("feed timeout "+d);
    SLATE=s; LG_T=leagueContext(); for(const k of Object.keys(RESULTS)) delete RESULTS[k]; for(const k of Object.keys(PRICED)) delete PRICED[k];
    __PX(n, tag); await window.__PXp; if(window.__PXdone!==true) throw new Error(String(window.__PXdone));
    __PXBstate.done++; }
  __PXBstate.cur=null; })().catch(e=>{ __PXBstate.err=String(e); }); return "started"; };
"harness ready";
