# lab-t6：三个现象一次定位 —— 是 3 个根因，但只有 2 个人该上，另外还有第 4 个没人认领的缺陷

## 0. 先给结论

- **三个现象 = 3 个独立根因**，分别落在三个不同的层：并发控制（`handlePay` 的 check-then-act 窗口）、超时常量配置（200ms 客户端上限 vs 300ms 慢查询）、资源生命周期（进程级 `EventEmitter` 上按请求注册、永不摘除的监听器）。
- 但**只对应两个"修复人"**：现象 3 的"内存涨"和"成功计数虚高"是**同一个根因**（监听器累积）的两个输出通道，谁要把它俩分给两个人，这两个人会各自改一半、互相打架。
- **还有第 4 个缺陷，三个人都没认领**：`handlePay` 把"扣库存"和"注册监听器"这两个不可逆副作用，都放在唯一可能失败的 `await dbReserve()` **之前**，且失败后不回滚。它横跨现象 1 和现象 2 —— 504 的订单照样扣库存、照样漏监听器。这条不修，修 S1 的人会以为自己控制住了库存，修 S2 的人会把 504 当成"纯丢单"。
- 所以答案不是"一个大 bug 的三个表现"，也不是"三件各修各的事"，而是：**3 个根因 + 1 个共同的代码形态（先改状态、再 await 可能失败、失败不补偿），且有 1 个根因吃掉两个症状**。

---

## 1. 我怎么定位（分诊第一刀）

不要先猜，先做**一刀切分**：把每个现象单发（并发=1、共 1 个请求）跑一遍。

| 单发结果 | 说明 | 指向 |
|---|---|---|
| 单发就复现 | 与并发、与负载无关 | 常量/配置/数据问题 |
| 只有高并发复现 | 时间窗口问题 | 竞态 |
| 与请求数正相关地单调累积，重启才归零 | 进程内状态没被回收 | 资源生命周期 |

这一刀下去三个现象立刻分到三个框里，而且**不需要改代码、不需要日志、不需要断点**——因为 `service.js:82-92` 的 `/health` 已经把内部状态全暴露了（`stock` / `stats` / `auditListeners` / `auditTrailLen` / `rssMb` / `dbClientTimeoutMs`）。定位靠**差分**，不靠猜：

```
[health fresh]      SKU_C=7  SKU_B=40 SKU_A=500 | ok=0      listeners=0   trailLen=0      rssMb=48
[health after SKU_C]SKU_C=-9 SKU_B=40 SKU_A=500 | ok=256    listeners=16  trailLen=256    rssMb=51
[health after 1xA]  SKU_C=-9 SKU_B=40 SKU_A=499 | ok=273    listeners=17  trailLen=273    rssMb=51
[health after 1xB]  SKU_C=-9 SKU_B=39 SKU_A=499 | ok=273    listeners=18  trailLen=273    rssMb=51
[health after 16xB] SKU_C=-9 SKU_B=23 SKU_A=499 | ok=273    listeners=34  trailLen=273    rssMb=52
[health after 320]  SKU_C=-9 SKU_B=23 SKU_A=179 | ok=75025  listeners=354 trailLen=75025  rssMb=77
[health after 320]  SKU_C=-9 SKU_B=23 SKU_A=-6  | ok=163803 listeners=539 trailLen=163803 rssMb=93
```

---

## 2. 现象 1：超卖 7 件卖 16 单，库存 -9

**代码**（`D:\DeepSeek-levelup\lab-t6\service.js:52-58`）：

```js
const remain = stock[sku];
if (remain === undefined) throw mkErr(400, 'E_NO_SKU');
if (remain <= 0) throw mkErr(409, 'E_NO_STOCK');
await sleep(3);                     // ← 检查与扣减之间让出事件循环
stock[sku] = stock[sku] - qty;      // ← 扣的是"当前值"，不再复查 remain
```

**实验**（并发 16 / 共 16 / SKU_C）：`byStatus={"200":16}`、`byCode={"OK":16}`，库存 `7 → -9`，`e409=0`。p50=73ms。

**判定**：
- 这是典型的 **check-then-act 竞态**，而且**不是丢更新**：16 次扣减一次没丢（7-16=-9 精确成立），丢的是"检查的有效性"。
- 窗口宽度 = `await sleep(3)` 的 3ms。所有在飞的 16 个请求都在这 3ms 内读到同一份**过期快照** `remain=7`，全部通过 `remain <= 0` 的检查，然后各自对**当前值**扣 1。
- 因为 `remain` 是局部变量、扣减时用的是 `stock[sku]`（已变负），所以库存穿过 0 之后，窗口内的请求仍然继续扣 —— 负数不是"少扣了"，是"该拒绝的没拒绝"。
- 复核（第二次 320 请求、SKU_A 剩 179、并发 64）：`200×185 + 409×135`，库存 `179 → -6`。超卖量 ≈ 穿过 0 那一刻的在飞请求数，与并发度同阶 —— 这条"超卖量与并发度同阶"是竞态的指纹，而不是"某处算错"。

