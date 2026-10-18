[🌳 林状图] [「根源在哪」是回溯触发词，且这是故障定位问题——因果深度未知而非选项广度未知，故用林状图；轴取**必经时序**（一次 Windows 服务进程从收到启动请求到进入 JS 主循环，每步必然发生且只发生一次），不取「权限/环境/DLL/杀软/配置」那种列举式轴]

---

## 0. 先解码：这个数字本身就把搜索空间砍掉了 90%

3221225794 = **0xC0000142** = `STATUS_DLL_INIT_FAILED`（signed32 又写作 **-1073741502**）。

这不是 Node.js 的退出码，是 **Windows 加载器/ntdll 的 NTSTATUS**。含义精确到字面：进程被创建了、PE 文件被映射了、静态导入的 DLL 也都被找到了 —— 但**其中某个 DLL 的初始化例程（DllMain）返回了 FALSE 或初始化超时**，加载器随即调用 `TerminateProcess`，进程死在 `main()` 之前。

用同族状态码互斥，直接用排除法砍枝（这一步比任何猜测都硬）：

| 若原因是 | 会得到 | 所以 |
|---|---|---|
| 依赖 DLL 缺失 | 0xC0000135 (`DLL_NOT_FOUND`) | ✗ 不是缺 DLL |
| 位数/映像损坏 | 0xC000007B (`INVALID_IMAGE_FORMAT`) | ✗ |
| 运行库存在但过旧、导出缺失 | 0xC0000139 (`ENTRYPOINT_NOT_FOUND`) | ✗ |
| 哈希/签名策略拦截（WDAC/AppLocker） | 0xC0000428 (`INVALID_IMAGE_HASH`) | ✗ |
| 内存不足 | 0xC0000017 (`NO_MEMORY`) | ✗ |
| **DLL 的 DllMain 说"我初始化不了"** | **0xC0000142** | ✅ 就在这一层 |

**推论**：故障点位于「PE 加载器 + DLL 初始化」这一段，**在 Node 运行时存在之前**。所以"没有堆栈"不是信息缺失，而是**位置证据**——JS 引擎还没起来，当然没有堆栈。

---

## 1. 选轴（生成源：必经时序，一步一格）

**格 1｜SCM 服务控制与 NSSM 包装**
生成理由：服务必须先被 SCM 接受，NSSM 必须先 `CreateProcess`。
故障症状：1053（启动超时）/ 1066 / 7000 / 1060，或 NSSM 报 `CreateProcess failed`（错误码 2/5/206）。**不产生 0xC0000142。**

**格 2｜令牌、会话、窗口站与桌面**
生成理由：进程要有 token、要落到 Session 0 的非交互 window station + desktop 才能跑。
故障症状：加载 `user32.dll`/`gdi32.dll` 的进程在 DllMain 处失败 → **0xC0000142**；特征是**开机自启失败、事后手动 `net start` 却成功**（资源竞争型）。

**格 3｜PE 加载器解析静态导入 + SxS 激活上下文**
生成理由：node.exe 的 import table 必须逐条解析，manifest/activation context 必须先激活。
故障症状：0xC0000135 / 0xC000007B / 0xC0000139，Application 日志出现 source=`SideBySide` 的错。SxS 激活失败在部分实现里会落到 0xC0000142。

**格 4｜每个已加载 DLL 的 DllMain（含被动注入的 DLL）**
生成理由：凡进入进程地址空间的 DLL，其 DllMain 都会被调用一次，一个返回 FALSE 就整进程死。
故障症状：**0xC0000142**，且「退出前最后一条 `Load Image` 就是凶手」；偶发性来自 EDR 签名更新时机、注入竞态。

**格 5｜进入 main，Node 启动（env / cwd / 权限 / 端口 / `require` 原生 addon）**
生成理由：main 之后才轮到你写的东西。
故障症状：JS 异常、`EACCES`、`ENOENT`、`EADDRINUSE` —— **都有堆栈有输出**。这一层在结构上**无法**产生 0xC0000142（唯一漏洞：把子进程的 NTSTATUS 透传成自身退出码）。

**格 6｜NSSM 的退出处理与上报**
生成理由：NSSM 是父进程，退出码由它写进事件日志。
故障症状：`AppExit` + `AppThrottle`（默认 1500ms）把"确定性失败"包装成"偶发重启"；没配 `AppStdout`/`AppStderr` 则**永远没有 stdout**。

> 三判据自检：正交 ✓（六格的根互不解释对方症状）；可生成 ✓（每格一句"为什么必然存在"）；可观测 ✓（每格都有专属症状）。格 5 与格 6 全空 ⇒ 坐标系没选错，而是**根不在那儿**。

