# 订单服务三方争吵：定位过程与根因判定

## 0. 结论先行

**不是一个根源，也不是三个。是 3 个独立根因 + 1 个结构性缺陷（放大器）。**
更要紧的是：这三个根因**不是并列的**，第 2 件事会持续往第 1 件和第 3 件事里灌脏水，所以"三个人分头修、各自验收通过"这条路必然失败。

| 症状 | 根因 | 位置 | 与其它两件的关系 |
|---|---|---|---|
| 1. SKU_C 7 件卖 16 单，库存 −9 | **A. 并发 TOCTOU**：检查库存与扣减库存之间隔了一个 `await`，检查用的是 `await` 之前的快照 | `service.js:52-58` | 被 D 污染（失败订单也扣库存） |
| 2. 某 SKU 订单全 504 | **C. 超时预算配错**：客户端 200ms < SKU_B 查询 300ms，`Promise.race` 必然由 guard 先抛 | `service.js:18-19, 36, 41-48` | **单请求即可复现，与并发、与内存完全无关** |
| 3. 内存 48→89MB 且成功计数大一个数量级 | **B. 审计监听器只 `on` 不 `off`**：每请求注册一个永不注销的监听器，`emit` 会调用**历史上所有**监听器 | `service.js:61-65, 68` | 内存与计数是**同一个 Bug 的两个出口**，不是两个人两摊事 |
| （不单独表现为症状） | **D. 副作用前置且无补偿**：扣库存发生在 `dbReserve` 之前，失败不回滚；监听器也在 `dbReserve` 之前注册 | `service.js:58` 早于 `67`/`62` | 把 A、B、C 三件事搅在一起的粘合剂 |

一句话判定：**症状 3 的两半必须交给同一个人修（同一个根因）；症状 1 和 2 是两个真独立的根因；但谁都绕不开 D —— 不先修 D，先修谁都会被另外两件的脏数据打脸。**

---

## 1. 怎么定位：三步把它们切开

分头修之前，先做三件"切分实验"，目的是把"看起来一起发生"拆成"各自可单独复现"。

### 第 1 步：把并发变量摘掉，看症状 1 是否还在

```
node load.js 1 10 SKU_C     # 并发=1，串行 10 单
```

| 实验 | 200 | 409 | 最终 stock |
|---|---|---|---|
| 并发 16，32 单（题面场景） | 16 | 16 | **−9** |
| **并发 1，10 单** | **7** | 3 | **0** |

串行时"7 件卖 7 单、后 3 单 409"完全正确。→ **不是库存初值写错，也不是扣减公式写错，是并发下的丢失更新。** 变量唯一化，根因锁定在并发。

### 第 2 步：给"读库存"装探针，看 16 个请求到底读到了什么

把 `service.js` 复制到本目录（`probe-svc.js`，原文件未改动），只在 `handlePay` 里加一行：把每次 qty 检查读到的 `remain` 记进 `reads` 并从 `/health` 暴露。同样跑 `16 32 SKU_C`：

```
reads@check = [7, 6,6,6,6,6,6,6,6,6,6,6,6,6,6,6, -9,-9,...(16个), ]
distinct = [-9, 6, 7]   count=32
stock SKU_C = -9   stats.ok = 256   listeners = 16
```

这就是完整的犯罪现场：
- 第 1 单读到 `7`，通过检查，扣成 `6`；
- **接下来 15 个请求在同一时刻都读到 `6`**——它们彼此看不见对方的扣减，全都通过 `remain <= 0` 检查，全都执行 `6 - 1`；
- 结果是 `6 − 15 = −9`；后 16 个请求读到 `−9` 才被 409 挡住。

`remain` 是 `await sleep(3)` **之前**的快照，扣减却是 `await` 之后现读现写（`stock[sku] = stock[sku] - qty`）。检查与扣减不在同一个 tick 内 → 教科书级 TOCTOU / lost update。

**顺带一个还没爆但存在同源的 Bug**：`if (remain <= 0)` 没有比较 `qty`。接口收 `qty` 参数，`remain=2` 时 `qty=5` 也能过检查，直接扣成 `−3`。修 A 时必须一起改成 `if (remain < qty)`。

### 第 3 步：对 SKU_B 打单发（并发=1，甚至不压测）

