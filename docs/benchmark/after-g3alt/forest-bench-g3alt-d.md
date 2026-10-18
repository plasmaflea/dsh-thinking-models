# 根源在哪：.NET 单 exe 静默死亡 + side-by-side 报错

[🌳 林状图] [选择理由] 提问是「根源在哪」，且故障形态是「确定性、无堆栈、无进程、无日志」——未知在**因果深度**而非选项广度，命中 `forest-hierarchical-backtracking`：先用「一次成功启动的必经时序」作轴把故障钉到唯一一格，再回溯到类根（这一类为什么在结构上可能），个例根挂在类根下，最后给处置根/消解根两把刀。本轮提问者与新会话均无预设结论，未触发 🧪 倒推闸门（下文中凡是猜测我都显式降级标注）。

---

## L0 类别判定

**软件（子层 `dependency`／`init`）** —— 判据：失败确定可复现（两种启动方式稳定给出同一结果）、只在本机复现而跨机不复现、失败由环境姿态而非物理介质决定。
**已排除的大类**：硬件（无随机性、无 CRC/ECC、系统日志无磁盘重试）、网络（本机双击，无链路）、权限/账号体系（若为权限问题应是「拒绝访问」或 740/0xC0000428，不是 14001）、组织与流程（技术事实已足够定位）。

## L1 树实例化

**树 = `software` → `win-service` · v1 · 核查 2026-10-18**（本轮实例化日 2026-10-18，树未升版）

- 采用 `software` 的六个正交子层作为选层依据：本故障落在 `dependency`（依赖解析）与 `init`（初始化）两格交界。
- 采用 `win-service` 的**第 3 格「PE 加载解析静态导入 + SxS 激活上下文」**——该节点明确记载此格的专属症状是「Application 日志 `source=SideBySide`」。**本次观测与该预测不符，这个不符本身就是判据，见 ⚠️ 第 1 条。**
- **本次判为不适用的节点部分（留档）**：`win-service` 的 `lifecycle` 侧（SCM 创建、Session 0、非交互窗口站、NSSM 包装、AppThrottle）——本例进程由 Explorer/cmd 在交互式会话创建，SCM 与 Session 0 语义全程不参与；`quota`（桌面堆）同理不适用。
- 判定不适用但**保留其码表**：`win-service` 的状态码互斥表用于排除 `0xC0000142 / 0xC0000135 / 0xC0000139 / 0xC000007B / 0xC0000428 / 0xC0000017`，这是本轮最硬的排除工具。
- **树外分支登记**：①「Windows 11 按需功能/精简镜像摘除 WinSxS 子集」②「`PreferExternalManifest` + 同目录遗留外部清单」——两者均不在树内，已进挂起表，未静默丢弃。若需固化为节点，登记 `v2 候选`，理由：现有 `win-service` 第 3 格只覆盖「服务形态下的 SxS」，未覆盖「交互式启动 + 机器本地 store 被外部工具改写」这一类。

## L2 逐层回溯

### 轴的选择（生成式，不列举）

生成源＝**必经时序**：「双击一个 exe → 它跑起来」这条链的每一步都必然存在，一格都不可省；每格必须能说出「这里坏掉时看到什么」——这正是「所有格都空而问题仍在 ⇒ 换轴」的反向用法：本轮的观测是**恰好一个格非空，其余六格空**，与故障形态一一对应。

