[🌳 林状图] 选择理由：题面问的是「根源在哪」，是单因追溯而非选项枚举或定量估算；且题面给的现象自相矛盾（「反复 OOMKilled」×「没有进程吃内存」×「曲线很平」），矛盾的唯一来源只能是**判决口径与观测口径不是同一个量**，这正是因果深度问题，只能走回溯法。

> L0 类别判定：`software`（判据：同一镜像在 40 台等价机器上行为可复现于某一环境姿态、失败由确定性竞争导致——「哪台机器中招」由该副本当时承载的流量/时序决定，不是物理介质随机性｜已排除：硬件故障〔症状应跟随机器且不随 pod 漂移、重启同一 pod 无效〕、网络问题〔OOMKilled 是本地内核判决，不来自链路〕、权限/账号体系〔无拒绝访问类症状〕、组织流程〔技术面已有监控与告警，问题仍复现〕）
>
> L1 树实例化：树 = `software` · v1 · 核查 2026-10-18 · 路径 `C:\Users\Administrator\.dsh\skills\forest-hierarchical-backtracking\tree\software.md`（工作区 `D:\DeepSeek-levelup\knowledge-tree\index.md` 不存在，按第 2 条取默认树）。本次实例化子层：`quota` 资源配额（主）、`lifecycle` 生命周期控制（容器代持生死）、`concurrency` 并发与时序（低频偶发）。**本次判为不适用**：`init`（容器已长跑数天才被杀）、`dependency`（同一镜像全量部署）、`config`（配置同镜像相同，不解释跨机器漂移）、L1 节点 `win-service`（Windows 服务形态，本次为 Linux/K8s 容器）。

---

## L2 逐层回溯

### 层 1 · 轴 = 恒等式 `memory.current = anon + shmem + file + kernel(slab/sock/pagetable/stack)`

轴为什么由恒等式生成（而非列举）：内核 cgroup 内存控制器做 OOM 判决时比较的就是 `memory.current` 与 `memory.max`，而 `memory.current` 按记账来源只有这四项。任何「吃掉了内存」的实体，数学上必须落进且只能落进其中一项——没有第五种可能。这四项在 memcg 记账里天然互斥（同一页只记一次），满足正交。

| 格 | 该格在管什么 | 该格故障的可观测症状 |
|---|---|---|
| **A1 anon** 进程匿名内存 | 应用堆、栈、glibc/jemalloc arena | per-process RSS 与 `container_memory_working_set_bytes` **同步**阶梯/方波上涨；`/proc/PID/smaps_rollup` 的 `RssAnon` 与 `memory.stat: anon` 一致。题面「查不到任何进程吃了内存」+「曲线平」对该格是强反证（除非采样太粗，见层 3） |
| **A2 shmem / tmpfs** 共享内存与内存盘 | `/dev/shm`、`emptyDir{medium:Memory}`、`/tmp` 为 tmpfs、`MAP_SHARED\|MAP_ANONYMOUS` 段 | `memory.stat: shmem` 单调上涨而**任何进程 RSS 都不涨**（共享页在多进程间分摊、往往落在 per-process top 之外）；`du -sh /dev/shm` 或 `/dev/shm` 里有残留段文件；**无 swap 时这部分不可回收**，内核只能杀；`memory.failcnt` 反而很平（不是回收失败，是无页可回收） |
| **A3 file 页缓存**（含 deleted-but-open 文件） | 容器可写层写日志/临时文件、挂载卷的读写、mmap 文件 | `memory.stat: file` 与 `active/inactive` 老化不动；`lsof \| grep deleted` 或 `ls -l /proc/*/fd` 看到几百 MB～GB 级 `(deleted)` 文件；**fd 仍持有 ⇒ 页不可回收，`echo 3 > drop_caches` 无效**；RSS 完全不涨。日志轮转把文件删了、进程没关 fd，是最典型的形态 |
| **A4 kernel memcg** slab/socket/page table/kernel stack | 大量文件产生的 `dentry/inode_cache`、连接泄漏的 socket 缓冲、线程泄漏的内核栈（约 16 KB/线程）、页表 | `memory.stat: slab / slab_reclaimable / sock / kernel_stack / pagetable` 中某一项随天数直线涨；`ss -m`/`/proc/net/sockstat` 连接数或 `Threads:` 数直线涨；`/proc/slabinfo` 的 dentry/inode 数量级异常；**RSS 完全不涨**；容器被杀的倒数分钟 `pgscan/pgsteal` 几乎不动（无可回收） |

