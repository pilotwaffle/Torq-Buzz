// Slice 2 controls gate driver. Attaches to the Buzz window only for input injection and log reads
// (no Runtime.enable, no console capture, no profiler), so the production page runs undisturbed.
//   node s2-controls.mjs <outfile> <rounds> <agentPubkey> <channelHash> <promptFile>
// Per round: send task prompt -> wait -> Pause -> Resume -> Steer (typed message) -> Cancel; acks read from window.__s1Log.
const PORT = process.env.CDP_PORT || "9222";
const [outfile, roundsArg, pk, channelHash, promptFile] = process.argv.slice(2);
const rounds = Number(roundsArg || "10");
const fs = await import("node:fs");
const prompt = fs.readFileSync(promptFile, "utf8").trim();
const wait = (ms) => new Promise((r) => setTimeout(r, ms));

async function target() {
  const list = await (await fetch(`http://127.0.0.1:${PORT}/json/list`)).json();
  return list.find((t) => t.type === "page" && /1420/.test(t.url)) ?? list.find((t) => t.type === "page");
}
function connect(t) {
  return new Promise((resolve, reject) => {
    const ws = new WebSocket(t.webSocketDebuggerUrl); let id = 0; const pending = new Map();
    ws.onopen = () => resolve({
      send: (method, params = {}) => new Promise((res, rej) => { const mid = ++id; pending.set(mid, { res, rej }); ws.send(JSON.stringify({ id: mid, method, params })); }),
      close: () => ws.close(),
    });
    ws.onerror = reject;
    ws.onmessage = (m) => { const msg = JSON.parse(m.data); if (msg.id && pending.has(msg.id)) { const { res, rej } = pending.get(msg.id); pending.delete(msg.id); msg.error ? rej(new Error(JSON.stringify(msg.error))) : res(msg.result); } };
  });
}
async function withPage(fn) { const c = await connect(await target()); try { return await fn(c); } finally { c.close(); } }
async function evalJs(c, expression) { const r = await c.send("Runtime.evaluate", { expression, returnByValue: true, awaitPromise: true }); if (r.exceptionDetails) throw new Error(r.exceptionDetails.text + " " + (r.exceptionDetails.exception?.description ?? "")); return r.result.value; }
async function typeCtrlEnter(c, text) { await c.send("Input.insertText", { text }); await wait(150); await c.send("Input.dispatchKeyEvent", { type: "keyDown", key: "Enter", code: "Enter", windowsVirtualKeyCode: 13, modifiers: 2 }); await c.send("Input.dispatchKeyEvent", { type: "keyUp", key: "Enter", code: "Enter", windowsVirtualKeyCode: 13, modifiers: 2 }); }
async function typeEnter(c, text) { await c.send("Input.insertText", { text }); await wait(150); await c.send("Input.dispatchKeyEvent", { type: "keyDown", key: "Enter", code: "Enter", windowsVirtualKeyCode: 13, text: "\r" }); await c.send("Input.dispatchKeyEvent", { type: "keyUp", key: "Enter", code: "Enter", windowsVirtualKeyCode: 13 }); }
const clickLabel = (label) => `(() => { const b=[...document.querySelectorAll('button')].find(x=>x.getAttribute('aria-label')===${JSON.stringify(label)}); if(!b) return 'missing'; if(b.disabled) return 'disabled'; b.click(); return 'clicked'; })()`;
const logLen = `(window.__s1Log||[]).length`;
const logSince = (n) => `(window.__s1Log||[]).slice(${n})`;
async function waitAck(sentLine, timeoutMs = 15000) {
  const id = /id=([^ ]+)/.exec(sentLine)?.[1];
  const t0 = Date.now();
  while (Date.now() - t0 < timeoutMs) {
    await wait(700);
    const found = await withPage((c) => evalJs(c, `(window.__s1Log||[]).find(l => l.includes('[agent-controls] ack id=${id} '))||null`));
    if (found) return found;
  }
  return null;
}
async function control(label, kind, extra) {
  const before = await withPage((c) => evalJs(c, logLen));
  const r = await withPage(async (c) => { const res = await evalJs(c, clickLabel(label)); if (res === "clicked" && extra) await extra(c); return res; });
  if (r !== "clicked") { console.log(new Date().toISOString(), kind, "button", r); return; }
  let sent = null;
  for (let i = 0; i < 10 && !sent; i++) { await wait(600); sent = (await withPage((c) => evalJs(c, logSince(before)))).find((l) => l.includes(`[agent-controls] sent kind=${kind}`)); }
  if (!sent) { console.log(new Date().toISOString(), kind, "no sent line"); return; }
  const ack = await waitAck(sent);
  console.log(new Date().toISOString(), kind, ack ? ack.slice(25, 120) : "NO ACK within 15 s");
}
console.log(`controls gate: ${rounds} rounds on ${pk.slice(0, 10)} channel ${channelHash}`);
await withPage((c) => evalJs(c, `(() => { localStorage.setItem('s1-gate','1'); const k='buzz-feature-overrides-v1'; const o=JSON.parse(localStorage.getItem(k)||'{}'); o.BUZZ_LIVE_ACTIVITY=true; o.BUZZ_AGENT_CONTROLS=true; localStorage.setItem(k, JSON.stringify(o)); return true; })()`));
try { await withPage((c) => evalJs(c, `location.reload()`)); } catch {}
await wait(6000);
await withPage((c) => evalJs(c, `(() => { window.__s1Log = window.__s1Log || []; location.hash=${JSON.stringify(channelHash)}; return true; })()`));
await wait(2500);