| 格 | 该格在管什么 | 该格故障的专属症状 | 本次观测 |
|---|---|---|---|
| G1 | 外壳解析与启动请求（Explorer 收双击、解 .lnk、定目标与工作目录） | 无任何反应且命令行也找不到目标：`系统找不到指定的文件` / 快捷方式失效 | **空**（命令行确实发起了启动，只是同一句 SxS 报错） |
| G2 | `CreateProcess` 前置（令牌、完整性级别、AppLocker/WDAC、信任/MOTW） | 740 提权失败、`0xC0000428`（哈希策略）、SmartScreen「已保护你的电脑」、`0x5` 拒绝访问 | **空**（无任何策略类文案） |
| G3 | **激活上下文生成**：读内嵌 manifest（`RT_MANIFEST/1`）、逐条解析 `<dependentAssembly>`、查 WinSxS／`Winners`／私有程序集 | **`ERROR_SXS_CANT_GEN_ACTCTX`＝14001（0x36B1）后 `CreateProcess` 直接返回失败，进程对象从未创建** | ✅ **命中** |
| G4 | 映像映射与静态导入解析（DLL 找到、位数、导出、`DllMain`） | `0xC0000135` / `0xC000007B` / `0xC0000139` / `0xC0000142`，且**进程已存在过**（会短暂出现在任务管理器、会有退出码） | **未到达**（G3 失败即返回，谈不上映射） |
| G5 | CLR 启动（.NET Runtime 加载、AppDomain、程序集绑定） | Application 日志出现 `.NET Runtime` / `.NET Runtime Optimization Service` 源条目、WER 崩溃报告 | **未到达** ⇒ 无 `.NET Runtime` 事件（与观测一致） |
| G6 | `main` / 窗口创建 / 消息循环 | 有窗口一闪、有业务日志、有首行输出 | **未到达** ⇒ 无窗口（与观测一致） |
| G7 | 退出与上报（WER、事件日志落盘、退出码回传） | `Application Error` / `Windows Error Reporting` 事件、非零退出码 | **未执行** ⇒ 无 Application Error、无系统日志（与观测一致） |

**三判据自检**：正交（G3 的根无法解释 G4 的 `0xC0000142`，反之亦然；各格症状互斥）／可生成（每一格都是「进程从点击到 `main` 的必经一站」，一句能说出为什么它必然存在）／可观测（每格都有专属症状，且本轮六格为空能一一对应到观测的空白）。

### 把故障钉进 G3 的推理链（五条事实是收口的，不是并列的）

1. 「任务管理器里连进程都找不到」⇒ **不是「进程起来又死」**。起来又死必然有进程对象、有退出码、有崩溃事件。进程不存在 ⇒ `CreateProcess` 本身返回了失败 ⇒ 故障在**进程对象诞生之前**。
2. 命令行唯一输出是那句 SxS 文本 ⇒ 这是 Win32 `14001`（`0x36B1`, `ERROR_SXS_CANT_GEN_ACTCTX`）的 `FormatMessage` 文本，由 `CreateProcess` 返回、由 cmd/conhost 打印 ⇒ 精确指向 G3。
3. 事件日志三处全空 ⇒ CLR 未加载（无 `.NET Runtime`）、无故障进程（无 `Application Error`/WER）、无内核态事由（无系统日志）⇒ 这不是「证据缺失」，是第 2 条的**确证**。三处空白与「进程从未创建」完全自洽，且除此之外没有第二种自洽解释。
4. 三个月未改 + 编译机未换 ⇒ 排除制品侧全部变量（清单内容、SDK/工具链、链接参数、版本号）。
5. 同文件夹拷到他机运行正常（就在昨天）⇒ 制品字节有效、内嵌清单声明本身**可被满足** ⇒ 不被满足的一侧在**本机的解析环境**，不在 exe。

五条合起来只剩一个坐标：**G3 的「解析对象」（机器本地 store／注册表）与 exe 清单的「声明」不再匹配，或 store 本身坏了。**

### 类根

> **exe 的启动依赖解析权（激活上下文生成）被代持给了机器本地的 side-by-side 子系统，而制品没有把这个依赖自包含。** 于是同一份字节在不同机器上「生死不同」，且失败发生在任何可观测设施（进程对象、CLR、事件日志）存在之前——「无窗口、无进程、无日志」不是三个故障，是这一个故障的三个面。

这就是 `software` 节点类根「某个本该由应用掌握的控制权被外部机制代持」在本例的具体形态：被代持的是**依赖解析**，代持者是 `WinSxS` + `HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\SideBySide`。

```
类根：启动依赖解析被代持给机器本地 SxS，制品未自包含
 ├ 个例根 I1：依赖的程序集已从本机 store 消失（卸载运行库／精简镜像／去臃肿工具摘除）
 ├ 个例根 I2：本机 store 被破坏（文件级还原打断 WinSxS 硬链接／清理器删内容／ManifestCache 损坏）
 └ 个例根 I3：解析配置态被改（Winners／InstallRoot／PreferExternalManifest／WinSxS ACL 被「安全加固」收紧）
```

