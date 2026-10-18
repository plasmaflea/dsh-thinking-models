# 节点 `software / win-service` · Windows 服务形态下的进程初始化

**父节点**：`software`（子层 `lifecycle` + `init`）　**版本**：v1　**核查**：2026-10-18

## 判据

进程由 SCM（或其包装器如 NSSM、winsw）创建，运行在 **Session 0**、非交互 window station/desktop 上，其生命周期与加载行为由外部代持。命中的信号：服务方式启动异常、手工命令行启动正常；事件日志只有退出码没有堆栈。

## 状态码互斥表（先解码再排查，比任何猜测都硬）

| 状态码 | 名称 | 含义 | 所以 |
|---|---|---|---|
| `0xC0000142` | `STATUS_DLL_INIT_FAILED` | 进程已映射、静态导入已找到，但某个 DLL 的 DllMain 返回 FALSE/超时，加载器 `TerminateProcess` | 故障在 main 之前 |
| `0xC0000135` | `DLL_NOT_FOUND` | 依赖 DLL 缺失 | 不是 0142 |
| `0xC0000139` | `ENTRYPOINT_NOT_FOUND` | 运行库过旧、导出缺失 | 不是 0142 |
| `0xC000007B` | `INVALID_IMAGE_FORMAT` | 位数不符/映像损坏 | 不是 0142 |
| `0xC0000428` | `INVALID_IMAGE_HASH` | WDAC/AppLocker 哈希策略拦截 | 不是 0142 |
| `0xC0000017` | `NO_MEMORY` | 提交内存不足 | 不是 0142 |

> 推论：`0xC0000142` 的搜索空间只有「哪一个 DLL、为什么它的初始化失败」，环境变量、文件权限、端口、业务代码在结构上都在它下游。

## 六格时序轴（生成源：一次服务启动的必经过程）

| 格 | 该格管什么 | 0xC0000142 可能性 | 专属症状 |
|---|---|---|---|
| 1 SCM 接受与 NSSM 包装 | 服务被接受、`CreateProcess` 成功 | ✗ 不产生 | 1053/1066/7000/1060；NSSM `CreateProcess failed` |
| 2 令牌、会话、窗口站与桌面 | 拿到 token、落到 Session 0 非交互桌面 | ✓ **主因** | 开机自启必死、事后手动启动常成功 |
| 3 PE 加载解析静态导入 + SxS 激活上下文 | import table 逐条解析、manifest 激活 | ✓ 子情形（SxS 激活失败） | Application 日志 `source=SideBySide` |
| 4 各 DLL 的 DllMain（含被动注入的 DLL） | 一个返回 FALSE 即整进程死 | ✓ **充要** | 退出前最后一条 `Load Image` 即凶手；偶发＝签名更新/注入时机 |
| 5 进入 main 之后 | env/cwd/权限/端口/`require` | ✗ 无法产生（唯一漏洞：子进程 NTSTATUS 透传） | 都有堆栈有输出 |
| 6 NSSM 退出处理与上报 | 退出码写进事件日志、重启节流 | ✗ 不改故障，改**观测** | `AppThrottle` 把确定性失败包装成「偶发」；未配 `AppStdout` 则永远无 stdout |

## 本节点的类根

**进程生命周期与加载行为由 SCM + PE 加载器代持**，而不是由应用掌握。因此：崩溃发生在应用能打日志之前、失败信息只有四位十六进制、偶发性来自外部注入时机与并发加载，而不是业务逻辑。

## 消解路径（离开这一类问题，不是缓解）

- 环境替换：Linux + systemd（无 Session 0 桌面堆、注入面小、启动失败有 `journalctl` 原文）
- 结构替换（不换 OS）：前台守护 + 进程管理器/容器托管，让应用自己掌握启动可观测性与重启策略
- 观测性永久化：`AppStdout/AppStderr/AppRotateFiles` + 启动面包屑 + WER LocalDumps（这不是消解根，是把「查不到」这一类消解掉）

## 已知易错归因（该被挂起的流行说法）

- 「调 SharedSection 第二项」— 服务态生效的是**第三项**（非交互窗口站），第二项是交互式。
- 「装 VC++ 运行库」— 缺失是 `0xC0000135`，过旧是 `0xC0000139`，都不是 `0xC0000142`。
