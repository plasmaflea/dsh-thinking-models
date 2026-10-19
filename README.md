# DSH Thinking Models / 三种逻辑模型思维技能

三个可安装的 Agent 技能（`SKILL.md` 格式），把一个宽泛的「好好想一下」变成**可审计的产物**：林状图、网状图、结构图。外加第四个技能——一件**反面教材**：把「先有答案、再补理由」的走形摊开。它独立运作，不依赖也不引用前三者。

Three installable agent skills (SKILL.md format) that turn a vague "think harder" into **auditable artifacts**: a causation forest, a weighted association web, and a structural pattern matched against a known problem class — with a boundary check, not just a formula. A fourth skill is a deliberate **anti-pattern**: it audits an answer for presupposed-answer backtracking. It runs standalone and does not depend on the other three.

> **当前版本 v0.9.0**（`VERSION` / `v0.9.0` 标签）。接手、改、验、发的完整流程见 [STATE.md](STATE.md)；变更历史见 [CHANGELOG.md](CHANGELOG.md)。
>
> 这套方法从哪来、为什么坚持先画结构再下结论——见文末 [后记](#后记这套方法是怎么来的)。

| 全称 | 简称（产物／动作） | 技能 id | 产物 | 触发 |
|---|---|---|---|---|
| 🌳 林状分层分类回溯法 | **林状图** ／ **回溯法** | `forest-hierarchical-backtracking` | 多根因果林 + 挂起表（含恢复条件） | 「根源在哪」「为什么会出错」「核心是什么」「本质是什么」 |
| 🕸️ 网状线索关联穷举法 | **网状图** ／ **穷举法** | `web-association-exhaustive` | 带权关联网 ＝ 一张穷举表 | 「有哪些可能」「还有什么没考虑到」「换个角度」 |
| 📐 结构同构质点代入法 | **结构图** ／ **代入法** | `structure-isomorphism-pointmass-substitution` | 结构模式 id + 变量集·边型·边界校验 + 量级区间 | 「预估一下」「帮我推算」「建个模型」「大概多少」「这类问题怎么办」 |
| 🧪 预设答案假设倒推法 | **倒推图** ／ **倒推法** | `presupposed-answer-hypothesis-backderivation` | 假设—证据链 + 走形命中的诊断报告 | 「我是不是先有答案了」「帮我审一下这段推理」「这是不是确认偏误」 |

### 命名结构

技能 id 是中文全称的**逐段直译**，不是另取的标签——`图名 · 核心限定 · 法名`：

| 中文全称的分段 | 英文 id 的分段 |
|---|---|
| 林状 ｜ 分层分类 ｜ 回溯法 | `forest` ｜ `hierarchical` ｜ `backtracking` |
| 网状 ｜ 线索关联 ｜ 穷举法 | `web` ｜ `association` ｜ `exhaustive` |
| 结构 ｜ 同构 ｜ 代入法 | `structure` ｜ `isomorphism` ｜ `substitution` |
| 预设答案 ｜ 假设 ｜ 倒推法 | `presupposed-answer` ｜ `hypothesis` ｜ `backderivation` |

「图」是产物，「法」是动作：林状图＝回溯法画出来的，网状图＝穷举法画出来的，结构图＝代入法画出来的。

三个作答技能互相有优先级约定：不确定用哪个时默认穷举；复杂问题按 林状图 → 网状图 → 结构图 联用。

第四个技能（倒推图）不是作答模式，是**独立的审计器**：它审「这段推理是怎么来的」，不产出答案。它自成一体——不引用其余三个技能，也不要求先有哪张图；触发条件是已经有一个想要的结论、正在倒着找理由。

---

## 三张图，三套关系语法 / Three grammars

三种方法都在做同一件事：**描述事物之间的关系**。区别只在用哪种关系语法去填那张矩阵。

| | 填的什么关系 | 允许的边 | 禁止的边 |
|---|---|---|---|
| 🌳 林状图 | 纵向：谁导致谁 | `A → B`（必要／充分，须标明）；`A ⊥ B` 挂起（须附恢复条件） | 跨维度边 |
| 🕸️ 网状图 | 横向：谁和谁近 | `A — B` 带权（物理距离·关联度）；`A ⊥ B` 挂起 | 「可能相关」的悬空边 |
| 📐 结构图 | 结构：这个陌生问题 ≅ 哪一类已经处理过的问题 | `P ≅ M`（须同时校验**变量集·边型·边界**）；三件不齐即降级为类比 | 只匹配公式形状、不校验边界的「假同构」 |

### 四种动作（三张图共用的骨架）

1. **选轴／切出实体**——林状图按必经时序或恒等式**生成**轴（不得列举），每格写出「该格故障的可观测症状」；网状图切线索，先求全不求准。切法决定后面能看见什么。
2. **定语法**——确定节点之间允许连哪一种边（三种语法见上表）。语法没定，图就没有意义。
3. **配对完整**——每个节点必须完整分叉到**所有**维度／线索／自由度；没连上的就是漏掉的。
4. **挂起也是结论**——「不是根」必须写成边，四列：分支／判定／依据／**恢复条件**。禁止删除：删掉的枝有根，只是被判为不是根。

> 结构图没有「切」这一步，它多的是**取结构树 + 边界校验**：先做先例检索，再校验变量集·边型·边界是否真的同构。
> 这套方法的关键不在图上有什么，而在图上**没有哪条边**。缺了第 4 条动作，产物就从「审查过的结构」退化成「想过的痕迹」——这也正是它区别于自由推理的地方。

### 第四张图：倒推图（反面教材，审计用）

前三个技能都在**回答问题**；它不。它审的是「这个问题是被怎么回答掉的」。

**预设答案假设倒推法** ＝ 先假定答案成立，再倒着补理由。数学类比：给定 x 的公式、问 x 的取值范围 → 先假设 `x>0` → 代入验算是否成立。

危险不在「先假设」。危险在两件事同时发生：只假设了**自己希望成立的那一种**（x=0、x<0 压根没试），以及假设被推翻时**换的是检验标准，不是假设**。

它堕落成反面教材需要三个条件同时成立（反过来读就是合法用法）：

1. 假设没有显式声明，读者以为那是事实
2. 只做确认性检验，不尝试证伪
3. 反例出现后，改的是标准／数据／题面，而不是假设

六种典型走形各带检测信号与纠正目标：单一假设、确认性检验、反例豁免、事后改标准、假设升格为事实、循环论证——完整表见技能正文。

它与前三张图**零接口**：不引用、不依赖、不假设它们存在。这样审的才是「这段推理本身」，而不是「你属于哪一派」；三张图产物的负边有没有被剪掉，只是它可以审的对象之一，不是它的前提。

> 只想研究**普通人思维本身**、不需要三张图当参照时，用姊妹仓库 [dsh-ordinary-thinking](https://github.com/plasmaflea/dsh-ordinary-thinking) 里的**模拟版**：同一模型，但它不判对错，只跑轨迹、记「运气／迟到调整／改题面」三条通道。两版可同时安装（id 不同）。

---

## 安装 / Install

技能没有中心化商店，分发单位就是一个目录 + 一份 `SKILL.md`。下面四种装法任选。

> **`tree/` 随技能一起装**：三张图的常量表（认知树／关系表／结构表）就在各自技能目录的 `tree/` 下，装技能即拿到，**不需要再装任何常量库**。常量库只给要改这些表的人用，见第 5 节。

### 1. DSH 技能仓库（推荐）

DeepSeek Harness + [Skills Manager](https://github.com/MichengAI/dsh-skills-manager) 插件：

设置 → 技能 → **技能仓库** → 添加仓库 → 填入本仓库的公开地址 → 扫描 → 逐项「安装」→ 选择「用户目录」或某个已登记工作区的 `.dsh/skills` → 核对路径确认。

- 只支持公开 GitHub 仓库，不提供私有凭证
- 安装后**不自动更新**，需要手动「刷新并检查更新」→ 预览差异 → 确认后备份更新
- 卸载会进回收站，可恢复

### 2. 手动拷贝（任意支持 SKILL.md 的宿主）

| 作用域 | 路径 |
|---|---|
| DSH 全局 | `~/.dsh/skills/<skill-id>/SKILL.md` |
| 跨 Agent 共享 | `~/.agents/skills/<skill-id>/SKILL.md`（DSH 的 `DSH_AGENTS_HOME` 可覆盖） |
| 项目内（随仓库提交） | `<project>/.dsh/skills/<skill-id>/SKILL.md` |

把仓库里的四个技能目录整个拷过去即可，不需要构建、没有依赖。

```powershell
$dst = "$HOME\.dsh\skills"
New-Item -ItemType Directory -Force -Path $dst | Out-Null
Copy-Item -Recurse -Force `
  .\forest-hierarchical-backtracking, `
  .\web-association-exhaustive, `
  .\structure-isomorphism-pointmass-substitution, `
  .\presupposed-answer-hypothesis-backderivation $dst
```

### 3. skills.sh / Claude Code / Cursor 等

```bash
npx skills add <owner>/dsh-thinking-models
```

该 CLI 会把技能写进对应 Agent 的目录（Claude Code、Cursor、Codex 等），**不包含 DSH**——DSH 用户请用第 1 或第 2 种方式。

### 4. 直接用

技能正文就是普通 Markdown。不想装，也可以把对应 `SKILL.md` 的内容贴进系统提示词，效果等同（代价是每一轮都占上下文）。

### 5. 常量库（只有要改表的人才需要，装技能不需要）

三张图的背景知识——认知树、关系类型表、结构模式库——单独维护在 [`dsh-thinking-models-constants`](https://github.com/plasmaflea/dsh-thinking-models-constants)。

**用技能的人不用碰它**：`tree/` 已随每个技能目录发布，上面四种装法都会把整个目录拷过去。只有在你要**改这些表**（加节点、改判据、记校准）时才 clone：

```powershell
git clone https://github.com/plasmaflea/dsh-thinking-models-constants
cd dsh-thinking-models-constants
.\scripts\sync.cmd  -SkillsRepo <你的本仓库路径> -InstallDir <你的技能安装目录>
.\scripts\state.cmd -Verify -SkillsRepo <你的本仓库路径> -InstallDir <你的技能安装目录>
```

（两个仓库 clone 在同一父目录时，`-SkillsRepo` 可省略，脚本会自动发现。）

方向是单向的：常量库是真相源，**本仓库的 `tree/` 是生成副本**，就地改会在下次同步时被覆盖。改法、升版规则、不变量见常量库的 `README.md`。

---

## 仓库结构 / Layout

```
.
├── forest-hierarchical-backtracking/SKILL.md   # 🌳 林状分层分类回溯法
│   └── tree/                                   # 认知树（v1）：software / win-service 节点
├── web-association-exhaustive/SKILL.md         # 🕸️ 网状线索关联穷举法
│   └── tree/                                   # 关系表（v1）：九类关系 + 秩矩阵 + 校准记录
├── structure-isomorphism-pointmass-substitution/SKILL.md     # 📐 结构同构质点代入法
│   └── tree/                                   # 结构模式库（12 基 + 2 修饰 + 复合表，v2.4 · 核查 2026-10-18）
├── presupposed-answer-hypothesis-backderivation/SKILL.md  # 🧪 预设答案假设倒推法（反面教材）
├── examples/                                   # 每个模式一组输入 → 完整产物
│   ├── forest-hierarchical-backtracking.md
│   ├── web-association-exhaustive.md
│   ├── structure-isomorphism-pointmass-substitution.md
│   └── presupposed-answer-hypothesis-backderivation.md
├── docs/                                       # 实验记录与论文流水线
│   ├── benchmark/README.md                     # 三题面 + 指标定义 + 已跑数据 + 诚实声明
│   └── paper/pipeline.md                       # 论文阶段与本项目的映射
├── scripts/
│   ├── bench-before.ps1 / bench-before.cmd     # 对照组环境开关（停用策略 + 撤 AGENTS.md，可逆）
│   └── sync-tree.ps1                           # 结构库同步：工作区源 → 仓库 tree/ → 安装位（-Check 可做提交前检查）
├── README.md
└── LICENSE
```

技能目录直接放在仓库根下，便于各家的技能扫描器发现；不要再往深层套子目录。

`<id>/tree/` 三份都是**生成副本**，真相源在独立仓库 [`dsh-thinking-models-constants`](https://github.com/plasmaflea/dsh-thinking-models-constants)（认知树 / 关系表 / 结构表，各自带 `vN` 与核查日期）。副本不要就地改：改常量库，再跑它的 `scripts/sync.cmd` 同步到本仓库与本机安装位，`state.cmd -Verify` 会报漂移。

---

## 设计取舍 / Design notes

- **流程进技能，纪律进宿主。** 技能正文只在被调用那一次进入上下文。所以「每轮标注当前模式」「固定输出格式」这类常驻约束**不能**只写在技能里，必须由宿主的常驻指令（如 `AGENTS.md`）承担。本仓库只装流程与产物形状。
- **`description` 是唯一的路由信号。** 决定技能会不会被加载的就是这一行，所以写成中英双语 + 具体触发词，而不是抽象的能力描述。
- **每个技能都自带失效条件。** 「风险与对策」节是刻意保留的：它告诉模型这套方法在什么时候不成立，比再写十条使用建议有用。
- **负边优先于正边。** 每张图都强制要求交付「被排除／被忽略」的部分。这是三套语法共同的纪律，也是它们相对自由推理唯一可验证的差异。
- **产物优先于论述。** 三个作答技能都要求先给结构（林／网／结构模式），再给结论。倒推图相反：它先审「这个结构是怎么来的」。
- **第 0 步在建树之前。** 林状图的入口不是直接取节点，而是 §0.3「定义→分类→概念拆解」：快档每轮验树，慢档才造树，造出的新节点登记 `v(N+1)` 候选。树是常量，常量要有造它的工序。
- **权重是刻度的读数，不是概率。** 网状图 §2.1 把边分成关联边（无向）与支持边（有向），权重＝关系类型 × 机制步数；只排序、不求和，跨题不比较。

## 适用边界（诚实版）

这套技能的收益主要在**产物的可审计性、失败的可定位性、成本的可截断性**，而不是单次运行的准确率。

- 更适合：没有唯一答案的开放任务——根因排查、方案穷举、量级估算、需要人复核的判断
- 不一定更好：有标准答案的选择题、短问答、事实检索（结构开销换不到收益）
- 已知代价：产物更长（token 成本上升），且强结构在简单问题上会造成过度展开

## 兼容性 / Compatibility

`SKILL.md` + YAML frontmatter（`name`、`description`）是跨 Agent 的通用格式，不依赖任何私有字段。`name` 必须是 ASCII kebab-case，所以中文全称放在正文与 `description` 里，id 用逐段直译。在 DeepSeek Harness 与 Skills Manager 的目录扫描下验证通过。

---

## 后记：这套方法是怎么来的

这一段不是技术文档，是我自己的来路。

十多年前我还在读初中，有一天怀疑自己是个天才，于是决定验证一下。要验证就得先定义什么叫天才；定义了，就得回答天才与普通人差在哪、普通人又怎么才能成为天才。就这么一个问题，前后耗了几年才有一点成果，又几年，才收敛成现在这三种逻辑模型。

出发点一直很简单：**让别人也能接近、甚至拥有我拥有的那点东西。** 所以这套模型是给人类设计的，不是给机器设计的。

换个角度来讲，如果人工智能掌握了这一套逻辑模型，那么基本上可以认为它的智力水平在这种状态下已经达到人类水平了。通用 AGI，差不多也就这样了吧。

但我更希望的是你自己学会它——让脑子习惯用这三种方式想事，把自己变成天才。

人工智能需要深度学习才能拥有智能，人类其实也一样：人也需要**深度学习**才能成为天才。而且越早开始越省力。考虑到大脑成型与思维能力的形成，大概 13 岁以上就该接触这三种逻辑模型了。

我 13 岁左右养成一个习惯：脑子随时都在想事。那时喜欢小说，就在脑子里纯凭脑力写同人——上课在想，走路在想，躺床上睡着前还在想；外部环境一安稳下来就立刻开始推进剧情，全靠记忆回忆写到哪一步了。我的记忆力其实不好，跟过目不忘的人比算很差，但这不妨碍我用这种方式高强度地练思维。有时候也不想小说，就想别的：生活里的小事反复回味，想当时如果做了别的选择会怎么样；想如果有人来问我一个奇怪的问题，我该怎么答、怎么解。比如"如果我成了日漫男主，我要怎么拯救世界"——很幼稚，但形式不重要，练的是思维。

后来用脑过度，落下了耳鸣型幻听。不影响生活，既不伤听力也不影响精神状态；只要一两个月不长时间用脑就会好转，甚至消失。问题是一两个月不长时间用脑实在太难，习惯已经养成。偶尔能控制住一个月，平时还是一不小心就过度用脑。

如果你也出现了过度用脑的症状，那说明你也练成了。

如果这三种模型真变成了你的本能、成了你遇到事情的第一反应，那恭喜你，你是天才了。就算没养成习惯，只要在有意识的时候会主动用这三种模型去思考、去重新审视世界，也算进了半步天才的门。

---

## 许可 / License

MIT，见 [LICENSE](LICENSE)。可自由修改与再分发，改动后建议保留出处链接。
