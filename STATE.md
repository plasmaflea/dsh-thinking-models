# 仓库状态与接手说明

> 给**下一个会话**看的。读完本文件 + `CHANGELOG.md`，应当在不知道任何历史的情况下，能独立完成「改 → 验 → 发 → 复扫」。
> 权威顺序：`git` 与磁盘 > 本文件 > 任何记忆/摘要。本文件里的哈希与版本会过期，**先用 `scripts/state.cmd` 拉一次真实状态**。

---

## 1. 这是什么

四个思维模型技能，用于 DSH（DeepSeek Harness）技能系统，也可被 DSH Skills Manager 从公开 GitHub 仓库扫描安装。

| id | 中文全称 | 简称（产物／动作） | 角色 |
|---|---|---|---|
| `forest-hierarchical-backtracking` | 林状分层分类回溯法 | 林状图／回溯法 | 作答模式：根因定位，根落在大类上 |
| `web-association-exhaustive` | 网状线索关联穷举法 | 网状图／穷举法 | 作答模式：穷举与关联映射，默认模式 |
| `structure-isomorphism-pointmass-substitution` | 结构同构质点代入法 | 结构图／代入法 | 作答模式：把陌生问题归到结构模式库的某类，必须校验变量集·边型·边界 |
| `presupposed-answer-hypothesis-backderivation` | 预设答案假设倒推法 | 倒推图／倒推法 | **审计模式**：负面教材，只产出诊断报告，不作答 |

姊妹仓库 `dsh-ordinary-thinking` 存放同一方法的**模拟版**（研究普通人思维本身，不追求正确答案）。

## 2. 上传信息（发布目标）

| 项 | 值 |
|---|---|
| 仓库 | https://github.com/plasmaflea/dsh-thinking-models |
| 远端 | `https://github.com/plasmaflea/dsh-thinking-models.git`（origin） |
| 可见性 | PUBLIC（Skills Manager 只扫公开仓库） |
| 默认分支 | `main` |
| 当前版本 | 见 `VERSION`（0.6.0）／标签 `v0.6.0` |
| topics | ai-agents, estimation, llm, prompt-engineering, reasoning, root-cause-analysis, skills |
| 账号 | GitHub `plasmaflea`；`gh` CLI 已登录（scope: `gist, read:org, repo`） |
| git 身份 | `plasmablue <1935153750@qq.com>` |

## 3. 文件地图

```
<id>/SKILL.md                 ×4  技能正文（放在仓库根，便于扫描器发现）
forest-.../tree/index.md          常量知识树索引（先读这个）
forest-.../tree/software.md       软件大类树（六层：concurrency/quota/init/config/dependency/lifecycle）
forest-.../tree/win-service.md    Windows 服务子类树
structure-.../tree/index.md       结构模式库索引（6 个模式，v1）
structure-.../tree/{multiplicative-rate,conservation,saturation,power-scale,additive-budget,queue-capacity}.md
examples/<id>.md              ×4  每个技能一份完整样例（改动时要同步）
docs/benchmark/README.md          before/after 实验：题面、指标、结果、诚实声明
docs/benchmark/rubric-v4.md       v4 评分口径（10 项判定）
docs/benchmark/prompts-v2.md      四道定稿题面
docs/benchmark/after-v2/ after-v4/ before-web-v2/ before-dsh-v2/
docs/paper/pipeline.md            25 阶段论文流水线映射
scripts/bench-before.ps1 + .cmd   对照组环境开关（Skills Manager 停用策略 + 撤 AGENTS.md，可逆）
scripts/bench-measure.ps1 + .cmd  产物实测（行/字符/表格/章节/负边）
scripts/state.ps1 + .cmd          本文件的机器版：打印真实仓库与安装位状态
README.md CHANGELOG.md VERSION STATE.md LICENSE
```

## 4. 本机安装位（DSH 用户级技能）

```
C:\Users\Administrator\.dsh\skills\<id>\SKILL.md
```

**仓库与安装位是两份拷贝**，必须保持一致：只改仓库，技能目录跑的还是旧版；只改安装位，推送会上丢。唯一的真相源是仓库。

同步（PowerShell）：

```powershell
$src = 'D:\DeepSeek-levelup\dsh-thinking-models'
$dst = "$env:USERPROFILE\.dsh\skills"
foreach ($id in 'forest-hierarchical-backtracking','web-association-exhaustive','structure-isomorphism-pointmass-substitution','presupposed-answer-hypothesis-backderivation') {
  Copy-Item "$src\$id\SKILL.md" "$dst\$id\SKILL.md" -Force
}
# 知识树是技能正文的引用目标，必须一起同步
Copy-Item "$src\forest-hierarchical-backtracking\tree\*" "$dst\forest-hierarchical-backtracking\tree\" -Recurse -Force
Copy-Item "$src\structure-isomorphism-pointmass-substitution\tree\*" "$dst\structure-isomorphism-pointmass-substitution\tree\" -Recurse -Force
```

