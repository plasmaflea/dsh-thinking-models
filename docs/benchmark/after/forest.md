<!-- date: 2026-10-17 -->
<!-- skills_used: forest-hierarchical-backtracking -->
<!-- artifact: 因果林表格 -->

# Node.js + NSSM 服务启动即退出（exit code 3221225794）根源回溯

## 0. 先落一件事实：这个数字不是「错误码」，是加载器的判决书

`3221225794` 不是 Node、不是 NSSM、不是你写的任何一层产生的。

```
3221225794 (dec) = 0xC0000142 (hex) = STATUS_DLL_INIT_FAILED
```

对照 NTSTATUS 的量纲就能确认：`0xC0000000` = 3221225472，加上 `0x142` = 322，正是 3221225794。

它的语义是唯一的：**Windows 加载器（`ntdll!LdrpInitialize`）在进程完成映像映射、逐个调用各 DLL 的 `DllMain(DLL_PROCESS_ATTACH)` 时，某一个 `DllMain` 返回了 `FALSE`（或抛出了加载器无法吞掉的异常），于是加载器放弃整个进程，以 `0xC0000142` 终止它。**

这件事发生的位置极其关键——它发生在**入口点之前**，也就是 `wWinMainCRTStartup` → `main()` → `node::Start()` 之前。

于是你那两个「看起来缺失的线索」其实是同一条证据的两面：

- **没有 stdout**：Node 的 stdout 是进程起来、libuv 初始化、NSSM 的管道/文件重定向生效之后才存在的东西。进程死在入口点前，一个字都不可能有。
- **没有堆栈**：JS 层异常、未捕获 rejection、native addon `require()` 失败，全都会走 `stderr` 并打印 stack。没有 stack 恰恰证明「Node 的 JS 运行时根本没被启动过」。

所以正确的读法是：**不是「日志丢了」，而是「能产生日志的那一层从未存在」。** 这条推断本身就是最强的剪枝工具——它一次性砍掉所有「应用层」假设，也顺带解释了你已经排查过的环境变量和文件权限为什么「看起来都正常」却无效：它们全部位于入口点之后，与本案不在同一个阶段。

> 一句话定位：**根因不在你的 Node 应用里，而在「这个进程被塞进了什么 DLL」以及「它所在的 Session 0 桌面还分不分配得出资源」这两件事之一。**

---

## 1. 四维正交切分

按「互不重叠」的要求切四刀。前三刀解释「为什么会死」，第四刀单独解释「为什么是偶发」——偶发是一个独立自由度，混进前三维里必然导致跨维度跳跃。

| 维度 | 问题 | 对应候选编号 |
|---|---|---|
| **A 阶段定位** | 进程死在生命周期的哪一点？ | 收敛为单值，汇总 1–14 |
| **B 装载对象** | 那个 `DllMain` 失败的是谁？ | 2, 3, 4, 5, 6, 9, 10, 11, 12, 13, 14 |
| **C 环境供给** | 为什么偏偏只在「服务 / Session 0」里发生？ | 1, 7, 8 |
| **D 触发时序** | 为什么是偶发而不是必现？ | 1, 4, 7, 9, 14 |

---

## 2. 候选原因清单（14 条，逐条定语法）

边类型只有三种：**必要**、**充分**、**无关（⊥）**。「相关」这种含糊词不允许出现在这张表里。

