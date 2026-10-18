[🌳 林状图] 选择理由：题面问「根源在哪」＋「查不到任何进程吃内存」——这是「偶发失败的可观测症状与真实因果脱节」类问题，未知在因果深度而不在选项广度，按触发词规则走回溯法。先读知识树（工作区树 `knowledge-tree/index.md` 不存在，属正常情况，按序降级到技能树，未宣布「树不存在」），再实例化。

---

## L0 类别判定

**类别 = `software` 的 `quota`（资源配额／记账判定）× `lifecycle`（谁决定容器存亡）复合子层**（判据：同一镜像在 40 台等价机器上行为可复现；失败由确定性竞争——内存压力到达阈值的时间——而非位翻转或物理介质决定｜已排除：①硬件故障（关键反证：症状跟着 pod 换位置，不跟着机器留；无 CRC/ECC 族症状）②网络（被杀是本地 SIGKILL 事件，与分层可达性无关）③权限/账号体系（与身份无关，且重启即恢复）④组织流程（技术层已有明确的事件类型与 3–5 天周期律））。

## L1 树实例化

`树 = software → quota / lifecycle · v1 · 核查 2026-10-18 · 路径 C:\Users\Administrator\.dsh\skills\forest-hierarchical-backtracking\tree\software.md`（索引：`C:\Users\Administrator\.dsh\skills\forest-hierarchical-backtracking\tree\index.md`；工作区覆盖树 `D:\DeepSeek-levelup\knowledge-tree\index.md` 不存在，按 0.1 规则降级到第 2 条来源）。

- 树上 `quota` 层原文覆盖「内存、句柄、桌面堆、线程、文件描述符」与「非交互／受限上下文的配额比交互式小」——本题是它的容器化实例，但树里**没有**「记账桶定义／判定权归属／killer 选中规则」这一支，登记为**树外分支**（见挂起表第 6 行，并登记 `v2 候选` 节点 `container-mem-accounting`）。
- 本次判为不适用的节点：`win-service`（Windows 服务形态，Session 0／桌面堆／注入 DLL，本题为 Linux 容器，不适用）；`hardware`／`network`／`org-process`／`data-consistency` 均为索引中「待建节点」，本次不用。

## L2 逐层回溯（轴：一次 OOMKilled 事件的必经时序）

**轴如何生成**：不列举，用恒等式＋必经时序。一次「被 OOMKilled」在结构上等价于
`事件 = 某桶有字节累积 ∧ 字节被 charge 到该容器 ∧ 某个判定者比较阈值 ∧ （若是全局 killer）按评分选中该进程 ∧ 退出状态被翻译成 OOMKilled ∧ 该翻译被观测到`
六个合取项缺一不可，故六格必然存在（可生成）；每格故障的根不解释其他格的症状（正交）；每格有专属取证点（可观测）。**跳步可以，格子不可省。**

