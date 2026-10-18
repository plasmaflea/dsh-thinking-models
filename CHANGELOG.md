# 变更记录

格式：Keep a Changelog；版本号：语义化 `0.x`（技能还在大改阶段）。

**标签是 2026-10-18 补打的**：本仓库前 18 个提交当时没有打标签，v0.1.0 / v0.2.0 指向的是历史提交（哈希写在下面），v0.3.0 指向当时的 HEAD。历史没有改写。

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