**修复方向**：把"读-判-扣"压成不可被 `await` 打断的同步段（`const left = stock[sku] - qty; if (left < 0) throw 409; stock[sku] = left;`），或改预占/确认两段式、或单飞串行化。同时把扣减挪到 `dbReserve` 成功之后（见第 5 节）。

---

## 3. 现象 2：某 SKU 全 504，换 SKU 就正常

**代码**（`service.js:18-19`、`:36`、`:41-48`）：

```js
const DB_CLIENT_TIMEOUT_MS = 200; // 客户端等待上限
const DB_SLOW_QUERY_MS = 300;     // SKU_B 需要一次 join，实际耗时更长
...
const cost = sku === 'SKU_B' ? DB_SLOW_QUERY_MS : 40;
await Promise.race([work, guard]);   // guard 在 200ms 抛 ETIMEDOUT
```

**实验**：
- **并发 1 / 共 1 / SKU_B**：`504 × 1`，延迟 219ms。→ **单发就挂，跟负载毫无关系**。
- 并发 16 / 共 16 / SKU_B：`504 × 16`，`E_DB_TIMEOUT`，延迟 217–227ms。
- 同并发 SKU_A：全 200，p50 47–61ms。

**判定**：这不是"某个 SKU 的数据坏了"，是**两个常量打架**：`cost(300ms) > guard(200ms)` 恒成立 → SKU_B 100% 超时，是**确定性配置缺陷**，并发 1 就能证伪"压测才有的问题"。`elapsedMs≈220ms` 也正好卡在 guard 的 200ms 上，而不是服务端算得慢。

顺带两个排障陷阱，要提前排掉：
1. `Promise.race` 之后**没有取消机制**：guard 抛错时 `work` 还在跑，300ms 后才结束 `finished=true`。这个"后台还在跑"的悬空 promise 很容易被误判为"泄漏/卡死"。
2. 超时被当成"请求失败"直接返 504，但**扣减已经发生了**（下面第 5 节）。

---

## 4. 现象 3：内存 48→89、成功计数大一个数量级（同一根因）

**代码**（`service.js:60-68`）：

```js
const ctx = Buffer.alloc(64 * 1024, 7);   // 每请求 64KB
audit.on('paid', () => {                  // ← on，不是 once；永不摘除
  stats.ok++;                             // ← 每次 emit 里自增，不是"每成功请求 +1"
  auditTrail.push(ctx.length);            // ← 闭包捕获 ctx，且每次 emit push 一条
});
await dbReserve(sku, qty);
audit.emit('paid', sku);                  // 一次 emit 触发"历史上所有"监听器
```

三个输出通道，一个根因：

1. **监听器累积**：每次请求 `audit.on(...)`，从不 `removeListener`/`off`。`audit` 是模块级 `EventEmitter`（`service.js:15`），进程活多久就存多久。实验里 listeners 单调增长：0 → 16 → 17 → 18 → 34 → 354 → 539。
2. **计数虚高**：`stats.ok++` 在监听器内部，而一次 `emit` 会调用**全部**已注册监听器 → 每个真实成功请求给 `ok` 加的是 `listenerCount`，不是 1。**决定性证据**：在已有 16 个监听器时，**单发一个** SKU_A 成功请求，`ok` 从 256 → **273（+17）**；如果是"一次成功 +1"，应该是 257。加 17 只能是"16 个旧监听器 + 本次新注册的 1 个，一起被这一次 emit 触发"。
   - 所以 `ok` 是 O(n²) 而不是 O(n)：16 个请求 → `ok=256`（16×16，虚高 16 倍）；到 320 请求后累计真实成功 337 个而 `ok=75025`（223 倍）；全流程真实成功 522 个而 `ok=163803`（**313.8 倍**）。题面说"大了一个数量级"是保守估计，实际是**随请求数二次增长**，压测越久越离谱。
   - 交叉验证：`auditTrailLen` 与 `stats.ok` 在**每一个**快照里都恒等（256/256、273/273、75025/75025、163803/163803）——两个计数出自同一个监听器，这也顺手证明了 `auditTrail` 同样在按"每次 emit push L 条"二次膨胀。