| # | 候选原因 | 维 | 边 | 能解释「偶发」吗 | 判定判据 |
|---|---|---|---|---|---|
| 1 | **Session 0 非交互桌面堆（Desktop Heap）耗尽** — `SharedSection` 第二值（默认 3072 KB）被所有服务共享，窗口站/桌面结构分配失败 | C/D | **充分** | ✅ 完美解释：累积型资源，服务数增长或某服务泄漏钩子后触发，重启即恢复 | 故障时**同时**有其他服务/进程起不来；`HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\SubSystems\Windows` 的 `SharedSection` 第三段偏小；Session 0 进程数偏多 |
| 2 | **应用目录（AppDirectory）里混入同名影子 DLL** — 加载顺序中应用目录优先于 `System32`（KnownDLL 除外），`libuv.dll` / `zlib1.dll` / `ssleay32.dll` / `vcruntime140.dll` / `msvcp140.dll` / `version.dll` / `winmm.dll` / `dwmapi.dll` 等被劫持加载 | B | **充分** | ✅ 部署脚本变更、打包残留、`windows-build-tools` 遗留、某次 CI 产物覆盖后出现 | `Get-ChildItem $AppDir -Filter *.dll` 有非预期 DLL；位数或版本与 `node.exe` 不匹配 |
| 3 | **`AppInit_DLLs` 注入** — `HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Windows` 的 `AppInit_DLLs` + `LoadAppInit_DLLs=1`，把某 DLL 强行注入**每一个**新进程 | B | **充分** | ✅ 组策略下发、某软件安装后一次性打开，之后持续 | 该键非空且 `LoadAppInit_DLLs=1`；故障范围超出本服务（全机新进程都起不来） |
| 4 | **AV / EDR 用户态 hook DLL 版本漂移** — 安全软件升级后注入的 DLL 与当前 OS/`node.exe` 不兼容 | B/D | **充分** | ✅ 经典：只在定义库/客户端升级后的时间窗出现 | 故障时刻与该 AV 的升级/定义更新时间高度重合；加排除项或临时停 AV 后恢复 |
| 5 | **Windows Exploit Protection 策略**（CFG / ACG / 强制 ASLR / 子进程限制）拒绝某注入 DLL 的初始化 | B | **充分** | ✅ 策略通过 Intune/GPO 刷新后生效 | `Get-ProcessMitigation -Name node.exe`；系统级 mitigation 是否覆盖 node |
| 6 | **Node 原生插件（`.node`）的 `DllMain` 失败**，且被 `--require` / `NODE_OPTIONS=--require` / `--loader` 在极早期加载 | B | **必要但一般不充分** | ⚠️ 只在「早期 require」这一前提下成立 | 命令行/`NODE_OPTIONS` 是否含早期 `--require`；把该 require 摘掉能否启动 |
| 7 | **系统级资源枯竭** — 提交内存接近上限、paged pool / 句柄配额、会话数上限导致 DLL 初始化无法完成 | C/D | **必要非充分** | ✅ 与业务峰值、并发会话、内存泄漏同步 | 性能计数器：`Committed Bytes` vs `Commit Limit`、`Pool Paged Bytes`、`Handle Count`、`Sessions` |
| 8 | **服务账户对 Session 0 窗口站/桌面无访问权** — 非 LocalSystem 账户缺少 `Service-0x0-xxxx$` 窗口站的访问权限 | C | **充分** | ⚠️ 通常是必现，偶发性弱 | 用 LocalSystem 跑同一份 `node.exe` 是否正常；窗口站 ACL |
| 9 | **`node.exe` 或其依赖 DLL 文件损坏 / 被半截写入** — 部署或升级过程中文件未写完就被启动，映像无法完整映射 | B/D | **充分** | ✅ 只在开机/部署并发窗口出现 | 文件哈希与官方包比对；`node.exe -v` 手动跑是否也崩 |
| 10 | **Application Compatibility shim（AppCompat DB）** 对 `node.exe` 下发的兼容层在初始化时失败 | B | **充分** | ⚠️ 需 shim 数据库变更 | `reg query "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\Layers"`；`CompatAdmin` 查 shim |
| 11 | **32/64 位混合加载** — 32 位 NSSM 拉 64 位 `node.exe`（或反之），叠加应用目录里的异位数影子 DLL | B | **间接相关**（不是纯无关，见 §5.7） | ⚠️ 单独不解释偶发 | `dumpbin /headers` 或读 PE 头比对 `nssm.exe` 与 `node.exe` 的 Machine 字段 |
| 12 | **映像映射失败** — 磁盘空间不足以容纳分页文件增长、或映像所在卷 IO 错误导致 `SEC_IMAGE` 映射失败 | B | **充分** | ✅ 磁盘被日志写满的时段 | 故障时刻系统盘剩余空间；事件日志中的磁盘/卷错误 |
| 13 | **字体驱动 / 打印驱动 / shell 扩展被 Session 0 加载并失败** — 服务进程也会碰到 `fontdrvhost`、`spoolsv` 注入路径 | B | **充分** | ✅ 打印队列堵塞或驱动更新后 | `spoolsv` 状态；`Get-PrinterDriver`；卸载最近驱动后观察 |
| 14 | **并发写导致的映像/DLL 被锁** — 同一时刻另一个进程正在替换那个 DLL，加载器读到不一致的文件 | B/D | **充分** | ✅ 只在并发窗口出现 | Procmon 抓 `Load Image` 结果；DLL 的 `LastWriteTime` 是否落在故障时刻附近 |

---

## 3. 各维度回溯链

### 维度 A：阶段定位 → 收敛为单点（这一维不产生候选，它产生判据）

