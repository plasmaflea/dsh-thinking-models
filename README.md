# DSH Thinking Models / 三种逻辑模型思维技能

三个可安装的 Agent 技能（`SKILL.md` 格式），把一个宽泛的「好好想一下」变成**可审计的产物**：林状图、网状图、公式图。

Three installable agent skills (SKILL.md format) that turn a vague "think harder" into **auditable artifacts**: a causation forest, a weighted association web, and a formula with declared boundaries.

| 全称 | 简称（产物／动作） | 技能 id | 产物 | 触发 |
|---|---|---|---|---|
| 🌳 林状分层分类回溯法 | **林状图** ／ **回溯法** | `forest-hierarchical-backtracking` | 多根因果林 + 无关边清单 | 「根源在哪」「为什么会出错」「核心是什么」「本质是什么」 |
| 🕸️ 网状线索关联穷举法 | **网状图** ／ **穷举法** | `web-association-exhaustive` | 带权关联网 ＝ 一张穷举表 | 「有哪些可能」「还有什么没考虑到」「换个角度」 |
| 📐 经验公式质点代入法 | **公式图** ／ **代入法** | `formula-pointmass-substitution` | 函数等式 + 质点假设 + 适用边界 | 「预估一下」「帮我推算」「建个模型」「大概多少」 |

### 命名结构

技能 id 是中文全称的**逐段直译**，不是另取的标签——`图名 · 核心限定 · 法名`：

| 中文全称的分段 | 英文 id 的分段 |
|---|---|
| 林状 ｜ 分层分类 ｜ 回溯法 | `forest` ｜ `hierarchical` ｜ `backtracking` |
| 网状 ｜ 线索关联 ｜ 穷举法 | `web` ｜ `association` ｜ `exhaustive` |
| 经验公式 ｜ 质点 ｜ 代入法 | `formula` ｜ `pointmass` ｜ `substitution` |

「图」是产物，「法」是动作：林状图＝回溯法画出来的，网状图＝穷举法画出来的，公式图＝代入法画出来的。

三个技能互相有优先级约定：不确定用哪个时默认穷举；复杂问题按 林状图 → 网状图 → 公式图 联用。

---

## 三张图，三套关系语法 / Three grammars

三种方法都在做同一件事：**描述事物之间的关系**。区别只在用哪种关系语法去填那张矩阵。

| | 填的什么关系 | 允许的边 | 禁止的边 |
|---|---|---|---|
| 🌳 林状图 | 纵向：谁导致谁 | `A → B`（必要／充分，须标明）；`A ⊥ B` 无关 | 跨维度边 |
| 🕸️ 网状图 | 横向：谁和谁近 | `A — B` 带权（物理距离·关联度）；`A ⊥ B` 无关 | 「可能相关」的悬空边 |
| 📐 公式图 | 定量：谁随谁变 | `Y = f(X₁,X₂…)`（须给出处）；其余一律进「被忽略清单」 | 无出处的经验系数 |

### 四种动作（三张图共用）

1. **切出实体**——确定图里有哪些节点。切法决定后面能看见什么。
2. **定语法**——确定节点之间允许连哪一种边。语法没定，图就没有意义。
3. **配对完整**——每个节点必须完整分叉到**所有**维度／线索／自由度；没连上的就是漏掉的。
4. **负边也是结论**——「无关」必须写成边并附理由，排除项必须留档。

> 这套方法的关键不在图上有什么，而在图上**没有哪条边**。
> 缺了第 4 条动作，产物就从「审查过的结构」退化成「想过的痕迹」——这也正是它区别于自由推理的地方。

---

## 安装 / Install

技能没有中心化商店，分发单位就是一个目录 + 一份 `SKILL.md`。下面四种装法任选。

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

把仓库里的三个目录整个拷过去即可，不需要构建、没有依赖。

```powershell
$dst = "$HOME\.dsh\skills"
New-Item -ItemType Directory -Force -Path $dst | Out-Null
Copy-Item -Recurse -Force `
  .\forest-hierarchical-backtracking, `
  .\web-association-exhaustive, `
  .\formula-pointmass-substitution $dst
```

### 3. skills.sh / Claude Code / Cursor 等

```bash
npx skills add <owner>/dsh-thinking-models
```

该 CLI 会把技能写进对应 Agent 的目录（Claude Code、Cursor、Codex 等），**不包含 DSH**——DSH 用户请用第 1 或第 2 种方式。

### 4. 直接用

技能正文就是普通 Markdown。不想装，也可以把对应 `SKILL.md` 的内容贴进系统提示词，效果等同（代价是每一轮都占上下文）。

---

## 仓库结构 / Layout

```
.
├── forest-hierarchical-backtracking/SKILL.md   # 🌳 林状分层分类回溯法
├── web-association-exhaustive/SKILL.md         # 🕸️ 网状线索关联穷举法
├── formula-pointmass-substitution/SKILL.md     # 📐 经验公式质点代入法
├── examples/                                   # 每个模式一组输入 → 完整产物
│   ├── forest-hierarchical-backtracking.md
│   ├── web-association-exhaustive.md
│   └── formula-pointmass-substitution.md
├── README.md
└── LICENSE
```

技能目录直接放在仓库根下，便于各家的技能扫描器发现；不要再往深层套子目录。

---

## 设计取舍 / Design notes

- **流程进技能，纪律进宿主。** 技能正文只在被调用那一次进入上下文。所以「每轮标注当前模式」「固定输出格式」这类常驻约束**不能**只写在技能里，必须由宿主的常驻指令（如 `AGENTS.md`）承担。本仓库只装流程与产物形状。
- **`description` 是唯一的路由信号。** 决定技能会不会被加载的就是这一行，所以写成中英双语 + 具体触发词，而不是抽象的能力描述。
- **每个技能都自带失效条件。** 「风险与对策」节是刻意保留的：它告诉模型这套方法在什么时候不成立，比再写十条使用建议有用。
- **负边优先于正边。** 每张图都强制要求交付「被排除／被忽略」的部分。这是三套语法共同的纪律，也是它们相对自由推理唯一可验证的差异。
- **产物优先于论述。** 三个技能都要求先给结构（林／网／式），再给结论。

## 适用边界（诚实版）

这套技能的收益主要在**产物的可审计性、失败的可定位性、成本的可截断性**，而不是单次运行的准确率。

- 更适合：没有唯一答案的开放任务——根因排查、方案穷举、量级估算、需要人复核的判断
- 不一定更好：有标准答案的选择题、短问答、事实检索（结构开销换不到收益）
- 已知代价：产物更长（token 成本上升），且强结构在简单问题上会造成过度展开

## 兼容性 / Compatibility

`SKILL.md` + YAML frontmatter（`name`、`description`）是跨 Agent 的通用格式，不依赖任何私有字段。`name` 必须是 ASCII kebab-case，所以中文全称放在正文与 `description` 里，id 用逐段直译。在 DeepSeek Harness 与 Skills Manager 的目录扫描下验证通过。

## 许可 / License

MIT，见 [LICENSE](LICENSE)。可自由修改与再分发，改动后建议保留出处链接。
