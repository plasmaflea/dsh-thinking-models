// 压测脚本
// 用法: node load.js [并发数] [总请求数] [sku]
// 例:   node load.js 16 320 SKU_A
//       node load.js 16 320 SKU_B

const http = require('http');

const CONC = Number(process.argv[2] || 16);
const TOTAL = Number(process.argv[3] || 320);
const SKU = process.argv[4] || 'SKU_A';
const HOST = process.env.HOST || '127.0.0.1';
const PORT = Number(process.env.PORT || 19090);

function call(path, method) {
  return new Promise((resolve) => {
    const t0 = Date.now();
    const req = http.request(
      { host: HOST, port: PORT, path: path, method: method || 'GET', timeout: 15000 },
      (res) => {
        let body = '';
        res.on('data', (c) => (body += c));
        res.on('end', () => resolve({ status: res.statusCode, ms: Date.now() - t0, body: body }));
      }
    );
    req.on('timeout', () => { req.destroy(new Error('client timeout')); });
    req.on('error', (e) => resolve({ status: 0, ms: Date.now() - t0, body: String(e.message) }));
    req.end();
  });
}

function parseCode(body) {
  try {
    const j = JSON.parse(body);
    return j.code || (j.ok ? 'OK' : 'UNKNOWN');
  } catch (e) {
    return 'NON_JSON';
  }
}

async function main() {
  const before = JSON.parse((await call('/health')).body);
  console.log('== health before ==');
  console.log(JSON.stringify(before));

  const results = [];
  let issued = 0;

  async function worker() {
    while (issued < TOTAL) {
      const i = issued++;
      const r = await call('/pay?sku=' + SKU + '&qty=1', 'POST');
      results.push(r);
    }
  }

  const t0 = Date.now();
  await Promise.all(Array.from({ length: CONC }, () => worker()));
  const elapsed = Date.now() - t0;

  const byStatus = {};
  const byCode = {};
  for (const r of results) {
    byStatus[r.status] = (byStatus[r.status] || 0) + 1;
    const c = parseCode(r.body);
    byCode[c] = (byCode[c] || 0) + 1;
  }

  const times = results.map((r) => r.ms).sort((a, b) => a - b);
  const q = (p) => times[Math.min(times.length - 1, Math.floor((p / 100) * times.length))];

  const after = JSON.parse((await call('/health')).body);

  console.log('== run ==');
  console.log('concurrency=' + CONC + ' requests=' + TOTAL + ' sku=' + SKU + ' elapsedMs=' + elapsed);
  console.log('byStatus=' + JSON.stringify(byStatus));
  console.log('byCode=' + JSON.stringify(byCode));
  console.log('latencyMs p50=' + q(50) + ' p90=' + q(90) + ' p99=' + q(99) + ' max=' + times[times.length - 1]);

  console.log('== health after ==');
  console.log(JSON.stringify(after));
  console.log('== delta ==');
  console.log(
    JSON.stringify({
      stock: after.stock,
      auditListeners: after.auditListeners,
      rssMb: after.rssMb,
      uptimeSec: after.uptimeSec
    })
  );

  const sample = results.filter((r) => r.status !== 200).slice(0, 5).map((r) => r.status + ' ' + r.body);
  if (sample.length) {
    console.log('== sample failures ==');
    sample.forEach((s) => console.log(s));
  }
}

main();
