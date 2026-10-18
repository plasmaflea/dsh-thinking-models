# 同一镜像 40 台随机 OOMKilled（进程 RSS 看不到）的根源回溯

**题面约束**：只回答这一题；仅基于题面信息，不检索本机文件、不"复现"。

---

[🌳 林状图／回溯法] 选择理由：题面问的是「根源在哪」，未知落在**因果深度**（是哪一环让"看到的内存"与"被算账的内存"分家），不是选项广度也不是数量关系，所以单用林状图，不与网状图／公式图联用（成本量级只给量级，不展开定量模型）。

L0 类别判定：**software · 子层 quota（容器内存配额）为主、concurrency（时序/采样）为辅**
（判据：同一镜像在等价机器上行为可复现、失败可由确定性累积＋配置姿态完全解释，不依赖任何物理介质异常｜已排除：**硬件故障**——出事机器不固定、重新调度即迁移、无 CRC/ECC 类校验错误；**网络**——OOMKilled 是本地 cgroup 事件，不随链路变化；**权限/账号体系**——不涉及 ACL/令牌/组成员；**组织流程**——技术侧已有确定性事件源（内核 OOM killer），不是人的决策产出）
L1 树实例化：路径 ①`D:\DeepSeek-levelup\knowledge-tree\index.md` **不存在**（正常，按序降级）→ 实际取路径 ②`C:\Users\Administrator\.dsh\skills\forest-hierarchical-backtracking\tree\index.md`（索引 v1 · 核查 2026-10-18）→ 命中节点 `C:\Users\Administrator\.dsh\skills\forest-hierarchical-backtracking\tree\software.md`。
**树 = software（L0）· 子层 quota+concurrency · v1 · 核查 2026-10-18 · 路径 C:\Users\Administrator\.dsh\skills\forest-hierarchical-backtracking\tree\software.md**
本次判为不适用的节点：`win-service`（Windows 服务形态／Session 0／桌面堆，本题为 Linux 容器）；`software` 的 `lifecycle`（容器生命周期由 kubelet 代持，但本症状不是"无堆栈猝死"而是有明确 OOMKilled 事件源）、`init`（死在日志首行之前，本题有长期运行期）、`dependency`（无错误码族／符号缺失）、`config`（配置改动不涉及读取阶段错位）——四者均判为**非根但已登记**，理由与恢复条件见挂起表。

---

## L2 逐层回溯

### 轴（生成式，非列举）

轴由 **memcg OOM 的判定恒等式**机械切分，不由联想列举：

```
OOMKilled ⟺ 记账量 M ≥ 限额 L   且   可回收量 R 在时限内回收失败
M = 匿名 RSS + shmem/tmpfs + file cache + kernel（slab/socket/stack）
```

把恒等式右边拆成因子，即得五个**必现**因子（少任何一个，OOMKilled 在结构上不可能发生）——这就是轴的可生成性：

| 格 | 因子 | 为什么这一格必然存在 | **该格故障的可观测症状** |
|---|---|---|---|
| **A 记账** | 哪些字节被写进 M | 无记账项则无可比较的量 | `memory.usage_in_bytes`/`memory.current` 明显大于 `Σ 进程 RSS`；`memory.stat` 里 `file`/`shmem`/`slab` 占大头而 `anon` 平；`ps`/`top`/JMX heap 全平 |
| **B 回收** | R 为什么没被回收掉 | 只要还有可回收余量就不会走到 OOM | `shmem`（tmpfs）与 `slab` 结构上不可回收；dirty 页回写受阻；`mlock` 页；cgroup v1 无 `memory.high` 缓冲 → 余量用尽一步直达 OOM，没有"变慢/变卡"的预警期 |
| **C 观测** | 为什么监控里看不到 | 观测函数与 M 不是同一个量 | 监控采的是进程 RSS／JVM heap／被平滑的 `working_set`；采样周期（30s–5min）> 事件持续时间；`memory.events` 的 `max` 计数在两次采集之间 +1，但曲线无台阶 |
| **D 到达** | 为什么是 3–5 天、随机 1–2 台 | 累积速率 λ 与限额 L 的比值决定触达时间，是概率到达过程 | 出事机器与机龄/机房/负载排名**无相关性**；同镜像同配置；重新调度后问题跟着 pod 走而不跟着机器走 |
| **E 反馈** | 为什么"重启就好"且反复 | cgroup 随 pod 创建/销毁，销毁即归还全部记账 | `delete pod` 后 usage 归零；同一 pod 反复 OOMKilled；**`rollout restart`（只重启容器、复用 pod 与 emptyDir）无效而重建 pod 有效** —— 这是判别"记账在 cgroup 里"还是"记账在 pod 卷里"的钥匙 |