3. **内存**：每个监听器的闭包捕获 `ctx`（64KB `Buffer`），只要监听器挂在 `audit` 上，这块内存就不可回收。539 个监听器 × 65536B ≈ **35.3MB**，实测 rss 48→93MB（题面 48→89）。另外 `auditTrail` 有 16 万条数字（约 1.3MB），加上 `EventEmitter` 内部节点/闭包开销，量级对得上。

**早就亮着的红灯**：第 11 个请求时 stderr 就有
`(node:17440) MaxListenersExceededWarning: Possible EventEmitter memory leak detected. 11 paid listeners added to [EventEmitter]. MaxListeners is 10.`
—— 这条告警是免费的，压测时没人看 stderr。

**修复方向**：`audit.once` 或请求结束 `off`；`stats.ok++` 挪出监听器（直接写在 `handlePay` 成功返回处）；`ctx` 不要进闭包（或干脆删掉这段"审计"）；`auditTrail` 用计数器代替 `push`。

---

## 5. 第 4 个缺陷：没人认领，但横跨现象 1 和现象 2

`handlePay` 的顺序是：**扣库存 → 注册监听器 → `await dbReserve()`（唯一会失败的地方）→ emit**。失败路径没有任何补偿。

**证据**（单发 SKU_B，返回 504）：

```
[health after 1xB]  SKU_B=39   ← 请求失败了，但库存少了 1 件
                    listeners=18  ← 失败的请求也留了一个监听器
[health after 16xB] SKU_B=23   ← 16 次全 504，库存少了 17 件（1+16）
```

**判定**：这是**"副作用先于确认"**的经典错误，它有两个后果：
- **504 的单子照样扣库存**：真实业务里就是"钱没收、货没了"。这部分虚耗不会出现在负数里，只能靠对账发现 —— 如果只盯 `-9` 那单，就会漏掉它。
- **失败的请求也在漏监听器**（18→34），所以现象 3 的膨胀速度比"成功数"更快，`ok` 的分子分母用的根本不是同一批请求。

**这才是三个人真正该吵的点**：现象 1 说"并发没控住"，现象 2 说"超时太短"，两边各自修完，库存仍然会因为 504 而慢慢漏。

---

## 6. 所以：一个还是几个？

| 现象 | 根因 | 所在层 | 与其它现象的关系 | 独立性证明 |
|---|---|---|---|---|
| 库存 -9 | `service.js:52-58` check-then-act 窗口（`await sleep(3)` 后不复查） | 并发控制 | 被第 4 个缺陷放大 | 并发 1 不复现、并发 16 复现；超卖量与并发度同阶 |
| SKU_B 全 504 | `service.js:18-19` 200ms 客户端上限 < 300ms 慢查询 | 常量/配置 | 与并发无关、与库存无关 | **并发 1 单发就 504**（219ms），这直接排除竞态与负载 |
| 内存 48→93 | `service.js:62` 每请求 `audit.on` 永不摘除 + 闭包持有 64KB | 资源生命周期 | — | rss 与 `listeners` 线性相关（539×64KB≈35MB） |
| 计数 163803 | 同一个监听器里的 `stats.ok++` | 资源生命周期 | **与上一条同根因** | 单发成功 +17（当 17 个监听器）；`trailLen ≡ ok` |
| 504 仍扣库存 | 副作用先于确认、失败不补偿 | 事务边界 | 横跨现象 1、2 | 504 后库存 40→39 |

**结论**：
- **不是 1 个根因**。现象 2 用"并发=1 单发即 504"就能和竞态彻底切干净；现象 1 的窗口和现象 3 的生命周期问题也没有因果链。
- **也不是 3 件独立的事**：4 个现象只对应 3 个根因（内存与计数同根），而这 3 个根因共享**同一个代码形态**——`handlePay` 里"先改状态 → 再 `await` 可能失败的操作 → 失败不补偿"。共同的处方是：**把不可逆副作用放到确认之后（或补上补偿/幂等）**，这一刀能同时收窄现象 1 的窗口、消掉现象 2 的库存污染；但它**不消除**现象 1（原子性还得单独做），也**治不了**现象 2 的常量。
- **分头上人的正确切法**：2 个人。一个管"扣减与事务边界"（原子扣减 + 失败回滚 + 幂等，S1+S4 一起），一个管"监听器与计数"（S3 内存与计数一起）。若按题面的 3 人分，修 S1 的人修完看不见 S2 的库存污染，修"计数"的人把 `ok++` 挪出来后内存仍然涨（因为监听器还在），两个人会互相证明对方没修好。

