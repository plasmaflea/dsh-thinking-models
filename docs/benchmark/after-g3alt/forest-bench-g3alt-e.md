# 根源在哪：exe 双击无反应、命令行只回 side-by-side configuration is incorrect

[🌳 林状图] [选择理由] 用户问的是「根源在哪」，命中回溯法触发词；且四个观测事实（无窗口／无进程／无 .NET Runtime 与 Application Error 日志／错误文本是加载器侧的 SxS 文案）构成一个「故障点在哪一层」的因果定位问题，不是选项广度问题、也不是定量问题。故用林状图，不用网状图与公式图。

## L0 类别判定

**类别**：软件类问题（判据：失败可复现于同一份二进制、跨机器行为分叉、错误文本确定性；符合 `software` 节点两条判据；已排除硬件（无随机性/无校验错误，同一文件在另一台机器上稳定跑通）、网络（不涉及可达性，且拷贝到本地路径同样失败）、权限/账号（报错是 SxS 而非 Access Denied，且换机器即好）、组织流程（技术面已有确定性文本，无人的决策滞留））

## L1 树实例化

**树 = `software`（L0 节点）→ 子层 `init` + `dependency` · v1 · 核查 2026-10-18**
根索引 v1 · 核查 2026-10-18。

- 本次判为**不适用**的节点：`software / win-service`。其判据是「进程由 SCM／NSSM 创建、运行在 Session 0 非交互窗口站」——本例题是交互式桌面应用双击启动，判据不满足，整节点不实例化。
- 但该节点的**第 3 格（PE 加载解析静态导入 + SxS 激活上下文）**作为共享格被借用：借用的是「故障发生在进程创建阶段的哪一格」这一时序结论，不是它的 Session 0 归因。此借用显式记账，不静默使用。
- **树外分支（登记，不丢弃）**：知识树当前只有服务形态节点，没有「交互式桌面／双启动路径（ShellExecute vs CreateProcess）」节点 → 登记 `desktop-interactive` 为 **v2 候选**，理由：本题的观测分叉（双击无提示、命令行有提示）正好落在这个缺失节点里，现有树无法表达。

## L2 逐层回溯

### 选轴（生成式，不是列举）

生成源 = **一次双击启动的必经时序**（一步一格）。为什么必然存在：任何 Win32 进程从「用户双击」到「窗口出现」，必须依次经过 Shell 发起 → 映像映射 → 激活上下文生成 → 静态导入与 DllMain → CLR 初始化 → 托管入口之后的窗口创建。六格正交（各格失败的错误来源不同）、可生成、可观测（各有专属症状）。

| 格 | 该格管什么 | 该格故障的专属症状 | 与本题观测的一致性 |
|---|---|---|---|
| G1 Shell 发起（Explorer→ShellExecuteEx） | 识别 exe、决定用什么方式 CreateProcess | 双击完全无反应（无提示）/「找不到关联程序」；命令行正常 | ✓ 只解释「双击无提示」，解释不了 SxS 文本 |
| G2 映像映射与 PE 校验 | 架构、映像完整性、签名/策略 | `0xC000007B`「不是有效的 Win32 应用程序」/ `0xC0000428` 被策略拦截 | ✗ 文本不符 |
| **G3 激活上下文生成（清单 → dependentAssembly → WinSxS／注册表 Winners）** | 用本机全局装配库把清单声明的依赖解析成激活上下文 | **ERROR_SXS_CANT_GEN_ACTCTX(14001)，文案正是本题那句**；托管代码 0 行执行；无进程残留 | ✓ **唯一全中**（见下） |
| G4 静态导入解析与各 DLL 的 DllMain | import table 逐条解析、DllMain 返回值 | `0xC0000135` 缺 DLL / `0xC0000139` 缺导出（运行库过旧）/ `0xC0000142` DllMain 失败；有的会点名 DLL | ✗ 文本不符 |
| G5 CLR 初始化（.NET Runtime 起来、config、强名称、JIT） | 运行时加载与托管入口 | **必有 `.NET Runtime` 事件 1000/1026**、错误对话框、进程存在过 | ✗ 与「日志一条都没有」直接冲突 |
| G6 托管 main 之后（WinForms/WPF 窗口、外部 DLL、权限、配置） | 业务与窗口创建 | 有窗口或半窗口、有 WER 转储、有 Application Error、有业务日志 | ✗ 与「什么都没有」直接冲突 |