约束（已验证，2026-10-18 修订）：`C:\Users\Administrator\.dsh\skills` 这个**根目录不能被整体改名/删除**（DSH 进程持有目录监听句柄）。但**不需要再逐技能 Move-Item**：`scripts\bench-before.ps1` 已改为写 Skills Manager 的停用策略（`<DSH_HOME>\skills-manager\state.json` 的 `disabledSkills.dsh`），只改「DSH 看到什么」、不动磁盘文件，运行中的会话也会热刷新（走 `POST /api/dsh-skills-manager/disable`）。不要自己写删除或移目录的逻辑。

⚠️ 写这份策略文件时**不要用 `ConvertTo-Json` 直接序列化有序字典**：PowerShell 5.1 会把空数组写成 `{}`，插件 `validManagerStateDocument()` 判非法 ⇒ 接口回 400、技能目录静默失效。脚本里是手工拼 JSON 的，改动时保持这一点。

## 5. 改一个技能的完整流程

```powershell
# 0 先看真实状态（不要凭记忆）
cd D:\DeepSeek-levelup\dsh-thinking-models
.\scripts\state.cmd

# 1 改仓库里的文件（先改仓库）
#    SKILL.md / examples/<id>.md / tree/*.md / README / AGENTS 对应条目
#    改了树 → 必须升节点 vN 并更新「核查 日期」

# 2 同步到本机安装位（见第 4 节命令）

# 3 验证
.\scripts\state.cmd -Verify     # 仓库 ↔ 安装位 哈希是否一致 + 树版本

# 4 更新 CHANGELOG.md（Added/Changed/Removed/Breaking）+ VERSION

# 5 提交、打标签、推送
git add -A
git commit -m "feat(forest): ..."
git tag vX.Y.Z
git push; git push --tags

# 6 复扫：DSH 设置 → 技能 → 技能仓库 → 重新扫描（安装后不自动更新）
```

## 6. 版本号规则

- `MAJOR` 恒为 0（技能仍在改）。
- `MINOR`：新增技能、新增/删树节点、评分口径变化（rubric）、输出骨架必填项变化。破坏性改动在提交标题加 `!`（先例：`2f8221b` 改 id）。
- `PATCH`：措辞、样例、脚本、文档修正。
- **树的 `vN` 与仓库版本独立**：树是常量知识体系，每次修改树都要升节点版本号并写核查日期，但不必升仓库 MINOR。
- 标签格式 `vX.Y.Z`，与 `VERSION`、`CHANGELOG.md` 三段一致。

## 7. 不可破坏的约束（改之前先读）

1. 技能 `name` 必须 ASCII kebab-case，且 = 中文全称的**逐段直译**（图名·核心限定·法名）。不要另取标签。
2. frontmatter 只写 `name` + `description`。`description` 决定路由：第一句写触发面，末句写边界；倒推法的末句是硬边界 `NOT to answer questions`（防止被误路由成作答模式）。
3. 技能正文**只在被调用那一次**进入上下文 ⇒ 「每轮标模式」「固定输出格式」这类常驻约束只能写在 `D:\DeepSeek-levelup\AGENTS.md`，不能只写在技能里。
4. 知识树是常量，不许每轮现编；树里没有的分支必须登记为「树外分支」+ `v(N+1) 候选`，不许静默丢弃。
5. 挂起表四列（分支／判定／依据／**恢复条件**），禁止用删除代替挂起。
6. 测量脚本必须显式 UTF-8：PowerShell 5.1 的 `Get-Content` 按 GBK 解码 UTF-8 中文会少数行（同一份 200 行文件被数成 144 行）。
7. 本机执行策略禁止直跑 `.ps1`，一律走配套 `.cmd`（内部 `-ExecutionPolicy Bypass`）；`.cmd` 内容必须是纯 ASCII + CRLF，否则 cmd 按 GBK 解析中文注释会报错。

## 8. 已知待办

- **正确性未测**：v4 林状图只在一道题上验过结构项（10/10），没有任何带 ground truth 的实验，因此不能声称「更准」。
- **论文**：ACL 2027 ARR 截止 2027-01-04（京都，2027-08-17~22；long 8 页；缺 limitations 直接拒）。当前最现实的是 arXiv + workshop 起步。
- **n=1**：before 三个条件（网页版／裸机／装技能）各只有一次运行。
- 极限与缺陷探测题集已设计：`docs/benchmark/stress.md`（12 题四组 + 反退化三项 + G 组注入实验，一次都没跑）。

## 9. 跨会话检索

稳定事实（仓库地址、版本、约束）已用 `hindsight_ingest_document` 落库；查历史对话用 `conversation_search`，读原文用 `conversation_history`。
