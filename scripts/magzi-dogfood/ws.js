#!/usr/bin/env node
// Dogfood: listen on a member's app socket and print every frame type (plus
// text) for N seconds. Raw HTTP upgrade so the bearer goes in the header like
// the app does — no deps. Usage: node ws.js <token> [seconds]
const http = require('http');
const crypto = require('crypto');
const [token, secs = '30'] = process.argv.slice(2);
if (!token) { console.error('usage: ws.js <token> [seconds]'); process.exit(2); }
const req = http.request({
  host: '127.0.0.1', port: 8767, path: '/mobile/v1/ws', method: 'GET',
  headers: {
    Connection: 'Upgrade', Upgrade: 'websocket', 'Sec-WebSocket-Version': '13',
    'Sec-WebSocket-Key': crypto.randomBytes(16).toString('base64'),
    Authorization: `Bearer ${token}`,
  },
});
req.on('upgrade', (_res, sock) => {
  let buf = Buffer.alloc(0);
  sock.on('data', (d) => {
    buf = Buffer.concat([buf, d]);
    for (;;) {
      if (buf.length < 2) return;
      let len = buf[1] & 0x7f, off = 2;
      if (len === 126) { if (buf.length < 4) return; len = buf.readUInt16BE(2); off = 4; }
      else if (len === 127) { if (buf.length < 10) return; len = Number(buf.readBigUInt64BE(2)); off = 10; }
      if (buf.length < off + len) return;
      const op = buf[0] & 0x0f;
      const payload = buf.subarray(off, off + len);
      buf = buf.subarray(off + len);
      if (op === 1) {
        try {
          const f = JSON.parse(payload.toString());
          const p = f.payload || {};
          console.log(`${f.type}\t${f.conversationId || ''}\t${JSON.stringify(p.line || p.text || p.delta || '')}`);
        } catch { console.log('text', payload.toString()); }
      } else if (op === 9) {
        sock.write(Buffer.from([0x8a, 0x80, 0, 0, 0, 0])); // masked empty pong
      }
    }
  });
  setTimeout(() => process.exit(0), Number(secs) * 1000);
});
req.on('response', (r) => { console.error('no upgrade: HTTP', r.statusCode); process.exit(1); });
req.on('error', (e) => { console.error(e.message); process.exit(1); });
req.end();
