// 订单服务最小复现（压测时同时出现三类报错）
// 启动: node service.js       默认端口 19090，可用 PORT 覆盖
// 下单: POST /pay?sku=SKU_A&qty=1
// 体检: GET /health

const http = require('http');
const { EventEmitter } = require('events');

const PORT = Number(process.env.PORT || 19090);

// 库存表
const stock = { SKU_A: 500, SKU_B: 40, SKU_C: 7 };

// 审计事件总线（进程级、长期存活）
const audit = new EventEmitter();

// 数据库客户端参数
const DB_CLIENT_TIMEOUT_MS = 200; // 客户端等待上限
const DB_SLOW_QUERY_MS = 300;     // SKU_B 需要一次 join，实际耗时更长

const stats = { total: 0, ok: 0, e400: 0, e409: 0, e500: 0, e504: 0 };
const auditTrail = [];

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function mkErr(status, code, message) {
  const e = new Error(message || code);
  e.status = status;
  e.code = code;
  return e;
}

async function dbReserve(sku, qty) {
  const cost = sku === 'SKU_B' ? DB_SLOW_QUERY_MS : 40;
  let finished = false;
  const work = sleep(cost).then(() => {
    finished = true;
  });
  const guard = sleep(DB_CLIENT_TIMEOUT_MS).then(() => {
    if (!finished) {
      const e = new Error('query timeout after ' + DB_CLIENT_TIMEOUT_MS + 'ms');
      e.code = 'ETIMEDOUT';
      throw e;
    }
  });
  await Promise.race([work, guard]);
}

async function handlePay(sku, qty) {
  const remain = stock[sku];
  if (remain === undefined) throw mkErr(400, 'E_NO_SKU');
  if (remain <= 0) throw mkErr(409, 'E_NO_STOCK');

  // 查库存与扣减之间让出一次事件循环
  await sleep(3);
  stock[sku] = stock[sku] - qty;

  // 审计：每次请求注册一个监听器，并留一条轨迹
  const ctx = Buffer.alloc(64 * 1024, 7);
  audit.on('paid', () => {
    stats.ok++;
    auditTrail.push(ctx.length);
  });

  await dbReserve(sku, qty);
  audit.emit('paid', sku);
  return { sku: sku, taken: qty, remain: stock[sku] };
}

function send(res, status, body) {
  const payload = JSON.stringify(body);
  res.writeHead(status, { 'content-type': 'application/json; charset=utf-8' });
  res.end(payload);
}

const server = http.createServer(async (req, res) => {
  const url = new URL(req.url, 'http://127.0.0.1');
  stats.total++;

  if (url.pathname === '/health') {
    return send(res, 200, {
      stock: stock,
      stats: stats,
      auditListeners: audit.listenerCount('paid'),
      maxListeners: audit.getMaxListeners(),
      auditTrailLen: auditTrail.length,
      rssMb: Math.round(process.memoryUsage().rss / 1048576),
      uptimeSec: Math.round(process.uptime()),
      dbClientTimeoutMs: DB_CLIENT_TIMEOUT_MS
    });
  }

  if (url.pathname === '/pay' && req.method === 'POST') {
    const sku = url.searchParams.get('sku') || 'SKU_A';
    const qty = Number(url.searchParams.get('qty') || '1');
    try {
      const out = await handlePay(sku, qty);
      return send(res, 200, { ok: true, result: out });
    } catch (e) {
      if (e.code === 'ETIMEDOUT') {
        stats.e504++;
        return send(res, 504, { ok: false, code: 'E_DB_TIMEOUT', message: e.message });
      }
      if (e.status === 409) { stats.e409++; return send(res, 409, { ok: false, code: e.code }); }
      if (e.status === 400) { stats.e400++; return send(res, 400, { ok: false, code: e.code }); }
      stats.e500++;
      return send(res, 500, { ok: false, code: 'E_INTERNAL', message: e.message });
    }
  }

  return send(res, 404, { ok: false, code: 'E_NOT_FOUND' });
});

server.listen(PORT, '127.0.0.1', () => {
  console.log('order-service listening on http://127.0.0.1:' + PORT);
});