### 层1：五格逐格回溯（跳步可以，格子不可省）

- **A 记账 → 根：M 里存在"不属于任何进程 RSS"的项。** 四个具体来源：①**shmem／tmpfs**（`emptyDir{medium: Memory}`、`/dev/shm`、System V 共享内存、memfd）——记在 memcg，`ps` 里一个字节都看不到；若共享内存段的创建者已退出而引用未归零，页会**挂着一个已死进程的账**继续占额。②**page cache**——page cache 按"第一次触碰它的 cgroup"收费，进程退出/被迁走之后**这些页仍留在原 cgroup 的账上**，于是"没有任何进程吃内存"而账很满。③**kernel memcg**（`slab` 里的 dentry/inode/kmalloc、`sock`、`kernel_stack`）——cgroup v1 需 `cgroup.memory=nokmem` 之外才会计 `kmem`，这类内存**从任何进程视角都不可能被看到**。④**容器可写层写入/日志产生的 dirty 与 file 页**。症状专属：`memory.stat` 各分量之和≈usage，但 anon 平。
- **B 回收 → 根：M 里恰好是不可回收的那部分，且没有缓冲带。** shmem 与 slab 不可回收；v1 只有一条硬线（`memory.limit_in_bytes`），没有 `memory.high` 那种"先节流再杀"的中间态，所以"内存曲线很平"与"突然 OOMKilled"完全可以并存，不矛盾。症状专属：`memory.stat` 里 `total_inactive_file` 很小而 `shmem` 很大；`pgscan`/`pgsteal` 在事发前没有明显抬升。
- **C 观测 → 根（结构性的一根）：观测口径 ≠ 记账口径。** 三处错位可叠加：采 `container_memory_working_set_bytes` 之外的自建 RSS/heap 指标；cAdvisor 抓取间隔 30s–1min，而 OOM 前最后一次分配可能只持续数秒；`working_set` 会减去"估算可回收"的部分，于是 shmem 之外的 file 部分在图上被削平。**这一格是"查不到谁吃内存"这句话的直接制造者**——不是数据缺失，是问了一个测不到的对象。
- **D 到达 → 根：低频缓慢累积 + 40 台并行 = 泊松式"总有一两台中招"。** 若单台每天触达概率 ~1%，40 台每天期望 0.4 次，正是"3–5 天 1–2 台"；且哪台先到阈由各自累积速率的微差决定，故**机器不固定、换机即换地方**。这一格同时**否掉硬件与"某台机器配置特殊"两条支路**（见挂起表）。
- **E 反馈 → 根：处置动作恰好把记账容器销毁了，于是"好了"但没修好。** 重建 pod ⇒ 销毁 cgroup ⇒ page cache/slab/shmem 记账一次性归还 ⇒ 观测立刻恢复正常。这解释了"重启就好"的**假象**：它修的不是病因，是账本。同理，"反复 OOMKilled"是因为重建后累积速率不变，重新开始计时。
- **层1 全格自检**：五格中 A/B/C/E 均有专属症状且互不解释对方（A 说"记什么"，B 说"为何不回收"，C 说"为何看不见"，E 说"为何重启有效"），D 只说时间分布——**无全空列，轴成立，不换轴**。
- ⚠️ 层1 的判别边界（必须声明）：若 `Σ 进程 RSS ≈ memory.current` 且两者同步上涨，则 A 格为空——此时不是"记账口径分裂"，而是"观测选错了进程"（看的是被杀容器，真凶是同 cgroup 的另一个容器或已退出的子进程），转挂起表第 3 行。

### 层2：五格收敛

