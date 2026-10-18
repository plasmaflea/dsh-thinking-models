[🌳 林状图／回溯法] [选择理由：题面问的是「根源在哪」，且四个症状（无凶手／曲线平／位置随机／重启愈）是同一机制在四个观测面上的投影，属于**因果深度**未知而非选项广度未知，所以先定因果骨架。选轴用「一次 OOMKilled 事件的必经时序」——生成式，不列举。]

---

## L0 类别判定

**类别：`software` 节点下的 `quota`（资源配额）子层，交叉 `lifecycle`（谁决定进程存亡）。**

- **判据**（按 `software.md` 的第 1 条）：同一份镜像在等价机器上行为等价，本次只在**某种环境姿态**下复现——这里的"环境姿态"是节点上的内存水位与其他工作负载的共存关系，而不是机器的物理身份。第 2 条也满足：失败由确定性竞争导致（谁先触到共享资源阈值），不是位翻转。
- **已排除的大类**：`硬件故障`（症状应钉死在特定机器上并带 ECC/MCE 痕迹，题面却是位置随机漂移）；`网络`（无超时/连接重置形态，且网络问题不会以 137/SIGKILL 收尾）；`权限·账号体系`（无拒绝访问类症状）；`组织与流程`（保留为共因挂起，见挂起表第 6 行）。
- **为什么必须排除硬件**：题面一句关键证据——"**出问题的机器不固定，换到别的机器上，出问题的也换地方**"。若某台机器的物理或内核配置有偏（swap 开关、`vm.overcommit_memory`、cgroup v1/v2 混装、page cache 策略），症状会**钉在那台机器上**。位置跟着负载漂移 ⇒ 40 台在结构上是同构的，只是每一台上都有一个**共享的、会缓慢累积到阈值的资源**在独立地跑到边界。

## L1 树实例化

- `树 = software · v1 · 核查 2026-10-18 · 路径 C:\Users\Administrator\.dsh\skills\forest-hierarchical-backtracking\tree\software.md`
- 索引路径：`C:\Users\Administrator\.dsh\skills\forest-hierarchical-backtracking\tree\index.md`（表版本 v1 · 核查 2026-10-18）
- 本次判为**不适用**的节点：`win-service`（Linux 容器 + cgroup，不涉及 Session 0／桌面堆／SxS／注入 DLL）。
- 树外分支已登记进挂起表第 8 行，不静默丢弃。

## L2 逐层回溯

**轴（生成源：必经时序，一步一格）**——任何一次 OOMKilled 事件，从"字节被占走"到"你在 Grafana 上看到一条平线"，必须依次经过六步，缺任何一步事件就不成立。所以六格必然存在、正交（各格的根不互相解释对方的症状）、可观测（每格有专属症状）。

| 格 | 这一步在管什么 | 该格故障的可观测症状 | 本格判定 |
|---|---|---|---|
| **层1 消耗发生** | 谁把物理页/内核对象占走了 | 进程 RSS 与 working_set 有峰；或 RSS 平而 cgroup usage／Slab／SReclaimable／Dirty+Writeback／`ss -m` 总量／`nf_conntrack_count` 涨 | **空**——但这正是题面的"查不到任何一个进程真的吃了内存"。⚠️ 这一格为空**不是"轴选错"**，而是候选定义域被限死在"进程的用户态堆"上；消耗发生在层2 的记账对象里，属"归属未清"，不是"无消耗" |
| **层2 记账归属** | 这些字节记到谁的账上 | 同一份内存可被记入 anon / file(page cache) / shmem(tmpfs,/dev/shm) / sock / slab / kernel_stack / hugepage；**只有 anon 会出现在进程 RSS 里** | **第一现场**：记账对象不是进程，所以"找进程"这个动作本身必然找不到凶手 |
| **层3 判据触达** | 谁判定"越界了" | **cgroup 级**：`memory.max`／v1 `memory.limit_in_bytes` 触达（含 page cache），memcg OOM killer 动手；**节点级**：全局 oom-killer 按 `oom_score` 挑人，受害者可以是任何进程——包括只占几 MB 的那个 | **分水岭**。可观测判据：`/sys/fs/cgroup/.../memory.events` 里 `oom_kill` 是否 +1；dmesg 的 oom 行里有没有 `oom_memcg=` 字段 |
| **层4 执行击杀** | 谁真的扣扳机 | memcg killer 杀本 cgroup 内占用最大者；**全局 killer 杀全节点 oom_score 最高者，可能根本不在肇事 pod 里**；kubelet 的驱逐也会停容器（但那记 `Evicted`，不记 `OOMKilled`） | **题面核心特征的出处**：被杀者 ≠ 消耗者。位置随机漂移就是"受害者由节点瞬时负载排序决定"的直接后果 |
| **层5 上报归因** | kubelet 怎么记账 | 容器 `exitCode: 137` + `reason: OOMKilled` 是 kubelet 对 **SIGKILL 的一刀切归因**：真凶、无辜受害者、被外部 SIGKILL 的容器，全部记成同一个 `OOMKilled` | **第二现场**：区分度在这一步被抹平，于是"随机受害"看起来像"反复 OOM" |
| **层6 观测呈现** | 监控给你看什么 | 采样间隔（15s/1m）× **均值/求和聚合**把短时尖峰平均掉；容器指标只暴露 RSS/working_set，看不到 page cache 与内核内存；relabel 把节点维度合并 | **第三现场**：这是"内存曲线很平"的**直接机制**，与"有没有吃内存"无关 |

