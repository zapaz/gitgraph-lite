// Frame real app captures for the README. Original screenshots stay unchanged.
// Requires Playwright and its Chromium browser; no app runtime dependencies.
const fs = require('node:fs');
const path = require('node:path');
const { chromium } = require(process.env.PLAYWRIGHT_MODULE || 'playwright');
const source = process.env.GITGRAPH_SCREENSHOTS || path.resolve(__dirname, '..');
const output = process.env.GITGRAPH_PRESENTATION || __dirname;
fs.mkdirSync(output, { recursive: true });
const img = name => 'data:image/png;base64,' + fs.readFileSync(path.join(source, name)).toString('base64');
const graph = `<svg viewBox="0 0 320 170" fill="none" aria-hidden="true"><path d="M34 0V170" stroke="#37dec5" stroke-width="3"/><path d="M142 0V45C142 70 34 75 34 105" stroke="#a994ff" stroke-width="3"/><path d="M250 0V90C250 115 142 120 142 170" stroke="#63a8ff" stroke-width="3"/>${[[34,24,'#37dec5'],[34,105,'#37dec5'],[142,35,'#a994ff'],[250,65,'#63a8ff'],[142,147,'#63a8ff']].map(([x,y,c])=>`<circle cx="${x}" cy="${y}" r="8" fill="#0c1728" stroke="${c}" stroke-width="3"/>`).join('')}</svg>`;
const css = `
*{box-sizing:border-box}html,body{margin:0;background:transparent}body{font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif;-webkit-font-smoothing:antialiased}
.art{position:relative;overflow:hidden;color:#f2f7ff;border:1px solid #30415b;border-radius:32px;background:radial-gradient(ellipse at 90% 0%,var(--glow),transparent 65%),linear-gradient(145deg,#132238,#09111f 80%)}
.art:after{content:"";position:absolute;pointer-events:none;inset:0;border-radius:inherit;box-shadow:inset 0 1px 0 #ffffff10}
.hero{width:1920px;height:1510px;--glow:#154047}.card{width:960px;height:760px;--glow:#173d40}
.kicker{position:absolute;left:56px;top:49px;font-size:20px;line-height:1.2;letter-spacing:3px;font-weight:650;color:var(--accent)}
h1,h2,p{margin:0}h2{position:absolute;top:100px;left:54px;right:48px;font-size:51px;letter-spacing:-1.8px;line-height:1.08;font-weight:650}
.sub{position:absolute;top:168px;left:56px;right:40px;color:#b6c6d9;font-size:25px;line-height:1.4;letter-spacing:-.3px}
.frame{position:absolute;overflow:hidden;border-radius:15px;border:1px solid #ffffff38;box-shadow:0 25px 55px #00000066;background:#fff}.frame img{display:block;width:100%;height:auto}
.foot{position:absolute;bottom:42px;left:56px;right:56px;display:flex;align-items:center;justify-content:space-between;color:#9eb2cb;font-size:18px;letter-spacing:2px;font-weight:550}.foot span:last-child{color:var(--accent);font-size:24px}
.hero .kicker{top:58px;left:84px;font-size:25px;letter-spacing:4px}.hero h1{position:absolute;top:108px;left:80px;font-size:76px;line-height:1.1;letter-spacing:-3px;font-weight:650}.hero .sub{top:203px;left:84px;font-size:29px}.hero .frame{left:84px;top:282px;width:1752px;border-radius:20px}.hero .motif{position:absolute;right:95px;top:43px;width:300px;height:170px;opacity:.8}
.workspaces .frame{left:52px;top:277px;width:856px}.chips{position:absolute;top:590px;left:56px;display:flex;gap:14px}.chip{border:1px solid #ffffff24;border-radius:12px;padding:16px 21px;color:#d7e9f6;font-family:ui-monospace,monospace;font-size:20px;background:#ffffff05}.chip:before{content:"";display:inline-block;width:9px;height:9px;border-radius:50%;margin-right:11px;background:var(--dot)}
.branches{--glow:#352453}.branches .frame{left:170px;top:220px;width:620px;border-radius:15px}
.diff{--glow:#153d5b}.diff .frame{left:52px;top:252px;width:856px;height:340px}.diff .frame img{position:absolute;width:1160px;max-width:none;left:-225px;top:-414px}
.unified{--glow:#30254c}.unified .frame{background:#1f1f1f}
`;
const footer = text => `<div class="foot"><span>${text}</span><span>↗</span></div>`;
const scenes = [
 { name:'overview', width:1920, height:1510, html:`<section class="art hero" style="--accent:#63e4ce"><div class="kicker">GITGRAPH LITE / PARALLEL AI DEVELOPMENT</div><h1>Every branch. Every workspace.</h1><p class="sub">The whole picture, from the first commit to the final review.</p><div class="motif">${graph}</div><div class="frame"><img src="${img('branch-actions.png')}" alt="Real GitGraph Lite capture with graph and branch action menu"></div></section>` },
 { name:'worktrees', html:`<section class="art card workspaces" style="--accent:#63e4ce"><div class="kicker">01 / WORKTREES</div><h2>One task. One workspace.</h2><p class="sub">Separate folders. Your branches stay in place.</p><div class="frame"><img src="${img('worktrees.png')}" alt="Real worktree manager capture"></div><div class="chips"><div class="chip" style="--dot:#63e4ce">main</div><div class="chip" style="--dot:#ab97ff">feature/search</div><div class="chip" style="--dot:#6cb4ff">release/1.2</div></div>${footer('OPEN / REUSE / REVIEW')}</section>` },
 { name:'branches', html:`<section class="art card branches" style="--accent:#bfacff"><div class="kicker">02 / BRANCHES &amp; PINS</div><h2>Choose your focus.</h2><p class="sub">Local and origin. Together in one view.</p><div class="frame"><img src="${img('branch-picker.png')}" alt="Real branch picker capture"></div>${footer('MULTI-SELECT / PINS / WORKTREES')}</section>` },
 { name:'side-by-side', html:`<section class="art card diff" style="--accent:#8ac6ff"><div class="kicker">03 / SIDE-BY-SIDE DIFF</div><h2>See exactly what changed.</h2><p class="sub">Before and after, down to the word.</p><div class="frame"><img src="${img('diff-side-by-side.png')}" alt="Detail of the real side-by-side diff capture"></div>${footer('REAL APP DETAIL / FULL CAPTURE')}</section>` },
 { name:'unified', html:`<section class="art card diff unified" style="--accent:#bfacff"><div class="kicker">04 / UNIFIED DIFF</div><h2>One patch. Every detail.</h2><p class="sub">A continuous diff, in dark mode.</p><div class="frame"><img src="${img('diff-unified.png')}" alt="Detail of the real unified diff capture"></div>${footer('REAL APP DETAIL / FULL CAPTURE')}</section>` }
];
(async()=>{
 const browser=await chromium.launch({headless:true});
 try {
  const page=await browser.newPage({deviceScaleFactor:1});
  for(const scene of scenes){
   await page.setViewportSize({width:scene.width||960,height:scene.height||760});
   await page.setContent(`<!doctype html><html><head><meta charset="utf-8"><style>${css}</style></head><body>${scene.html}</body></html>`);
   await page.locator('img').evaluateAll(images=>Promise.all(images.map(im=>im.decode())));
   await page.screenshot({path:path.join(output,scene.name+'.png'),omitBackground:true});
   console.log(scene.name+'.png');
  }
 } finally {await browser.close();}
})().catch(error=>{console.error(error);process.exitCode=1;});