A（记的是非进程项）+ B（恰为不可回收）+ C（观测不看这个量）+ E（重启销毁账本）四格指向**同一个结构**：配额这件事由 cgroup 代持，而应用只掌握"自己能看见的那部分内存"；记账口径与观测口径从设计上就是两个不同的量。D 格只提供时间分布，不提供因果。

→ **类根（这一类在什么结构条件下必然可能发生）**：
**内存配额的记账权被 cgroup 代持，而工程侧的观测与认知口径（进程 RSS／堆指标／平滑曲线）只覆盖 M 的一个子集——只要这个"口径分裂"存在，"看不到谁吃内存却被 OOMKilled"就是这一类环境的必然产物，与具体是 shmem、page cache 还是 slab 无关。**
（与树里 `software` 节点的类根同构：某个本该由应用掌握的控制权——这里是**配额的自我预算与自我告警**——被外部机制代持，于是失败发生在应用的可见域之外。**树内子层 `quota` 判为命中，但树里 `quota` 只写了"受限上下文配额更小"，未细分"记账口径 vs 观测口径"，此分支登记为树外分支，见挂起表第 6 行。**）

**个例根（挂在类根之下，是子节点，不是平行清单）**——本次到底是哪一条：

| 编号 | 个例根（挂于类根） | 机制一句话 | 专属判据（现场一次采样即可分辨） |
|---|---|---|---|
| **A1** | shmem／tmpfs 记账（`emptyDir{medium:Memory}`、`/dev/shm`、共享内存段、memfd） | 不可回收，且创建者可已退出，仍占 cgroup 额度 | `memory.stat` 中 `shmem` 单调上升；`df -h /dev/shm`、`mount \| grep tmpfs` 增长；进程 RSS 不含此项 |
| **A2** | page cache 归属首次触碰它的 cgroup | 进程退出后页仍在原 cgroup 账上，`ps` 永远看不到 | `memory.stat` 中 `file`/`active_file` 高、`total_inactive_file` 低；容器可写层或日志目录持续写入 |
| **A3** | kernel memcg（slab dentry/inode/kmalloc、`sock`、`kernel_stack`） | 内核对象记在 memcg，任何进程视角都不可见 | `memory.stat` 中 `slab`/`slab_reclaimable`/`sock` 上升；`/proc/slabinfo` 里 dentry/inode 单调涨；host `slabtop` 同步 |
| **A4** | 瞬时尖峰落在采集间隙 | 峰值只持续数秒（fork/exec 风暴、批量读盘、副本重建），1min 采样看不见 | `memory.events` 的 `max` 计数与曲线不对应；降到 1–5s 采样才出现锯齿 |
| **A5** | 受害者≠元凶 | OOM killer 按 `oom_score` 杀，被杀 pod 是"好杀"的那个，真正涨的是同 cgroup 的另一个容器（sidecar/init/已退出子进程） | `dmesg` 的 oom-kill 行里 `anon-rss/file-rss/shmem-rss` 与被杀进程 RSS 不符；pod 内多容器共享 pod 级 cgroup |

---

## L3 双根

**处置根（修本次）**：
下次 OOMKilled 时现场**已经不存在**（cgroup 随 pod 销毁）——这是本题最容易踩空的地方。所以处置的第一步不是"去看"，而是**事前留下账本**：在 40 台机器的每个 pod 上加一个 5–10s 采样的小进程（3 行 shell / 一个 sidecar / 一个 DaemonSet 的 nsenter 循环），滚动写 `memory.current`、`memory.stat` 全分量、`memory.events`、`sum(RSS)`；OOM 前的最后 10 行就是现场。
判据一次成型：对账 `memory.current ≈ anon + file + shmem + slab + sock`，**看哪一项在涨**——A1/A2/A3/A4/A5 由此当场定夺，再对症（清 tmpfs／去掉 memory emptyDir／限制可写层与日志／加 `memory.high` 缓冲／提高限额／改 pod 级 cgroup 归因）。这一步成本 = **一次采样**，不改变任何架构，能覆盖 Share 最高的三条个例根。