> ⚠️ 全空列判据自检：本层四格每一格都有专属症状且互不解释（A2 涨的是 shmem、A3 是 file、A4 是 slab/sock），不构成「全空列」，轴有效，无需换轴。

### 层 2 · 轴 = 内核 OOM 通路的必经时序 `charge 失败 → reclaim 尝试 → 选 victim → 执行 kill`

轴为什么由必经时序生成：`OOMKilled` 这个状态只可能在走完这四步后产生；任一步不成立就没有 OOMKilled。四步在时间上不可交换、互斥。

| 格 | 该格在管什么 | 该格故障的可观测症状 |
|---|---|---|
| **B1 判定点** | 是 `memory.max` 被击穿，还是 `memory.high` 只 throttle、还是 v1 的 `memsw/use_hierarchy/kmem` 语义 | `memory.failcnt`、`memory.events: max/high` 计数；v1 里 `memory.memsw.limit_in_bytes` 与 `memory.limit_in_bytes` 不等会给出「RSS 没过 limit 却死了」的假象 |
| **B2 回收是否可能成功** | 干净 file 页可回收、anon 有 swap 可回收；shmem / deleted-open 页 / mlock / 无 swap 的 active anon **不可回收** | OOM 前 `pgscan_*`/`pgsteal_*` 暴增 ⇒ 是「真的在挣命回收」（多为 A1/A3 干净页）；**完全不动** ⇒ 不可回收项（A2 / deleted-open / A4），这是判定「无可回收」的关键指纹 |
| **B3 victim 选择** | `oom_score_adj`、`memory.oom.group`、同 cgroup 内多进程/多容器 | 被杀的不是内存最大者；sidecar 与主容器共 cgroup 时杀错人；未设 `oom.group` 时零散杀进程而非整容器 |
| **B4 执行者** | cgroup OOM killer（`memory.events: oom_kill`）／节点级 oom-killer／kubelet eviction | 同节点**其它 pod 是否同时死**；pod 状态是 `OOMKilled` 还是 `Evicted`；`dmesg` 里是 `Memory cgroup out of memory` 还是 `Out of memory: Killed process` |

### 层 3 · 轴 = 观测链的必经时序 `采集 → 聚合 → 归因 → 留存`

轴为什么由必经时序生成：任何一条「内存曲线」都必须经过采集间隔、聚合函数、归因维度、留存策略四道闸，缺一道就没有曲线。四道闸互斥且逐序。

| 格 | 该格在管什么 | 该格故障的可观测症状 |
|---|---|---|
| **C1 采集间隔** | 15–60 s 的 scrape 对 <1 s 的分配尖峰是零概率命中 | 曲线平滑**且** `memory.peak`（cgroup v2）/`memory.max_usage_in_bytes`（v1）显著高于所有采样点——这是「尖峰存在但没被看见」的硬证据 |
| **C2 聚合函数** | `avg`/`rate`/分位数会把尖峰抹平；只有 `max_over_time` 保留 | 同一时间窗用 `max_over_time(container_memory_working_set_bytes[1h])` 重算，曲线立刻出现台阶——曲线「平」是聚合造的，不是内存真的平 |
| **C3 归因口径** | per-process RSS ≠ per-container working_set ≠ per-pod 合计；sidecar/exec 进程、init 容器残留、VPA 改过 limit 都让「limit 与看到的量」不同源 | 面板上的 limit 线与 `kubectl get pod -o yaml` 里的实际 limit 不一致；被杀的容器名不是主容器；把 `container_memory_usage_bytes`（含 cache）当 RSS 读 |
| **C4 留存与断点** | pod 重建后 pod 名/UUID/cgroup 路径变更，时间序列断成两条，旧序列停在历史值、新序列从低基线起步 | 「重启就好」+ 每条序列各自都很平 ⇒ 两个平段拼出「一直很平」的错觉；OOM 前最后 30 s 无任何留存 |

### → 类根（这一大类在什么结构条件下才可能发生）

**`OOMKilled` 是内核按 memcg 记账做出的**判决**，不是对「谁吃了内存」的**观测结论**。只要「守护容器内存上限的观测面」与「判决依据的记账和」不是同一个量——不同源（进程 RSS vs `memory.current` 四项和）、不同期（分钟均值 vs 微秒级判决）、不同粒度（pod 名 vs 容器 cgroup）——那么「被判死刑」与「没人吃内存」就可以同时为真，而且必然同时为真。这一类问题的结构条件就是：**容器内存上限由一个看不见其内部成分的观测面去守护**。它跟你跑什么镜像无关，所以同一镜像 40 台照样偶发。