const turnIdExpr = `(() => { const el=document.querySelector('[aria-label="Agent controls"]'); if(!el) return 'nobar'; const k=Object.keys(el).find(k=>k.startsWith('__reactFiber')); let f=el[k]; for(let i=0;i<12&&f;i++){const p=f.memoizedProps; if(p&&'turnId' in p) return p.turnId||'idle'; f=f.return;} return 'noprops'; })()`;
async function openPanel() {
  for (let i = 0; i < 20; i++) {
    const st = await withPage((c) => evalJs(c, `(() => { if (document.querySelector('[aria-label="Agent controls"]')) return 'bar'; const t=document.querySelector('[data-testid=bot-activity-composer-trigger]'); const item=document.querySelector('[data-testid="bot-activity-composer-item-${pk}"]'); if(!item && t) t.click(); const it2=document.querySelector('[data-testid="bot-activity-composer-item-${pk}"]'); if(it2) it2.click(); return document.querySelector('[aria-label="Agent controls"]') ? 'bar' : 'nobar'; })()`));
    if (st === "bar") return true;
    await wait(1500);
  }
  return false;
}
async function waitTurn(want, maxMs) {
  const t0 = Date.now(); let last = null;
  while (Date.now() - t0 < maxMs) {
    last = await withPage((c) => evalJs(c, turnIdExpr));
    const inFlight = last !== "idle" && last !== "nobar" && last !== "noprops";
    if (want === "inflight" ? inFlight : !inFlight) return last;
    await wait(700);
  }
  return null;
}
async function sendPrompt(round, tag) {
  const text = prompt.replace(/ROUND/g, `${round}-${tag}-${Date.now()%100000}`);
  const chId = channelHash.replace(/^#\/channels\//, "");
  await withPage((c) => evalJs(c, `window.__TAURI_INTERNALS__.invoke('send_channel_message', { channelId: ${JSON.stringify(chId)}, content: ${JSON.stringify(text)}, mentionPubkeys: [${JSON.stringify(pk)}], parentEventId: null, rootEventId: null, mediaTags: null, emojiTags: null, mentionTags: null, sentFromThreadTag: null, kind: null, expectedRelayUrl: null, expectedSignerPubkey: null }).then(r => r.eventId || 'sent')`));
  console.log(new Date().toISOString(), `round ${round}: ${tag} prompt sent`);
  await wait(1500);
  await openPanel();
  const turn = await waitTurn("inflight", 40000);
  console.log(new Date().toISOString(), `round ${round}: ${tag} turn ${turn}`);
  await wait(1200);
}
for (let round = 1; round <= rounds; round++) {
  await sendPrompt(round, "cancel");
  await control("Cancel current turn", "cancel");
  console.log(new Date().toISOString(), `round ${round}: turn ended -> ${await waitTurn("idle", 40000)}`);
  await wait(1500);
  await sendPrompt(round, "steer");
  await control("Steer agent with a message", "steer", async (c) => { await wait(500); await evalJs(c, `(() => { const t=[...document.querySelectorAll('textarea')].find(x=>x.getAttribute('aria-label')==='Steer message'); t.focus(); return true; })()`); await typeCtrlEnter(c, `Steer ${round}: keep going exactly as instructed, and also append the line STEERED ${round} at the very end.`); });
  console.log(new Date().toISOString(), `round ${round}: turn ended -> ${await waitTurn("idle", 60000)}`);
  await wait(1000);
  await control("Pause agent queue", "pause");
  await wait(1500);
  await control("Resume agent queue", "resume");
  await wait(2500);
}
const lines = await withPage((c) => evalJs(c, `(window.__s1Log||[]).filter(l => l.includes('[agent-controls]'))`));
fs.writeFileSync(outfile, lines.join("\n") + "\n");
console.log(`done: ${lines.length} control log lines -> ${outfile}`);