**消解根（灭这一类）**：
**让"被计入配额的量"与"被观测、被应用自己管理的量"成为同一个量**——即把配额的自我预算权交还应用（应用内对 anon + shmem + socket buffer + direct/mmap 显式核算，主动 GC／丢弃／拒绝请求），cgroup 硬限只作**兜底**，同时观测管道按记账口径分解采集（`current` + `memory.stat` 全分量 + `memory.events`，10s 粒度）而不是只采一个进程 RSS／平滑 working_set。
- **不可发生判据**：如果当时采用它，则 M 的每一个字节都同时出现在"应用看得见的预算表"与"监控看得见的曲线"里，并且应用对这个量有闭环反馈 → 「查不到谁吃内存却 OOMKilled」**在结构上不可能发生**（只会退化成"看得见的过载＋看得见的限流"，那是另一类问题，不是这一类）。注意这只是让问题变成"可见且可控"，不是变小概率。
- **可执行首边（很小）**：**先在 pre-prod 给每个服务挂一个"cgroup 口径对账"探针**（10 行代码，输出 `current − (anon+shmem+file+slab)`），差值单调增长即告警。这一条即可把"3–5 天的黑箱"变成"上线 1 天内可见的斜率"。
- **成本量级（交给 📐 公式图定量，此处只给量级）**：探针 ≈ 1 人日／集群；按记账口径重建监控面板与告警 ≈ 1–2 人日；cgroup v1→v2（获得 `memory.high` 节流带 + `memory.psi`）≈ 1–2 人周／集群，且需内核与运行时兼容验证；应用侧自管预算按服务数计，量级在**每服务数人日**。与"每 3–5 天损失 1–2 个 pod 的可用性 + 值班排查工时"同量级，故可决策。

---

## L4 迁移出口（消解根把本次问题降级，而不是绕过）

消解根一旦指向"口径统一 + 配额自管"，就会带出这些后续问题；本次问题只是其中一项：

1. **运行环境与语义**：cgroup v1→v2 迁移（`memory.high` 节流带、`memory.psi`、`memory.stat` 字段变化、`working_set` 语义差异），以及 kernel memcg 记账开关的差异。
2. **可观测性**：监控管道指标口径改造——从"进程 RSS / 平滑 working_set"改为"`current` + `memory.stat` 分解 + `memory.events` 计数"，采样从 30s–1min 降到 10s，OOM 事件必须与 `max` 计数对齐。
3. **存储与状态**：`emptyDir{medium:Memory}`、`/dev/shm`、共享内存段、可写层与日志落盘的治理（谁准用 tmpfs、配额多少、清理策略）。
4. **生命周期与归因**：pod 级 cgroup 下多容器的归因（谁涨的、该杀谁），`memory.oom.group` 与 `oom_score` 调优。
5. **凭据与权限**：现场采样探针需要访问 cgroup 文件系统与 `nsenter` 权限，与最小权限模型冲突，需单列授权方案。
6. **组织能力**：值班 Runbook 从"OOM 就重启"改为"读 `memory.stat` 快照再决定"；服务 owner 必须能回答"我的内存记账口径是什么"。

→ **本次问题降级为**：第 2 项（可观测性口径）与第 6 项（Runbook）里的一个子项——**"配额记账口径的一次性对账"**。修掉它，本题的"查不到谁吃内存"这一半就永久消失；剩下一半（谁在涨）才是常规容量问题。

---

## 候选根排序（Share × Lever ÷ Cost）

**预算声明**：本次预算 = **只允许在下一次 OOMKilled 时抓一次现场**（Cost=1 的那一档）；Cost≥2 的候选只能留在挂起，不能拿去验证。这就是为什么下面的表只有前三条进验证队列——预算有限时，排序才有意义，否则产物退化成清单。

取值：Share 唯一=3／主因=2／共因=1.5／次要=1；Lever 改配置=3／改架构=2／换环境=1／动不了=0.5；Cost 一次采样=1／一次重启=2／一次迁移=5。