### └ 个例根（挂在类根下，不是平行清单）

该 pod 的 cgroup 里存在一个**不归属任何进程、且在无 swap 条件下不可回收**的记账项，被一个**随 pod 移动、低频**的动作驱动（每个副本按自己承载的流量/时间表触发，故「出问题的机器不固定、换机器问题跟着换地方」），在 3–5 天里单调累积到 `memory.max`；内核在 charge 失败后尝试回收（`pgscan` 不动），发现无页可回收，直接杀；重启把整本账清零，于是「好了」，再过一个周期重演。按证据强度排序，这一项首选 **A2 shmem/tmpfs**，次选 **A3 deleted-but-open 页缓存**，再次 **A4 dentry-inode slab / socket buffer**。

> 汇合层（旧三层，作为「问题本身根源」的取法）
> - 背景现象：同镜像 40 台、3–5 天、一两台、位置漂移 ⇒ 触发来自「流量/时间的低频事件」，镜像内容与静态配置已被排除（否则 40 台应同周期必现）。
> - 提问者意图：表面要救这一两个 pod，实际要的是「40 台规模下把不可解释的 OOM 变成可归因」——单点打补丁会让他每 3–5 天回来一次。
> - 问题本身根源：取上面的类根（判决口径 ≠ 观测口径），个例根只是它在本次的落地形态。

---

## L3 双根

### 处置根（修本次，2 小时内可指认成分）

对被杀的**那一个 container**（不是 pod）同时取四份证据：
1. `memory.stat` 全项 + `memory.events`（oom/oom_kill/high/max）+ `memory.peak`——看哪一项在涨、`pgscan` 是否动；
2. 容器内 `ls -l /proc/*/fd | grep deleted`、`du -sh /dev/shm`、`df -h /tmp`、`ss -m`、`cat /proc/net/sockstat`、`Threads:`——定位 A2/A3/A4；
3. `kubectl get pod -o yaml` 的实际 limit 与监控面板上的 limit 对账——排除 C3；
4. 把 limit 临时 +25% 观察一个周期：周期按比例延长 ⇒ 累积型（A2/A3/A4）；周期不变但杀伤力下降 ⇒ 尖峰型（A1 + C1/C2）。这一步是「累积 vs 尖峰」的唯一判别器，成本一次重启。

### 消解根（灭这一类）

条件：**容器内存这个数，只由可命名成分构成，且每个成分都有独立上限与独立告警；看守它的观测面就是判它的那个账本。**
1. 同源：监控采集 `memory.current` 与 `memory.stat` 分解，与判决依据同一个量；对外展示一律用 `max_over_time`，禁止 avg。
2. 分解：anon / shmem / file / slab / sock / kernel_stack / pagetable 各自一条线、各自一个阈值。
3. 去垃圾桶：热点容器禁 tmpfs 与 `emptyDir{medium:Memory}`（或强制 `sizeLimit`）；日志一律 stdout 或独立 volume，不落容器可写层；连接/线程/fd 设上限。
4. 留证：`memory.peak` + OOM 前 60 s 的 `memory.stat` 快照（eBPF oomkill 探针在杀之前 dump）。

- **不可发生判据**：若当时已满足上述四条，则任何一次 OOMKilled 在发生前必然已有一个**具名成分**越线并被独立告警记录——「查不到谁吃了内存」在结构上不可能出现（只可能「查得到但预算内没修」，那已经是另一个问题类）。注意：这**不是**让 OOM 变少见，而是让「无因之死」这一类不存在。
- **可执行首边**：在 40 台上加一个 node-exporter textfile collector，15 s 直读 `/sys/fs/cgroup/**/memory.{current,stat,events,peak}`（只读、零业务侵入、可当天上线）；同时给每个节点挂一个 `bpftrace` 的 `oomkill` 探针，在被杀瞬间 dump 该 cgroup 的 `memory.stat`。
- **成本量级**：工程 1–3 人日（collector + 看板 + 探针）；存储 +20–50 MB/节点/天，40 台约 1–2 GB/天，需降采样或只留分解后的 7 条序列；判别成本 O(1) 次采样。
- 三道闸门核验：①不可发生判据 ✅（结构上消灭「无因」）②可执行首边 ✅（textfile collector，当天可上线）③成本量级 ✅（已给量级，定量收敛交给 📐 公式图）。

---

