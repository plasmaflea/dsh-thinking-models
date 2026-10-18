# NSSM + Node.js 服务启动即退，exit code 3221225794 的根源

## [🌳 林状图／回溯法] 选择理由

问题问的是「根源在哪」，是单点故障的因果定位，不是「有哪些可能」的广度枚举，也不是「预估多少」的定量建模。按工作区约定走林状分层分类回溯法：把四个正交维度各自独立回溯到根，再在汇合层合并，最后交付负边。

---

## 第 0 步：先把那个十进制数翻译过来（这一步本身就排掉了一半的病因）

```
3221225794 (dec) = 0xC0000142 (hex) = STATUS_DLL_INIT_FAILED
```

对照表（拿到十进制码的第一件事就是查这张表，别猜）：

| 十进制 | 十六进制 | NTSTATUS | 含义 |
|---|---|---|---|
| 3221225477 | 0xC0000005 | ACCESS_VIOLATION | 进程内非法访存（有 Application Error 1000） |
| 3221225595 | 0xC000007B | INVALID_IMAGE_FORMAT | 32/64 位错配、或依赖的 DLL 位宽不对 |
| 3221225781 | 0xC0000135 | DLL_NOT_FOUND | 隐式导入的 DLL 找不到 |
| **3221225794** | **0xC0000142** | **DLL_INIT_FAILED** | **某个 DLL 的 DllMain（进程附加阶段）返回 FALSE，或加载器没能完成该 DLL 的初始化** |
| 3221226505 | 0xC0000409 | STACK_BUFFER_OVERRUN / fastfail | 栈保护触发、V8 OOM fastfail |

`0xC0000142` 的含义极其关键：**它是在进程入口点（CRT 初始化、`main`／`wWinMain`）之前，由 Windows 加载器（ntdll 的 LdrpInitializeProcess）返回的**。此时：

- Node 的 JS 引擎还没起来，一行 JS 都没执行 → 所以「不是代码 bug」；
- C 运行时还没初始化，stdio 还没接上 → 所以 **stdout／stderr 一行都不会有**（NSSM 的 `AppStdout` 句柄早就通过 `CreateProcess` 传进去了，但没人写）；
- 没有进入用户态异常分发 → 所以 **没有堆栈、通常也不会产生 Application Error 事件 1000**（没有 faulting module 可报）。

> 若你的事件查看器里**确实**有 1000 事件且带 faulting module 名，那就是失败 DLL 的真实名字，直接照抄，后面的排查可以砍掉 80%。

于是"事件查看器里只有 exit code、没有堆栈、没有 stdout"这一组合**不是信息缺失，而是精确的定位证据**：故障发生在加载器层，比 Node 低一整层。

---

## 维度一：故障发生在哪一层 —— 回溯链

```
现象：无堆栈、无 stdout、只有退出码
  → 必要条件①：进程未到达 JS 入口（否则 stderr 必有输出，Node 的未捕获异常会打到 stderr）
  → 必要条件②：进程未到达 CRT 初始化（否则至少能写一行）
  → 充分条件：退出码 ∈ 加载器 NTSTATUS 集合
  → 事实：0xC0000142 = LdrpInitializeProcess 返回失败
  → 根：故障点是「进程初始化时被隐式/注入加载的某个 DLL」的 DllMain，而不是 node 的业务代码
```

**A → B 定性**：现象组合 ⇔ 加载器阶段失败（充分且必要，可反证：任何入口点之后的失败都必然留下 stderr 或 WER 记录）。
**这一根先钉死，后面三个维度都是在找"是哪个 DLL、为什么是偶发"。**

这是排查方向错位的经典陷阱：`环境变量`和`文件权限`是**应用层**的两个嫌疑，而故障在应用层之下。你不是"排查过了没问题"，你是**在错误的层里排查**——层错了，检不出东西是必然的，不能当成"已排除"。

---