```
POST /pay?sku=SKU_B&qty=1
→ 504  {"ok":false,"code":"E_DB_TIMEOUT","message":"query timeout after 200ms"}
```

一个请求、零并发、服务刚起，照样 504。→ **症状 2 与压力、与并发、与内存毫无关系，是个纯配置/预算错误。** 响应体里已经自己报出答案：`query timeout after 200ms`；而 `/health` 里 `dbClientTimeoutMs: 200`；代码里 `DB_SLOW_QUERY_MS = 300`。一个数字比较就够了，不需要压测。

为什么"换别的 SKU 就正常"：`service.js:36` 的 `const cost = sku === 'SKU_B' ? DB_SLOW_QUERY_MS : 40;` —— 只有 SKU_B 走 300ms 分支。这是**按 SKU 硬编码**的慢查询，不是全站慢。

### 第 4 步：内存与计数的"同一根因"验证

`/health` 每次返回的三个数已经能自证同源：

| 实验 | 真实 200 | `stats.ok` | 放大倍数 | `auditListeners` | `auditTrailLen` | `rssMb` |
|---|---|---|---|---|---|---|
| 并发 1，10 单 SKU_C | 7 | 28 | 4× | 7 | 28 | 49 |
| 并发 16，32 单 SKU_C | 16 | **256** | **16×** | 16 | 256 | 51 |
| 并发 16，512 单 SKU_A | 503 | **132450** | **263×** | 503 | 132450 | **86** |
| 并发 16，45 单 SKU_B（全 504） | 0 | 0 | — | 45 | 0 | 53 |

三个铁证：
1. **`auditTrailLen` 恒等于 `stats.ok`**（28/28、256/256、132450/132450）→ 两者是同一个闭包里相邻的两行（`service.js:63-64`），是**一个** Bug。
2. **放大倍数不是常数**（4× → 16× → 263×），随流量增长。所以题面说的"大一个数量级"只是他们恰好看到的那个规模；谁要是想"除以 10 修正"永远修不对。原因是：`stats.ok++` 在监听器里，而 `emit` 调用**当时存量的全部**监听器，总量是 N² 量级（串行是三角数 N(N+1)/2，并发时所有监听器都在第一次 `emit` 前注册好，就接近 N²）。
3. **rss 增量 ≈ 监听器数 × 64KB**：503 × 64KB = 32MB，实测 48 → 86MB。每个泄漏的闭包都pin住 `service.js:61` 那个 `Buffer.alloc(64 * 1024, 7)`。

而且 `node` 的 stderr 在**第 11 个**监听器时就已经喊了：

```
(node:13544) MaxListenersExceededWarning: Possible EventEmitter memory leak detected.
11 paid listeners added to [EventEmitter]. MaxListeners is 10.
```

只看 `/health` 数字、不看 stderr 的人会漏掉这条最直接的信号（`/health` 里的 `maxListeners: 10` 也在那儿摆着）。

**为什么偏偏只有 `ok` 错？** 因为 `e400/e409/e500/e504` 都在请求层自增（`service.js:103-109`），只有 `ok++` 躲在监听器里。这个不对称本身就是指向根因的路标。

---

## 2. 代码坐标（逐行）