三者同层、同格（G3）、彼此正交：任何一个都能独立产生 14001，也可以同时存在。

### 个例根（本机机制）

这台机器上，G3 要解析的那一条 `<dependentAssembly>` 已经不可满足。**最可能的候选对象**：`Microsoft.Windows.Common-Controls` 6.0.0.0（Visual Studio 的默认 `app.manifest` 只要勾了视觉样式就带上这一条，它是 .NET Framework 桌面项目的**唯一**一条 SxS 依赖），其次是某个 VC 运行库（`Microsoft.VC*.CRT`，仅当项目是 C++/CLI 或带原生引导段时存在）。
**该具体是哪一条、以及它是怎么没的——这两个问题从题面信息推不出来，必须由 `sxstrace` 定案（见 ✅）。此处标记为「高置信猜测，未定案」。**

### 为什么「双击静默」而「命令行有一句话」——不是两个故障

同一个失败，两个 UI 面：
- cmd 调 `CreateProcess` 失败后，用 `FormatMessage` 打一行 ⇒ 你看到那句话。
- Explorer 的失败走「硬错误 UI / Windows 错误报告」对话框，而这个 UI **可以被整体抑制**：`HKLM\SOFTWARE\Microsoft\Windows\Windows Error Reporting\DontShowUI = 1`（企业镜像/组策略/用户点过「不再显示」都会设上）。抑制后就是彻底静默——无窗口、无弹窗、无进程。
⇒ 「双击什么都不发生」证明的不是「第二次不同的故障」，而是**这台机器连故障的可见性都关掉了**。这恰好也解释了为什么题面里只剩命令行一句孤证。

### 为什么「日志里真的什么都没有」——树节点预测落空

`win-service` 第 3 格预测 G3 故障会写 `Application` 日志 `source=SideBySide`（典型 ID 32/33/59）。本次为空，只有两种解释：
- **（更可能）归因设施本身也在 store 里**：SideBySide 事件的 provider 注册与消息资源 DLL 都落在 WinSxS/注册表，store 一旦被破坏，连「把错因写进日志」这一步都做不到 ⇒ 反过来加重 I2。
- （次要）检索范围/provider 过滤不完整（见 ⚠️ 第 3 条）。

这条反向推理是本轮最值钱的推论：**「该有的日志没有」在我这里被当作 I2 的加权证据，而不是被忽略的噪声。**

---

## L3 双根

### 处置根（修本次）

按 Cost 升序，前一步的产出决定下一步做什么：

1. **`sxstrace`（5 分钟，决定性）**：`sxstrace trace -logfile:sxs.etl` → 双击/命令行跑一次 → `sxstrace stop` → `sxstrace parse -logfile:sxs.etl -outfile:sxs.txt`。输出会直接给出**解析不到的那条 `assemblyIdentity`（名字＋版本＋publicKeyToken＋processorArchitecture）与尝试过的路径**。报错文本自己就在指这条路——这是全题唯一能一次结束争论的动作。
2. **按缺失对象反向修**：缺失的是 CRT 类 ⇒ 装回与清单声明版本一致的可再发行包；`DISM /Online /Cleanup-Image /RestoreHealth` + `sfc /scannow` 修 store；`HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\SideBySide\Winners` 与 `InstallRoot` 核对是否被改写。
3. **兜底（store 修不动时）**：给这个 exe 重嵌一个不含 `<dependency>` 的最小清单（`mt.exe -manifest app.manifest -outputresource:tool.exe;#1`），当场绕过解析。
4. **顺手恢复可见性**：去掉 `DontShowUI`，让下次故障能一眼看见——把「查不到」这一类消解掉（注意：这是观测性改善，不是本轮消解根）。

### 消解根（灭这一类）

> **让制品的启动路径上不存在任何需要机器本地 SxS 解析的声明。** 具体：删掉内嵌清单里的 `<dependency>` 段（保留 `asInvoker` + `supportedOS` + `dpiAware` + `compatibility`）；确需运行库则改为 app-local 私有程序集或 self-contained 单文件，把依赖随制品走。