---

## 7. 最小修复清单（按依赖顺序）

1. **事务边界**（先做，成本最低、影响最大）：`await dbReserve()` 成功之后才扣库存、才注册监听器；失败路径不产生任何持久副作用；引入 `orderId` 幂等键，避免"超时=未知结果"被当成"失败"重复扣减（超时是未知，不是失败）。
2. **原子扣减**：`const left = stock[sku] - qty; if (left < 0) throw mkErr(409,'E_NO_STOCK'); stock[sku] = left;`，中间不许有 `await`；对同一 SKU 的扣减串行化（单飞/队列/CAS）。
3. **超时语义**：让 `DB_CLIENT_TIMEOUT_MS > DB_SLOW_QUERY_MS`，或给慢查询单独预算/异步化；guard 抛错后要能取消 work（`AbortController`），别留悬空 promise。
4. **监听器生命周期**：`audit.once(...)` 或 `finally { audit.off(...) }`；`stats.ok++` 移出监听器；`ctx` 不进闭包；`auditTrail` 改计数器。或直接删掉 `EventEmitter` 这层"审计"——它对业务没有任何作用。
5. **告警治理**：`MaxListenersExceededWarning` 应当直接让压测失败（`--throw-deprecation` / 监控 stderr），这类问题是唯一会自己喊出来的。
6. **回归用例**（把今天这四条钉死）：
   - 并发 ≥ 库存数时压完，`stock >= 0` 且 `成功数 + 409 数 == 请求数`，一份不多一份不少；
   - 单发 SKU_B 在 SLA 内成功（不再 504）；
   - 连打 1000 个请求，`auditListeners` 与 `rssMb` 不随请求数增长；
   - `stats.ok == 真实 2xx 响应数`（严格相等，不是"大概"）。

---

## 8. 一句话回答

三个现象是三个不同层的独立缺陷，其中"内存涨"和"计数虚高"其实是同一个根因（`audit` 上按请求注册、永不摘除的监听器），而三个人都没注意到第 4 个缺陷——504 的失败请求同样扣库存、同样漏监听器，它才是让库存对不上这件事最难查的那一半。判定只靠一招：**先单发（并发=1）再做差分**，单发就复现的归配置，只有高并发复现的归竞态，单调累积的归生命周期。

---

## 附录：实验原始记录（端口 19109，一次性脚本内起停服务）

```
EXPERIMENT 1  SKU_C  conc=16 total=16
  byStatus={"200":16}  byCode={"OK":16}  latency p50=73 p90=74 max=74
  stock.SKU_C: 7 -> -9      stats.ok: 0 -> 256 (真实成功 16)   listeners: 0 -> 16   trailLen 256   rss 48 -> 51

EXPERIMENT 2  SKU_A  conc=1  total=1     (此时已有 16 个监听器)
  byStatus={"200":1}   latency p50=62
  stats.ok: 256 -> 273  (+17 = 16 旧监听器 + 1 新注册)        listeners: 16 -> 17  trailLen 273

EXPERIMENT 3a SKU_B  conc=1  total=1
  byStatus={"504":1}   byCode={"E_DB_TIMEOUT":1}  latency 219ms
  stock.SKU_B: 40 -> 39   (失败但已扣)   stats.ok 不变(未 emit)  listeners: 17 -> 18

EXPERIMENT 3b SKU_B  conc=16 total=16
  byStatus={"504":16}  latency p50=217
  stock.SKU_B: 40 -> 23   (16 次全失败，共扣 17)   e504=17   listeners: 18 -> 34

EXPERIMENT 4a SKU_A  conc=64 total=320
  byStatus={"200":320}  latency p50=61 p90=76 p99=80 max=81
  stock.SKU_A: 500-1 -> 179      stats.ok: 273 -> 75025 (累计真实成功 337)  listeners 354  rss 77

EXPERIMENT 4b SKU_A  conc=64 total=320
  byStatus={"200":185,"409":135}   latency p50=47 p90=76
  stock.SKU_A: 179 -> -6 (超卖 6)  stats.ok: 75025 -> 163803 (累计真实成功 522 → 313.8x)
  listeners 539  trailLen 163803  rss 93

服务端 stderr:
  (node:12572) MaxListenersExceededWarning: Possible EventEmitter memory leak detected. 11 paid listeners added to [EventEmitter]. MaxListeners is 10.
```

实验完毕后已 `Stop-Process` 停掉自己起的服务（pid 12572），`Get-NetTCPConnection -LocalPort 19109` 已无监听。

[技能] none