**→ 类根（这一大类在什么结构条件下必然可能发生）**

> **内存的判据权、记账权、执行权、归因权，全部由应用之外的机制代持**：记账在 memcg（含大量非进程对象），判据在内核阈值，执行在 oom-killer 的 badness 排序，归因在 kubelet 的一刀切映射，呈现权在监控的聚合函数。应用与 on-call 手里只剩一个**代理指标**（进程 RSS）。**只要观测口径与判据口径不是同一个口径，这一大类故障就必然表现为：没有凶手、曲线很平、位置随机、重启即愈。**

这正是 `software` 节点类根的实例化——"某个本该由应用掌握的控制权被外部机制代持，于是失败发生在应用能打日志之前"：在这里，被代持的是**"我的内存为什么被判越界的解释权"**。

**└ 个例根（本次到底是哪一个）**——四个候选全部挂在上面这个类根下，都是子节点，不是平行清单：

- **个例根 a（节点级全局 OOM 的随机受害者）**：真凶是节点上不可回收的内核内存（`slab`／`sock`／`nf_conntrack`）或另一个 pod 的瞬时尖峰；全局 killer 按 badness 挑中了一个只有几 MB 的容器；kubelet 把它记成 `OOMKilled`。这一支**唯一能同时解释四个症状**：凶手不在本 pod（查不到）、真凶的曲线在被杀 pod 的图上（曲线平）、受害者随节点负载漂移（位置随机）、重启后节点水位与排序被重置（重启即愈）。
- **个例根 b（记账在 cgroup，不在进程）**：本 pod 自己把内存顶到 limit，但顶上去的是 **shmem／tmpfs／`/dev/shm`**（v1 下无 swap 时不可回收）或 **dirty page cache**；进程 RSS 与 working_set 平，`memory.usage_in_bytes` 满。重启清空 shmem／cache → "重启就好"。
- **个例根 c（page cache 顶到 limit）**：与 b 同构，只是对象是 file cache，通常可回收，需要 dirty/writeback 叠加才会真炸。定为**共因**。
- **个例根 d（观测口径）**：均值聚合 + 采样间隔吞掉尖峰。只能解释"看不见"，**不能解释"被杀"**，定为**次要**，但它决定了你为什么至今没归因。

**为什么"重启就好"是关键指纹**：重启重置的不是代码，是三样**计数器**——cgroup 的记账对象（shmem／cache／slab 归属被释放）、该容器在 oom_score 排序里的位置、以及它与邻居 pod 的相对占用关系。**"重启即愈"是记账型／竞争型故障的指纹，不是代码缺陷型故障的指纹**（后者重启后会在同一周期重现，且会 40 台全中）。

**量级自检（交 📐 定量，这里只给推导）**：40 台 × 每 3–5 天 1–2 起 ≈ 每天 0.3–0.6 起 ≈ 单机每天 1% 量级、每年 3 次量级。这条曲线的形状是"低概率、全局共享资源、受害者随机"的泊松样分布；**确定性的代码缺陷不会长成这个形状**（它会集中在少数机器或全集群爆发，且与部署版本强相关）。

**轴的自我否证条件（必写）**：若六格全部干净——`memory.stat` 各分项平、`memory.events` 无 `oom_kill`、节点 dmesg 无 `Out of memory` 行——而 `OOMKilled` 仍出现，则**不是轴选错，是"OOMKilled 这个标签本身不可信"**（可能是外部 SIGKILL、驱逐、runtime 误标）⇒ 换轴到"标签可信度"重切。