| 层级 | 候选根 | Share | Lever | Cost | 分值 |
|---|---|---|---|---|---|
| **类根** | 配额记账权被 cgroup 代持 + 观测口径 ≠ 记账口径 | 唯一 3 | 改架构 2 | 1 | **6.0** |
| └ 个例 | **A1 shmem／tmpfs** | 唯一 3 | 改配置 3 | 1 | **9.0** ← 首验证 |
| └ 个例 | **A2 page cache 归属** | 主因 2 | 改配置 3 | 1 | **6.0** ← 并列 |
| └ 个例 | **A5 受害者≠元凶** | 主因 2 | 改配置 3 | 1 | **6.0** ← 并列 |
| └ 个例 | A4 瞬时尖峰落采样间隙 | 共因 1.5 | 改配置 3 | 1 | 4.5 |
| └ 个例 | A3 kernel memcg／slab | 共因 1.5 | 换环境 1 | 2 | 0.75（不首验） |

验证队列 = A1 → A2/A5 并列（同一次采样可同时分辨），A4 作为同一次采样的副产品（把间隔降到 5s 即可）；A3 需换内核或开 `kmem` 记账，代价高一档，留挂起。

---

## 挂起表

| 分支 | 判定 | 依据 | 恢复条件 |
|---|---|---|---|
| 硬件故障（内存条/ECC/温度） | 挂起·非根 | 出事机器不固定、重新调度即迁移；无 CRC/ECC 类校验错误；若为硬件则重负载机高发，与题面"随机 1–2 台"不符 | 若同一物理机连续多日在**不同 pod** 上复现 OOM，且 node_exporter 有 CE/ECC 计数或 `mcelog` 记录 → 恢复为本类 |
| 网络问题 | 挂起·非根 | OOMKilled 是本地 cgroup 事件，不经过网络路径 | 若 `kubectl describe` 显示实为探针超时被 kubelet 杀并误标为 OOMKilled（exit 137 但 `memory.events` 无增长）→ 恢复 |
| 进程内堆外内存（direct buffer／mmap／线程栈／jemalloc 碎片） | 挂起·可能共因 | 若它是真凶，进程 RSS 会涨，"查不到进程吃内存"就不成立——除非当时查的是 heap 指标而非 RSS（这是观测口径错位的另一种形态，与 C 格同源） | 若 `Σ RSS` 与 `memory.current` **同步**上涨（A 格为空）→ 恢复为主因 |
| 采样错过瞬时尖峰 | 挂起·可能共因 | 能解释"曲线很平"，但不能解释"反复落在同一 pod"与"3–5 天"的低频特征（尖峰型通常与定时任务/请求波峰挂钩，频率更高） | 把采样降到 1–5s 后出现与 OOM 时刻对齐的周期性尖峰 → 恢复 |
| "OOMKilled" 标签本身误读（实为 liveness 失败／节点压力驱逐 Evicted） | 挂起 | 题面明确称 OOMKilled，姑且采信，但这是全网最常见的误判源 | 若 `kubectl describe` 的 Reason 为 Evicted/Error，且对应 cgroup 的 `memory.events:max` 未增长 → 恢复 |
| 树内不适用节点 `win-service`（Session 0／桌面堆／注入 DLL／SxS） | 挂起·非根 | 本题为 Linux 容器形态，无 SCM/桌面堆语义 | 若实际是 Windows 容器工作负载 → 恢复并整树切换 |
| 树内子层 `lifecycle`／`init`／`dependency`／`config` | 挂起·非根 | 症状是"运行期低频被杀"而不是"死在日志首行之前／无堆栈猝死／错误码族／配置读取阶段错位" | 若发现崩溃发生在启动阶段或伴随明确加载器/依赖错误码 → 逐项恢复 |
| **树外分支**：内核 memcg 记账缺陷／cgroup v1 `kmem` 泄漏／节点级内存碎片与 NUMA 分配失败 | 挂起 | 树内 `software` 的六子层只到"配额"层，未细分"记账口径"这一维；碎片又无法解释"重建 pod 即好" | 若 A1/A2/A3/A5 全部排除而 `memory.current` 仍单调涨 → 恢复（登记 `v2 候选` 节点 `container-memcg`，理由：本类问题全部落在"记账口径 vs 观测口径"这一未被现有树覆盖的维度） |
| 镜像/配置在某几台机器上不一致（非幂等滚动） | 挂起·非根 | 题面明确"同一个镜像"，且换机后问题跟着 pod 走 | 若发现机器侧存在配置漂移或镜像 digest 不一致 → 恢复 |