```
现象：无 stdout + 无 stack + 有 NTSTATUS 退出码
  └─ 必要条件①：产生 stdout 的那一层从未执行    （Node runtime 未启动）
  └─ 必要条件②：产生 stack 的那一层从未执行     （V8 / JS 未启动）
  └─ 必要条件③：退出码由内核/加载器生成        （不是用户态异常码 0xE06D7363 / 0xC0000005）
        ⇒ 三点同时满足的唯一阶段 = LdrpInitialize 的 DllMain 阶段
        ⇒ 根 A：某个 DllMain 在 attach 时失败（充分：只要在这一步失败，必然呈现完全相同的三个现象）
```

**根 A 的作用不是给答案，是给你一把刀**：它把「Node 代码 / 依赖 / 配置 / 权限 / 端口」整片森林一次性剪掉（见 §5）。

### 维度 B：装载对象 → 根 = 「有非预期 DLL 进入了这个进程的加载集合」

先枚举完整父类（不枚举就一定会漏根）：一个进程里会跑 `DllMain` 的 DLL 只有四个来源——

```
B. 谁在被初始化
├─ B1 node.exe 自身映像 + 静态依赖的系统 DLL（kernel32 / ntdll / ws2_32 / advapi32 / user32…）
│    → 系统 DLL 自身初始化失败极罕见；一旦发生基本等于 OS 组件损坏或系统级资源枯竭（导向 C 维）
├─ B2 应用目录 / 工作目录里的同名影子 DLL（#2 / #11 / #14）
│    → 加载顺序决定它优先于 System32（KnownDLL 除外）。这是「你部署的东西」里最脏的一块
├─ B3 被外部强行注入的 DLL（#3 / #4 / #5 / #10 / #13）
│    → AppInit_DLLs、AV/EDR hook、Exploit Protection、AppCompat shim、打印/字体注入
│    → 特征：它注入到**每一个**新进程，所以故障范围会扩散到本服务之外
└─ B4 应用自己 LoadLibrary 的原生模块（#6）
     → 剪枝：正常 require 失败会抛 JS 错并打 stderr；只有「极早期 require」才可能表现为 0xC0000142
```

**根 B 不是单根，是一个集合故障**：具体是哪一个 DLL 只能靠 Procmon 的 `Load Image` 结果（`SUCCESS` vs `NAME NOT FOUND` vs `IMAGE CHECKS 校验失败`）点名，无法靠推理唯一确定。但**它属于 B2 还是 B3，有一个免费的二分判据**：故障时这台机器上**其他**新进程能不能起得来。

- 只有这个服务起不来 → B2（B4 次之）
- 全机新进程都起不来 → B3
- 只有 Session 0 里的服务起不来、交互式登录正常 → C 维

### 维度 C：环境供给 → 根 = Session 0 的非交互桌面堆

```
C. 为什么只在服务里发生
├─ C1 桌面堆（#1）
│    服务跑在 Session 0 的非交互窗口站 Service-0x0-xxxx$，
│    该窗口站/桌面的堆由 SharedSection 的**第二值**固定（默认 3072 KB，单位 KB）。
│    所有 Session 0 服务共享这一块。进程创建时加载器要为它分配窗口站/桌面结构，
│    分配失败即 CreateProcess 内部失败 → 0xC0000142。
│    ⇒ 充分条件：这一步失败必然表现为启动即退出、无任何进程内输出。
│    ⇒ 唯一能同时满足「服务专属 + 偶发 + 无输出 + 与权限无关」的根。
├─ C2 窗口站访问权（#8）→ 充分但通常必现，偶发性弱
├─ C3 系统资源枯竭（#7）→ 必要非充分，需与其他条件叠加
├─ C4 账户 profile / TEMP 不可用 → ⊥ 无关：这是入口点**之后**的事，与「无 stdout」矛盾
├─ C5 SCM 30 秒启动超时 → ⊥ 无关：码值是 1053，不是 0xC0000142
└─ C6 AppDirectory 路径不存在 → ⊥ 无关：CreateProcess 直接失败，NSSM 自己报错，码值不同
```

**根 C = C1**。它对你描述的「偶发 + 排查过权限和环境变量都正常」吻合度最高，因为桌面堆**根本不是权限问题也不是配置问题**，它是一块按 KB 计的固定池，用完了就完了。

### 维度 D：触发时序 → 根 = 偶发性来自「外部状态漂移」，不来自「代码不稳定」