## L3 双根

**处置根（修本次：把归因从"进程"搬到"cgroup + 内核"，一次现场即可定死 a/b/c）**

1. **先验标签**：`kubectl get pod -o yaml` 看 `lastState.terminated.reason`=OOMKilled 与 `exitCode`=137；同时**必须在事件后尽快**（cache/slab 会被回收，窗口约 30 分钟）在被杀 pod 所在节点取：
2. **验 cgroup 级**：`/sys/fs/cgroup/<cg>/memory.events`（`oom`／`oom_kill` 计数）或 v1 的 `memory.oom_control`（`under_oom`／`oom_kill`），以及 `memory.usage_in_bytes` vs `memory.limit_in_bytes`；
3. **验记账对象**：`memory.stat` 分项——`anon` / `file` / `shmem` / `sock` / `kernel` / `slab` / `kernel_stack`。**`anon` 平而 `shmem`／`slab`／`sock` 高，即个例根 b/a 成立**；
4. **验节点级**：`dmesg -T | grep -iE "out of memory|oom"`——看 oom 行**有没有 `oom_memcg=`**（有＝cgroup 级；没有＝全局 killer，即 a），以及 `total-vm/anon-rss` 是否小得离谱（小 rss 被杀＝随机受害者的铁证）；辅以 `slabtop -o`、`/proc/meminfo` 的 `SReclaimable/Dirty/Writeback/Shmem`、`ss -m` 汇总、`nf_conntrack_count`；
5. **止血**：节点补 `system-reserved`/`kube-reserved` 与 `eviction-hard`（把不可回收内核内存纳入预算）；`/dev/shm` 一律 `emptyDir{medium:Memory,sizeLimit}` 顶上限；热点 pod 改 Guaranteed。

**消解根（灭这一类）**

> **让"内存越界"在结构上成为一次有主、有账、有判据、可复算的事件**——把判据权与观测权从"进程 RSS + 内核默认策略 + 均值聚合"移交给显式预算与分项记账。

- **不可发生判据**：若下列三项当时成立——①每个 cgroup 的 `memory.max` 显式且 `requests == limits`（Guaranteed 化），②节点的 `system-reserved/kube-reserved` 与 `eviction-hard` 显式覆盖 slab/sock/conntrack 等不可回收内核内存，③每个 137 事件自动携带 `memory.stat` 分项 + `memory.events` + dmesg 行才能闭环——则：(1) 任何 cgroup 越界必被自己杀，**受害者也必然是越界者**（全局 killer 挑无辜者的路径被关掉）；(2) 任何不可回收内核内存都有主、有预算、有采集（"没人吃内存"的路径被关掉）；(3) 任何 OOM 都自带分项现场（"曲线很平"的路径被关掉）。⇒ 本类问题的组合症状**在结构上不可能同时成立**：仍可能 OOM，但一定知道是谁、花了什么。
- **可执行首边（可以很小）**：在现网**一台**机器上把 cAdvisor 已有的 `container_memory_usage_bytes`／`working_set_bytes`／`memory.stat` 分项与 `memory.events` 接进监控并画出分项堆叠图，同时把 exit137 的告警 body 里塞入 `kubectl describe` 的 `lastState` 段。**当天可做**。
- **成本量级**：一次现场取证 = 分钟级；分项指标接线 = 小于 1 人日；全集群 Guaranteed 化 + reserved 预算 + 一轮容量重算 = 数十节点滚动配置变更，人日到人周级；cgroup v1→v2 迁移（若节点 OS 还是 v1）= 季度级。（精确定量交 📐 公式图，此处只给量级。）

## L4 迁移出口

消解根落到"把内存变成显式预算的资源"之后，**产生的新问题清单**：

1. **装箱率下降**：`requests` 抬高会让调度碎片化、出现 Pending，需要在 SLO 与成本之间重算出货比。
2. **容量规划模型重做**：原来靠"节点还剩多少"的经验值失效，必须按 reserved + 分项预算重新建模。
3. **page cache 被 limit 挤压**：热点读路径 IO 性能下降——要么给 file cache 显式留预算，要么外移到外部缓存层。
4. **可观测性与值班流程重写**：告警口径从"均值曲线"改成"分项 + 事件"，137 必须带现场才算闭环，值班手册与 on-call 训练同步改。
5. **cgroup v1→v2 的兼容与灰度**：kubelet、runtime、OS 层联调，按节点池灰度。