---

## 2. 逐格回溯：定语法（必要／充分／挂起）

- **格 1 → 结果**：`⊥`。SCM/NSSM 只负责把子进程的退出码**转述**出来；`CreateProcess` 失败会报 NSSM 自己的错误码，不会伪造 NTSTATUS。**NSSM 是信使，不是根。**
- **格 2 → 格 4**：`充分不必要`。桌面堆耗尽 ⇒ `user32` 的 DllMain 失败 ⇒ 0xC0000142（充分）。但 0xC0000142 不必由桌面堆解释（不必要）——所以它是候选根，不是唯一根。
- **格 3 → 格 4**：`必要`。所有分支都必须过加载器；但加载器自身失败码不同（见上表），所以格 3 只在 SxS 激活这一子情形上与 0xC0000142 相交。
- **格 4 → 结果**：`充要`。**0xC0000142 的定义就是"某个 DLL 的初始化失败"**。这是唯一与症状等价的格 —— 也就是说，"哪一个 DLL、为什么失败"才是唯一的开放问题。
- **格 5 → 结果**：`⊥`（除透传子进程码）。发生在 JS 层之后的故障会留下 JS 证据，与"无堆栈无输出"矛盾。**环境变量和文件权限就落在这里 —— 你对它们的排查结论正常，是结构上的必然，不是运气。**
- **格 6 → 观测**：`⊥`（不改故障），但它**改"偶发"这个观测**。

---

## 3. 汇合层（三层回溯合并）

- **背景现象层**：Windows Server + NSSM + Node.js，进程启动即退，事件日志仅 exit code 3221225794，无堆栈无 stdout，环境/权限已排除。
- **提问者意图层**：你要的不是"DLL 初始化失败"这句同义反复，而是"**到底哪个环节在我这套部署里必然踩到**"，且要能一次定位、不靠猜。
- **问题本身根源层**：服务形态与交互式形态之间，**多了三样交互式运行从来没有的东西**——① 非交互窗口站的桌面堆配额；② 在服务上下文里同样加载、但初始化条件不同的注入型 DLL；③ 开机时多进程并发加载 DLL 的 loader lock 竞争。

**合并出的真根源（两句话）**：故障发生在**加载器初始化某个 DLL 的阶段**，而不在 Node 里；在服务形态下，这一段比交互式形态多了"桌面堆配额 / 第三方注入 DLL / 并发加载"三个额外失败源，任一被踩中即整进程无声猝死。

**候选根排序（Share × Lever ÷ Cost，Cost 单位＝一次重启/一次采样）**

| # | 候选根 | Share | Lever | Cost | 判据 |
|---|---|---|---|---|---|
| 1 | **注入型 DLL 的 DllMain 失败**（EDR/AV 代理、`AppInit_DLLs`、AppCompat shim、IFEO 调试器/GlobalFlag） | 唯一（可单独解释全部观测） | 改配置/加排除项 | 一次 ProcMon 采样 | 最后一条 Load Image 即凶手；偶发＝签名更新/注入时机 |
| 2 | **非交互桌面堆耗尽**（`SharedSection` 第三个值，默认 768KB） | 主因 | 改注册表 | 一次重启 | **开机自启失败、手动启动成功**是它的指纹 |
| 3 | **SxS / manifest 激活失败**（私有程序集 `.local`、`Microsoft.VC*.CRT` 残留、清单版本不匹配） | 主因 | 装 redist / 改清单 | 一次日志采样 | Application 日志 source=`SideBySide` |
| 4 | node 把子进程 NTSTATUS 透传为自身退出码 | 次要 | 改代码 | 一次文件探针 | 只有 JS 确实跑过时才可能 |

---

## 4. 一次定位的判定程序（按成本从低到高，前两步就能定域）

**① 文件探针（Cost≈0，最决定性）**
在 app **第一行**（任何 `require` 之前）写：
```js
require('fs').appendFileSync('C:\\temp\\boot.log', new Date().toISOString() + '\n');
```
- 文件**没出现** → 确认是加载器级失败，故障在 `main()` 之前，格 5 全体出局，直奔 ②④。
- 文件**出现了** → JS 跑过，退出码另有来源（子进程透传 / 有东西在 JS 之后 `TerminateProcess`），改走格 5。