```
D. 为什么是偶发
├─ D1 累积型（#1 桌面堆 / #7 内存句柄 / #12 磁盘）→ 随负载与运行时长单调增长，重启回落
├─ D2 被动变更型（#3 / #4 / #5 / #10 / #13）→ 某次 AV 升级 / WU / GPO 下发后开始，回滚后消失
└─ D3 竞态型（#2 / #9 / #14）→ 只在开机并发窗口、部署并发窗口出现
```

三者互不排斥。**根 D 的实用价值在于：它把「查代码」这条死路彻底堵死，把调查方向强制改到「时间相关性」上。** 偶发的 0xC0000142 几乎总是能被一条时间轴解释。

---

## 4. 汇合层：三根合并成一个二分判据

三个维度的根不能直接相加，必须合并成一个可执行的判定树：

```
根 A（加载器阶段失败）
  ├─ 问：故障时这台机器上「别的新进程」起得来吗？
  │    ├─ 起不来  ──────────────→ 根 B3：AppInit_DLLs / AV 注入 / Exploit Protection / AppCompat shim
  │    └─ 起得来
  │         └─ 问：故障时「别的 Windows 服务」起得来吗？
  │              ├─ 起不来  ─────→ 根 C1：Session 0 非交互桌面堆耗尽（优先查这个）
  │              └─ 起得来  ─────→ 根 B2：本服务应用目录内的影子 DLL / 原生插件 / 映像损坏
  └─ 问：手动以同一账户、在交互式会话里跑同一个 node.exe，能起来吗？
       ├─ 能    ───────────────→ 指向 C 维（会话/桌面供给）
       └─ 不能  ───────────────→ 指向 B 维（进程映像与 DLL 集合）
```

**真正的根（三层回溯合并后）**：

- **现象层**：进程在入口点之前被加载器判死，`0xC0000142`。
- **提问者意图层**：你要的是「为什么偶发、为什么没日志、怎么让它稳」。注意——你已经排查的**环境变量与文件权限，恰好是本案两个错误维度**，它们都预设了「Node 已经跑起来了」这个不成立的前提。这不是排查不认真，是阶段判断错了。
- **问题根源层**：**`0xC0000142` 的根不在 Node，也不在 NSSM 的配置语法，而在「这个进程被塞进了不兼容的 DLL」或「它所在的 Session 0 桌面堆已经分不出资源」——二者由「故障影响范围是单服务还是整机」这一个判据切开。**

---

## 5. 已排除项 / 无关项（负边，附剪枝理由）

这一节与上面的正边同等重要。**说「X 无关」和说「X 是根」是同等分量的结论。**

| # | 被排除项 | 边 | 剪枝理由 |
|---|---|---|---|
| 5.1 | **环境变量配置错误**（`PATH` / `NODE_ENV` / `NODE_OPTIONS` / 自定义变量） | ⊥ 无关 | 错误的 `NODE_OPTIONS` 会让 `node` 起来后打 stderr 再退出，码值为 9 或 1；不会产生 NTSTATUS。**但注意 #6 的例外**：`NODE_OPTIONS=--require <坏 .node>` 是唯一能把环境变量拉回本案的路径，值得单独排一次。 |
| 5.2 | **文件 / 目录 NTFS 权限**（服务账户对 app 目录、日志目录的 ACL） | ⊥ 无关 | ACL 不足时是 `0xC0000022`（`STATUS_ACCESS_DENIED`），或 NSSM 直接报 `CreateProcess failed`，码值不同。权限问题也不会表现为「偶发」。 |
| 5.3 | **JS 代码 bug / 未捕获异常 / 依赖缺失 / 端口占用 `EADDRINUSE`** | ⊥ 无关 | 全部发生在入口点之后，必然有 stdout 或 stderr，退出码为 1。无输出这一点已把它们全部否掉。 |
| 5.4 | **NSSM 配置语法错误**（`Application` 路径写错、`AppParameters` 错、`AppDirectory` 不存在） | ⊥ 无关 | NSSM 会写自己的日志并报 `CreateProcess failed`；SCM 30 秒超时给 `1053`。码值不匹配。 |
| 5.5 | **服务账户密码过期 / 缺少「作为服务登录」权限** | ⊥ 无关 | SCM 直接拒绝启动，报 `1069` / 登录失败，进程根本不会被创建——你也就看不到子进程退出码。 |
| 5.6 | **磁盘满 / 目录只读** | ⊥ 无关（但 #12 例外） | 一般会在入口点之后由 Node 自己报错；只有「分页文件无法增长导致 `SEC_IMAGE` 映射失败」这一窄路径才会变成 `0xC0000142`，归入 #12。 |
| 5.7 | **32/64 位不匹配本身** | **间接相关，非直接根** | 纯粹的位数不匹配典型码是 `0xC000007B`（`STATUS_INVALID_IMAGE_FORMAT`），不是 `0xC0000142`。但它会**放大** #2：32 位 NSSM 进程里若被强制加载 64 位影子 DLL，就绕成了 `DllMain` 失败。所以它是 #2 的放大器，不是独立根。 |
| 5.8 | **Node 版本升级 / 版本本身有 bug** | ⊥ 无关 | 版本问题必现且通常伴随 stderr；不符合「偶发 + 零输出」。 |
| 5.9 | **NSSM 本身有 bug** | ⊥ 无关 | NSSM 只是 `CreateProcess` + 句柄重定向，不做 DLL 注入。它能把子进程码值如实转发；它自己失败时报的是它自己的错误文本。 |
| 5.10 | **防火墙 / 端口 / 网络策略** | ⊥ 无关 | 全部在 `listen` 阶段生效，远在入口点之后，且必有输出。 |