**→ 本次问题降级为：上面第 4 项（可观测性与归因闭环）里的一个子项——"OOMKilled 归因缺失"，而不再是独立的"神秘 OOM"。**

## 候选根排序（Share × Lever ÷ Cost，必须带预算）

| 层级 | 候选根 | Share | Lever | Cost | 序 |
|---|---|---|---|---|---|
| **类根** | 判据／记账／执行／归因权全被外部代持（记账含非进程对象 ＋ 全局 killer 挑人 ＋ 137 一刀切 ＋ 均值聚合） | **唯一**（四个症状只此一条能同时解释） | 改配置 + 改可观测性（可控） | 一次 `memory.stat` + 一次 dmesg = 分钟级 | 1 |
| 个例根 a | 节点级全局 OOM 的随机受害者 | 主因 | 改配置 | 一次节点 dmesg/memory.events 采样 | 2 |
| 个例根 b | shmem／tmpfs／`/dev/shm`／slab／sock 记账在 cgroup 而非 RSS | 主因 | 改配置 | 一次 `memory.stat` 分项采样 | 3 |
| 个例根 c | page cache／dirty 顶到 limit | 共因 | 改配置 | 同上（同一次采样即可分辨） | 4 |
| 个例根 d | 采样间隔 + 均值聚合吞掉尖峰 | 次要（只解释"看不见"） | 改配置 | 一次改 scrape interval | 5 |

**预算约束**：以上前三条**共用同一次现场采样**（`memory.stat` 分项 + `memory.events` + dmesg），所以本轮的实际预算是"一次事件 ← 一次取证"，不是五次。这正是"排序必须带预算"的意义：不做这个归并，清单会退化成五条并列猜测。

## 挂起表

| 分支 | 判定 | 依据 | 恢复条件（什么证据下推翻本行） |
|---|---|---|---|
| 应用真的内存泄漏（进程 RSS 真有峰） | ⊥ 排除（个例根层面） | 题面"查不到任何进程真的吃了内存 + 曲线很平"；且 40 台同一镜像若代码泄漏，应 40 台全中、`anon` 单调增长、重启后按同周期重现，与"位置漂移"矛盾 | `memory.stat` 的 `anon` 分项确认单调增长且与 3–5 天周期同步 ⇒ 恢复为该支的根 |
| 磁盘／overlay 写放大、镜像层体积 | ⊥ 排除 | 症状是 `OOMKilled` 而非 `Evicted(DiskPressure)`；且磁盘型不会"重启就好" | `memory.stat` 的 `file`/`dirty` 分项与写路径强相关且重启后按同速率回升 ⇒ 恢复 |
| 硬件内存故障（ECC／坏条） | ⊥ 排除（按 `software.md` 排除项） | 症状不跨进程一致、无 CRC/ECC 日志；物理故障不会"重启就好" | dmesg 出现 MCE/EDAC，且同机多 pod 同时异常 ⇒ 恢复，转 `hardware` 节点（树外分支，索引中为待建） |
| 网络／conntrack 表满 | ⊥ 部分排除 | conntrack 满的主症状是丢包/超时，不是 137 | 但 `nf_conntrack_count` 达上限且 `memory.stat` 的 `sock`/`slab` 同步涨 ⇒ 恢复为层2 的"消耗归属"支（不是根，是消耗来源） |
| 权限／账号体系 | ⊥ 排除 | 无拒绝访问类症状，容器内路径一致 | 无 |
| 组织流程（容量预算无人负责） | ⊥ 挂起（非本次根，但是消解根的成本来源） | `system-reserved`/`eviction-hard` 长期无人维护，才让随机 OOM 至今没被归因 | 若查证 reserved/eviction 确实长期空缺 ⇒ 恢复为**共因**，且提高消解根的优先级 |
| 监控 relabel 合并维度／采样过稀 | ⊥ 挂起为"观测共因" | 只能解释"看不见"，不能解释"被杀"；作用是掩盖而非致害 | 改口径后曲线仍平而 OOM 仍在 ⇒ 提升为主因，重切到观测轴 |
| **树外分支**：`hardware`、`org-process`（索引中标注"待建"） | 登记，不静默丢弃 | 本次用不到节点文件，但两个大类都被触及 | 需 `v2` 建节点时再核查 |
| **`v2` 候选节点：`container-memory-accounting`** | 登记（本次回溯必用而树里没有） | `software.md` 的 `quota` 子层只覆盖"受限上下文的配额比交互式小"，**不覆盖"记账口径"与"判据权归属"**；本次的根正好落在这一空白上 | 理由成立即可升版本：判据＝"故障的字节数不出现在任何进程 RSS 里"；典型根＝shmem/slab/sock/page cache/全局 killer 随机受害者 |
| kubelet 一刀切 `OOMKilled` 归因 | ⊥ 不是根，是**抹平器**（层5） | 它不产生 OOM，只销毁区分度 | 若确认 `reason` 与 `memory.events` 计数不一致（有 reason 无 oom_kill）⇒ 恢复为独立的"归因缺陷"支 |

