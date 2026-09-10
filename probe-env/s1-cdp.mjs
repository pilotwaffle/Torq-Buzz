// Slice 1 gate helper: drive the Buzz dev window over the WebView2 remote-debugging port.
// Requires the desktop launched with WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS=--remote-debugging-port=9222
// (Start-S16Desktop.ps1 sets this). Node 22+ (global WebSocket, fetch).
//
//   node s1-cdp.mjs targets                       list debuggable pages
//   node s1-cdp.mjs eval "<js expression>"        evaluate in the Buzz page, print result
//   node s1-cdp.mjs flag-on                       set BUZZ_LIVE_ACTIVITY override = true (localStorage), reload
//   node s1-cdp.mjs capture <outfile> <seconds>   append "[live-activity] paint" console lines to outfile
//   node s1-cdp.mjs hash "#/channels/<id>"        navigate the app (hash router)
const PORT = process.env.CDP_PORT || "9222";
const [cmd, ...rest] = process.argv.slice(2);

async function pickTarget() {
  const list = await (await fetch(`http://127.0.0.1:${PORT}/json/list`)).json();
  const pages = list.filter((t) => t.type === "page");
  const buzz = pages.find((t) => /127\.0\.0\.1:1420|localhost:1420/.test(t.url)) ?? pages[0];
  if (!buzz) throw new Error("no page target found on port " + PORT);
  return buzz;
}

function connect(target) {
  return new Promise((resolve, reject) => {
    const ws = new WebSocket(target.webSocketDebuggerUrl);
    let id = 0;
    const pending = new Map();
    const listeners = [];
    ws.onopen = () =>
      resolve({
        send: (method, params = {}) =>
          new Promise((res, rej) => {
            const mid = ++id;
            pending.set(mid, { res, rej });
            ws.send(JSON.stringify({ id: mid, method, params }));
          }),
        on: (fn) => listeners.push(fn),
        close: () => ws.close(),
      });
    ws.onerror = (e) => reject(e);
    ws.onmessage = (m) => {
      const msg = JSON.parse(m.data);
      if (msg.id && pending.has(msg.id)) {
        const { res, rej } = pending.get(msg.id);
        pending.delete(msg.id);
        msg.error ? rej(new Error(JSON.stringify(msg.error))) : res(msg.result);
      } else if (msg.method) {
        for (const fn of listeners) fn(msg);
      }
    };
  });
}

async function evalJs(cdp, expression) {
  const r = await cdp.send("Runtime.evaluate", { expression, returnByValue: true, awaitPromise: true });
  if (r.exceptionDetails) throw new Error(r.exceptionDetails.text + " " + JSON.stringify(r.exceptionDetails.exception?.description ?? ""));
  return r.result.value;
}

const target = cmd === "targets" ? null : await pickTarget();
if (cmd === "targets") {
  const list = await (await fetch(`http://127.0.0.1:${PORT}/json/list`)).json();
  for (const t of list) console.log(t.type, t.url, t.title);
  process.exit(0);
}
const cdp = await connect(target);

