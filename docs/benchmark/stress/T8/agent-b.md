# 容器"没吃内存却被 OOMKilled"的类根回溯

[🌳 林状图] [选择理由] 题面问的是"根源在哪"，且现象自带三个硬约束（无进程占内存 / 曲线平 / 故障随 pod 迁移而不随机器），属**因果深度**问题而非选项广度问题；按模式表命中回溯法。回溯的根不落在"这次是哪台机的哪个 pod"，而落在"这一整类为什么可能在结构上发生"。

---

## L0 类别判定

**类别 = `software` 的 `quota`（资源配额）子层，兼 `lifecycle`（退出码归因）。**
判据（必须同时满足）：① 可复现性来自环境姿态而非物理介质——同一镜像在 40 台机器上表现不同，只在某种节点姿态下才越线；② 失败由确定性竞争导致——阈值 + 时序触发，不是位翻转。
**已排除的大类**：硬件故障（症状随 pod 迁移而不随机器，重启即恢复，无 MCE/EDAC/CRC 症状族）；网络问题（无超时/连接重置症状族，但"内核 socket 缓冲"作为**记账科目**保留在本树内，见 1.4）；权限/账号（无拒绝访问、无服务账户特有失败）；组织流程（纯技术阈值现象，人的决策未参与）。

## L1 树实例化

`树 = software/quota（主）+ software/lifecycle（次） · v1 · 核查 2026-10-18 · 路径 C:\Users\Administrator\.dsh\skills\forest-hierarchical-backtracking\tree\software.md`
（索引路径：`C:\Users\Administrator\.dsh\skills\forest-hierarchical-backtracking\tree\index.md`，同为 v1 · 核查 2026-10-18）

本次判为**不适用**的节点：`software/dependency`（无缺失/版本/符号类错误码族）、`software/init`（不是死在日志第一行之前，是稳定运行数天后被杀）。
本次命中的树内类根原话："某个本该由应用掌握的控制权，被外部机制代持——生命周期、配额、依赖解析、启动顺序，其中任何一项被代持，失败就会发生在应用能打日志之前，于是表现为『无堆栈、无输出』。" 本题正是 **配额被代持**那一支的实例。

## L2 逐层回溯

**轴（生成式，非列举）**：恒等式展开。OOMKill 事件的恒等式是

```
OOMKilled  ⟺  ①某实体把内存记到"这个 cgroup"账上
             ∧ ②该账本达到/将达上限
             ∧ ③回收在当时的分配速率下失败
             ∧ ④内核选中它当牺牲品
```

四个因子**必然存在**（任何一个不发生，就没有 OOMKill 这个词），且互相正交（各有专属症状）。边语法：`1→2→3→4` 全部是**必要条件**链，四层同时成立构成 OOMKill 的**充分条件**。

### 层1 账本归属：谁的内存被记到这个容器名下

| 格 | 内容 | 该格故障的可观测症状 |
|---|---|---|
| 1.1 | 容器主进程 anon（heap/stack/mmap） | 进程 RSS 阶梯上涨，top/APM 可见。**本题判定为空** |
| 1.2 | 容器的 **file page cache**（镜像层、日志、数据文件；含脏页） | `memory.stat` 的 `file`/`dirty` 上涨；`container_memory_usage_bytes` 贴着 limit，而 `container_memory_rss` 与 working_set 平；OOM 时刻与写盘时段对齐 |
| 1.3 | **shmem / tmpfs**（`/dev/shm`、`emptyDir{medium:Memory}`、`/tmp` 挂 tmpfs） | `memory.stat.shmem` 单调涨；`df /dev/shm` 或目标目录 `du` 在涨而进程 RSS 不动；重启清零后从零再爬 3–5 天 |
| 1.4 | **kmem**（socket 收发缓冲、slab/dentry/inode、page table） | `memory.kmem.usage_in_bytes`/`slab` 涨；与连接数、并发、打开文件数强相关；短连接风暴或连接泄漏 |
| 1.5 | **别的 cgroup**（同节点邻居吃满节点内存，内核全局 OOM 挑了这个 pod） | 被杀 cgroup 自己远低于 limit；dmesg 是 `Out of memory: Killed process` 且**没有** `Memory cgroup out of memory`；`node_memory_MemAvailable` 掉 |

**全空列判据的实际应用**：1.1 格判空，而问题仍在 ⇒ 直觉坐标系（"进程内存"）被证伪，必须换到恒等式轴重切——这正是本题的分岔点。而 1.2/1.3/1.4 的共同特征是**它们都不在进程地址空间里**，这解释了"查不到任何一个进程"。

### 层2 达限判定：这个账本被谁判成超了