**全空列判据的反向用法**：本题不是「所有格都空」，而是「只有 G3 一格能同时解释四条观测」。四条观测互相锁死：
- 有 SxS 文本 → 只能是 G2/G3/G4 之一（系统错误码族）；
- 文本精确等于 14001 → 只能是 G3；
- 无 .NET Runtime／无 Application Error → 托管运行时（G5）从未初始化、进程也从未「崩溃」（崩溃才写 WER）；
- 任务管理器无进程 → 进程在 CreateProcess 返回前即终止或存续短于任何采样间隔；
- 系统日志无新东西 → 预期，SxS 激活失败不是驱动/服务/内核事件，不进 System 日志。

### 层2：G3 内部按恒等式分解

恒等式（生成源 = 等号右边的因子）：

```
激活上下文 = f( 请求侧: exe 清单里的 dependentAssembly 列表,
               供给侧: 本机 WinSxS 装配库 + 注册表 SideBySide\Winners／激活上下文缓存,
               中间件: sxs.dll 的解析与重定向策略(publisher policy/redirection) )
```

- **请求侧不变**：exe 三个月未改、编译机未换、同一份文件夹在另一台机器上昨天跑通 → 请求侧不是变量，且在另一环境下**可满足**。
- 因此失败必然落在**供给侧或中间件**：本机用来满足该请求的装配，在前两天被某次安装／卸载／更新／清理改动（注册表 Winners 与 WinSxS 是所有安装程序共享写入的全局状态，第三方 installer、VC++ redist 卸载、DISM `/StartComponentCleanup /ResetBase`、第三方「系统清理/精简」工具都能改它，而应用既没有写权限也没有读取失败的观测权）。

→ **类根**：**进程启动前的依赖解析权被操作系统代持**。应用无法在自己的代码里声明「我自带哪个版本的装配」，加载器必须先用本机全局共享装配库把清单解析成激活上下文；这个库跨所有软件共享写入，而解析失败的后果落在「应用第一行代码之前」——所以故障在任何日志能力之前发生，表现为「无窗口、无进程、无日志」。

  └ **个例根**：exe 清单声明的某个 `dependentAssembly`（最常命中 `Microsoft.VC80.CRT` / `Microsoft.VC90.CRT`，其次 `Microsoft.Windows.Common-Controls 6.0.0.0`；若清单带 publisher policy，还可能是被重定向到一个已删掉的旧版本）在本机供给侧解析不出来 → `CreateProcess` 返回 `ERROR_SXS_CANT_GEN_ACTCTX(14001)`，系统按该错误码的标准文案弹出／打印「The application has failed to start because its side-by-side configuration is incorrect.」。

## L3 双根

**处置根（修本次，按预算排序执行）**
1. 把 exe 的清单取出来看它到底依赖什么：`mt.exe -inputresource:tool.exe;#1 -out:tool.manifest`（或 `sigcheck -m tool.exe`）。这一步把搜索空间从「整个系统」缩到 1–3 个 `assemblyIdentity`。
2. 抓失败的确切装配名：`sxstrace trace -logfile:sxs.etl` → 复现一次 → `sxstrace parse`，得到「期望版本 vs 实际可见版本」。
3. 按名字处置：VC 运行库类 → 重装对应位数与版本的 `vcredist`（重装会重写 Winners）；Common-Controls／系统装配类 → `sfc /scannow` + `DISM /Online /Cleanup-Image /RestoreHealth`；有 pending reboot 先重启（半提交的 WinSxS 状态会让解析在重启前后分叉）。
4. 若清单侧解析就失败（不是装配缺失，而是请求本身读不出来）：清掉 exe 同目录同名外部 `*.manifest`、`*.local` 目录；查 `HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\Layers` 是否有该路径的 shim；确认 exe 在本地 NTFS 路径而非 UNC/同步盘/被重定向的目录。