```js
// service.js:52-58  ← 根因 A：检查与扣减跨 await
  const remain = stock[sku];          // 52  快照
  if (remain === undefined) throw ...
  if (remain <= 0) throw mkErr(409, 'E_NO_STOCK');   // 54 拿旧快照做判断（且没比较 qty）
  await sleep(3);                     // 57  让出事件循环 → 所有并发请求都带着同一份旧快照通过检查
  stock[sku] = stock[sku] - qty;      // 58  无条件扣减 → 丢失更新

// service.js:58 vs 62/67  ← 结构性缺陷 D
  stock[sku] = stock[sku] - qty;      // 58  先扣库存
  const ctx = Buffer.alloc(64 * 1024, 7);   // 61  先分配 64KB
  audit.on('paid', () => {...});      // 62  先注册监听器
  await dbReserve(sku, qty);          // 67  可能抛 ETIMEDOUT —— 上面三件事全部不回滚

// service.js:61-65 + 68  ← 根因 B
  const ctx = Buffer.alloc(64 * 1024, 7);   // 61  每请求 64KB，被闭包永久持有
  audit.on('paid', () => {            // 62  每请求注册，全文件无 off / removeListener / removeAllListeners
    stats.ok++;                       // 63  emit 一次，历史所有监听器各加一次
    auditTrail.push(ctx.length);      // 64  同样被放大
  });
  audit.emit('paid', sku);            // 68  扇出到全部存量监听器

// service.js:18-19 / 36 / 41-48  ← 根因 C
const DB_CLIENT_TIMEOUT_MS = 200;     // 18  客户端上限
const DB_SLOW_QUERY_MS = 300;         // 19  SKU_B 实际耗时
const cost = sku === 'SKU_B' ? DB_SLOW_QUERY_MS : 40;  // 36
const guard = sleep(DB_CLIENT_TIMEOUT_MS).then(() => { // 41  200ms 必先到
  if (!finished) { ... throw ETIMEDOUT }               // 42-46  此时 finished 仍为 false
});
await Promise.race([work, guard]);    // 48  确定性失败，与负载无关
```

`grep` 全文确认：`audit.on` 出现 1 次（62），`audit.off` / `removeListener` / `removeAllListeners` / `setMaxListeners` **出现 0 次**；`stats.ok++` 出现 1 次，在监听器内部（63）。

---

## 3. 分头修为什么一定失败（这是"一个还是几个"的真正答案）

| 只修 | 症状 1 库存 | 症状 2 504 | 症状 3 内存/计数 |
|---|---|---|---|
| **A**（原子扣减） | ✅ 不超卖了 | ❌ 照旧 504 | ❌ |
| **B**（监听器） | ❌ 照旧 −9 | ❌ | ✅ 两个出口一起好（**必须同一人**） |
| **C**（调大 timeout） | ❌ **反而更糟** | ✅ | ❌ |
| **A+B+C**（漏 D） | ⚠️ 并发不超卖了，但 504/失败订单仍扣库存，账面对不上 | ✅ | ✅ |

关键的三处交叉污染，都是 D 造成的：

1. **SKU_B 的 504 虽然一单没成功，却把库存吃掉了。** 实测：`node load.js 16 45 SKU_B` → `{"504":45}`、`ok:0`，而 `stock.SKU_B` 从 40 变成 **−5**。零成功的 45 个请求卖了 45 件。负责"库存"的人如果只盯 SKU_C，永远查不到这条泄漏。
2. **失败的请求照样漏监听器。** 单发一个 SKU_B（504）就让 `auditListeners` 从 16 涨到 17——因为 `audit.on`（62）在 `dbReserve`（67）之前。它们不放大 `ok`（`emit` 没执行），但内存照漏。负责"内存"的人如果只在 SKU_A 上压测，会低估泄漏面。
3. **修好 C 的那天，是库存最糟的一天。** SKU_B 一能下单，40 件库存立刻加入 A 的竞态大军，超卖从 SKU_C 扩散到 SKU_B；如果有人用"加 retry"来治 504，超时重试还会**重复扣减**（因为 D 没有幂等和补偿）。

所以正确的分工不是"一人一件"，而是：**D 先修（顺序与补偿），然后 A / C 各一人，B 的内存+计数一个人包掉。**

---

## 4. 修复建议与各自验收标准

### D（先修，前置）：把副作用挪到可失败操作之后，或失败时补偿

```js
async function handlePay(sku, qty) {
  // 1) 原子段：读-判-扣，同一 tick，不跨任何 await
  const remain = stock[sku];
  if (remain === undefined) throw mkErr(400, 'E_NO_SKU');
  if (remain < qty) throw mkErr(409, 'E_NO_STOCK');   // 注意用 < qty，不是 <= 0
  stock[sku] = remain - qty;

  try {
    await dbReserve(sku, qty);        // 2) 失败必须回滚
  } catch (e) {
    stock[sku] += qty;                // 补偿：单线程下安全（中间无 await）
    throw e;
  }
  // 3) 落账/审计放在成功之后，且不每请求注册监听器
  stats.ok++;
  return { sku, taken: qty, remain: stock[sku] };
}
```

验收：SKU_B 压测 45 单若仍返回 504，库存必须**保持 40 不变**。