- **① 不可发生判据**：manifest 里不存在 `<dependentAssembly>` ⇒ 加载器在 G3 **没有要从机器 store 解析的对象** ⇒ 14001 这一类在结构上不可能发生，而不是「变少见」。本类的发生入口被物理删除，不是被修好。
- **② 可执行首边**：打开项目的 `app.manifest`，删掉 `<dependency>` 节点 → 重编译 → 在出问题那台机器上双击一次。**半天内可完成，不需要先搞清 store 到底哪坏了。**
- **③ 成本量级**：1 人 · 0.5 天（改 + 重编译 + 验证）；若要连 CI 干净 VM 冒烟一起做，约 1 人 · 1 天。（定量交 📐 公式图；此处只给量级。）

**与处置根的分工**：处置根救这台机器（分钟级，一次性）；消解根救整类（半天级，永久）。二者不互相替代——只做处置根，下次换台机器重演；只做消解根，这台机器今天还是打不开。

## L4 迁移出口

消解根一旦落地，必然带来这五个新问题（不列出来，「不解决具体问题」就是遗漏而不是策略）：

1. **视觉与 DPI 回归**：删掉 Common-Controls 依赖后控件退回经典外观，`dpiAware` 行为需真机核对——一定会踩，成本低但必踩。
2. **分发体积与更新**：改 self-contained ⇒ 从「几百 KB 单 exe」变成 60–100 MB 级；内网分发、增量更新、版本回滚的成本全部上升。
3. **补丁责任转移**：.NET／CRT 的 CVE 不再由 Windows Update 兜底，必须自建「重编译节奏 + 依赖清单/SBOM」；这是长期运营负担，不是一次性改造。
4. **信任与 AV**：大体积单文件、自解压到 `%TEMP%\.net`、MOTW 行为差异 ⇒ AV 误报与拦截风险上升；需要代码签名与例外流程。
5. **组织能力**：现场排障手册「装个运行库就好了」整段失效，要换成「版本自检 + 自动更新」。

**→ 本次问题降级为第 3 项（运行时分发与补丁节奏）下的一个子项**，而不是「环境坏了修环境」这类一次性处置。

## 候选根排序（Share × Lever ÷ Cost，上下级结构）

| 层级 | 候选根 | Share（能解释多少观测） | Lever | Cost | 排序 |
|---|---|---|---|---|---|
| 类根 C | 启动依赖解析被代持给机器本地 SxS，制品未自包含 | 唯一（解释全部 5 条观测的形状） | 改架构 | 0（结构性推论，无需实验） | **1** |
| 个例 I1 | 依赖的程序集从 store 消失 | 主因 | 改配置（装回） | 5 分钟 `sxstrace` + 查已安装程序 | **1** |
| 个例 I2 | store 被破坏（硬链接断裂／清理器／ManifestCache） | 主因（且解释「连 SideBySide 事件都没有」） | 改环境（`DISM`+`SFC`） | 30–60 分钟 | **2** |
| 个例 I3 | 解析配置态被改（Winners／InstallRoot／ACL／PreferExternalManifest） | 共因 | 改配置 | 10 分钟 `reg query` | **3** |
| 观测 I4 | 硬错误 UI 被抑制（`DontShowUI`） | 次要（只解释「双击静默」，不解释 14001） | 改配置 | 1 分钟 | **4** |
| 观测 I5 | 磁盘/文件系统损坏 | 次要 | 动不了（需换盘） | 小时级 | **5** |

排序即预算：I1/I2 用半小时的 `sxstrace` 就能分清，所以不先做任何重装、不做系统还原、不问「你是不是改了什么」——**Cost 就是预算，先做最便宜且能一剑封喉的那一刀。**

---

## 挂起表