| 层 | 轴格 | 该格在管什么 | 故障形态（本格成为根时的样子） | 该格故障的可观测症状 |
|---|---|---|---|---|
| 层1 T1 | 字节累积 | 真实增长的桶：`anon`（堆/栈/未归还 arena）、`file`（page cache，尤其脏页）、`shmem`（tmpfs、/dev/shm、memory 型 emptyDir）、`kernel`（slab、socket buffer、conntrack、页表）、碎片 | 累积发生在**不在进程 RSS 里**的桶 | `cgroup/memory.current` 与 `sum(container_memory_working_set_bytes)`／进程 RSS 出现稳定扩大的**差额**；`memory.stat` 中 file/shmem/slab/sock 单调增长而 anon 平 |
| 层2 T2 | 记账归属 | 字节 charge 到哪个 cgroup；limit 是否真的绑上 | pod 无 limit（BestEffort）→ 字节实际落在节点 root，真阈值是节点可用内存；cgroup 路径与 pod 不匹配（runtime/cgroup 版本差异） | `memory.max = max`、`qosClass=BestEffort`；被杀 pod 的 limit 与实际约束点不在同一层 |
| 层3 T3 | 阈值判定者 | 谁在比较、比什么 | 三种判定者被混为一谈：①memcg 回收失败（容器内 fast path，受 limit 约束）②节点级全局 OOM killer（受节点可用内存约束）③kubelet 驱逐（按 working_set 信号） | `memory.events` 的 `oom_kill` 计数 ／ `dmesg` 的 `Killed process …` 行 ／ kubelet 事件类型，三者指向不同的判定者，任选其一都会误判根 |
| 层4 T4 | 选中规则 | 全局 killer 杀谁 | killer 按 `oom_score = 实际用量 + oom_score_adj` 选；`oom_score_adj` 由 request/limit 与节点 Allocatable 导出（Guaranteed≈-997、BestEffort=1000、Burstable 按 request 比例），**与实际用量弱相关** | 被杀 pod 的 request 高、实际用量低；同节点上真正吃内存的邻居 pod 存活；被杀容器自身 cgroup 无 oom 计数 |
| 层5 T5 | 状态翻译 | 退出状态怎么变成 `OOMKilled` 这个字符串 | 137 = 128+SIGKILL，来源可以是容器内存超限、全局 killer、liveness 探针失败、驱逐、runtime 侧 kill；标注层不区分 | `describe` 显示 OOMKilled，但容器日志无 panic、无 lastState 堆栈、`memory.events` 无 oom_kill 增量 |
| 层6 T6 | 观测暴露 | 监控的采样面与指标口径 | 采样 15–60s 漏掉瞬时峰值；指标只取 working_set/RSS，漏 file/shmem/kernel 三桶；pod 重启后容器 ID 变、序列断裂，`memory.peak` 随 cgroup 删除而丢失；聚合到 pod/node 掩盖单容器 | 把采样降到 1s 或改读 `memory.peak` 才看见尖峰；历史库里「被杀前一刻」恰是空的 |

逐层收敛：

- 层1（累积）＋层2（归属）→ **报到的「内存」是记账量，不是物理量**；这解释了「查不到进程吃内存」：被记账的桶（page cache、shmem、slab/socket、未归还 anon）大部分不在 `ps`/RSS/working_set 口径里。
- 层3（判定者）→ 40 台机器上真正的判定者未必是 pod 的 limit，而是节点可用内存；「limit 没动过却反复被杀」由此可解。
- 层4（选中规则）→ 这是**三重随机性的结构来源**：机器随机＝节点级压力源（邻居 pod、脏页回写速率、磁盘 IO、内核版本）在 40 台上的分布；pod 随机＝killer 在一批评分相近的容器里挑，挑中谁与实际用量无关；时间随机（3–5 天）＝累积型桶到阈值的周期，不是请求驱动。
- 层5＋层6（翻译＋观测）→ 这是「你查不到」的结构原因：事件被贴上 `OOMKilled` 标签，而标签的粒度与监控的粒度都比真因果粗一档。