| 格 | 内容 | 症状 |
|---|---|---|
| 2.1 | limit 按 **anon** 估出来，账本里还有 cache/shmem/kmem | limit 恒定；OOM 时 `usage_in_bytes` 恰等于 limit；可算出科目占比 |
| 2.2 | request/limit 失衡 + 节点超卖（Burstable，limit 之和 > 物理内存） | 节点 limit 汇总超物理；故障率与同节点 pod 数相关 |
| 2.3 | **采样窗口 vs 事件时刻**（15s/30s 抓点抓不到毫秒级 burst） | OOM 时刻曲线上无峰；但 `memory.max_usage_in_bytes`（历史峰值）显著高于所有采样点——**这是"曲线很平"的技术原因之一，且一个计数器即可证伪** |
| 2.4 | 记账口径版本差（v1 `usage_in_bytes` / v2 `memory.current` 含 cache 与 kmem；你画的 working_set 减掉了 `inactive_file`） | 两条曲线差一个量级，差值 ≈ 页缓存 |

### 层3 回收失败：为什么缓存没被回收掉、直接杀

| 格 | 内容 | 症状 |
|---|---|---|
| 3.1 | **脏页写回跟不上**（慢盘/NFS/网络存储、`dirty_ratio`、writeback 拥塞） | `dirty`、`writeback`、`iowait` 同时偏高；OOM 与写盘时段对齐；**"换机器就换地方"= 换掉的是盘与存储路径的延迟** |
| 3.2 | **shmem 不可回收**（无 swap 或 `memory.swap.max=0`） | `shmem` 涨而 `swap` 恒 0；这是 cgroup 内**唯一无法驱逐**的记账项 |
| 3.3 | kmem 不可回收（slab 不可回收部分、socket 缓冲） | `slab_unreclaimable` 涨 |
| 3.4 | **分配速率 > 回收速率**（突发大 alloc / fork / 大 buffer） | `memory.events` 的 `high`/`max` 计数突增，OOM 前无渐进斜率 |
| 3.5 | 节点无 swap + 全局回收压力（cgroup 内回收先失败） | `pgscan`/`pgsteal` 飙升但 free 不回升 |

### 层4 牺牲品选择：为什么是这个 pod、这台机

| 格 | 内容 | 症状 |
|---|---|---|
| 4.1 | cgroup OOM killer 选容器内 `oom_score` 最高者（通常是主进程） | 被杀的是主进程，重启立即正常 |
| 4.2 | 节点全局 OOM 按 `oom_score_adj` 选（Burstable/BestEffort 先死） | 被杀 pod 自报内存很小——**"它没吃内存却被杀"的表象在这格得到最省事的解释** |
| 4.3 | 归因误标（137 来自 liveness SIGKILL / 驱逐 / preStop 超时） | `describe` 的 Reason 与 LastState 不一致；`memory.events.oom_kill` 计数为 **0**。一个计数器即可排除 |

### → 类根

**这个容器的"内存"被两套口径分别持有：裁决口径是 cgroup 账本（含内核代持的 file cache / shmem / kmem），观测口径是进程 RSS 与 working_set（不含这些）。当内核代持的那部分在暗处单调增长、且其中含不可回收科目时，"任何进程都没吃内存"与"容器被判超限"可以同时为真。**

推论（这是本题最硬的一步）：若节点总内存不紧张（否则曲线不会"平"）、进程 RSS 平、且无进程占内存，那么把账本推过 limit 的内存必然**既不在进程地址空间、也不在节点总用量里显眼**——只能是 cgroup 记账项中"按 cgroup 归账、由内核代持"的那部分。三者择一的判据是 limit 与负载形态：limit 小且写日志/读大文件 → 1.2+3.1；limit 小且有共享内存/临时文件 → 1.3+3.2；高并发短连接 → 1.4+3.3。

```
└ 个例根（挂在类根下，需一次现场取证定位到具体科目，按 Share×Lever÷Cost 排序）
   ├ G1 = 1.2+3.1 脏页写回跟不上 → cgroup 账本被不可回收的 dirty page 顶穿（Share 主因）
   ├ G2 = 1.3+3.2 tmpfs/shm 单调累积且无 swap 可换出（Share 主因，且"唯一不可回收"）
   ├ G3 = 1.4+3.3 socket 缓冲/slab 增长（Share 共因）
   └ G4 = 1.5+4.2 同节点邻居造成全局 OOM，本 pod 因 QoS 顺序被挑中（Share 次要）
```

## L3 双根

### 处置根（修本次，1 天内、零架构变更）