## 结论

**根源不在某个进程里，在"谁有权判你内存越界"这件事被代持了。** 你被杀，是因为有人替你越了界：要么是节点上不可回收的内核内存／别的 pod 的瞬时尖峰把全局 oom-killer 逼出手，它按 badness 挑了个无辜的小进程（位置随机、查不到凶手、真凶的曲线不在你那张图上）；要么是你自己把 cgroup 的内存顶满了，但顶上去的是 shmem/tmpfs/dirty cache 这类**不进进程 RSS** 的对象。kubelet 把所有 SIGKILL 一刀切成 `OOMKilled`，监控把分项均值成一条平线——所以这个故障在结构上必然长成"**没有凶手、曲线很平、位置随机、重启即愈**"。**"重启就好"是记账型故障的指纹：被清零的是计数器，不是 bug。**

**修本次**：事件后 30 分钟内在节点取一次 `memory.stat` 分项 + `memory.events` + dmesg 的 oom 行，三个候选当场分完。**灭这一类**：让内存越界变成有主、有账、有判据、可复算的事件（Guaranteed 化 + 节点 reserved/eviction 显式化 + shmem 顶上限 + 137 必须带分项现场）——那时仍会 OOM，但永远不会再出现"不知道是谁"。

## [✅ 验证]

本题是纯题面推理，**未执行任何现场取证**（按约束不检索本机来"复现"题面）。上面所有判定都写成了**可被一次现场推翻**的形式，验证动作即 L3 处置根第 1–4 步；判据是：`anon` 平而 `shmem/slab/sock` 高 ⇒ b/a；dmesg oom 行无 `oom_memcg=` 且被杀进程 rss 极小 ⇒ a；有 `oom_memcg=` 且 = 该容器 ⇒ b/c。

## [⚠️ 异常／矛盾／空白]

1. ⚠️ **题面信息不足以在 a / b 之间定死**。两者症状完全同构（都是"无凶手 + 曲线平 + 随机 + 重启愈"），只能靠一次现场分项采样消歧。这不是推理缺陷，是本类故障的结构性质——所以我把它们并列为同一类根下的两个个例根，而不是二选一猜一个。
2. ⚠️ **"内存曲线很平"存在两种互斥解释**（真凶不在你的图上／尖峰被聚合吞掉），两者可叠加，但归因动作不同：前者要改**对象维度**（看 cgroup 分项与节点内核内存），后者要改**时间维度**（缩采样间隔）。题面没给监控的抓取间隔与聚合函数，这一步必须补数据。
3. ⚠️ **cgroup v1 / v2 未声明**：`memory.events`（v2）与 `memory.oom_control`（v1）路径不同，`memory.max`（v2）与 `memory.limit_in_bytes`（v1）语义也有差异。取证命令需按实际版本选，这一步不能靠猜。
4. ⚠️ **空白点**：题面未说明这 40 台是否同构（OS 版本、cgroup 版本、swap 开关、节点规格是否一致）。若不同构，则层3 的"节点配置偏差钉死位置"这条排除依据需要重新核对——但题面的"位置随机漂移"已强烈支持同构假设。

## [💡 灵感备注]

这类"找不到凶手"的问题有一个通用指纹：**故障的量纲与观测的量纲不一致**。你在看"进程的字节数"，而判据在"cgroup 的字节数"，执行在"badness 的排序"，归因在"退出码的映射表"——四层量纲四层错位。凡遇到"现象确定存在但所有监控都干净"，第一动作不是加大采样频率，而是**找出判据那一侧到底读的是哪个变量**。这条比本题的答案更耐用。

[技能] forest-hierarchical-backtracking