→ **类根（这一大类在什么结构条件下必然可能发生）**：容器层的「内存占用」是**记账量而非物理量**；当「桶的定义（T1）、charge 归属（T2）、判定者（T3）、选中规则（T4）、状态翻译（T5）、观测采样面（T6）」这六件事分别由内核（cgroup/killer）、kubelet、监控栈代持，而**排障只用六者中最窄的一口径（anon RSS / working_set / 15s 快照）去看时，「被杀」与「有进程真的用了内存」在结构上必然解耦**——失败会发生在应用能打日志之前、发生在监控能采到之前，于是表现为「无堆栈、无峰值、换位置」。

  └ **个例根（本次具体机制，三条并行实例路径，共用同一类根）**：
  1. **判定权在节点级**：pod 未加 limit（或 limit 远宽于节点水位），节点在**不可见的累积桶**上先到临界（脏页积压回写跟不上、tmpfs/shmem 增长、slab/socket/conntrack、语言 runtime 未归还 arena），触发**全局 OOM killer**；killer 按 `oom_score_adj`（由 request 导出）选，于是被杀者是「配置大 request 但用量小」的那台那一个 → 机器随机、pod 随机。
  2. **累积型而非请求型**：增长源是每读写一次就涨一点的 page cache／shmem／kernel 桶，不是业务高峰；3–5 天到阈值 → 周期律。
  3. **标注与观测双窄**：退出码 137 被翻译成 `OOMKilled`，语义上不区分「容器超 limit」与「被全局 killer 选中」；监控按 15–60s 取 working_set，看不到尖峰与三桶 → 你查什么都是平的。

  **重启就好＝换 cgroup 实例、清空累积桶、重建记账**；而如果压力源在节点/邻居侧，「重启」只是把被杀对象换成别人——这与「换到别的机器出问题的也换地方」完全同构。

## L3 双根

**处置根（修本次，先分叉再动手）**：对一台**正在出事但不重启**的节点做一次 6 小时取证，用三个证据把 T3 的判定者定死——
① `dmesg` 中的 `Killed process …` 行（**有** = 全局 killer 路径；**无**且 `memory.events` 的 `oom_kill` 有增量 = memcg 路径）；
② `cgroup/…/memory.stat` 的桶分解 ＋ `memory.current` 与 RSS 的差额（定 T1 到底是哪个桶）；
③ pod 的 `qosClass`／`limit`／`oom_score_adj` ＋ 节点 Allocatable 与 `sum(requests)`（定 T2、T4 的选择偏置）。
取证完按支修复：全局 killer 路径 → 给关键 pod 抬 request／改 Guaranteed＋给节点加 kube-reserved/system-reserved＋收敛临时性大内存邻居；memcg 路径 → 按超标的桶修（脏页 ratelimit/回写、memory 型 emptyDir 换 disk-backed、runtime 归还参数）。**不做这一步的任何调参都是在猜。**

**消解根（灭这一类）**：让「记账桶—charge 归属—判定者—选中规则—观测面」收敛到**同一坐标系**：工作负载统一 Guaranteed（request = limit，`oom_score_adj` 与真实用量同构）、节点显式预留水位使「节点级判定者」不再对业务 pod 生效、不可见桶要么被排除（禁 memory 型 emptyDir、日志走 disk、限制 page cache 影响面）要么被纳入可见预算、监控改为**事件驱动**（`memory.events`／`memory.peak`＋1s 采样）而非 15s 快照推断。

- 闸门① **不可发生判据**：若上述四项同时成立，则「被杀者不是账本超限者」与「账本不可观测」两种情形在结构上都不再可能——每一次 OOMKilled 都能指到某个具体桶的具体数字。不是「变少见」，是因果关系闭合。
- 闸门② **可执行首边**（从现状出发的第一步，很小）：部署一个 DaemonSet（或先在 1 台故障节点跑脚本），每 1s 采 `memory.current / peak / stat / events` 四个文件，只读不改应用。
- 闸门③ **成本量级**：40 节点 × 约 30 容器 × 5 序列 @1s ≈ 6000 点/s ≈ 5×10⁸ 点/天；压缩后约 1–2 GB/天、**几十至几百 GB/月**量级；工程侧 Guaranteed 化的改配 1–2 人周＋装箱率下降（需重算节点规格）。量级判定：**存储成本可控、工程成本小**，具体数值交 📐 公式图定量，不在本图里凭空给数。

## L4 迁移出口

消解根指向「判定权回收＋观测面重构」，故必须列出迁移问题清单，并把本次问题降级为其中一项：

