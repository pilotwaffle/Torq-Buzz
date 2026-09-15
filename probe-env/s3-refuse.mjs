// Slice 3 runbook step 5.1: publish an invoke_agent definition (kind 30620) signed by a
// NON-owner key and record the relay's refusal. Uses a throwaway key generated here; the
// key is printed as pubkey only (secret never written). Run from desktop/ so nostr-tools resolves.
//   node ../../../probe-env/s3-refuse.mjs <channelId> <agentPubkey> [throwawaySecretHex]
import { generateSecretKey, getPublicKey, finalizeEvent } from "nostr-tools/pure";

const [channelId, agentPk, skHex] = process.argv.slice(2);
const sk = skHex ? Uint8Array.from(Buffer.from(skHex, "hex")) : generateSecretKey();
const pk = getPublicKey(sk);
console.log("signer pubkey", pk);

const yaml = `name: s3-gate-refused-agent-signed
trigger:
  on: schedule
  interval: 15m
steps:
  - id: s1
    action: invoke_agent
    agent_pubkey: ${agentPk}
    prompt: "REFUSED CONTROL: never fire"
    result_channel: ${channelId}
    idempotency_key: "s3-refused-{{trigger.timestamp}}"
    token_budget_per_run: 20000
    token_budget_per_day: 200000
enabled: true
`;
const wfId = crypto.randomUUID();
let defId = null;
const ws = new WebSocket("ws://127.0.0.1:3300");
const send = (o) => ws.send(JSON.stringify(o));
ws.onopen = () => console.log("connected");
ws.onmessage = (m) => {
  const msg = JSON.parse(m.data);
  if (msg[0] === "AUTH") {
    const auth = finalizeEvent({ kind: 22242, created_at: Math.floor(Date.now() / 1000), tags: [["relay", "ws://127.0.0.1:3300"], ["challenge", msg[1]]], content: "" }, sk);
    send(["AUTH", auth]);
    setTimeout(() => {
      const ev = finalizeEvent({ kind: 30620, created_at: Math.floor(Date.now() / 1000), tags: [["d", wfId], ["h", channelId]], content: yaml }, sk);
      defId = ev.id; console.log("publishing 30620", ev.id.slice(0, 12), "d", wfId);
      send(["EVENT", ev]);
    }, 500);
    return;
  }
  console.log(new Date().toISOString(), JSON.stringify(msg).slice(0, 300));
  if (msg[0] === "OK" && msg[1] === defId) { console.log("RESULT accepted=" + msg[2] + " message=" + msg[3]); ws.close(); }
};
ws.onclose = () => { console.log("closed"); process.exit(0); };
setTimeout(() => { console.log("timeout"); process.exit(1); }, 15000);