if (cmd === "eval") {
  console.log(JSON.stringify(await evalJs(cdp, rest.join(" ")), null, 2));
} else if (cmd === "hash") {
  await evalJs(cdp, `location.hash = ${JSON.stringify(rest[0])}; location.hash`);
  console.log("hash set to", rest[0]);
} else if (cmd === "flag-on") {
  const out = await evalJs(
    cdp,
    `(() => { const k='buzz-feature-overrides-v1'; const o = JSON.parse(localStorage.getItem(k) || '{}'); o.BUZZ_LIVE_ACTIVITY = true; localStorage.setItem(k, JSON.stringify(o)); return localStorage.getItem(k); })()`,
  );
  console.log("overrides now:", out);
  await cdp.send("Page.reload");
  console.log("page reloaded");
} else if (cmd === "send") {
  // Type a message into the DM composer and press Enter.
  const text = rest.join(" ");
  await evalJs(cdp, `(() => { const el = document.querySelector('[data-testid=message-input]'); el.focus(); return true; })()`);
  await cdp.send("Input.insertText", { text });
  await new Promise((r) => setTimeout(r, 200));
  await cdp.send("Input.dispatchKeyEvent", { type: "keyDown", key: "Enter", code: "Enter", windowsVirtualKeyCode: 13, text: "\r" });
  await cdp.send("Input.dispatchKeyEvent", { type: "keyUp", key: "Enter", code: "Enter", windowsVirtualKeyCode: 13 });
  console.log("sent", text.length, "chars");
} else if (cmd === "run") {
  // Full gate run: run <outfile> <seconds> <agentPubkey> <promptFile>
  // Sends the prompt, opens the agent session panel from the composer activity bar the first time
  // the agent is working, captures paint lines, and re-sends the prompt whenever the agent goes idle.
  const [outfile, secondsArg, pk, promptFile] = rest;
  const seconds = Number(secondsArg || "200");
  const fs = await import("node:fs");
  const prompt = fs.readFileSync(promptFile, "utf8").trim();
  await cdp.send("Runtime.enable");
  let n = 0;
  cdp.on((msg) => {
    if (msg.method !== "Runtime.consoleAPICalled") return;
    const text = msg.params.args.map((a) => a.value ?? a.description ?? "").join(" ");
    if ((text.includes("[live-activity]") || text.includes("[ipc-stall]") || text.includes("[longtask]") || text.includes("[react-commit]"))) {
      fs.appendFileSync(outfile, `${new Date().toISOString()} ${text}\n`);
      n++;
    }
  });
  const sendPrompt = async () => {
    await evalJs(cdp, `(() => { document.querySelector('[data-testid=message-input]').focus(); return true; })()`);
    await cdp.send("Input.insertText", { text: prompt });
    await new Promise((r) => setTimeout(r, 200));
    await cdp.send("Input.dispatchKeyEvent", { type: "keyDown", key: "Enter", code: "Enter", windowsVirtualKeyCode: 13, text: "\r" });
    await cdp.send("Input.dispatchKeyEvent", { type: "keyUp", key: "Enter", code: "Enter", windowsVirtualKeyCode: 13 });
    console.log(new Date().toISOString(), "prompt sent");
    lastSent = Date.now();
  };
  let lastSent = 0;
  const state = async () =>
    evalJs(
      cdp,
      `(() => ({ item: !!document.querySelector('[data-testid="bot-activity-composer-item-${pk}"]'), trigger: !!document.querySelector('[data-testid=bot-activity-composer-trigger]'), timeline: !!document.querySelector('[aria-label="Agent activity timeline"]'), session: document.querySelector('[data-testid=agent-session-agent-name]')?.textContent ?? null }))()`,
    );
  await sendPrompt();
  let opened = false;
  let idleTicks = 0;
  const t0 = Date.now();
  while (Date.now() - t0 < seconds * 1000) {
    await new Promise((r) => setTimeout(r, 3000));
    const s = await state();
    if (!opened && !s.timeline) {
      if (!s.item && s.trigger) await evalJs(cdp, `(() => { document.querySelector('[data-testid=bot-activity-composer-trigger]').click(); return true; })()`);
      const s2 = await state();
      if (s2.item) {
        await evalJs(cdp, `(() => { document.querySelector('[data-testid="bot-activity-composer-item-${pk}"]').click(); return true; })()`);
        await new Promise((r) => setTimeout(r, 2000));
        const s3 = await state();
        opened = s3.timeline;
        console.log(new Date().toISOString(), "session panel opened, timeline mounted =", s3.timeline, "session =", s3.session);
      }
    }
    // Re-send cadence: fixed CADENCE_S seconds (default 60) — one long turn at a time,
    // no prompt stacking. (The composer activity chip disappears once the session
    // panel is open, so chip-based idle detection is not usable here.)
    const cadence = Number(process.env.CADENCE_S || "60");
    if (Date.now() - lastSent >= cadence * 1000) { await sendPrompt(); }
    if ((Date.now() - t0) % 30000 < 3000) console.log(new Date().toISOString(), `paint lines so far: ${n}, timeline=${s.timeline}, working=${s.item}`);
  }
  console.log(`done: ${n} paint lines captured to ${outfile}`);
} else if (cmd === "profile") {
  // profile <outfile.cpuprofile> <seconds>: sample the page main thread and write a V8 CPU profile.
  const [outfile, secondsArg] = rest;
  const seconds = Number(secondsArg || "120");
  const fs = await import("node:fs");
  await cdp.send("Profiler.enable");
  await cdp.send("Profiler.setSamplingInterval", { interval: 2000 });
  await cdp.send("Profiler.start");
  console.log(`profiling main thread for ${seconds}s ...`);
  await new Promise((r) => setTimeout(r, seconds * 1000));
  const { profile } = await cdp.send("Profiler.stop");
  fs.writeFileSync(outfile, JSON.stringify(profile));
  // Summarise self time by function and by script.
  const dt = profile.timeDeltas; const samples = profile.samples;
  const selfByNode = new Map();
  for (let i = 0; i < samples.length; i++) selfByNode.set(samples[i], (selfByNode.get(samples[i]) || 0) + (dt[i] || 0));
  const byFn = new Map(), byUrl = new Map();
  for (const n of profile.nodes) {
    const t = selfByNode.get(n.id) || 0; if (!t) continue;
    const url = (n.callFrame.url || "(native)").replace(/^.*\/\/[^/]+/, "");
    const fn = `${n.callFrame.functionName || "(anon)"} ${url}:${n.callFrame.lineNumber}`;
    byFn.set(fn, (byFn.get(fn) || 0) + t); byUrl.set(url, (byUrl.get(url) || 0) + t);
  }
  const total = [...byFn.values()].reduce((a, b) => a + b, 0);
  console.log(`total sampled ${(total / 1e6).toFixed(1)}s`);
  console.log("top scripts by self time:");
  for (const [u, t] of [...byUrl].sort((a, b) => b[1] - a[1]).slice(0, 12)) console.log(`  ${(t / 1e6).toFixed(2)}s  ${u}`);
  console.log("top functions by self time:");
  for (const [f, t] of [...byFn].sort((a, b) => b[1] - a[1]).slice(0, 20)) console.log(`  ${(t / 1e6).toFixed(2)}s  ${f}`);
} else if (cmd === "gate-nodebug") {
  // gate-nodebug <outfile> <seconds> <agentPubkey> <promptFile> <channelHash>
  // No debugger attached while measuring: enable the runtime log flag, send one prompt,
  // open the session panel, DISCONNECT, then re-send prompts blindly every CADENCE_S seconds
  // (each send is a short attach/detach), and finally read window.__s1Log.
  const [outfile, secondsArg, pk, promptFile, channelHash] = rest;
  const seconds = Number(secondsArg || "210");
  const cadence = Number(process.env.CADENCE_S || "60");
  const fs = await import("node:fs");
  const prompt = fs.readFileSync(promptFile, "utf8").trim();
  const wait = (ms) => new Promise((r) => setTimeout(r, ms));
  await evalJs(cdp, `(() => { localStorage.setItem('s1-gate','1'); window.__s1Log = []; location.hash = ${JSON.stringify(channelHash)}; return true; })()`);
  await wait(2500);
  const sendOnce = async (c) => {
    await evalJs(c, `(() => { document.querySelector('[data-testid=message-input]').focus(); return true; })()`);
    await c.send("Input.insertText", { text: prompt });
    await wait(200);
    await c.send("Input.dispatchKeyEvent", { type: "keyDown", key: "Enter", code: "Enter", windowsVirtualKeyCode: 13, text: "\r" });
    await c.send("Input.dispatchKeyEvent", { type: "keyUp", key: "Enter", code: "Enter", windowsVirtualKeyCode: 13 });
    console.log(new Date().toISOString(), "prompt sent");
  };
  await sendOnce(cdp);
  // open the session panel from the activity chip once the agent is working
  let opened = false;
  for (let i = 0; i < 20 && !opened; i++) {
    await wait(2000);
    opened = await evalJs(cdp, `(() => { if (document.querySelector('[aria-label="Agent activity timeline"]')) return true; const t=document.querySelector('[data-testid=bot-activity-composer-trigger]'); const item=document.querySelector('[data-testid="bot-activity-composer-item-${pk}"]'); if(!item && t) t.click(); const it2=document.querySelector('[data-testid="bot-activity-composer-item-${pk}"]'); if(it2){ it2.click(); } return false; })()`);
  }
  console.log(new Date().toISOString(), "session panel open =", opened, "— detaching debugger for the measurement window");
  cdp.close();
  const t0 = Date.now();
  let lastSent = Date.now();
  while (Date.now() - t0 < seconds * 1000) {
    await wait(3000);
    if (Date.now() - lastSent >= cadence * 1000) {
      const t = await pickTarget(); const c = await connect(t);
      try { await sendOnce(c); } catch (e) { console.log("send failed:", e.message); }
      c.close(); lastSent = Date.now();
    }
  }
  const t = await pickTarget(); const c = await connect(t);
  const lines = await evalJs(c, `(() => (window.__s1Log || []).slice())()`);
  fs.writeFileSync(outfile, lines.join("\n") + "\n");
  console.log(`done: ${lines.length} log lines read from window.__s1Log -> ${outfile}`);
  c.close();
  process.exit(0);
} else if (cmd === "capture") {
  const [outfile, secondsArg] = rest;
  const seconds = Number(secondsArg || "200");
  const fs = await import("node:fs");
  await cdp.send("Runtime.enable");
  let n = 0;
  cdp.on((msg) => {
    if (msg.method !== "Runtime.consoleAPICalled") return;
    const text = msg.params.args.map((a) => a.value ?? a.description ?? "").join(" ");
    if ((text.includes("[live-activity]") || text.includes("[ipc-stall]") || text.includes("[longtask]") || text.includes("[react-commit]"))) {
      fs.appendFileSync(outfile, `${new Date().toISOString()} ${text}\n`);
      n++;
    }
  });
  console.log(`capturing paint lines to ${outfile} for ${seconds}s ...`);
  await new Promise((r) => setTimeout(r, seconds * 1000));
  console.log(`done: ${n} paint lines captured`);
} else {
  console.log("unknown command");
}
cdp.close();
process.exit(0);
