#Requires -Version 5.1
<#
.SYNOPSIS
    对照组（before）环境开关：把 DSH 技能目录下的技能临时移走、把工作区 AGENTS.md 临时改名，
    让新启动的 dsh web 以「无结构化纪律」的干净状态运行。

.DESCRIPTION
    对照组要固定的变量只有两个：技能（~/.dsh/skills 下的各技能目录）与工作区纪律（AGENTS.md）。
    其余（同一 DSH_HOME、同一模型配置、同一工具集、同一 hindsight 插件、同一工作区文件）
    必须与实验组保持一致——所以本脚本只动这两处，别的一个字节都不碰。

    注意：不能整体重命名 skills 根目录——DSH 进程对它持有监听句柄，会返回「拒绝访问」。
    所以改为把 skills 下的每个技能目录移进 skills.off\；根目录留着但空着，技能目录自然为空。

    全程只用 Move-Item，不删除任何东西；-Restore 一定能把现场还原。

.EXAMPLE
    .\scripts\bench-before.ps1              武装：移走技能 + 改名 AGENTS.md
    .\scripts\bench-before.ps1 -Restore     恢复现场
    .\scripts\bench-before.ps1 -Status      只查看状态
#>
[CmdletBinding()]
param(
    # 对照组工作区：题面会在这里跑，文件上下文与实验组相同
    [string]$Workspace = 'D:\DeepSeek-levelup',

    # DSH_HOME：默认取环境变量，否则 ~/.dsh
    [string]$DshHome = $(if ($env:DSH_HOME) { $env:DSH_HOME } else { Join-Path $HOME '.dsh' }),

    [switch]$Restore,
    [switch]$Status,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

$skillsDir  = Join-Path $DshHome 'skills'
$skillsOff  = Join-Path $DshHome 'skills.off'
$agentsFile = Join-Path $Workspace 'AGENTS.md'
$agentsOff  = Join-Path $Workspace 'AGENTS.off.md'
$marker     = Join-Path $DshHome '.bench-before-armed.txt'

function Get-LiveSkills   { @(Get-ChildItem -LiteralPath $skillsDir -Directory -ErrorAction SilentlyContinue) }
function Get-ParkedSkills { @(Get-ChildItem -LiteralPath $skillsOff -Directory -ErrorAction SilentlyContinue) }

function Test-State {
    $live   = (Get-LiveSkills).Count
    $parked = (Get-ParkedSkills).Count
    $hasAgents = Test-Path -LiteralPath $agentsFile
    $hasAgOff  = Test-Path -LiteralPath $agentsOff

    if ($live -eq 0 -and $parked -gt 0 -and -not $hasAgents -and $hasAgOff) { return 'armed' }
    if ($parked -eq 0 -and $hasAgents -and -not $hasAgOff) { return 'clean' }
    if ($live -eq 0 -and $parked -eq 0 -and -not $hasAgents -and -not $hasAgOff) { return 'empty' }
    return 'mixed'
}

function Show-State($state) {
    Write-Host ''
    Write-Host '=== 对照组环境状态 ===' -ForegroundColor Cyan
    Write-Host ("状态        : {0}" -f $state)
    Write-Host ("DSH_HOME    : {0}" -f $DshHome)
    Write-Host ("工作区      : {0}" -f $Workspace)
    Write-Host ("在册技能    : {0} 个" -f (Get-LiveSkills).Count)
    Write-Host ("已移走技能  : {0} 个（{1}）" -f (Get-ParkedSkills).Count, $skillsOff)
    Write-Host ("AGENTS.md   : {0}" -f $(if (Test-Path -LiteralPath $agentsFile) { '在位' } else { '已撤' }))
    Write-Host ("AGENTS 存档 : {0}" -f $(if (Test-Path -LiteralPath $agentsOff) { '存在' } else { '无' }))
    switch ($state) {
        'armed' { Write-Host '→ 已武装：现在启动的 dsh web 是干净对照组。跑完请 -Restore。' -ForegroundColor Yellow }
        'clean' { Write-Host '→ 正常态：技能与 AGENTS.md 都在位（实验组环境）。' -ForegroundColor Green }
        'empty' { Write-Host '→ 两侧都没有：技能与 AGENTS.md 都不存在，这通常是全新 DSH_HOME。' -ForegroundColor DarkYellow }
        'mixed' { Write-Host '→ 半开状态：有人手工改过。用 -Force 对齐到武装态，或 -Restore 拉回。' -ForegroundColor Red }
    }
    Write-Host ''
}

function New-RecordSheet {
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $path  = Join-Path $Workspace ("bench-before-record-{0}.md" -f $stamp)
    $body = @"
# 对照组（before）记录单 — $stamp

## 环境
- 工作区：$Workspace
- DSH_HOME：$DshHome
- 技能：已全部移出（skills 根目录仍在但为空，DSH 技能目录为空）
- AGENTS.md：已改名为 AGENTS.off.md
- 宿主与模型配置：与实验组相同（同一 DSH_HOME、同一 provider）

## 跑法（必须严格遵守）
1. 另起一个 dsh web（建议换端口，避免与现有 19387 冲突；参数以 ``dsh web --help`` 为准）。
2. 每个题面开一个**全新会话**。
3. **逐字**贴题面原文（见 ``docs/benchmark/README.md`` 的三题面），一个字都不改。
4. 贴完不追加任何引导、不解释、不追问、不补信息。
5. 把完整回答原样粘到本文件下方。
6. 三题跑完后执行：``.\scripts\bench-before.cmd -Restore``

## 记录表

| 项 | 题面 A（pwsh 起不来） | 题面 B（方案穷举） | 题面 C（估算） |
|---|---|---|---|
| 输出行数 |  |  |  |
| 输出字符数 |  |  |  |
| 是否产出结构（林／表／式） |  |  |  |
| **是否给出负边清单** |  |  |  |
| 命中 8 因子真因 | __/8 | __/8 | __/8 |
| 有收敛判据 |  |  |  |
| 是否编造证据 |  |  |  |

> 对照值（实验组，已实测）：题面 A 235 行／13013 字符；题面 B 212 行／10648 字符；题面 C 258 行／8569 字符。
> 8 因子真因清单与指标定义见 ``docs/benchmark/README.md``。

## 原始产物

### 题面 A

```
（粘贴完整回答）
```

### 题面 B

```
（粘贴完整回答）
```

### 题面 C

```
（粘贴完整回答）
```

## 诚实声明（跑完再填）
- 实验者是否非盲（跑之前已知实验组结论）：是
- 是否全程未干预（只贴题面）：是 / 否
- 备注：
"@
    Set-Content -LiteralPath $path -Value $body -Encoding UTF8
    return $path
}

# ---------------- 主流程 ----------------

$state = Test-State

if ($Status) { Show-State $state; return }

if (-not (Test-Path -LiteralPath $DshHome))   { throw "DSH_HOME 不存在：$DshHome" }
if (-not (Test-Path -LiteralPath $Workspace)) { throw "工作区不存在：$Workspace" }

if ($Restore) {
    if ($state -eq 'clean') {
        Write-Host '已经是正常态，无需恢复。' -ForegroundColor Green
        Show-State $state
        return
    }
    foreach ($item in (Get-ParkedSkills)) {
        $target = Join-Path $skillsDir $item.Name
        if (Test-Path -LiteralPath $target) {
            Write-Host ("跳过（目标已存在，未覆盖）：{0}" -f $item.Name) -ForegroundColor Red
            continue
        }
        Move-Item -LiteralPath $item.FullName -Destination $target
        Write-Host ("已恢复技能：{0}" -f $item.Name) -ForegroundColor Green
    }
    if (Test-Path -LiteralPath $agentsOff) {
        if (Test-Path -LiteralPath $agentsFile) {
            Write-Host "跳过（AGENTS.md 已存在，未覆盖）" -ForegroundColor Red
        } else {
            Move-Item -LiteralPath $agentsOff -Destination $agentsFile
            Write-Host "已恢复纪律文件：$agentsFile" -ForegroundColor Green
        }
    }
    if ((Get-ParkedSkills).Count -eq 0) {
        Remove-Item -LiteralPath $skillsOff -Force -ErrorAction SilentlyContinue
    }
    if (Test-Path -LiteralPath $marker) { Remove-Item -LiteralPath $marker -Force }
    Show-State (Test-State)
    return
}

if ($state -eq 'armed' -and -not $Force) {
    Write-Host '已经处于武装态，未做改动。跑完记得 -Restore。' -ForegroundColor Yellow
    Show-State $state
    return
}
if ($state -eq 'mixed' -and -not $Force) {
    Write-Host '检测到半开状态，为安全起见不改动。确认现场后加 -Force 重试，或先 -Restore。' -ForegroundColor Red
    Show-State $state
    return
}

if (-not (Test-Path -LiteralPath $skillsDir)) { New-Item -ItemType Directory -Path $skillsDir -Force | Out-Null }
if (-not (Test-Path -LiteralPath $skillsOff)) { New-Item -ItemType Directory -Path $skillsOff -Force | Out-Null }

$moved = 0
foreach ($item in (Get-LiveSkills)) {
    $target = Join-Path $skillsOff $item.Name
    if (Test-Path -LiteralPath $target) {
        Write-Host ("跳过（skills.off 里已有同名）：{0}" -f $item.Name) -ForegroundColor Red
        continue
    }
    Move-Item -LiteralPath $item.FullName -Destination $target
    Write-Host ("已移走技能：{0}" -f $item.Name) -ForegroundColor Yellow
    $moved++
}

if (Test-Path -LiteralPath $agentsFile) {
    if (Test-Path -LiteralPath $agentsOff) {
        Write-Host "AGENTS.off.md 已存在，跳过改名（请人工确认）" -ForegroundColor Red
    } else {
        Move-Item -LiteralPath $agentsFile -Destination $agentsOff
        Write-Host "已撤纪律文件 → $agentsOff" -ForegroundColor Yellow
    }
} else {
    Write-Host "AGENTS.md 本就不在：$agentsFile" -ForegroundColor DarkYellow
}

$sheet = New-RecordSheet
Set-Content -LiteralPath $marker -Value ("armed at {0}`nmoved={1}`nworkspace={2}`ndsh_home={3}" -f (Get-Date -Format s), $moved, $Workspace, $DshHome) -Encoding UTF8

Show-State (Test-State)
Write-Host "记录单已生成：$sheet" -ForegroundColor Cyan
Write-Host ''
Write-Host '下一步：' -ForegroundColor Cyan
Write-Host '  1) 另起一个 dsh web（建议换端口，参数以 dsh web --help 为准）'
Write-Host '  2) 每个题面开全新会话，逐字贴题面，不追加任何引导'
Write-Host '  3) 三题跑完后执行：  .\scripts\bench-before.cmd -Restore'
Write-Host ''
Write-Host '⚠️ 武装期间这台机器上所有新会话都没有技能、没有 AGENTS.md——别在这期间干别的活。' -ForegroundColor Yellow