| 分支 | 判定 | 依据 | 恢复条件 |
|---|---|---|---|
| .NET Framework 缺失／版本不符 | **不是根** | 该场景文案是 "To run this application, you must first install…" 或 `0xC0000135`/`0xC0000139`；且 CLR 会先起进程，必有 `.NET Runtime` 事件 | 若 Application 日志出现 `.NET Runtime` 源条目，或 `sxstrace` 显示缺的是 CLR 程序集，则推翻 |
| exe/清单损坏、编译产物变了 | **不是根** | 三个月未改、编译机未换、整文件夹他机运行正常 | 若 exe 的 PE 时间戳或哈希与三个月前基线不一致则推翻 |
| 传输损坏／ACL／MOTW 区域标记 | **不是根** | 整文件夹拷走后他机可运行；MOTW 的症状是 SmartScreen 拦截，不是 14001 | 若双击出现「Windows 已保护你的电脑」或提示缺少文件则推翻 |
| 杀软/EDR 拦截 | **不是根** | 拦截码是 `0xC0000428`（WDAC/AppLocker）或 `0x5` 拒绝访问；且命令行不会稳定输出同一句 SxS 文本 | 若目录/进程加白名单后错误消失则推翻 |
| 位数不符（32/64） | **不是根** | 报 `0xC000007B` 或「不是有效的 Win32 应用程序」 | 若 `sxstrace` 出现 `processorArchitecture` 不匹配记录则推翻 |
| 内存/句柄/桌面堆配额 | **不是根** | 报 `0xC0000017`/`0xC000012D`；且不会只在双击时「什么都没」而命令行只给一句 SxS | 若同机其他程序也开始随机启动失败则推翻 |
| 双击目标 ≠ 命令行目标（快捷方式指向另一份拷贝） | **需复核** | 题面未声明两者路径相同；若不同，G1 的「无症状」判定要重切 | 若快捷方式属性中的目标路径与命令行路径不同则推翻 |
| 「日志里什么都没有」＝全体 provider | **需复核** | 题面只点名排除了 `.NET Runtime` 与 `Application Error`；`MsiInstaller`、`WindowsUpdateClient`、`SideBySide`、`Windows Error Reporting` 是**不同 provider**，未被排除 | 若两天前存在 `MsiInstaller` 卸载记录 ⇒ I1 直接结案 |
| （树外）按需功能/精简镜像摘除 WinSxS 子集 | **保留待查** | 不在树内，但属 I1/I2 同类；若 store 修复后仍失败则按此复查 | 若 `DISM /Get-Capabilities` 或镜像来源显示经过 NTLite/精简，则升为个例根 |
| （树外）`PreferExternalManifest=1` + 同目录遗留外部清单 | **保留待查** | 这能完美解释「他机正常、本机报错」：他机忽略外部清单，本机读了它。但该键在 Win10 1607+ 支持情况有争议，且题面未提同目录有 `.manifest` | 若本机存在该注册表值且 exe 同目录有 `<exe>.manifest`，则升为个例根 I3 的主机制 |
| 「双击无弹窗」是第二个故障 | **不是根** | 与命令行失败同源同码；`DontShowUI` 一项即可完全解释静默 | 若在 `DontShowUI=0` 后双击出现 SxS 弹窗，则确认同源；若仍无反应则需重查 G1/G2 |

## 结论

**根源不在那个 exe，也不在 .NET，在这台机器的 side-by-side 激活上下文解析链上。**

`CreateProcess` 在 G3（生成激活上下文）就已经失败并返回 `14001`，进程对象从未被创建——所以「没有窗口、任务管理器没有进程、三处事件日志全空」不是三个故障，而是同一个失败的三个面：没有进程就没有 CLR 事件，没有进程就没有崩溃报告，SxS 是纯用户态加载器问题所以系统日志天然无感。

exe 内嵌清单里声明的那条**机器本地**依赖（最可能 `Microsoft.Windows.Common-Controls` 6.0.0.0，其次某个 VC CRT）在这台机器上已经无法解析：要么它随某次卸载／精简镜像／去臃肿工具从 store 消失了，要么这台机器的 WinSxS 本身被破坏（文件级还原打断硬链接、清理器删内容、ManifestCache 损坏）。**而「另一台机器昨天跑得好好的」正是判据本身**：制品字节有效、清单可被满足，不能被满足的一侧只可能是本机的解析环境。

