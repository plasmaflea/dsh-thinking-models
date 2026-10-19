# 变更记录

格式：Keep a Changelog；版本号：语义化 `0.x`（技能还在大改阶段）。

**标签是 2026-10-18 补打的**：本仓库前 18 个提交当时没有打标签，v0.1.0 / v0.2.0 指向的是历史提交（哈希写在下面），v0.3.0 指向当时的 HEAD。历史没有改写。

## [0.10.0] - 2026-10-19

### Added
- **`forest-hierarchical-backtracking` §11 重点保全（五句可机械执行的话）**：题面冻结（原话逐字抄，不许改写）／删掉检验（删掉这段推理，结论变不变）＋补丁（删掉它会不会让某个**错**的结论变得可信）／分支预算（并行线 ≤ 3）／类型分叉（问「为什么」时结论第一句必须是题面直接回答，方案类标「以下是推论，不是你所问」）／每三支回读。核心不是加规则，是**把不可判的问题（「这重要吗」）换成可判的问题（「删了结论变吗」）**。
- **§12 标注义务**：①根的类型必须标 `发生`／`维持`／`杠杆`／`归责`（「中段能不能当根」的争论由此消解）②凡涉及参与者必须给**可选集**（有效竞争／被迫竞争／被裹挟）③分类是**约束不是入口**——L0 判一次就全量沿用会把分区属性碾平。
- **§13 知识树取用补充**：知识树 v2 起有族轴（决定轴，不可缺）与域轴（给症状与先例，可缺），取树先判族，不按题面主题词。

### Changed
- **输出骨架 v2**：新增「题面（逐字冻结）」「每格必写症状」「根类型标注」「可选集」「结论第一句必须是题面冻结句的直接回答」。
- 起因（实测缺陷，非优化）：一次关于「教育制度的问题根源」的多轮作答里，同一个执行体在分支最多的两轮漏条款最多（没写症状、没写类根、没标「已换题」），在收敛成一主轴的轮次执行最全；且把提问者的「为什么」答成了「怎么办」——**五层骨架的 L3／L4 是必填层，问「为什么」也会长成「改制度」**。§11 的机制 4 就是补这个结构性偏向。

### Notes
- 配套常量库 `dsh-thinking-models-constants` **1.1.0**：认知树 v1→v2（补族轴 + 首个族节点 `rationing` + 根四型 + 判类三道闸门 + 否决「树里加权重」）。`tree/` 副本已同步至 v2。

## [0.9.3] - 2026-10-19

### Added
- **`scripts/verify-install.ps1` / `.cmd`——空房校验**：`git clone --depth 1` 仓库（或 `-Ref <tag>`）到临时目录，与本机安装位逐文件 SHA256 比对，同时反向检查「本机多出、仓库里没有」的文件（那才是清空重装会丢的知识）。`0` = 一致，`1` = 有漂移，`2` = 参数/环境问题。默认安装位 `$env:USERPROFILE\.dsh\skills`，可用 `-InstallDir` / `DSH_THINKING_INSTALL_DIR` 覆盖。

### Changed
- `README` 仓库结构、`STATE.md` 文件地图与改技能流程（第 3 步验证）补入该脚本；发版后增加一道 `verify-install.cmd -Ref vX.Y.Z`。

### Notes
- 起因：一次真实的「删光安装位 → 从 GitHub 重装」操作，23 个文件逐字节复现；这条流程因此固化为脚本，用来在发版前证明公开仓库装得出完整的一套。
- 实测：默认分支与 `v0.9.2` 标签均通过（23 文件）；`v0.8.0` 标签正确报出 `web-association-exhaustive` 缺 `tree/` 三件套（本地独有 3 文件、4 个 SKILL.md 内容不同），证明检查器能抓到真实缺口。

## [0.9.2] - 2026-10-19