**消解根（灭这一类）**
把依赖解析权从「本机全局共享装配库」收回到 exe 自带：**清单零外部 `dependentAssembly`**——C++ 侧静态链接 CRT，不再把 Common-Controls 6 当硬依赖（或明确接受老样式），.NET 侧用 self-contained 而不是依赖机器上的 redist。

- **不可发生判据**：若清单中不含任何外部 `dependentAssembly`，则加载器生成激活上下文时**不存在可失败的解析请求** → `ERROR_SXS_CANT_GEN_ACTCTX` 这一类（随本机装配库某天被别的安装程序改动而突然炸、且跨机器行为分叉）在结构上不可能发生，不是变罕见。✓
- **可执行首边**：今天就用 `mt.exe` 导出清单、数一遍 `dependentAssembly` 条数（一条命令，不改代码、不动 CI），据此决定「要不要动工程」。✓
- **成本量级**：一次性小时级（清单改写 + 重新构包 + 一次回归）；长期代价是把「运维装个 redist」换成「每次运行库变更都要重新出包」。不涉及架构迁移。✓

## L4 迁移出口

若把消解根继续外推（连 .NET Framework / 运行库的机器依赖都不要，改 self-contained 单文件或原生静态链接），新问题清单：

1. **分发与体积**：自包含单文件 60–150 MB 量级，内部通道／增量更新要跟着改。
2. **签名与信任**：产物哈希变了，SmartScreen/AV 白名单/企业签名流程要重新走一遍。
3. **清单与体验**：DPI、主题、Common-Controls 视觉样式要自己保留或主动放弃。
4. **目标机兼容**：实质放弃 Win7/8.1；x86/x64 双份或只留 x64。
5. **回归与可观测**：打包链校验、启动失败时的自我诊断面包屑（把「查不到」这一子类永久消解）。
6. **组织能力**：从「运维重装 redist」变成「发版流程负责运行库」的技能与值班口径变化。

→ **本次问题降级为**：第 5) 项「部署形态与运行库耦合」的一个子项。

## 候选根排序（Share × Lever ÷ Cost，上下级结构）

| 级 | 候选根 | Share（能解释已观测现象的比例） | Lever（能不能动它） | Cost（排除它要花多少） | 排序 |
|---|---|---|---|---|---|
| 类根 | 依赖解析权被本机全局装配库代持 | 唯一 | 改架构 | 天级 | 第 4（结构结论，但不是第一步动作） |
| 个例 | A. 清单声明的装配在本机缺失/版本漂移（VC redist 被卸/回退） | 唯一～主因 | 改配置（装/修 redist） | 分钟级 | **第 1** |
| 个例 | B. 清单侧解析失败（外部 `.manifest` 冲突、`.local`、appcompat shim、非本地路径） | 共因 | 改配置 | 分钟级（导出比对） | **第 2** |
| 个例 | C. WinSxS 装配库/注册表 Winners 被清理工具或更新破坏 | 主因 | 改配置（DISM/SFC/重启） | 十分钟～小时 | 第 3 |
| 个例 | D. 安全软件拦截 SxS 相关 DLL 加载或抑制提示 | 次要 | 改配置 | 一次白名单 | 第 5 |
| 个例 | E. 系统级 DEP/AppCompat/SRP 策略变化 | 次要 | 改配置 | 一次策略核对 | 第 6 |

## 挂起表

