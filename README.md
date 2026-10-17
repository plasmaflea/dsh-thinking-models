# DSH Thinking Models / 三种逻辑模型思维技能

三个可安装的 Agent 技能（`SKILL.md` 格式），把一个宽泛的「好好想一下」变成**可审计的产物**：关系林、穷举表、公式加边界。

Three installable agent skills (SKILL.md format) that turn a vague "think harder" into **auditable artifacts**: a causation forest, an enumeration table, and a formula with declared assumptions.

| 技能 / Skill | 产物 / Artifact | 触发 / Trigger |
|---|---|---|
| `root-cause-forest` 🌳 林状分层分类回溯法 | 多根关系林 + 被排除分支清单 | 「根源在哪」「为什么会出错」「核心是什么」「本质是什么」 |
| `clue-web-exhaustive` 🕸️ 网状线索关联穷举法 | 穷举表（线索/假设/证据/可能性/结论） | 「有哪些可能」「还有什么没考虑到」「换个角度」 |
| `point-mass-estimation` 📐 经验公式质点代入法 | 经验公式或类比 + 质点模型 + 收敛判据 | 「预估一下」「帮我推算」「建个模型」「大概多少」 |

三个技能互相有优先级约定：不确定用哪个时默认穷举；复杂创造性问题按 林状回溯 → 穷举 → 质点代入 联用。

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
| DSH 全局 | `~/.dsh/skills/<skill-name>/SKILL.md` |
| 跨 Agent 共享 | `~/.agents/skills/<skill-name>/SKILL.md`（DSH 的 `DSH_AGENTS_HOME` 可覆盖） |
| 项目内（随仓库提交） | `<project>/.dsh/skills/<skill-name>/SKILL.md` |

把仓库里的三个目录整个拷过去即可，不需要构建、没有依赖。

```powershell
$dst = "$HOME\.dsh\skills"
New-Item -ItemType Directory -Force -Path $dst | Out-Null
Copy-Item -Recurse -Force .\root-cause-forest,.\clue-web-exhaustive,.\point-mass-estimation $dst
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
├── root-cause-forest/SKILL.md
├── clue-web-exhaustive/SKILL.md
├── point-mass-estimation/SKILL.md
├── examples/                 # 每个模式一组输入 → 产物样例
│   ├── root-cause-forest.md
│   ├── clue-web-exhaustive.md
│   └── point-mass-estimation.md
├── README.md
└── LICENSE
```

技能目录直接放在仓库根下，便于各家的技能扫描器发现；不要再往深层套子目录。

---

## 设计取舍 / Design notes

- **流程进技能，纪律进宿主。** 技能正文只在被调用那一次进入上下文。所以「每轮标注当前模式」「固定输出格式」这类常驻约束**不能**只写在技能里，必须由宿主的常驻指令（如 `AGENTS.md`）承担。本仓库只装流程与产物形状。
- **`description` 是唯一的路由信号。** 决定技能会不会被加载的就是这一行，所以写成中英双语 + 具体触发词，而不是抽象的能力描述。
- **每个技能都自带失效条件。** 「风险与对策」节是刻意保留的：它告诉模型这套方法在什么时候不成立，比再写十条使用建议有用。
- **产物优先于论述。** 三个技能都要求先给结构（林 / 表 / 式），再给结论。这正是这套方法相对自由推理的主要差别。

## 适用边界（诚实版）

这套技能的收益主要在**产物的可审计性、失败的可定位性、成本的可截断性**，而不是单次运行的准确率。

- 更适合：没有唯一答案的开放任务——根因排查、方案穷举、量级估算、需要人复核的判断
- 不一定更好：有标准答案的选择题、短问答、事实检索（结构开销换不到收益）
- 已知代价：产物更长（token 成本上升），且强结构在简单问题上会造成过度展开

## 兼容性 / Compatibility

`SKILL.md` + YAML frontmatter（`name`、`description`）是跨 Agent 的通用格式，不依赖任何私有字段。在 DeepSeek Harness 与 Skills Manager 的目录扫描下验证通过。

## 许可 / License

MIT，见 [LICENSE](LICENSE)。可自由修改与再分发，改动后建议保留出处链接。