### A：并发正确性

验收：`node load.js 16 32 SKU_C` → 7 个 200 + 25 个 409，`stock.SKU_C === 0`。再加 `qty` 用例：`stock=2` 时 `qty=5` 必须 409。

### B：监听器与计数

如果审计总线确实需要，**在模块初始化时注册一次**，绝不每请求注册；并去掉每请求 64KB 的 `ctx`（或改成小记录 + 容量上限）。

验收：`auditListeners` 恒为 0 或 1；`stats.ok` 严格等于 200 响应数；`rss` 不随请求数线性增长；stderr 无 `MaxListenersExceededWarning`。

### C：超时预算

`DB_CLIENT_TIMEOUT_MS` 必须**大于最慢查询**（300），例如 800，并改成可配；或者让 reserve 支持取消 + 超时后走 D 的补偿路径。注意：题面把 `DB_SLOW_QUERY_MS` 注释成"实际耗时更长"，说明是**客户端预算配错**，不是"查询需要优化"——压测时 p50 实测 218ms，正好卡在 200 上面一点，是典型"预算贴着实际耗时"的配置。

验收：`POST /pay?sku=SKU_B&qty=1` 返回 200，`e504 === 0`。

---

## 5. 复现命令（端口 19108）

```powershell
cd D:\DeepSeek-levelup\lab-t6
$env:PORT='19108'; node service.js     # 另开窗口/后台

# 症状1：7 件卖 16 单
$env:PORT='19108'; node load.js 16 32 SKU_C
# → byStatus {"200":16,"409":16}  stock.SKU_C = -9  stats.ok=256  listeners=16  rss 48→51

# 对照：串行就正常
$env:PORT='19108'; node load.js 1 10 SKU_C
# → {"200":7,"409":3}  stock.SKU_C = 0  stats.ok=28  listeners=7

# 症状3放大：内存 48→86，ok 放大 263 倍
$env:PORT='19108'; node load.js 16 512 SKU_A
# → {"200":503,"409":9}  stats.ok=132450  listeners=503  rss=86  (stderr 有 MaxListenersExceededWarning)

# 症状2 + D：45 单全 504，库存却被吃掉 45 件
$env:PORT='19108'; node load.js 16 45 SKU_B
# → {"504":45}  ok=0  stock.SKU_B = -5  listeners=45
```

（探针版本：本目录 `probe-svc.js`，与原文件唯一差别是把每次 qty 检查读到的 `remain` 暴露在 `/health.reads`。实验结束后已停掉我起的 node 进程，端口 19108 已关闭。）

---

## 6. 一个会误导对账的小坑

`stats.total++` 在路由分派**之前**（`service.js:80`），所以 `/health` 请求也被计入。实测 32 个下单请求 + 3 次 `/health` = `total: 35`，而 `ok + e400 + e409 + e500 + e504` 永远对不上 `total`。团队在"对账吵库存"的时候，如果拿 `total` 当分母，会凭空多出几笔"来路不明的请求"，这是在真 Bug 上再叠一层假线索。修 B 的时候顺手把这个计数口径也理一下。

---

## 7. 最终判定

- **根源是一个还是几个？3 个独立根因 + 1 个结构性缺陷。**
  - **A 并发竞态**（`service.js:52-58`）：解释症状 1；
  - **C 超时预算 200ms < 300ms**（`service.js:18-19/36/41-48`）：解释症状 2，单请求可复现，与并发无关；
  - **B 审计监听器只加不减**（`service.js:61-65/68`）：**同时**解释症状 3 的内存增长和计数放大——这两个是同一个 Bug，拆给两个人修必然撞车；
  - **D 副作用前置且无补偿**（`service.js:58/62` 早于 `67`）：本身不产生症状，但让 C 的失败去污染 A 的库存、让所有失败路径去污染 B 的泄漏。
- **所以"分头去修自己那摊"可以，但边界必须重划**：D 是公共前置，B 的两半归一个人，A 和 C 才是两个真正独立的活。按"三个症状三个人"分，三个人会各自交出一份"自测通过"的补丁，合起来库存依然错——而且修好 504 的那天，超卖会从 SKU_C 扩散到 SKU_B。

[技能] none