### Changed
- **取树路径去机器化**：`forest-hierarchical-backtracking/SKILL.md` §0.1 第 2 条与 `structure-isomorphism-pointmass-substitution/SKILL.md` §0.1 第 2 条，不再把 `C:\Users\Administrator\...` 当作默认路径示例，改为「`<技能目录>` 取 `skill` 工具输出的 `Base directory for this skill:`，**用它拼路径，不要照抄示例**」。外部读者不再看到别人机器上的绝对路径。
- **README 安装节**补一句：`tree/` 随技能目录一起安装，装技能即拿到三张图的常量表，**不需要另装常量库**；并新增「5. 常量库（只有要改表的人才需要）」，给出 clone + `sync.cmd` / `state.cmd -Verify` 用法与「副本只读」的方向说明。

### Notes
- 配套：常量库 [`dsh-thinking-models-constants`](https://github.com/plasmaflea/dsh-thinking-models-constants) 1.0.1（脚本去掉写死的本机路径、`state.cmd` 版本行修复）。两个仓库各自打标签，互不依赖。

## [0.9.1] - 2026-10-19

### Added
- **常量层独立成库**：[`dsh-thinking-models-constants`](https://github.com/plasmaflea/dsh-thinking-models-constants) v1.0.0——认知树（v1，3 节点）／关系表（v1，新建）／结构表（v2.4，13 文件），各带 `vN` 与核查日期；配 `scripts/sync.cmd`（三库 → 本仓库 `tree/` + 安装位，`-Check` 只比对）与 `scripts/state.cmd`（仓库／库／副本三方体检）。
- `web-association-exhaustive/tree/`：**关系表常量**（九类关系、远近步数、秩矩阵、两条硬规则、校准记录模板）。此前网状图是三张图里唯一没有常量表的。
- `web-association-exhaustive/SKILL.md` §2.1 末：指向常量库 `tree/relations.md`，声明「与库冲突以库为准，改表去改库」。
- `AGENTS.md` 新增规则 18「常量库是唯一真相源」；规则 11、15 的取树路径加 ⓪ 常量库。

### Changed
- `README.md` 仓库结构：补 `forest tree/`、`web tree/` 两行，并写明「`<id>/tree/` 是副本、真相源在常量库、改常量跑 sync.cmd」。
- `STATE.md`：真相源分两级（常量库／本仓库）；同步命令改为 `sync.cmd` + 手工 SKILL.md；改流程第 1–2 步与约束第 8 条同步。

### Fixed
- 常量库 `scripts/state.cmd -Verify` 的版本行取错（取到用法说明那一行）——改为锚定 `版本**：`。

## [0.9.0] - 2026-10-19

### Added
- `forest-hierarchical-backtracking/SKILL.md`：**§0.3 建树／校树：定义 → 分类 → 概念拆解**（L0→L1 的入口）。双档——快档每轮把题面关键词对回既有节点、口径未变即过；慢档走 定义→分类→拆解→登记 四步，产物登记 `v(N+1)` 候选。三条边界：定义只写事实不写价值、描述性定义 ≠ 规定性定义、分类必须补穷尽性（兜底格）。附三条反模式与「与 §4 的分工」。
- `web-association-exhaustive/SKILL.md`：**§2.1 权重是一个刻度，不是一堆数字**——关联边（无向）与支持边（有向）分栏；`权重 = 关系类型（强度上限）× 机制步数（衰减）`；9 类关系类型表（1 步／2 步／≥3 步）；两条硬规则（同题单尺、跨题不比较；不相干须写阈值）；权重只排序、不当概率；交付须附边表。`description` 同步由「物理距离与关联度」改为「关系类型与机制步数」。
- `AGENTS.md`：规则 15 补「第 0.5 步：建树／校树」及三条边界；新增规则 17「权重只排序，不当概率」。

### Changed
- `presupposed-answer-hypothesis-backderivation/SKILL.md`：**与三种逻辑模型完全隔离**。删除「与三个正式模型的关系」整节（含「第四个回答模式」「负边审计器」「三张图跨的是同一条线」「纠正目标指向穷举法／林状法／结构图」等全部表述）；六种走形的「纠正目标」列改为通用「纠正动作」列（补全假设集／证伪先行／反例优先／判据写死／假设表分栏／来源独立）；新增「独立性：不与其他任何方法耦合」，把「零接口」写成可执行禁令（正文、示例、变更记录不得出现任何方法名与图名）；风险表加第 5 条。
- `examples/presupposed-answer-hypothesis-backderivation.md`：纠正映射由指向模型改为指向通用动作（判据写死／补全假设集／来源独立）。
- `README.md`：第四技能改为「独立运作、不依赖前三者」；「四种动作」改为三图共用骨架＋结构图差异说明（修复 README 与 `web` 正文动作清单不一致）；设计取舍新增「第 0 步在建树之前」「权重是刻度的读数」两条。
- `AGENTS.md` 规则 13：审计对象由「三张图交付前」改为「任何带结论的推理交付前」，并声明倒推法独立运作。
- `STATE.md`：当前版本 0.9.0；文件地图同步结构库 v2.4（12 基 + 2 修饰 + 复合表，12 个节点）。

### Fixed
- `README.md` 版本号停留在 v0.6.0（实际已 0.8.0）、`STATE.md` 同步——两处均改到 0.9.0。
- `v0.8.0` 标签此前未打：本次一并补打于 `b5c557c`（当时 `VERSION` / `CHANGELOG` 已到 0.8.0）。
- `scripts/state.cmd`：装过 PowerShell 7 的机器上 `-Verify` 必失败——`powershell.exe`（5.1）会到 PS7 的模块目录里找 `Microsoft.PowerShell.Utility`，`Get-FileHash` 因此「不是 cmdlet」。改为有 `pwsh` 用 `pwsh`、没有才回退 5.1。

## [0.8.0] - 2026-10-18

### Changed
- **术语：「挂牌」→「明示／默示」**。明示＝写下来、可被外部检查；不写即默示——**默示 `G` 对持有者有效、对外部不可审计**。依据：术语的价值在**失败态有没有名字**；「未挂牌」只说漏了一步，「默示 `G`」说出错在"用了一个别人看不见却已生效的目标"（法律同构：默示条款有约束力，但不能对抗不知情的第三人）。`挂牌` 留作别名。`AGENTS.md` 与 `structure-tree/index.md` 中的「降级挂牌」「类比挂牌」两处**语义不同，保留原词**。
- `AGENTS.md`「模式选择速查」由触发词列举改为**五问路由表**（是什么／为什么／有哪些／会怎样／怎么办）。原「五问（WWH 的补全）」条从「推理元规则」移出——**路由表是界面，三模式是内核，界面不焊进内核**；判据：内核的标志是单义，而第 5 问「怎么办」有歧义槽（锁现状 `G` vs 改 `G`）。

### Added
- `AGENTS.md`「立场方式」条：三作答模式对立场的规定**不同且不可混用**（🌳 锁一个／🕸️ 并列全列／📐 锁一个 + 校验执行者同向性）；事实层可中立、处置层必锁；`G` 可见度分级（已内嵌／已公开／未声明）；消解二分解（重定义边界 vs 改 `G`）。
- `AGENTS.md`「定义力的边界」条：定义只能消解**定义病**，不能消解**约束病**（配额／资源／不可逆）。
- `tree/index.md` → **v2.4**：标题版本号与「树版本」对齐（此前标题写 v2.1、树版本写 v2.3），`[G 锁定]` → `[G 明示]`。
- `structure-isomorphism-pointmass-substitution/SKILL.md`：**§0.3 先例检索**（T1／T2／T3，必答，允许跨域）、**§0.4 `G` 明示**（第四校验＝`G` 同向性）、**§0.5 结构图内禁止消解**（只许重定义边界）。
- `forest-hierarchical-backtracking/SKILL.md`：**§6.1 消解根落在哪一层**——类根/因果链属事实层，处置根/消解根属处置层。
- `web-association-exhaustive/SKILL.md`：新增「立场：并列全列，不锁一个」；穷举表固定列与输出骨架加**持有者**列。
- `presupposed-answer-hypothesis-backderivation/SKILL.md`：新增「守 is–ought 线：查 `G` 是否被偷换」。
- `structure-isomorphism-pointmass-substitution/tree/`：结构模式库由 **v1**（6 个「量」结构）升到 **v2.4**（12 基＝量六＋质六，2 修饰，3 组合规则，复合表，先例检索），12 个节点与索引同目录；索引内写死的安装位绝对路径 `C:\Users\...` 改为相对文件名——此前别的机器上必然断链。`README.md` 的仓库结构同步更新。
- `scripts/sync-tree.ps1`：结构库三份拷贝（工作区源 → 仓库 `tree/` → 安装位 `tree/`）的**单向同步**。同步前过三道闸（索引存在／节点 ≥ 12／索引无机器绝对路径与「同上目录」），通过才写盘；`-Check` 只比对、有漂移 exit 1，可做提交前检查；只增改不删除，目标多出的文件只告警。

### Fixed
- 全仓 5 处 `2026-10-19`（比当天晚一天，未来日期）改为 `2026-10-18`：CHANGELOG 的 0.5.0／0.6.0／0.7.0 三条版本头、`docs/benchmark/README.md` 的 T6 标题、`examples/structure-isomorphism-pointmass-substitution.md` 的核查日期。

## [0.7.0] - 2026-10-18（本提交）

### Changed（Breaking）
- **第三个技能再次改名**：`structure-isomorphism-substitution`（结构同构代入法）→ **`structure-isomorphism-pointmass-substitution`**（**结构同构质点代入法**；简称仍是 **结构图**（产物）／**代入法**（动作））。旧 id 作废，安装位与 DSH 技能仓库需重新扫描。
- id 段数由 3 个 token 变 4 个，依据是「id 逐词直译中文全称」——与 `presupposed-answer-hypothesis-backderivation`（"预设答案"一段译两词）同例。「同构质点」是一段两词，故 4 token 仍是三段。

### Rationale
- 四个技能全称字数原先 9／9／9／**7**，第三个独短：核心限定段只剩"同构"一个词，比另三个薄一截。补"质点"后 9／9／9／**9**，段密度对齐。
- "质点"承重：只写"结构同构"易被读成「长得像就照抄答案」；写明质点，强制那句"先压成单自由度、并声明砍掉了什么"，正是被砍自由度回收判据的入口。
- 不删 `v0.6.0` 标签、不抹历史：0.6.0 按当时事实保留（仅修正当时写错的 tree 文件清单）。
## [0.6.0] - 2026-10-18（本提交）

### Changed（Breaking）
- **第三个技能改名**：`formula-pointmass-substitution`（经验公式质点代入法／公式图）→ `structure-isomorphism-substitution`（**结构同构代入法**／**结构图**；动作名「代入法」不变）。旧 id 作废，安装位与 DSH 技能仓库需重新扫描。（**注：该 id 在 0.7.0 再次改名为 `structure-isomorphism-pointmass-substitution`，本条按当时事实保留。**）

### Added
- `tree/`：**结构模式库 v1**（`index.md` + `multiplicative-rate` + `additive-budget` + `queue-capacity` + `saturation` + `conservation` + `power-scale`），每个模式的字段是 结构式／成立条件／变量映射／已知边界／失效点／典型量级。
- SKILL.md 新增五构件：命中模式（id + 出处）／边界包含性（四条判据）／被砍自由度回收判据／回补路径／跨域迁移落点；丢参行为一律进挂起表。

### Rationale
- 用户把代入法的目的重述为「**把未知问题转化成已处理过的问题**」。按此标准，旧版只是"选个公式代进去"，缺三个构件——结构映射、边界包含性校验、跨域迁移——那等于编数。
- 同结构问题可否复用同一方案？**可以，但只在边界包含时**；被砍自由度恰好是另一模式的核心自由度时必须回补（例：库存模型砍掉利用率 ⇒ 漏掉排队项与尾延迟）。
- 故重心从「经验公式」移到「**结构模式库**」：库是常量（与知识树同构），每轮实例化 + 边界校验；库里没有的问题登记 v2 候选，不许硬套最近的模式。
## [0.5.0] - 2026-10-18（本提交）

### Added
- `docs/benchmark/runs/T6/`：**T6（三真根并列，带注入真值）**——题面 `prompts.md`、预注册口径 `rubric-preregistered.md`、结果 `results.md`，10 份原文在 `outputs/A`（装技能）与 `outputs/B`（无技能）。
- 注入环境 `lab-t6/`（`service.js` + `load.js`）：三个真根手工注入——R1 查库存跨 `await` 的读-改-写、R2 DB 超时 200ms < SKU_B 查询 300ms 且扣减早于预留、R3 每请求 `audit.on('paid')` 从不移除且闭包持有 64KB。

### Result
- **预注册五项判定平手**：真根召回 **15/15 vs 15/15**、并列声明 5/5 vs 5/5、区分实验 5/5 vs 5/5、误并 **0/5 vs 0/5**、修复独立性 5/5 vs 5/5。两组都自发多找到题面未写的第四处（扣减早于预留、失败不回滚）。
- **差异全在槽位**（事后关键词计数，不在预注册口径内）：`类根` 5/5 vs **0/5**、`消解根` 5/5 vs **0/5**、`L4/迁移出口` 5/5 vs 1/5、`挂起表` 5/5 vs **0/5**、`不可发生判据` 5/5 vs **0/5**。
- **代价**：字符中位 +23%（11667 vs 9554）、表格数据行中位 **+152%**（50 vs 19）、行数中位 −21%（187 vs 238，散文被压进表格）。
- **反例**：允许读安装位时，无技能 agent 会直接读磁盘上的 `SKILL.md` 并照其流程产出 ⇒ 技能开关只切断「目录可见性」，不切断「文件可取性」（该份作废，留档 `outputs/B-contaminated-agent-b.md`）。

## [0.4.4] - 2026-10-18

### Added
- `docs/benchmark/stress/r2/`：**同一四题重跑一遍**（R2），20 份原文 + `results.md` + 预注册口径 `rubric-preregistered.md`（= 发题前写定的 `rubric-v2.md`）。

### Result
- **主判定可复现**：4/4 题与 R1 份数差为 0，四题再次全饱和（主判定 5/5 × 4）。
- **机械判分不可复现**：T8 的 K1 用同一正则，R1 数出 5/5、R2 数出 0/5，而人工两轮都是 5/5 ⇒ 机械项复现的是写作风格，不是判断力。
- 作者埋设的 T8 真根（"limit 按 P50"）两轮合计命中 **0/10**，10 份全部落到更深的一层"记账域 ≠ 观测域"（K5 67–123 次/份）。
- 结构：字符中位 T7 −6.6% / T8 **+27.3%** / T9 +5.4% / T10 +1.4%；单题内极差最高 1.89×。

## [0.4.3] - 2026-10-18（`41562fb`）

### Added
- `docs/benchmark/stress/`：**T7–T10 压力题第一轮**（4 题 × 5 份 = 20 份）+ `results.md` + 各题 `rubric-preregistered.md`。
- `scripts/measure-kw.ps1` / `.cmd`：预注册关键词计数器。

### Result
- 四题**全部饱和**；同时暴露三处判分缺陷：K1 词表漏检、K4 只数"提及"不判"主张"、预设真根只能测作者想到的答案。
- 方法论结论：纯文本题的机械判分只对"违规/守规"有效，要判"更好"必须回到注入真值。
## [0.4.2] - 2026-10-18（本提交）

### Added
- `docs/benchmark/t5/`：**技能 vs 裸机的 A/B 对照**（题面 5 · 证据不足），每条件 5 份、共 10 份原文 + `results.md` + 预注册口径 `rubric-preregistered.md`。
- `scripts/measure-t5.ps1`：三项机械指标（M1 声明不可辨识 / M2 排除项条数 / M3 带判据下一步）的计数器。

### Result
- **M2 是本轮唯一无歧义的差异**：before 中位 3（1–3），after 中位 16（6–19），区间不重叠。
- **M1 方向为正但未达阈值**：1/5 → 3/5（预注册要求「仅 B 组 ≥4/5」才算有效）⇒ 不写成「技能让模型更诚实」。
- **M3 两组都 5/5 ⇒ 该指标作废**。
- 关键发现：`1−(1−p)²≈2p`、`F−R` 拆解、ρ/(1−ρ)、Little's law 这些**方法内核在裸机组也全部自己出现** ⇒ 此前归功于技能的能力，实际是模型先验；技能改的是记账方式（挂起表、排序、五层），不是推理本身。

## [0.4.1] - 2026-10-18（本提交）

### Changed
- **对照组开关改为 Skills Manager 停用策略**（`scripts\bench-before.ps1` 重写）。旧版把 `~/.dsh/skills` 下每个技能目录 `Move-Item` 到 `skills.off\`；新版只写 `<DSH_HOME>\skills-manager\state.json` 的 `disabledSkills.dsh`，不动磁盘文件，也不再受「skills 根目录被 DSH 监听句柄占住、无法整体改名」的约束。给了 `-Port` 就顺带调 `POST /api/dsh-skills-manager/{disable,enable}`，让**运行中**的服务器热刷新技能目录。
- 记录单（`bench-before-record-<时间戳>.md`）从 4 题扩到 5 题，新增题面 5（证据不足、多嫌疑不可分离）与「是否声明无法辨识」一行。

### Verified（实测，非推断）
- 停用 4 个思考类技能后，当前会话的 `available_skills` **立刻**只剩 5 个（office-docx/pptx/xlsx + diagnose-windows-sandbox-acl + hindsight-coding-agent）；`-Restore` 后 9 个全部回来。两个方向都验过。
- 不带 `-Port` 的纯文件路径同样有效：`state.json` 写完后 `disabledSkills.dsh` 有 4 项、其余源为 `[]`，新进程启动即按此策略构建目录。
- 关不掉的边界：office-× 3 与 diagnose-windows-sandbox-acl 来自 DSH 内置 runtime，不在 `state.json` 的任何源里；hindsight-coding-agent 属 `agents` 源，需 `-AlsoAgents`。

### 修掉的两个自身 bug
- **`ConvertTo-Json` 把空数组写成 `{}`**：PowerShell 5.1 序列化有序字典时，`@()` 会变成 `{}`，插件 `validManagerStateDocument()` 判文档非法 ⇒ 接口一律回 400、技能目录静默失效。改为手工拼 JSON，并在落盘前用正则确认每个源的值都以 `[` 开头。
- **写前自检误判单元素数组**：`ConvertFrom-Json` 会把单元素数组解包成字符串，最初的类型检查因此误报。已放宽为「字符串或数组都合法，只拒绝 PSCustomObject」。

## [0.4.0] - 2026-10-18（本提交）

### Changed
- **林状图知识树加载从「建议」改为六步硬规则**：默认树路径写死成绝对路径 `C:\Users\Administrator\.dsh\skills\forest-hierarchical-backtracking\tree\index.md`；工作区 `knowledge-tree/index.md` 不存在**是正常情况**，明令「不许据此宣布知识树不存在」；三处都读不到才允许降级，且必须在正文首行挂牌 `[⚠️ 知识树未加载：试过 <路径>]`；四元组增加 `路径` 字段并加一句「**写不出真实路径就不要写版本号**」；`L0 类别判定必须显式一行`；树里没有的分支**必须先登记进挂起表再往下推**。触发原因是 T2 里 3/5 份把加载失败写成「知识树不存在」，2/5 份漏了 L0。
- `AGENTS.md` 规则 15 同步重写。

### Added
- `docs/benchmark/runs/T1/`、`runs/T2/`、`runs/T3/`：三轮压力测试的题面、预注册 rubric、产物与结果全部入库（T1 = D5 假证据、T2 = D2 层间撞车、T3 = D10' 数据退化）。

### 已知问题
- VERSION 曾在 T2 提交时被推到 `0.3.4`，但没有对应 CHANGELOG 条目与标签 ⇒ 本次一次性并入 `0.4.0`，`0.3.3`／`0.3.4` 两个版本号作废不用。
- **S2 短板待补**：T3 五份里 0 份把「两个变更同分钟、无对照」升级成结论置信上限，都在**用可分解性冒充可辨识性**。v0.5.0 需在技能里加一条硬规则（见 `docs/benchmark/runs/T3/results.md` §5.2）。

## [0.3.2] - 2026-10-18（本提交）

### Added
- `docs/benchmark/injection-sxs.md`：用 `csc /win32manifest` 做**真实注入**，证明 SxS／清单失败是 `CreateProcess` 失败（Win32 14001 = `0x36B1`）、进程根本不会被创建，与 `0xC0000142` 分属不同层；追加实测还推翻了旧题面「日志全空」的前提——真实注入会产生 `SideBySide` 源 Event 33，并把缺失的 identity 五个字段直接印出来
- `docs/benchmark/rubric-g3alt.md`：跑前定死的八因子 + 两个主指标（**分水岭命中** F2 ／ **误并家族**）
- `docs/benchmark/g3alt-results.md` 与 `docs/benchmark/after-g3alt/`：n=5 盲跑，5/5 命中分水岭、0/5 误并 `0xC0000142` 家族、均分 7.8/8

### Changed
- **评分口径更正**：8 因子表中的「⑦ SxS 配置错误」不能直接产生 `0xC0000142`。剔掉 ⑦ 后 v2／v3／裸机的真因覆盖率为 6/7、7/7、7/7——旧 8 因子分母不可再用，论文须如实写明
- `docs/benchmark/stress.md` 的 G3 已执行并改写为 G3-alt（SxS 题面）
## [0.3.1] - 2026-10-18（`c7bdffd`）

### Added
- `docs/benchmark/stress.md`：林状图极限探测题集——4 个难度因子（生成源可得性／根唯一性／树覆盖度／验证可得性）+ 12 题四组（破坏 F1／破坏前提→反顺从／破坏 F2 多根循环时变／破坏 F4 无数据与规模）+ 反退化三项（套话／顺从／诚实）+ G 组故障注入三例（NSSM 路径、共享端口 flake、SxS 清单）——**全部未执行**
## [0.3.0] - 2026-10-18（`50d3547`）

林状图 v4：把「根」从个例上移到大类。

### Added
- `docs/benchmark/rubric-v4.md`：10 项判定口径（L0 类别判定 / L1 树实例化 / L1b 树外分支登记 / L2 类根 / L2b 父子结构 / L3 处置根 / L3b 消解根+不可发生判据 / L3c 首边+成本 / L4 迁移出口 / 挂起表四列）
- `forest-hierarchical-backtracking/tree/`：常量知识树 `index.md`、`software.md`、`win-service.md`（v1）
- `docs/benchmark/after-v4/task5.md`：全新题面（CI 上约 1/7 偶发红）的验证产物，10/10 结构项
- `VERSION`、`CHANGELOG.md`、`STATE.md`、`scripts/state.ps1` + `state.cmd`

### Changed
- `forest-hierarchical-backtracking/SKILL.md` 五层骨架：L0 → L1 → L2 → L3（双根：处置根／消解根 + 三道闸门）→ L4（迁移出口，本次问题降级为清单中一项）
- 回溯的根从「个例根」上移到「类根」；个例根成为类根的子节点
- 消解根必须过三闸门：不可发生判据 / 可执行首边 / 成本量级，缺一降级为挂起

## [0.2.0] - 2026-10-18（`f9206c8`）

### Added
- 第四个技能 `presupposed-answer-hypothesis-backderivation`（预设答案假设倒推法）——**反面教材型审计器，不作答**
- `docs/paper/pipeline.md`：把 25 阶段论文流水线映射到本项目（保留 12 / 改写 5 / 5 条红线 / 自补 3 缺口）
- 姊妹仓库 `dsh-ordinary-thinking`（模拟版，研究普通人思维本身）

### Changed
- README 增加「第四张图：倒推图」整节与命名结构对照表；AGENTS.md 增加核心规则 13（交付前过六种走形）

## [0.1.0] - 2026-10-18（`2f8221b`）

### Added
- 三个作答技能：林状分层分类回溯法 / 网状线索关联穷举法 / 经验公式质点代入法
- 技能 id 定为中文全称的逐段直译（图名·核心限定·法名）
- 三套关系语法（纵向因果 / 横向带权 / 定量函数）与四种动作（选轴→定语法→配对完整→挂起）
- `examples/` 三份按新骨架重写；MIT 许可

### Breaking
- 技能 id 从英文意译改为中文全称直译（`root-cause-forest` → `forest-hierarchical-backtracking` 等），旧目录已删