## 维度二：是谁的 DllMain 失败了 —— 候选机制分支

进程初始化时要加载的 DLL 集合 = `node.exe` 自身隐式导入 + 系统 API Set shim + **AppInit_DLLs / 安全软件注入 DLL** + 应用目录下的原生依赖（`.node` 插件、pkg 打包产物带的 `ucrtbase/vcruntime140/msvcp140`）。失败者可能是其中任何一个，**不一定非得是 Node 自己的导入**。

| 分支 | 机制（A → B，必要性） | 与"偶发"的吻合度 | 现场特征 |
|---|---|---|---|
| **B1 注入型 DLL 未就绪**（杀毒/EDR/终端管控/输入法/显卡/监控驱动注入） | 安全软件的用户态注入 DLL 在系统启动早期被强制注入新进程，其 DllMain 需要自身的服务/驱动/规则库已完成初始化；未完成则返回 FALSE → 加载器中止 → 0xC0000142 | ★★★★★ 只在**开机后早期**偶发，手动重启服务必好 | 装了国产杀软/EDR（360、火绒、深信服、亚信等）几乎必命中；`fltmc filters`、`driverquery /v` 能看到第三方驱动 |
| **B2 隐式依赖 DLL 来源错乱**（DLL 搜索顺序劫持/版本错配） | PATH 或 `AppDirectory`（未设时 NSSM 用 `C:\Windows\System32`）里有同名 `ucrtbase.dll`／`vcruntime140.dll`／`msvcp140.dll`／`libeay` 等，加载到与 node.exe 不匹配的版本，其 DllMain 初始化失败 | ★★★ 与"装过另一个版本的 Node/工具链"强相关；**必然性偏高**，但只要 PATH 不变就稳定复现 | 服务里 `PATH` 含多个 node 目录；`where /r` 能找到多份同名 DLL |
| **B3 会话 0 桌面堆耗尽** | 开机时大量服务并发创建，非交互会话（Session 0）桌面堆 `SharedSection` 第三个值（默认 768KB）不够；任何需要在初始化阶段接触 user32/gdi32/desktop 的 DLL 失败 → 0xC0000142 | ★★★★ 典型偶发，与并发启动数量相关；重启几次成功率不同 | 注册表 `HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\SubSystems\Windows` 的 `SharedSection`；参见 [Desktop Heap Overview](https://learn.microsoft.com/ka-ge/archive/blogs/ntdebugging/desktop-heap-overview) |
| **B4 启动时序依赖未就绪** | node.exe 隐式导入链里的 DLL（crypt32/iphlpapi/userenv 等，视版本而定）在初始化阶段要等 RPC/注册表/网络/用户配置文件服务；SCM 按 `DependOnService`（默认只有空或极少）启动，依赖尚未 ready → 初始化超时失败 | ★★★★★ 与 B1 同源的"时序竞争"，是"偶发"的主要来源 | `sc qc`／`nssm get <svc> DependOnService` 基本为空；服务是"自动"而非"自动（延迟启动）" |
| **B5 服务账户的上下文缺失** | LocalSystem/NetworkService 下用户配置文件未加载、`%TEMP%` 不可写、Session 0 window station ACL 异常，某些 DLL 的初始化路径失败 | ★★ 多表现为必现而非偶发 | 换成本地交互账户跑一次对照 |
| **B6 UCRT 缺失/损坏** | Server 2008 R2 / 2012 / 2012 R2 未打 KB2999226（Universal CRT），`System32\ucrtbase.dll` 缺失或版本过旧 → node.exe 初始化即失败 | ★（必现，不偶发） | `Test-Path C:\Windows\System32\ucrtbase.dll` |
| **B7 NSSM 配置把退出码"转手"了** | `Application` 指向 `npm.cmd`／`.bat` 包装而非 `node.exe`，中间多了 cmd.exe 一层；或 NSSM 位数与 node 不一致、`AppDirectory` 未设导致 cwd 落在 System32 | ★★ 会让"退出码看起来像 node 的"其实不是 | `nssm dump <svc>` 看 `Application`／`AppParameters`／`AppDirectory` |

**维度二的结构性结论**：能解释"偶发"的分支只有 B1、B3、B4 —— 三者共同点是**启动时序/资源竞争**，与"环境变量、文件权限正常"完全不冲突。B2/B5/B6 是稳定复现型，如果你确认每次重启都这样，反而应该优先查它们。

---

## 维度三：为什么是"偶发"而不是"必现" —— 回溯链

```
偶发
  → 必要条件：同一份二进制、同一份配置，有时成功有时失败
  → 排除：确定性因素（缺失文件、错位 DLL、权限、位宽）——这些不会随机翻转
  → 剩下：非确定性因素 = 时序（谁先 ready）、资源（桌面堆余量）、外来注入（安全软件的启动窗口）
  → 根：这是一个「启动竞态」，不是「配置错误」
```

**这条根决定了处置方式**：配置错误靠改配置，竞态靠**去掉竞争条件**（加依赖、延迟启动、收窄注入面、加大资源），而不是继续在配置文件里翻。

最便宜的决定性实验（10 分钟，先做这个）：

```powershell
sc.exe config <服务名> start= delayed-auto
# 或让 NSSM 托管的服务显式依赖关键服务
nssm set <服务名> DependOnService Tcpip Afd RpcSs CryptSvc ProfSvc
```

如果改成延迟启动后**不再偶发**，则 B1/B3/B4 这条时序根被坐实（三者在现象上同源，靠下一步的加载器追踪再细分）。

---

## 维度四：为什么"环境变量和文件权限看起来都正常" —— 追溯到证据的失效原因

```
你检查的是：env 值对不对、目录能不能读、账户有没有权限
  → 这三项失败会表现为：0xC0000135（找不到 DLL）、EPERM/EACCES 的运行时错误、明确的日志
  → 而实际是 0xC0000142（DLL 初始化失败）
  → 根：检查项与故障层不匹配；且 env 里唯一与 0xC0000142 有关的子项是「PATH 参与 DLL 搜索顺序」，
         这一子项并没有被真正验证（"值看起来正常"≠"解析出的 DLL 是那一份"）
```

**结论：不是"env 和权限没问题"，而是"env 和权限不是这个故障的因变量"。** 唯一的例外是 PATH 的 **DLL 搜索顺序**——它属于 env 的范畴，却造成加载器失败，这是 B2 分支必须单独验证的原因（用 `where` 列出所有同名 DLL，而不是肉眼看 PATH 字符串）。

---

## 汇合层：四个维度合并

```
[加载器层失败] × [某个 DLL 的 DllMain 在进程附加阶段失败]
              × [失败概率随"启动时机"波动 → 竞态]
              × [排查方向停在应用层，故一切"看起来正常"]
= 根：服务在系统启动早期被拉起，node.exe 在进程初始化阶段加载的某个 DLL
      （头号嫌疑：安全软件/终端管控的注入 DLL；次之：桌面堆耗尽的 user32 系初始化；
       再次：node 隐式导入的 DLL 等待尚未就绪的 RPC/网络/配置文件服务）
      其 DllMain 在当时的环境下返回失败，加载器以 0xC0000142 终止进程，
      进程连 CRT 都没进，所以无栈、无 stdout。
```

**一句话给提问者的根**：不是 Node 的问题，也不是权限问题，是**启动竞态导致某个 DLL 初始化失败**——而且大概率不是你自己的代码或配置，是**机器上别的东西（安全软件/注入驱动/系统资源）在你启动服务的那一瞬间还没准备好**。

---

## 定位处方（按性价比排序，做到第 5 步必定出名字）

1. **确认退出码的归属与配置原貌**（2 分钟）
   ```powershell
   sc.exe qc <服务名>
   nssm dump <服务名>            # 看 Application / AppParameters / AppDirectory / AppEnvironmentExtra / DependOnService
   Get-WinEvent -LogName System -MaxEvents 200 |
     Where-Object { $_.Id -in 7000,7009,7011,7031,7034,7038 } |
     Select-Object TimeCreated,Id,Message -First 20
   Get-WinEvent -LogName Application -MaxEvents 200 |
     Where-Object { $_.Id -eq 1000 } | Select-Object TimeCreated,Message
   ```
   → 没有 1000 事件 = 坐实加载器阶段失败；有 1000 且带 faulting module = 直接得到 DLL 名。

2. **确认不是你自己的导入链**（5 分钟）
   ```powershell
   Test-Path C:\Windows\System32\ucrtbase.dll
   where.exe /R C:\ ucrtbase.dll 2>$null      # 以及 vcruntime140.dll / msvcp140.dll
   ```
   → 出现多份 = B2 命中，删掉 PATH/目录里的野生副本。

3. **在服务上下文里手动复现**（5 分钟，关键分水岭）
   ```powershell
   psexec -s -i 0 cmd.exe
   # 在 Session 0 里：
   set                                    # 看真实环境，不是你登录会话的环境
   "C:\Program Files\nodejs\node.exe" -v  # 连 -v 都 0xC0000142 → 100% 与你的代码无关
   ```
   → `-v` 也失败：与业务代码彻底切割，问题在机器/注入/资源。
   → `-v` 成功但跑你的入口失败：转向原生模块/打包产物（B2）。

4. **检查注入面与资源**（3 分钟）
   ```powershell
   Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Windows' AppInit_DLLs,LoadAppInit_DLLs
   Get-ItemProperty 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows NT\CurrentVersion\Windows' AppInit_DLLs
   fltmc filters ; driverquery /v | Select-String -Pattern '360|huorong|sangfor|edr|av'
   (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\SubSystems').Windows
   ```
   → `SharedSection=1024,20480,768` 里的第三个值 768 就是非交互会话桌面堆；并发服务多时提到 2048 或更高（需重启）。AppInit_DLLs 非空 = 直接找到嫌疑注入源。

5. **抓失败的那一个 DLL**（决定性，15 分钟；只在 1–4 未定位时做）
   - **ProcMon 引导日志**：`procmon.exe /Quiet /Minimized /BackingFile C:\boot.pml /EnableBootLogging`，重启后 `procmon /OpenLog C:\boot.pml`，过滤 `Process Name is node.exe`，看 `Load Image` 序列的最后几项 + `Process Exit` 的 Status。加载到一半断掉的那个模块就是凶手。
   - **Loader Snaps**（直接给出"哪个 DllMain 返回 FALSE"）：
     ```
     gflags.exe /i "C:\Program Files\nodejs\node.exe" +sls
     windbg.exe -g -G "C:\Program Files\nodejs\node.exe"        # 输出里搜 DLL_PROCESS_ATTACH 失败项
     gflags.exe /i "C:\Program Files\nodejs\node.exe" -sls      # 抓完务必关掉，否则 node 起不来
     ```
     或用 lucasg 的 `Dependencies.exe`，开启 "Loader Snaps / Profiling" 后它会把失败 DLL 和 `DllMain returned FALSE` 一并报出来。

---

## 从根解决（不是让症状消失）

| 针对的根 | 动作 | 效果 |
|---|---|---|
| B4 时序 | `nssm set <svc> DependOnService Tcpip Afd RpcSs CryptSvc ProfSvc` + `sc.exe config <svc> start= delayed-auto` | 消除"抢跑"这个必要条件，治本 |
| B1 注入 | 把 `node.exe` 与业务目录加入安全软件**排除项**；或与安全厂商确认启动早期注入策略 | 治本（需要安全团队配合） |
| B3 资源 | 调大 `SharedSection` 第三值；减少开机并发服务 | 治本（需重启） |
| B2 解析 | NSSM 里设绝对路径 + `AppDirectory` 指到应用目录；服务内显式把 `PATH` 收窄为 `%SystemRoot%\system32;%SystemRoot%;<node 目录>` | 治本，且防将来复发 |
| 可用性兜底 | `nssm set <svc> AppRestartDelay 5000`、`AppThrottle 15000`、`AppExit Default Restart`；配合 `AppStdout/AppStderr` 落盘 | **不治本**，但把偶发故障变成一次自动重试，同时留下证据 |

> 顺序很重要：先按上表治本，再叠兜底。只用重启策略兜着，等于把根因永久藏起来。

---

## 负边（被排除的分支 + 剪枝理由，必填）

- **⊥ 不是你的 Node 业务代码 bug**。剪枝理由：`0xC0000142` 由加载器在入口点之前返回；JS 未执行、CRT 未初始化。任何 JS/业务层错误都不可能产生这个码。
- **⊥ 不是缺 DLL**（那是 `0xC0000135` / 3221225781），**⊥ 也不是 32/64 位错配**（那是 `0xC000007B` / 3221225595）。剪枝理由：码不同。这两项最常见的误诊已被码义直接否掉。
- **⊥ 不是 V8 内存不足 / OOM**（那是 `0xC0000409` fastfail 或 `Fatal process out of memory`）。剪枝理由：OOM 必然有 stderr 输出。
- **⊥ 不是文件权限不足**。剪枝理由：ACL 拒绝会给出 `0xC0000135`（找不到被 ACL 隐藏的 DLL）或运行期 EACCES；且权限问题不产生"偶发翻转"。
- **⊥ 不是环境变量配错**（除 PATH 的 DLL 搜索顺序这一子项之外）。剪枝理由：误配 env 的典型表现是连不上 DB/端口错，不是加载器失败；而 PATH 子项未被真正验证，故不列入已排除，转入 B2。
- **⊥ 不是 NSSM 自身的 bug**（保留一个待验证边）。剪枝理由：NSSM 用 `GetExitCodeProcess` 原样上报子进程退出码，`0xC0000142` 是子进程的 NTSTATUS；但 `Application` 若指向 `.cmd/.bat` 包装，则码的归属需要先证实（第 1 步已覆盖）。
- **⊥ 不是"重启服务就好了"所以没事**。剪枝理由：能自愈的是竞态，不是修好的配置；不定位则换机器/换版本/加并发时必然复发，且掩盖真实故障率。
- **⊥ 不做无证据的确定性断言**：在没跑第 5 步（ProcMon 引导日志 / Loader Snaps）之前，「B1 安全软件注入」是**最高先验概率的嫌疑**，不是已被证实的结论。概率排序 ≠ 事实认定。

---

## 结论（三句话）

1. **3221225794 = 0xC0000142 = STATUS_DLL_INIT_FAILED**，是 Windows 加载器在进程入口点之前报的错，所以必然没有堆栈、没有 stdout——这条码本身就是定位，不是信息缺失。
2. **根源是启动竞态**：服务在系统启动早期被拉起时，进程初始化阶段加载的某个 DLL（头号嫌疑是安全软件/终端的注入 DLL，其次是 Session 0 桌面堆耗尽，再次是 node 隐式导入的 DLL 等待尚未就绪的 RPC/网络/配置文件服务）其 DllMain 返回失败。**不是 Node 的代码问题，也不是权限问题**——你在应用层查，故障在加载器层。
3. **先做延迟启动 + 补 `DependOnService`** 验证竞态（10 分钟、可逆），**再用 ProcMon 引导日志 / Loader Snaps 抓出具体 DLL 名**（15 分钟、必出结果），然后按 DLL 归属去治本（加排除项、调桌面堆、收窄 PATH），最后才叠 NSSM 的重启兜底。