定案只需一条命令：`sxstrace`。它会直接说出缺哪个程序集、要什么版本、在哪些路径找过——这一步的成本是 5 分钟，在这之前做任何重装、还原、改注册表都是浪费。

**一句话的根**：制品不自包含，把「启动依赖解析」这个控制权交给了机器本地的 store；前两天那台机器的 store 变了（被摘掉或被破坏），于是同一份 exe 在同一台机器上再也起不来——快得连进程都来不及出现，也快得来不及留下任何日志。

---

## ✅ 验证（可执行取证路径，按 Cost 排序；**未在本机执行**，以下为推理产物导出的动作清单）

1. `sxstrace trace -logfile:sxs.etl` → 运行 exe → `sxstrace stop` → `sxstrace parse -logfile:sxs.etl -outfile:sxs.txt`（5 分钟，决定性）
2. `mt.exe -inputresource:tool.exe;#1 -out:tool.manifest`，看内嵌清单里有几条 `<dependentAssembly>`（5 分钟，决定修法分支）
3. `dir %WINDIR%\WinSxS\Manifests\*common-controls*`；`reg query "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\SideBySide\Winners"`；`reg query "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\SideBySide" /v PreferExternalManifest`（10 分钟）
4. `Get-WinEvent -LogName Application -MaxEvents 200`（**不只看 `.NET Runtime`/`Application Error`，要看 `MsiInstaller` 与 `SideBySide`**），对照「前两天」的时间线（10 分钟）
5. `sfc /scannow` + `DISM /Online /Cleanup-Image /RestoreHealth`；顺带看 `%WINDIR%\WinSxS\ManifestCache` 是否存在且非空（30–60 分钟）
6. 反证自检：`reg query "HKLM\SOFTWARE\Microsoft\Windows\Windows Error Reporting" /v DontShowUI`——若为 1，「双击静默」当场解释完毕，不必再找第二个故障（1 分钟）

## ⚠️ 异常/矛盾/空白

1. **报错文本与日志矛盾**：文案承诺「see the application event log or use sxstrace.exe」，而 `Application` 日志里没有 `source=SideBySide` 条目，与树节点 `win-service` 第 3 格的专属症状直接冲突。这要么说明归因设施本身也坏了（加权 I2），要么说明检索范围不完整。**不澄清这一点，I1 与 I2 无法判别。** 建议：先只做「看全 provider」，再谈修。
2. **「双击」与「命令行」是否同一路径/同一文件**未声明。若快捷方式指向另一份拷贝，G1 的判定要重切。
3. **「日志什么都没有」的口径过窄**：明确排除了 `.NET Runtime` 与 `Application Error`，但 `MsiInstaller` 才是解 I1 的钥匙，`WindowsUpdateClient` 是解「两天前发生了什么」的钥匙——三者是不同的 provider，不能互相代表。
4. **三项关键事实缺失**，它们直接决定个例根的子分支：①该 exe 是 .NET Framework 还是 .NET Core/5+；②是否内嵌 manifest；③清单里到底声明了哪几条 `dependentAssembly`。缺 ①③ 时「Common-Controls」只是高置信猜测。
5. **「前两天开始」这个时间点没有被利用**：题面只说日志里没东西，但没说这两天装/卸了什么。时间线取证（已安装程序按日期排序 + `MsiInstaller`）是本轮最便宜的一条旁证，却完全空着。

## 💡 灵感备注

- 把 `14001` 当**环境指纹**用：凡是「同一份字节在不同机器生死不同、且失败无日志」的问题，第一问永远是「这一步的解析权在谁手里」。这个问法能把排查从「猜配置」变成「查代持者」。
- 「没有日志」经常被当成信息缺失；本例里它是**信息本身**——三处空白恰好划出了「进程从未创建」这个唯一解。下次遇到「什么都没发生」，先问「按设计，本该发生的第一件事是什么」，再问「它为什么连第一件事都没发生」。
- 给这类分发制品加一条 CI 冒烟：干净 VM 上双击一次 + 断言进程存活 3 秒。成本 1 人日，挡掉整类「只有现场才炸」的问题——这是把消解根工程化，而不是靠人记。

[技能] forest-hierarchical-backtracking