1. **容量与调度**：request = limit 会让装箱率下降、碎片增加，需重算节点规格、HPA 与超卖策略（本次问题的「修好」会以容量成本的形式回来）。
2. **可观测性**：1s 采样的 TSDB 写入与基数（container_id 维度爆炸）；需定保留期、降采样与 downcardinality 策略。
3. **应用侧**：缓存型服务必须把 page cache／tmpfs／runtime arena 纳入显式预算；日志落盘与 IO 行为从「随便写」改为「有预算地写」。
4. **告警与值班**：告警从「OOMKilled 计数」改为「各记账桶水位与 oom 事件率」，值班判断从「重启」改为「先定判定者」。
5. **组织能力**：团队需掌握 cgroup v1/v2 语义、QoS 与 eviction/killer 语义——这是最容易被低估的一项。
→ **本次问题降级为第 2 项（可观测性缺口）下的一个子项**：不是「某个 pod 有病」，而是「这台集群的 OOM 判定权与观测面从未对齐」的一个表现。

## 候选根排序（Share × Lever ÷ Cost）

| 候选根（上下级） | Share 份额 | Lever 可控性 | Cost 证伪代价 | 排序 |
|---|---|---|---|---|
| **类根 A｜判定权在节点级＋`oom_score_adj` 由 request 导出**（解释随机性） | 主因 | 改配置 | 一次 `dmesg`＋`memory.events` | **1** |
| **类根 B｜不可见累积桶（page cache 脏页／shmem／slab-socket／未归还 anon）**（解释 3–5 天与「查不到」） | 主因 | 改配置 | 一次 `memory.stat` 桶分解 | **2** |
| **类根 C｜观测面窄（15–60s 采样＋working_set 口径＋peak 丢失）**（解释「曲线很平」） | 共因 | 改配置 | 一次 1s 采样 DaemonSet | **3** |
| └ 个例根 D｜language runtime 未归还 arena（MADV_FREE 类行为，与内核版本相关） | 次要 | 改架构／运行时参数 | 一次同镜像跨内核对比 | 4 |
| └ 个例根 E｜137 被宽泛翻译成 OOMKilled（探针/驱逐混标） | 次要 | 改流程 | 一次 `describe`＋`lastState` 对齐 | 5 |
| └ 个例根 F｜内核/运行时版本在 40 台上不一致（同一镜像、不同记账语义） | 共因 | 换环境 | 一次版本清单核对 | 6 |

> 排序是预算的函数：以上全部 Cost 都在「一次采样／一次重启／一次迁移」之内，故先取前三条（三条合起来才构成完整因果链，单独验任何一条都只会得到「部分解释」）。

## 挂起表

| 分支 | 判定 | 依据 | 恢复条件 |
|---|---|---|---|
| 真·应用内存泄漏 | 不是主因 | 泄漏应跟着镜像与请求量走、anon 单调上升、且换机器后原机器仍复发；题面是「换机器症状跟着换位置」 | 把该 pod 固定到一台安静节点、隔离邻居后仍 3–5 天被杀，且 `memory.stat.anon` 单调上升 |
| 硬件故障（内存条/ECC/主板） | 否 | 症状跟随 pod 而非跟随机器；无 MCE/EDAC/CRC 族日志 | `dmesg` 出现 MCE/EDAC，或 pod 换走后**原机器**继续复发 |
| 网络 / `nf_conntrack` 表满 | 挂起（可贡献 T1 的 kernel 桶） | conntrack 计入内核内存，但通常先表现为新建连接失败/丢包，而非 OOMKilled 事件 | `nf_conntrack_count` 逼近 max、`dmesg` 有 `nf_conntrack: table full` |
| 应用 runtime GC／arena 不归还（仅当镜像含 Go/Java 等） | 留作个例根 D 待验 | 这是「cgroup anon 记账高于 RSS」的经典形态，且与内核版本/回收压力相关，可解释随机性 | 同镜像换内核后症状消失/出现；`GODEBUG=madvdontneed=1` 或等价参数后不再被杀 |
| limit／LimitRange 在 namespace 间漂移 | 挂起（共因） | 若被杀 pod 与正常 pod 的 limit/request 有系统性差异，则 T2 独立成根 | 逐 namespace 对齐 limit/request 后症状仍在 |
| **树外分支：`container-mem-accounting`（cgroup 记账桶与 OOM 判定权）** | 树外，登记 `v2 候选` | 树 v1 的 `quota` 层只写「受限上下文配额更小」，无「记账桶／判定权／选中规则」三分；本图 T1–T4 全部落在树外 | 树升到 v2 收录该节点，本挂起转为正式实例化；理由：容器排障的绝大多数误判都发生在这一支 |
| 监控采集端错误（口径/聚合/采样） | 被折叠进类根 C，不单独作根 | 与 T6 同源，独立作根会与 C 重复计数 | 已确认 1s 全桶采集后仍无峰值——则此支重新独立成根 |
| 组织/流程问题 | 否 | 技术层已有确定的事件类型与稳定周期律 | 技术取证全部通过而「重启」SOP 仍在掩盖问题 |

