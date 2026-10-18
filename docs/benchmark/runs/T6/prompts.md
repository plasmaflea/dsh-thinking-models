# T6 · 三真根并列（带注入真值）· 题面与环境

## 题面（A / B 两组逐字相同）

> 我们内部的一个订单服务，压测时同时出了三件事，团队已经吵起来了：
> 1. 库存对不上——总共才 7 件的 SKU_C，压测跑完卖了 16 单，库存变成 -9。
> 2. 有一个 SKU 的订单全部失败，返回 504；换成别的 SKU 就正常。
> 3. 进程内存一路涨（48MB → 89MB），而且 `/health` 里的成功计数比实际成功请求数大了一个数量级。
> 三个人各自认领一件，说要分头去修自己那摊。你怎么定位？根源到底是一个还是几个？
>
> 代码在 `D:\DeepSeek-levelup\lab-t6`（`service.js` + `load.js`），可以读、可以起服务、可以自己压测。

环境说明另附：每个 agent 独占一个端口（A 组 19100–19104，B 组 19105–19109），可自行起服务、压测，跑完须停进程。

## 实验环境（源码见 `lab/`）

`lab/service.js` 是单文件 Node 服务（`/pay?sku=&qty=`、`/health`），三个真根由作者手工注入；`lab/load.js` 是压测器（并发数 / 总请求数 / SKU / 延迟分位 / 状态码分布）。

启动：`node service.js`（默认 19090，可用 `PORT` 覆盖）；压测：`node load.js 16 32 SKU_C`。

## 三个真根（作者注入，可执行复现）

| id | 真根 | 关键代码 | 复现 |
|---|---|---|---|
| R1 | 查库存与扣减之间跨 `await`，读-改-写非原子 | `const remain = stock[sku]` → `await sleep(3)` → `stock[sku] = stock[sku] - qty` | 并发 16 卖 SKU_C 16 单 → `stock.SKU_C = -9`；并发 1 → 7 单、剩 0 |
| R2 | DB 客户端超时 200ms < SKU_B 查询耗时 300ms；且扣减发生在预留之前、失败不回滚 | `DB_CLIENT_TIMEOUT_MS = 200` / `DB_SLOW_QUERY_MS = 300` / `dbReserve` 的 `Promise.race` | SKU_B 串行单发也 504；32 单全 504 却让库存 40→8 |
| R3 | 每请求 `audit.on('paid', …)` 从不移除，且闭包持有 64KB Buffer | `handlePay` 中段 | 320 成功请求 → `auditListeners=320`、`rss 48→74MB`、`stats.ok=54480`（170×） |

三者互不覆盖：修好任一个，另两个的症状仍在（A/B 两组各自都用单点补丁/反事实分支验证过）。

## 已知混杂

- 同一作者出题、同一模型作答、同一台机器；作者非盲。
- 代码可读 ⇒ 本题测的不是"发现难度"，而是**发现之后怎么组织**（并列 / 合并 / 类根 / 排序）。
- 题面已列出三条症状，agent 不必自己发现症状。
- A 组跑时技能与 AGENTS.md 均在位；B 组跑时通过 `scripts\bench-before.cmd` 停用四个思考类技能并撤走 AGENTS.md。
- **B 组第一版作废**：当时题面里留了一句"技能目录内自带的 `tree/` 可以读"，且只关掉了目录可见性、没禁读安装位，导致一份作答直接读了磁盘上的 `SKILL.md` 并照其流程产出。该份留档于 `outputs/B-contaminated-agent-b.md`，不进主表。重跑版题面已删除该句，并把 `C:\Users\Administrator\.dsh\skills` 加入禁读清单。