1. **现场取证（先做，成本最低、信息量最大）**：OOM 那台机上抓 `cat /sys/fs/cgroup/memory/memory.stat`、`cat .../memory.max_usage_in_bytes`、`dmesg | grep -i oom`（看是 `Memory cgroup out of memory` 还是全局 `Out of memory: Killed process`）、`cat .../memory.oom_control`。这四个命令半天内能把 1.2/1.3/1.4/1.5 收敛到一个。
2. **按"分科目真实峰值"重算 limit**，而不是按 anon 峰值；同时加 20–30% 缓冲，或配 `memory.high` 让超限先变成节流。
3. **把不可回收科目搬出容器账本**：`/dev/shm`、`emptyDir{medium:Memory}`、tmpfs 的 `/tmp` 改磁盘卷并设 sizeLimit；日志/大文件写入改独立卷或直接 I/O，减少本 cgroup 的 dirty 页。

### 消解根（灭这一类）

**让"会被计费的内存"全部经过一个可见、可归因、可回收的出口。** 三件事同时成立才成立：① 计费科目显式化（cgroup v2 + 分科目指标 `file/shmem/slab/sock` 与 limit 同屏）；② 不可回收科目移出容器账本或换介质（shmem→磁盘卷、限 socket 缓冲、`memory.swap.max>0` 兜底）；③ 超限不硬杀（`memory.high` 节流取代硬 OOM，应用得到的是变慢而不是 SIGKILL）。

- **① 不可发生判据**：在该状态下，任何内存增长都必须先在一个与 limit 同屏的科目上出现，且不存在"按 cgroup 归账、不可回收、应用与监控都看不见"的增长路径 ⇒ "查不到谁吃内存却被 OOMKilled"在结构上**不可能发生**（不是变少见）。
- **② 可执行首边**（可以很小）：今天就在 OOM 的机器上把 `memory.stat` 的 `file/shmem/slab/sock` 四项接进同一个面板，并与 `max_usage_in_bytes` 对齐——观测口径一旦并到一个屏幕上，这一类问题就失去藏身处。
- **③ 成本量级**：取证 0.5 人日；分科目指标 1–2 人日；迁 cgroup v2 + `memory.high` + 开 swap 需 1–2 周含压测（数字交给 📐 公式图定量，此处只给量级）。

## L4 迁移出口

消解根指向"改记账口径 + 改介质 + 改超限语义"，必须列迁移问题清单：

1. **运行时与内核**：cgroup v1→v2 的记账语义差异、`memory.high` 节流对 P99 延迟的影响、开 swap 对 IO 与延迟抖动的影响。
2. **数据与介质**：tmpfs/shm → 磁盘卷后的容量、性能、GC 策略；日志与临时文件落点变化。
3. **可观测性**：指标从 RSS/working_set 迁到分科目 + 事件口径；告警阈值重定；OOM 现场自动取证 hook（在 cgroup 被销毁前 dump `memory.stat`）。
4. **配额与调度**：request/limit 重算与超卖策略；QoS class 变化会改变节点驱逐顺序。
5. **组织能力**：值班从 `top`/RSS 改看 `memory.stat`；OOM 复盘模板改问"哪个科目涨的"。

→ **本次问题降级为第 3 项（可观测性口径）下的一个子项**：多租户节点上 cgroup 级内存事件的科目级归因。它不再是一个"神秘故障"，而是这条迁移线上一件有工单、有验收标准的工作。

## 候选根排序（Share × Lever ÷ Cost，预算有限故必须排序）

| 层级 | 候选根 | Share | Lever | Cost | 排序 |
|---|---|---|---|---|---|
| 类根 | 记账口径 ≠ 观测口径（内核代持内存） | 唯一（能同时解释三条约束） | 改配置＋改架构 | 半天取证 | **1** |
| 个例 | G1 脏页写回顶穿账本 | 主因 | 改配置（limit/卷/dirty 参数） | 一次采样 | 2 |
| 个例 | G2 tmpfs/shm 累积、无 swap | 主因 | 改配置（改挂载） | 一次采样 | 3 |
| 个例 | G3 socket/slab 增长 | 共因 | 改配置（连接/缓冲） | 一次采样 | 4 |
| 个例 | G4 邻居全局 OOM + QoS 顺序被杀 | 次要 | 改调度/配额 | 一行 dmesg | 5 |
| 个例 | 4.3 归因误标 | 次要 | 改探针配置 | 一行 `describe` | 6 |
| — | 应用堆泄漏 | 无（被题面排除） | — | — | 挂起 |

Budget 说明：Cost 就是预算。前 6 条**全部是"一次采样/一行命令"级别**，所以排序成立；若某条要"一次迁移"才能证伪，它就只能留在挂起表里等预算，而不是排在前面猜。

## 挂起表（分支 / 判定 / 依据 / 恢复条件）

