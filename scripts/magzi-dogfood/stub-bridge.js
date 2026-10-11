// Dogfood WhatsApp sidecar stub: no Baileys, nothing reaches a real phone.
// Announces "connected", then tails inbox.jsonl (next to this file) and relays
// each line to magzid exactly as the real sidecar would, so a test can inject
// a WhatsApp DM: {"type":"message","conversationId":"<jid>","senderId":"<jid>",
// "messageId":"wa-test-1","text":"hi","metadata":{"isGroup":false}}.
// Every outbound send is confirmed ok and logged to outbox.jsonl so a test can
// see what Magzi "sent" to WhatsApp.
const fs = require('fs');
const path = require('path');
const readline = require('readline');
const dir = path.dirname(__filename);
const inbox = path.join(dir, 'inbox.jsonl');
const outbox = path.join(dir, 'outbox.jsonl');
const emit = (o) => process.stdout.write(JSON.stringify(o) + '\n');
emit({ type: 'connected' });
let offset = 0;
try { offset = fs.statSync(inbox).size; } catch {}
setInterval(() => {
  let size = 0;
  try { size = fs.statSync(inbox).size; } catch { return; }
  if (size <= offset) return;
  const fd = fs.openSync(inbox, 'r');
  const buf = Buffer.alloc(size - offset);
  fs.readSync(fd, buf, 0, buf.length, offset);
  fs.closeSync(fd);
  offset = size;
  for (const line of buf.toString().split('\n')) if (line.trim()) process.stdout.write(line.trim() + '\n');
}, 500);
readline.createInterface({ input: process.stdin }).on('line', (line) => {
  let o; try { o = JSON.parse(line); } catch { return; }
  fs.appendFileSync(outbox, JSON.stringify({ at: Date.now(), ...o }) + '\n');
  if (o.sendId !== undefined) emit({ type: 'send_result', sendId: o.sendId, ok: true, messageId: 'wa-' + o.sendId });
});