## L4 迁移出口（消解根指向「观测口径与 limit 同源」的架构变更，本次问题降级为其中一项）

1. **指标基数爆炸**：每容器 7 条成分线 × 40 节点 × pod 数 → 必须定聚合与降维策略。
2. **cgroup v1→v2 语义差异**：`memory.kmem` 并入 `memory.stat`；`oom.group` 的行为变化；`memory.high` 只 throttle；swap 记账与 v2 默认 `memory.swap.max=0`。
3. **内核/运行时要求**：eBPF 需 ≥4.18 + BTF，老内核没有 `memory.peak`，探针要降级到 `memory.max_usage_in_bytes`。
4. **采样抖动**：15 s 直读 cgroup 文件对节点 IO 与 kubelet/cadvisor 的额外开销，以及采集本身的内存/CPU 回冲。
5. **组织能力**：值班要会读 `memory.stat`/`failcnt`/`pgscan`，而不是看图说话；告警规则要从「内存使用率」改成「成分越线」。

→ **本次问题降级为：第 1 项「指标基数与归因看板」下的一个具体 case。** 修完 L4 的第 1、2 项，本次这类「没人吃内存却被杀」会自动变成一条带成分名的告警。

---

## 候选根排序（预算函数：`Share × Lever ÷ Cost`，Share 唯一4/主因3/共因2/次要1；Lever 改配置3/改架构2/换环境1；Cost 一次采样1/一次重启2/一次迁移3）

| 层级 | 候选根 | Share | Lever | Cost | 分 | 判 |
|---|---|---|---|---|---|---|
| 类根 | 判决口径 ≠ 观测口径（memcg 记账 vs 进程 RSS+分钟均值） | 唯一 4 | 改配置 3 | 一次采样 1 | **12** | 必查，第一名 |
| 个例根 | R1 不可归因且不可回收的记账项累积（shmem / deleted-open 页 / dentry-slab / sock） | 主因 3 | 改配置 3 | 一次采样 1 | **9** | 首选假设 |
| 个例根 | R2 亚采样窗瞬时尖峰（大请求、大对象、解压、GC 前复制） | 共因 2 | 改架构 2 | 一次采样 1 | **4** | 并行排除 |
| 个例根 | R3 limit/指标/容器维度不同源（sidecar 共 cgroup、exec 进程、VPA、看错指标） | 共因 2 | 改配置 3 | 一次采样 1 | **6** | 顺手排除，几乎零成本 |
| 个例根 | R4 victim 选择错（`oom_score_adj`、未设 `oom.group`） | 次要 1 | 改配置 3 | 一次重启 2 | 1.5 | 只在已确认 OOM 后才看 |
| 个例根 | R5 节点级 OOM 被记成 OOMKilled | 无 1 | 动不了 1 | 一次采样 1 | 1 | 挂起 |

排序口径说明：**Cost 就是预算**。前四名全都只需一次采样（读取现成的 cgroup 文件），所以它们可以并行做，不需要按序；一旦某条的 Cost 升到「一次迁移」（如 R5 需要换节点/换内核），它就应该被挂起而不是被验证。

## 挂起表