---

## 结论

1. **真凶不是进程，是"被记到 pod 头上却不属于任何进程 RSS"的不可回收内存**：最可能是 tmpfs／shmem（`emptyDir{medium:Memory}`、`/dev/shm`、共享内存段）与按首次触碰归属的 page cache，其次是 kernel memcg（slab/socket）。它们记在 cgroup 账上，`ps`／`top`／JMX 里一个字节都看不到。
2. **"监控曲线很平"不是数据错，是问错了对象**：观测口径（进程 RSS／堆指标／30s–1min 的平滑曲线）只覆盖记账量的一个子集，而 OOM 判定用的是另一个量。这个**口径分裂**就是本题的类根——只要它在，"看不到谁吃内存却 OOMKilled"是这类环境的必然产物，跟具体是 shmem 还是 slab 无关。
3. **判定动作只有一个，而且必须事前做**：OOM 后 cgroup 随即销毁，现场不留痕，所以先给每个 pod 挂 5–10s 的 `memory.current` + `memory.stat` + `memory.events` 快照；对账 `current ≈ anon + file + shmem + slab + sock`，**哪一项在涨就是哪一条个例根**。3–5 天的周期意味着最多两轮采样必出斜率。治本不是杀人也不是调限额，而是把配额口径与观测口径并成一个量、硬限只做兜底。

[✅ 验证] 按题面要求未做本机检索与复现，本节只列**可执行的验证路径**而非已执行结果（不声称已跑通）：`cat /sys/fs/cgroup/memory.stat`（v1 另有 `memory.kmem.usage_in_bytes`）／`memory.current` + `memory.events`（v2）；`dmesg -T | grep -i "oom-kill"` 看被杀任务的 `anon-rss/file-rss/shmem-rss` 三行；`df -h /dev/shm` 与 `mount | grep -E "tmpfs|memory"`；`/proc/slabinfo` 的 dentry/inode 增速；`Σ RSS`（`cadvisor` 或 `ps -eo rss,comm`）与 `memory.current` 求差。判据：差值单调增长的**分量名**直接指向 A1/A2/A3/A4/A5 之一。

[⚠️ 异常/矛盾/空白]
- ⚠️ **"重启就好"语义歧义（本小题最大的判别缺口）**：题面未区分"容器重启（pod 保留、emptyDir 保留）"与"pod 重建（cgroup 与卷全销毁）"。前者有效 → 记账在 cgroup（A2/A3）；后者才有效 → 记账在 pod 卷（A1，尤其 emptyDir-memory）。建议任何后续处置都先固定这个口径，否则 A1 与 A2/A3 无法分开。
- ⚠️ **缺现场三件套**：`memory.stat` 分解、`dmesg` oom-kill 的 rss 三行、`memory.events` 计数——没有这三样，A1/A2/A3/A5 只能并列，不能定夺。本题只能给到"类根确定 + 个例根排序"的粒度，这是信息边界，不是推理保留。
- ⚠️ **候选根 A4（瞬时尖峰）与题面"内存曲线很平"存在张力**：若监控采样本就是 1min，则"平"可能只是假平，A4 不能被"曲线平"这一句话排除，故只降权不剪除（见挂起表）。
- ⚠️ **树覆盖空白**：现有 `software` 节点六子层未含"记账口径 vs 观测口径"这一维，本题三个主要个例根全落在空白里，已登记 `v2 候选` 节点 `container-memcg`；在此之前的结论只建立在 `quota` 子层的粗粒度定位上。

[💡 灵感备注]
- 这类"记账口径分裂"是通类结构，不限于内存：CPU 的 `cpuacct` vs `cpu.stat`、IO 的 throttling 计数 vs 应用看到的延迟、甚至账单口径 vs 用户感知用量——凡是"外部代持一个量 + 内部只看子集"，就会出现"没人越界却越界了"。
- "重启就好"是极强的误导信号：它证明的是**状态被销毁**，不证明**病因被移除**。任何"重启即恢复"的偶发故障，第一问应是"重启销毁了什么账本"，而不是"重启修好了什么"。

[技能] forest-hierarchical-backtracking