## 结论

1. 根源不在应用：容器里的「内存」是**记账量**，而「谁记账、谁判定、按什么选、标成什么、采到什么」五件事都由内核/kubelet/监控代持，排障时你只用了其中最窄的一口径，所以「被杀」与「真的用了内存」在结构上必然脱节。
2. 本次最可能的机制组合：pod 的实际约束点是**节点可用内存**而非自身 limit，3–5 天里 page cache/shmem/slab/runtime arena 这类**不可见桶**累积到临界，**全局 OOM killer 按由 request 导出的 `oom_score_adj`** 选中了这个 pod；137 被翻译成 `OOMKilled`，而监控按 15–60s 取 working_set，两头都看不见。
3. 第一步不要调参：先在一台故障节点上取三样东西（`dmesg` 的 `Killed process` 行、`memory.events` 的 `oom_kill`、`memory.stat` 的桶分解），用它把「判定者是谁」定死——这一步决定了后面所有修复的方向。

---

[✅ 验证] 知识树按 0.1 顺序实读：`D:\DeepSeek-levelup\knowledge-tree\index.md` 不存在（glob 无结果，属正常情况，未据此宣布树缺失），降级读技能树索引与节点文件，产物已回填真实路径与版本日期。全文未读题面外任何集群/日志文件，未在本机搜索「复现」——机制层结论的取证动作全部写在产物里作为待执行步骤，而非声称已观测。

[⚠️ 异常/矛盾/空白]
1. ⚠️ 题面缺 4 项关键信息，任一项缺失都会改变个例根权重：①被杀 pod 的 `qosClass`／request／limit；②节点 `dmesg` 里那段 `Killed process` 行（有/无）；③`memory.events` 的 `oom_kill` 是否有增量；④「内存曲线」具体指标名（working_set／RSS／usage）。建议一次问齐，否则「随机」无法收敛到具体桶。
2. ⚠️ 逻辑分叉必须点明：题面同时断言「没有任何进程吃内存」与「pod 反复被杀」。二者只能通过两种结构同时成立——**判定权与实际用量解耦**（T3/T4）或**观测面窄于记账面**（T6）。二者必有其一，这就是一次就能证伪的分叉点，不存在「都没有」。
3. ⚠️ 知识树缺口：v1 无容器记账/OOM 判定权节点（已登记 `v2 候选` 并写入挂起表），本图 T1–T4 实际建在树外分支上，树背书只覆盖到 `software → quota/lifecycle` 的类别判定层。

[💡 灵感备注] 把「随机」变成「分布」的杠杆极低：在 40 台上加一个 30 行采集器，只记 `memory.events` 的 `oom_kill` 变化率与 `memory.stat` 五桶的斜率，一周内就能看出挨杀的容器与哪个桶的斜率同相位——随机性往往只是记录粒度不够造成的错觉。

[技能] forest-hierarchical-backtracking
