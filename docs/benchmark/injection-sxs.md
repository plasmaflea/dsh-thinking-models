# SxS 注入实验：`0xC0000142` 与清单失败的码位边界

> 目的：为「林状图漏掉 SxS」这一判分找出地面真值。做法是**真的注入**，不靠推理。
> 结论：**假设被推翻**——SxS/清单失败不会产生 `0xC0000142`，因为进程根本没有被创建。

## 手段

本机无任何原生编译器（`cl.exe` / `gcc` / `clang` / `rustc` / `zig` / `tcc` 全部不存在），无法编一个 `DllMain` 返回 `FALSE` 的原生 DLL。改用现成的 .NET 编译器给托管 exe 打**嵌入清单**：

```
C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe /target:exe /win32manifest:<manifest> /out:<exe> <src.cs>
```

工作目录 `D:\DeepSeek-levelup\sxs-lab`。

## 三个对象与实测

| exe | 嵌入清单里的依赖 | 实测结果 |
|---|---|---|
| `app-good.exe`（3072 B） | 只有自身 `assemblyIdentity name="lab.good"` | exit 0，正常输出 |
| `app-bad.exe`（3584 B） | `Microsoft.VC90.CRT version="9.0.21022.8"` | **exit 0，正常跑起来** |
| `app-bad2.exe` | `TotallyMissing.Assembly.Name version="1.0.0.0"` | **进程从未被创建**；`CreateProcess` 失败并回 `The application has failed to start because its side-by-side configuration is incorrect.`（Win32 **14001 = 0x36B1** `ERROR_SXS_ASSEMBLY_NOT_FOUND`） |

`app-bad.exe` 之所以毫无障碍，是因为本机 WinSxS 里确实存在该程序集：

```
amd64_microsoft.vc90.crt_1fc8b3b9a1e18e3b_9.0.21022.8_none_750b37ff97f4f68b
amd64_microsoft.vc90.crt_1fc8b3b9a1e18e3b_9.0.30729.1_none_99b61f5e8371c1d4
amd64_microsoft.vc90.crt_1fc8b3b9a1e18e3b_9.0.30729.6161_none_08e61857a83bc251
```

（另有 VC80 CRT `8.0.50727.*` 三份。）清单写了依赖 ≠ 依赖会失败；只有依赖**解析不到**才失败。

## 结论：两种失败不在同一层

| | SxS / 清单激活失败 | `0xC0000142` `STATUS_DLL_INIT_FAILED` |
|---|---|---|
| `CreateProcess` | 返回 `FALSE`（14001） | 成功，进程被创建 |
| 宿主看到什么 | 启动失败的错误文案，**没有退出码** | 退出码 `3221225794` |
| 进程是否存在过 | 从未存在 | 存在过，死在 loader/DllMain 阶段 |
| Application 日志 | **有 `SideBySide` 源 Event 33，且直接印出缺失的 assemblyIdentity**（见下） | 可能有 Faulting module |
| 可观测残迹 | `sxstrace.exe` 的激活上下文日志 | 加载器快照 / WER dump |

## 对 benchmark 的影响（必须写进论文）

- v2/v3/v4 的 8 因子表把「⑦ SxS 配置错误」列为 `0xC0000142` 的候选根，**这一步是错的**：直接注入走不通，它顶多是一条两步弱链（某个被加载 DLL 的 `DllMain` 内部再去做激活）。
- 因此「林状图两次都漏掉 SxS」不能算作它的盲区。剔掉 ⑦ 之后：v2 = 6/7，v3 = 7/7，裸机 web = 7/7——**after 与裸机的真因覆盖率差距被抹平**。
- 论文的 limitations 要写这一条：**评分表本身可能把不可达的根算成漏项**，这是评测设计错误，不是方法缺陷；修正方式是每个因子都先做一次可达性注入。
- 剩下的真实盲区只有一条：`⑧ 受限令牌 / 低完整性级别`（两次全 0 命中），且它在 DSH 沙箱场景里是真实根因。

## 复现

```powershell
$csc = 'C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe'
& $csc /nologo /target:exe /win32manifest:bad2.manifest /out:app-bad2.exe app.cs
# 直接跑会看到：The application has failed to start because its side-by-side configuration is incorrect.
Start-Process .\app-bad2.exe -Wait          # 抛错，取不到 ExitCode
cmd /c ".\app-bad2.exe"                      # 同样只回文案，无退出码
```

## 追加实测：SxS 失败**会**写 Application 日志（把我的题面证伪了）

`Get-WinEvent -FilterHashtable @{LogName='Application'; StartTime=(Get-Date).AddHours(-3)}` 过滤 `SideBySide`，取到：

```
TimeCreated      : 2026/10/18 16:20:32
Id               : 33
LevelDisplayName : Error
ProviderName     : SideBySide
Msg              : Activation context generation failed for "D:\DeepSeek-levelup\sxs-lab\app-bad2.exe".
                   Dependent Assembly TotallyMissing.Assembly.Name,processorArchitecture="amd64",
                   publicKeyToken="1111111111111111",type="win32",version="1.0.0.0" could not be found.
                   Please use sxstrace.exe for detailed diagnosis.
```

`Get-WinEvent -ListProvider *SideBySide*` 确认该源的 `LogLinks = {Application}`——**它就写在「应用程序」日志里**，且一条事件里同时给出 `name / processorArchitecture / publicKeyToken / type / version` 五个字段（即 F5 的完整 grounds truth）与 `sxstrace.exe` 的指引。

推论两条：
1. 我在 G3-alt 题面里写的「事件查看器的应用程序日志里没有 .NET Runtime、没有 Application Error、什么都没有」**不符合真实注入**——真实症状是「有且只有一条 source=SideBySide 的 Event 33，它直接把缺失的 identity 印出来」。题面人为删掉了最强的那条证据，属于出题缺陷。
2. 但 5 份产物里有 4 份主动把这处矛盾报了出来（⚠️「SxS 失败本该留 SideBySide 条目却全空，与机制矛盾」）。这说明异常报告机制在题面信息不完整时确实会触发，也说明**这批产物没被题面误导着走完**。
3. 对评分口径的影响：F5 与 F7 在这个题面上可判，但完整版的难度低于真实场景——真实场景里答案是白给的（Event 33 直接点名）。若要把难度顶到极限，应当把 Event 33 保留、但把 `publicKeyToken` 与版本擦掉，只留「could not be found」，逼它去 `sxstrace` 或清单里做排除。