**② 最小复现，把业务代码摘出去（Cost＝一次重启）**
用**完全相同的服务账户、`AppDirectory`、环境**把探针装成第二个 NSSM 服务：
```powershell
nssm install svc-probe C:\node\node.exe
nssm set svc-probe AppParameters "-p process.version"
nssm set svc-probe ObjectName ".\<同账户>" "<同密码>"
nssm set svc-probe AppDirectory "C:\同目录"
nssm set svc-probe AppStdout C:\temp\probe.out
nssm set svc-probe AppStderr C:\temp\probe.err
nssm start svc-probe
```
它若同样 0xC0000142 → 与你的代码、你的依赖**完全无关**，是环境姿态问题（格 2/3/4）；它若正常 → 你多加载了东西。

**③ 抓凶手 DLL（Cost＝一次采样）**
ProcMon：`Process Name is node.exe` → `Operation is "Load Image"`，看**退出前最后一条**。或开 loader snaps `gflags /i C:\node\node.exe +sls` 配合 DebugView/WinDbg，能直接读到"DLL X 初始化失败"的原文。**更快的一条：`C:\ProgramData\Microsoft\Windows\WER\ReportArchive` 里找 `node.exe` 的 APPCRASH 报告，`Faulting module name` 直接点名**（若 WER 没被关掉）。

**④ 桌面堆（Cost＝一次重启）**
```powershell
reg query "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\SubSystems" /v Windows
```
`SharedSection=xxxx,yyyy,zzzz`：**第一个＝共享段大小，第二个＝交互式窗口站每桌面堆，第三个＝非交互式（服务用的）每桌面堆**。服务态要动的是**第三个**（默认 768，提到 1024～2048，别贪大，吃的是内核分页池）。改完必须重启。
先验证假设再改：`(Get-Service | ? Status -eq 'Running').Count` 与"失败是否只发生在开机/多服务并发启动时"做相关。

**⑤ 注入与 SxS（Cost＝几条查询）**
```powershell
reg query "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Windows" /v AppInit_DLLs
reg query "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Windows" /v LoadAppInit_DLLs
reg query "HKLM\SOFTWARE\WOW6432Node\Microsoft\Windows NT\CurrentVersion\Windows" /v AppInit_DLLs
reg query "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\Layers"
Get-WinEvent -FilterHashtable @{LogName='Application'; ProviderName='SideBySide'} -MaxEvents 20
nssm dump <你的服务名>     # 看 AppStdout/AppStderr/AppExit/AppThrottle 的真实口径
```

---

## 5. [挂起表]

| 分支 | 判定 | 依据 | 恢复条件 |
|---|---|---|---|
| 环境变量配错（`NODE_ENV`/`PATH`/`NODE_OPTIONS`） | ⊥ 不是根 | 环境变量只在 `main()` 之后被读；错值给 `EACCES`/`ENOENT`/JS 异常，都有堆栈。0xC0000142 早于该层 | 若 loader snaps 显示某 DLL 在 DllMain 内读环境变量/注册表并因此返回 FALSE，且改该变量能稳定复现/消除 → 本行恢复（此时环境变量是**上游诱因**，根仍是格 4） |
| 文件权限（node.exe / 目录 ACL） | ⊥ 不是根 | 你排的是"Node 读不到自己文件"这一类；该类给出 0xC0000135/0xC0000022 或 JS 层报错，不是 0xC0000142 | **部分恢复**：若某个被注入的 DLL 在自己的 DllMain 里访问受保护资源（受保护目录、HKLM 项、用户配置文件未加载时的 HKCU）失败 → 权限就是上游诱因。用 ProcMon 看凶手 DLL 失败前的 `ACCESS DENIED` 即可确认 |
| 端口被占用 / 磁盘满 / 内存不足 | ⊥ | 端口占用有 `EADDRINUSE` 堆栈；磁盘满在 JS 层报错；内存不足给 0xC0000017 | 若探针文件未落盘且系统日志同期有资源耗尽记录 → 回到格 2/3 重新评估 |
| 业务代码 bug / 依赖没装 | ⊥ | 需要 JS 跑起来才能触发；且缺模块是 `MODULE_NOT_FOUND` | 若①号探针文件出现（说明 JS 跑过）→ 本行恢复，改查退出码透传路径 |
| NSSM 自身缺陷 | ⊥ 是信使 | 它只把子进程退出码转述进事件日志；`CreateProcess` 级失败会报 NSSM 自己的错误码 | 若 `nssm dump` 显示配置里存在非官方构建/自定义钩子，或换用 `sc.exe` 直接托管同一条命令行后症状消失 → 本行恢复 |
| 杀软/EDR 直接终止进程 | ⊥（作为"根"） | 安全产品 kill 进程通常给 0xC0000006/自有码，且会在其自身日志留事件，不是 DLL 初始化语义 | 若厂商日志显示"在 DllMain 阶段阻断"或加了排除项后症状消失 → 它其实是**格 4 的注入侧**，本行并入候选根 1 |
| 原生 addon（`.node`）的 DllMain 违规 | ⊥（大幅降低） | 关键结构事实：`.node` 是 `require()` 时**用 `LoadLibrary` 动态加载**的，那时 Node 已在跑；失败会走 `uv_dlopen` → JS 抛错，而不是进程以 0xC0000142 猝死 | 仅当存在自定义启动器/延迟加载导入/`.node` 被静态链进自编译的 node.exe 时恢复 —— 此时它归入格 4 |
| 32/64 位混装 | ⊥ | 混装给 0xC000007B，码不符 | 若 WER 报 `Faulting module` 是某个位数不符的 DLL 且实际返回 0xC0000142 → 恢复，按格 3 处理 |