| 分支 | 判定 | 依据 | 恢复条件 |
|---|---|---|---|
| 1.1 应用堆泄漏（Go 不归还 / JVM 堆） | 非根 | 题面给定"没有任何进程真的吃了内存、RSS 曲线平"；若为它，重启后应按同一斜率复现且 RSS 可见 | `memory.stat.anon` 呈阶梯上涨，或 RSS 峰值与 OOM 时刻对齐 → 立即升为第一候选 |
| 硬件（内存条/ECC/温度） | 非根 | 症状随 pod 迁移而不随机器；重启即恢复；无 MCE/EDAC/CRC | dmesg 出现 MCE/EDAC/CRC；或同镜像换机后故障仍固定原机 |
| 网络问题 | 非根（sock 缓冲作为账本项保留在 1.4） | 无超时/重置症状族，分层可达性可测 | 出现连接超时族、conntrack 表满或 DNS 解析失败 |
| 权限/账号体系 | 非根 | 无拒绝访问、无服务账户特有失败 | 出现 403/Denied、服务账户特有失败 |
| 组织流程 | 非根 | 纯技术阈值现象 | 全部取证为绿仍周期性复发 |
| 树外分支 `k8s/kubelet`（OOMKilled 标注、驱逐策略、QoS 语义） | 树外 · 登记 `v2 候选` | 树 v1 仅 `software`/`win-service` 两节点，无编排层归因语义节点 | 需新增节点：容器编排层的失败归因 |
| 树外分支 `kernel/mm`（cgroup 记账、回收、dirty 写回） | 树外 · 登记 `v2 候选` | 同上 | 需新增节点：内核内存记账与回收 |
| 树外分支 `observability`（观测口径与采样窗口） | 树外 · 登记 `v2 候选` | 同上 | 需新增节点：裁决口径与观测口径错位 |

> 说明：本次回溯的主战场恰好整体落在这三个树外分支上——这说明树需要扩充，而**不是**这些分支不该被考虑。三个节点登记为 `v(N+1) 候选`，理由即上表"需新增节点"列。

## 结论

1. **你查的"谁吃了内存"和 OOM 判据采用的"哪个 cgroup 账本超了"不是同一个对象。** 判据跑在账本上，人却盯着进程表。
2. 真正增长的那部分内存由**内核代持**：文件页缓存（尤其写回跟不上的脏页）、tmpfs/`/dev/shm` 的 shmem、以及 socket 缓冲/slab 等 kmem。它们按 cgroup 归账、进程 RSS 与 working_set 里根本没有、容器一销毁就归零——所以"曲线很平、找不到进程"，且"重启就好、3–5 天后复发"。shmem/kmem 在无 swap 时**不可回收**，缓存来不及驱逐就只剩杀进程一条路。
3. **机器不固定不是机器有差异，而是触发条件在节点上下文**：同节点邻居的压力、盘与存储路径的写回延迟、连接突发——pod 只是受害者，所以搬机器问题跟着走。半天内用 `dmesg | grep -i oom`（区分 `Memory cgroup out of memory` 与全局 OOM）＋`memory.max_usage_in_bytes` 对比采样峰值＋`memory.stat` 的 `file/shmem/slab/sock` 四项，就能把它钉死到具体科目。

## ⚠️ 异常 / 矛盾 / 空白

- ⚠️ 题面"监控里内存曲线很平"未指明是 **pod 曲线**还是**节点曲线**。若节点曲线也平，则 1.5（邻居全局 OOM）直接被排除，只剩 cgroup 内不可回收科目——这一区分决定第一刀切哪里，必须先问清或两处都取数。
- ⚠️ 缺少三个关键数：limit 值、OOM 时刻的 `memory.stat`、`max_usage_in_bytes` 与采样峰值的差。没有它们，G1–G4 只能是**候选而非定论**；本回答不把候选说成事实。
- ⚠️ 若被杀 pod 是 BestEffort/Burstable 且节点上有大缓存/大页型邻居，1.5 概率显著上升；而"换机器问题也换地方"与此仍兼容（邻居也会被调度走），故不能靠"跟着 pod 走"单独排除 1.5，必须靠 dmesg 那一行。

## 💡 灵感备注

把 limit 想成"容器里所有内存的收据总额"，RSS 只是"你手里捏着的那几张收据"。本题的通用形态是 **裁决口径 ≠ 观测口径**：同族的还有 CPU throttling（`cfs_quota` 节流而进程 CPU% 不高）、inode 用尽而 `df -h` 显示有空间、文件句柄被内核持有而 `lsof` 看不到。凡是"指标都正常但被系统杀掉"，第一问永远是——**谁在替它记账，那本账我看得到吗？**

[技能] forest-hierarchical-backtracking