| 分支 | 判定 | 依据 | 恢复条件 |
|---|---|---|---|
| 硬件故障（ECC/坏内存/主板） | 不是根 | 症状随 pod 漂移而不随机器固定；重启同一 pod 即恢复；无 CRC/ECC/温度相关指纹 | `dmesg` 出现 MCE/EDAC 计数，或同一节点上**不相关**的多个 pod 同时出现异常；把 pod 钉在该节点仍复现 |
| 节点级 oom-killer / kubelet eviction | 不是主因（挂起） | 「重启就好」且只死一个 pod，同节点其它 pod 存活；pod 状态为 `OOMKilled` 而非 `Evicted` | `dmesg` 出现 `Out of memory: Killed process`（非 `Memory cgroup out of memory`），或同节点多 pod 同时被杀 |
| 纯匿名内存泄漏（应用 heap 泄漏） | 降级为次要（挂起） | per-process RSS 与 working_set 应同步阶梯上涨，与「任何进程都没吃内存 + 曲线平」矛盾 | 1 s 采样或用 `/proc/PID/smaps_rollup` 看到 `RssAnon` 阶梯上涨（此时回到 A1，类根结论不变，个例根改写） |
| 镜像内容/静态配置缺陷 | 不是根 | 同镜像 40 台全量部署，静态缺陷应当全量同周期必现，而非少数偶发 | 40 台上出现相同周期、相同时间的同步发作 |
| limit 被误设 / 被 VPA 改小 | 共因（保留，需排除） | 能解释「为什么超」，但解释不了「为什么看不见」；且不解释位置漂移 | `kubectl get pod -o yaml` 的 limit 明显低于该容器常态基线 |
| 语言运行时/分配器不归还 OS（glibc arena、jemalloc dirty page） | 不是根 | 这类问题 RSS 会涨，属 A1 的可见子集，与「曲线平」不符 | RSS 阶梯涨而 `memory.stat: anon` 稳定（说明是 file/mmap 型，落回 A3） |
| 无 swap 导致「没吃多少就死」 | 共因（成立但不独立） | cgroup v2 默认 `memory.swap.max=0`，使 shmem/anon 无路可退；但它只是**放大器**，不是「谁涨的」 | 启用 swap 后 OOM 周期延长但仍在 ⇒ 回到 A2/A3/A4 找具体成分 |
| 树外分支：`container-cgroup-quota`（K8s/memcg 配额与记账细则） | 树里无此节点，本次靠 `software` 的 `quota` 子层临时承载 | 知识树 v1 只有 `software` 与 `win-service`，无容器/memcg 专节点；细则（`memory.stat` 字段语义、`oom.group`、v1/v2 差异）不在树内 | 登记为 **v2 候选**（理由：本次与后续 K8s 类问题高频命中该支），核查后落盘并升版本 |
| 树外分支：`observability-aliasing`（采样/聚合/归因导致的观测失真类） | 树里无此节点，本次靠层 3 临时承载 | 这是一整类独立故障（不止内存），`software` 的六个子层都没有覆盖「观测面本身失真」 | 登记为 **v2 候选**（理由：层 3 的四格全是这一类，重复出现概率高） |

## 结论

根源不在内存本身，而在**判决口径与观测口径不是同一个量**：`OOMKilled` 是内核拿 `memory.current`（anon+shmem+file+kernel 四项之和）跟 `memory.max` 比出来的判决；你查的是「进程 RSS + 分钟均值 + pod 名」。于是**「被判死刑」和「没人吃内存」可以同时为真**。同一镜像在 40 台上偶尔中招、位置漂移，是因为触发源是随副本走的低频累积（首选 `/dev/shm`／tmpfs 段、被轮转删掉但 fd 未关的大文件页缓存，其次 dentry-inode slab 与 socket 缓冲）——重启只是把账本清零，所以「重启就好」，3–5 天后再来一次。

三句话落地：
1. 先读被杀容器的 `memory.stat` 四个成分 + `memory.peak` + `memory.events`，2 小时内就能指认是哪一项在涨（这一步不用改任何配置）。
2. 再把 limit 抬 25% 看周期是否按比例延长，用它判别「累积型」还是「尖峰型」。
3. 消解是把监控口径换成与 limit 同源的 `memory.current` 分解，并给每个不可回收成分单独立限——做完之后这类问题不是变少，而是**变得必须先具名才能发生**。

[✅ 验证] 本文所有机理解均落在可读取的 cgroup 文件与内核记账语义上（`memory.current`/`memory.stat`/`memory.events`/`memory.peak`/`failcnt`/`pgscan`/`oom.group`），未做任何机器复现（题面禁止、且题面信息已足够定位）；知识树仅加载 `software` 节点 v1（路径已回填），无捏造路径或版本。

[⚠️ 异常/矛盾/空白]
- ⚠️ 题面缺「被杀的是主容器还是 sidecar、exit code 是否 137、`memory.events` 数值」——因此本图用正交格覆盖而非单点押注；若这些数据到手，可把个例根从 3 选 1 收敛到 1。
- ⚠️ 「重启就好」有两种相反含义（记账清零 vs 换了个节点顺带换了触发者），题面未区分；前者支持累积型个例根，后者支持「触发源跟随流量」。
- ⚠️ 知识树 v1 缺容器/memcg 与观测失真两个节点，本次靠 `software` 的 `quota` 子层与自建层 3 承载，已按规则登记为 v2 候选。

[💡 灵感备注] 「重启就好」在这个问题里是最容易被误读的线索：它看起来像「状态被清了」，实际上是**清零了一个你从没看过的账本**。凡是「重启就好 + 查不到原因」的组合，第一反应都应该是「我查的量不是系统用来做决定的那个量」——这条启发可以脱离内存，直接搬到句柄、连接数、inode、conntrack 上。

[技能] forest-hierarchical-backtracking