---

## 6. [结论]（从根解决，而不是从症状解决）

**根源**：`0xC0000142` 是加载器状态码，你的 Node 进程**从未启动过**——所以"环境变量和文件权限都正常"是必然的，它们在此故障点下游。真正的根在**服务形态独有的 DLL 初始化差异**上，按证据最可能落在：**某个被注入/被预加载的 DLL 在 Session 0 的非交互上下文里 DllMain 返回失败**（EDR/AppInit_DLLs/shim 侧），其次是非交互桌面堆耗尽（指纹：开机自启必死、手动启动常活），再次是 SxS 激活失败。

**动作（按顺序，前三步基本必中）**：
1. 上文件探针 + 建 `node -p process.version` 对照服务 → 一次性判定"加载器级 vs 业务级"。
2. 开 WER LocalDumps 拿到 `Faulting module name`，或 ProcMon 抓最后一条 `Load Image` → 直接点名凶手 DLL。
3. 若是安全产品注入：让厂商给 `node.exe` 做服务态/Session 0 排除项，别用"关掉防护"当方案。
4. 若是桌面堆：`SharedSection` 第三个值 768 → 1024/2048，重启；并把该服务设为**延迟启动**打散开机并发（这是绕开资源竞争的合法手段，不是掩盖问题）。
5. 若是 SxS/运行库：补齐 x64/x86 对应 VC++ redist，清掉 `node.exe` 旁残留的 `.local` 目录与 `Microsoft.VC*.CRT` 私有程序集。
6. **永久修复观测性（这才是"查不到根"的第二层根）**：`nssm set <svc> AppStdout/AppStderr C:\logs\...` + `AppRotateFiles 1` + 启动面包屑 + WER LocalDumps（`DumpType=2`）。否则下一次同类故障你依然只有四位十六进制。

---

[✅ 验证] 退出码解码经本机 `pwsh` 实跑确认：`3221225794 -> 0xC0000142 (signed32: -1073741502)`。其余为状态码语义与 Windows 服务加载机制的知识推演，**未在你的服务器上取过证**——所以第 4 节的探针必须你来跑，仓促接受任何单一根因都是不负责任的。

[⚠️ 异常/矛盾/空白]
- ⚠️ **「没有 stdout」是弱证据**：NSSM 默认**不捕获**子进程输出，必须显式配 `AppStdout`/`AppStderr` 才有文件。所以"没有任何输出"很可能与故障无关，只是没接线。→ 建议：先接线，再排查，否则会持续误判。同理"事件查看器里只有 exit code"也说明你没开 WER 本地转储。
- ⚠️ **「偶发」可能是 NSSM 造出来的假象**：`AppThrottle`（默认 1500ms）+ `AppExit` 的 restart 策略会把一个**确定性**失败变成周期性重启，看起来像"偶发"。→ 建议：先确认失败率到底是"每次必现"还是"某条件下必现"，这两者的搜索方向完全不同。
- ⚠️ **空白点**：你未提供"是否只在开机后首次失败"、"装了什么 EDR"、"node_modules 里有没有原生 addon"、"nssm dump 的完整参数"。这三条信息能把候选根从 4 条压到 1 条。

[💡 灵感备注] `0xC0000142` 在运维圈有个流传极广的错误归因——"把桌面堆第二项调大"或"装 VC++ 运行库"。但严格按状态码语义：**运行库缺失是 0xC0000135、运行库过旧是 0xC0000139**，都不是 0xC0000142；桌面堆对服务生效的是 `SharedSection` 的**第三项**（非交互窗口站）、不是常被改的第二项。下次有人贴这个码，先看码族再动手，能省掉一整轮试错。

[技能] forest-hierarchical-backtracking