---

## 6. 按调查顺序的排序（信息增益 ÷ 成本）

排序原则：**先用 1 分钟的动作砍掉一半假设，再用 10 分钟的动作点名具体 DLL。**

| 序 | 动作 | 耗时 | 期望产出 / 决策点 |
|---|---|---|---|
| **0** | 确认码值语义：`0xC0000142 = STATUS_DLL_INIT_FAILED`（加载器阶段） | 1 min | 直接剪掉 §5 全部应用层假设。**不做这一步，后面全是浪费。** |
| **1** | **看事件日志的 `Source` 字段**：这条 3221225794 的提供程序是 `nssm` 还是 `Application Error` / `Windows Error Reporting`？ | 1 min | 是 `nssm` → NSSM 转述子进程退出码；是 `Application Error` → WER 已记录 node.exe 崩溃，可直接取 dump。见 §8 ⚠️ |
| **2** | **建立时间轴**：故障时刻 vs AV 定义更新 / Windows Update（`Get-HotFix`）/ 最近部署 / 服务数量增长 / 磁盘占用 | 5 min | 命中 D1/D2/D3 中的哪一条，把 14 条候选砍到 3–5 条 |
| **3** | **测影响范围**（二分判据，信息增益最高）：故障时另起一个无关的新进程（`cmd /c echo ok`）、另起一个无关服务、交互式登录跑 `node -v` | 5 min | 直接走到 §4 判定树的某个叶子：B2 / B3 / C1 |
| **4** | **桌面堆体检**：读 `HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\SubSystems\Windows` 的 `SharedSection`（形如 `1024,3072,512`，第二值＝非交互桌面堆 KB）；数 Session 0 进程数 | 5 min | 第二值 ≤ 3072 且服务数偏多 → 高度怀疑 #1，直接试调大 |
| **5** | **影子 DLL 扫描**：`Get-ChildItem $AppDir -Recurse -Filter *.dll`；对 `node.exe` 做 `dumpbin /dependents`；比对 `node.exe` 与 `nssm.exe` 的 PE Machine 字段 | 5 min | 指认 #2 / #11。应用目录里除 `node_modules` 外的任何 DLL 都该被解释或删除 |
| **6** | **查 AppInit_DLLs**：`HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Windows` 的 `AppInit_DLLs` / `LoadAppInit_DLLs` | 2 min | 非空 → #3，命中率极高且修复成本极低 |
| **7** | **Procmon 抓一次故障启动**：过滤器 `Process Name is node.exe` + `Operation is Load Image`，看第一个 `NAME NOT FOUND` 或校验失败的 Image | 15 min | **决定性一步**：直接点名 §3 维度 B 里的具体 DLL，无需再推理 |
| **8** | **开 WER LocalDumps 拿 dump**：`HKLM\SOFTWARE\Microsoft\Windows\Windows Error Reporting\LocalDumps\node.exe`（`DumpFolder` / `DumpType=2`），复现后 `!analyze -v` 看 `FAILED_INIT` 与初始化线程栈 | 30 min | 兜底。前 7 步无果时才做 |
| **9** | 查 `Get-ProcessMitigation -Name node.exe`、AppCompat Layers、`Get-PrinterDriver` | 10 min | 覆盖 #5 / #10 / #13 三条低概率分支 |

**处置动作（从根解决，对应上面的根）**：