| 分支 | 判定 | 依据 | 恢复条件 |
|---|---|---|---|
| exe 本身被改坏／被替换（含编译产物损坏） | ⊥ 不是根 | 三个月未改、编译机未换、同一份文件在另一台机器跑通 | 另一台机器也失败，或哈希/PE 校验和与基线不一致 |
| 硬件故障（磁盘坏道、内存位翻转） | ⊥ 不是根 | 错误文本确定性、同一文件跨机行为分叉、无 CRC/重试/随机症状 | 出现读取错误、校验失败、同程序时好时坏 |
| 权限/ACL/令牌 | ⊥ 不是根 | 报错族是 SxS（14001）而非 Access Denied；换机器即好 | `icacls`/procmon 报拒绝访问，或换账号前后行为分叉 |
| .NET Runtime/CLR 缺失或损坏 | ⊥ 不是根 | CLR 未装会走「需要安装 .NET Framework」提示或进程活到写 `.NET Runtime` 事件；本题日志为零 | Application 日志出现 `.NET Runtime`/`Application Error` 事件 |
| 位数不符/映像损坏 | ⊥ 不是根 | 会报 `0xC000007B`「不是有效的 Win32 应用程序」，文本不同 | 报错文本变成 0xC000007B 或「不是有效的 Win32 应用程序」 |
| 缺少依赖 DLL（本地 DLL 缺失） | ⊥ 不是根 | 那是 `0xC0000135` 且常点名 DLL；本题是 SxS 文案 | 文本变成 0xC0000135 或出现具体 DLL 名 |
| 病毒把 exe 删掉/隔离 | ⊥ 不是根 | 命令行能执行到报错，说明文件存在且可映射 | 文件大小/签名异常、AV 隔离记录指向该路径 |
| 「双击无提示、命令行有提示」是**第二个**故障点 | ⊥ 不是第二个故障点（判为观测通道差异） | 双击走 ShellExecuteEx、命令行走 CreateProcess；14001 由系统 hard error 弹出，弹窗在 Shell 路径下可能被抑制/落在不可见前台 | 从资源管理器启动时抓到同一句 SxS 弹窗，则本行撤销；若双击报的是别的错，开新分支 |
| 「任务管理器看不到进程」说明进程从未被创建 | ⊥ 表述不精确但结论不变 | SxS 失败时进程对象可能已建后立即终止，或存续短于采样间隔 | 若在「显示所有用户进程」且高频刷新下看到瞬时 PID，本行撤销（不影响定位） |
| Application 日志**没有** `SideBySide` 事件（Event ID 33/59） | ⏸ 挂起（与树节点第 3 格典型症状不符） | 一是清单侧解析失败可能只走 hard error 不落 SxS 事件；二是事件发布通道被抑制/日志被清/组策略关闭 | 检索到 Event ID 33/59 → 确认为「装配缺失」子分支；彻底无事件 → 偏向「清单侧解析失败」子分支（两者同格，处置路径不同） |
| Windows 更新是这两天的触发者 | ⏸ 挂起（可能但未证实） | 系统日志无新事件**不能**反证没打补丁（补丁记录在 Setup/CBS 侧） | `Get-HotFix` 时间戳落在前两天，或 CBS.log/Setup 日志有对应条目 |
| 安全软件注入/拦截 | ⏸ 挂起 | 无法从现有信息判定 | 干净启动（`msconfig` 最小集）或卸载 AV 后复现失败 |
| 第三方清理工具/DISM `ResetBase` 删掉旧版装配 | ⏸ 挂起（最贴「前两天突然变」的时间形态） | 无时间线证据 | 本机前两天有清理动作或装机记录 |
| **树外分支**：知识树缺「交互式桌面应用」节点 | ⏸ 挂起（登记 v2 候选 `desktop-interactive`，不静默丢弃） | 现有树只覆盖 SCM/Session 0 服务形态，无法表达双击/命令行两条启动路径的分叉 | 下一个桌面类案例再次需要该格 → 升版建节点 |