- 根 B2：清空应用目录里的非必要 DLL；把 `node.exe` 放进干净目录；用完全限定路径调用。
- 根 B3：清空 `AppInit_DLLs` 并把 `LoadAppInit_DLLs` 置 0；给 AV 加进程/目录排除；临时以安全模式验证。
- 根 C1：把 `SharedSection` 第二值调大（如 `1024,8192,512`）后重启；根治是减少 Session 0 服务数量、修掉泄漏窗口句柄的那个服务。
- 通用兜底（**不是修根因，是让下一次偶发留证据**）：NSSM 里配 `AppStdout` / `AppStderr` 到文件 + `AppRotateFiles 1` + `AppRotateOnline 1`；同时打开上面的 WER LocalDumps。

---

## 7. 结论

一句话：**`3221225794 = 0xC0000142 = STATUS_DLL_INIT_FAILED`，说明 node.exe 从未启动过——它在 Windows 加载器逐个初始化 DLL 的阶段就死了，死在入口点之前。所以「没有堆栈、没有 stdout」不是日志丢失，而是能产生日志的那一层根本不存在。**

因此根源必在下面两处之一，且由「故障时别的新进程/别的服务能不能起来」这一个判据切开：

1. **有非预期 DLL 进入了这个进程的加载集合**（应用目录影子 DLL、`AppInit_DLLs`、AV hook、Exploit Protection、AppCompat shim、损坏映像）。
2. **Session 0 的非交互桌面堆被耗尽**（`SharedSection` 第二值不够分给新进程的窗口站/桌面结构）。

你已排查的环境变量和文件权限都通向「Node 已经跑起来之后」，与本案不在同一阶段——这就是它们「看起来都正常」却对定位毫无帮助的原因。

下一步只有一件事值得先做：**确认这条事件的 Source 是 `nssm` 还是 `Application Error`，然后测故障时的影响范围是单服务还是整机。** 这两步加起来 5 分钟，能把 14 条候选砍到 2 条。

---

## 8. ⚠️ 异常 / 矛盾 / 空白点

1. **⚠️ 事件的 `Source` 未被说明。** `3221225794` 若是 `nssm` 源记录的，那是 NSSM 转述子进程退出码；若是 `Application Error` / `Windows Error Reporting` 源记录的，说明 WER 已经抓到了 node.exe 的崩溃现场——后者可以直接导 dump，省掉 Procmon 那一步。这两种情况的信息价值差一个数量级，必须分开。
2. **⚠️ 「偶发」的频次与分布未给出。** 是「开机后第一次必挂、重启服务就好」（→ 累积型 #1），还是「跟时间无关、随机挂」（→ 竞态型 #9/#14），还是「某天开始一直挂」（→ 被动变更型 #3/#4）？这三种时间形态指向完全不同的根，而描述里目前无法区分。
3. **⚠️ 「排查过环境变量和文件权限」的具体方法未说明。** 如果是在交互式会话里、用你的账户验证的，那么它没有排除 Session 0 / LocalSystem 上下文下的差异——「都正常」这个结论的适用域可能根本不覆盖故障场景。建议重做一次，明确账户与会话。
4. **空白点：故障时系统的资源水位完全未知。** 提交内存、paged pool、句柄数、系统盘剩余空间、Session 0 进程数——这五项里任何一项触顶都能单独造成 `0xC0000142`，而它们都不在「环境变量 / 文件权限」的检查清单上。

## 9. 💡 灵感备注

- `0xC0000142` 是一个**被严重低估的诊断信号**：它把「应用层问题」和「进程创建环境问题」干净地切开了。团队里如果只有一条排障 SOP，应该把这张 NTSTATUS 对照表放在第一页——`0xC0000142`（DLL 初始化）、`0xC000007B`（位数/映像格式）、`0xC0000022`（权限）、`0xC0000135`（依赖 DLL 缺失）、`0xC0000005`（访问违例）五码分流，能省掉大量「先查代码」的弯路。
- NSSM 托管 Node 的一个廉价加固：给每个服务配 `AppStdout` / `AppStderr` 到独立文件 + `AppRotateOnline 1`，并同时开 WER LocalDumps。**这两件事都不会防止故障，但能把「偶发且零证据」变成「偶发但有现场」——这才是偶发问题的真正成本所在。**
- Windows Server 上服务数量一多，桌面堆就是一个隐形的容量上限。它不在任何「资源管理器」里显示，也没有计数器直接告警，但它和内存一样是会耗尽的。把它加进容量规划清单。