## 结论

根源不在 exe，在**「进程创建之前的依赖解析权被本机全局 SxS 装配库代持」**这个结构上：exe 清单里声明的某个 `dependentAssembly` 在本机解析不出来（`ERROR_SXS_CANT_GEN_ACTCTX` / 14001），加载器在托管代码第一行之前就拒绝启动它。所以那三个「没有」不是「没查到」，而是**故障点在所有日志能力之前**——CLR 从未初始化（无 `.NET Runtime`）、进程从未崩溃（无 Application Error/WER）、SxS 失败又不进系统日志，任务管理器因此连 PID 都抓不到；exe 三个月未变、别处能跑，恰恰把变量唯一地钉在「本机这两天被动过的装配库/解析环境」上。下一步按处置根四步走：`mt.exe` 导出清单看它依赖什么 → `sxstrace` 抓解析失败的确切装配名 → 装/修对应 redist 或 `DISM /RestoreHealth` / 清掉同名外部清单与 shim；要灭这一类，则把清单改成零外部 `dependentAssembly` 的自包含部署。

## ✅ 验证

- **互斥表内部校验**：G2/G4 的错误码族（`0xC000007B`/`0xC0000135`/`0xC0000139`/`0xC0000142`）各自有专属文案，均不等于本题文案；G5/G6 必然留下 `.NET Runtime` 或 `Application Error` 事件，与「日志为零」直接冲突。剩余唯一可行格 = G3。
- **外部锚点**（用于确认 14001 的两个子分支「清单找不到」与「装配找不到」，与本文层2 的请求侧/供给侧分解一致）：[Microsoft Q&A：遗留 Windows 应用启动失败——Side-by-Side 清单或装配找不到](https://learn.microsoft.com/fr-fr/answers/questions/6038314/chec-de-lancement-dune-application-windows-h-rit-e)、[SAP：The application has failed to start because its side-by-side configuration is incorrect（SideBySide Master）](https://userapps.support.sap.com/sap/support/knowledge/en/1902990)、[Error 14001 的服务启动失败记录](https://knowledge.broadcom.com/external/article/286632/server-service-fails-to-start-with-error.html)。
- 未做任何本机复现（按要求），以上定位由题面四条观测 + 加载器时序推出，处置根的每一步都是可验证动作。

## ⚠️ 异常/矛盾/空白

1. ⚠️ **Application 日志缺 `SideBySide` 事件**：知识树 `win-service` 第 3 格的典型症状是「`source=SideBySide`」。本题日志为零 → 要么清单侧解析就失败（只走 hard error），要么事件通道被抑制/日志被清。建议：按 `source=SideBySide` 与 Event ID 33/59 定向检索一次再定子分支。
2. ⚠️ **双击零提示 vs 命令行有提示**：这是观测通道差异（ShellExecuteEx 的 hard error 弹窗可见性），不是第二个故障点。建议：从资源管理器启动时用 `sxstrace` 在跑、并临时关掉 AV 弹窗抑制再试一次。
3. ⚠️ **树缺节点**：没有「交互式桌面应用」节点，本题的双启动路径分叉无处安放，已登记 v2 候选。
4. ⚠️ **空白**：题面没说「这两天本机装过/卸过什么」——这正是唯一缺的那条时间线证据，它决定个例根落在 A/B/C 哪一支。

## 💡 灵感备注

这类「什么都没有」的故障，判据不是「查不到」，而是「故障点落在所有日志能力之前」。把日志能力的起点按时间轴排出来（Shell→映射→激活上下文→DLL→CLR→main），空白本身就是一个坐标。附带经验：清单零外部 `dependentAssembly` 的 exe，永远不会以这种方式死——它把一整类「某天被别的安装程序弄炸」的风险从结构上删掉了。

[技能] forest-hierarchical-backtracking
