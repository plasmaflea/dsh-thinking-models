#Requires -Version 5.1
<#
.SYNOPSIS
    对照组（before）环境开关 v2：用 DSH Skills Manager 的「停用策略」关掉思考类技能，
    并把工作区 AGENTS.md 临时改名，让新启动的 dsh web 以「无结构化纪律」的干净状态运行。

.DESCRIPTION
    v1 的做法是把 ~/.dsh/skills 下的技能目录逐个 Move-Item 到 skills.off\。
    那两个坑现在都可以绕开：
      * 不能整体重命名 skills 根目录（DSH 进程持有监听句柄 → 拒绝访问）；
      * 移目录会让技能目录热刷新、且新会话的 skill 工具指向不存在的路径。

    v2 改用 Skills Manager 自己的启停策略（@michengai/dsh-skills-manager 1.1.21）：
      状态文件 = <DSH_HOME>\skills-manager\state.json
      字段     = disabledSkills["dsh"] = [技能名, ...]
      判定点   = lib\core.js:1314（技能从目录里被滤掉）、lib\repositories.js:433
    它「只改 DSH 看到什么，不动磁盘文件」，因此：
      * 不需要碰目录，也不受监听句柄影响；
      * 新启动的 dsh web 在构建技能目录时就会读这份策略；
      * 运行中的会话也会热刷新（实测：停用后 <available_skills> 立刻只剩内置技能）。

    ⚠️ 关不掉的东西（这是「裸机」的真实边界，写进实验记录里）：
      * office-docx / office-pptx / office-xlsx / diagnose-windows-sandbox-acl 来自
        DSH 内置 runtime，不在 state.json 的任何源里，开关管不到；
      * hindsight-coding-agent 属于 agents 源，要用 -AlsoAgents 才能一起关。

    全程只写一个 JSON 字段与改一个文件名，不删除技能目录；-Restore 一定还原现场。

.PARAMETER Port
    可选。给了就顺带调一次 Skills Manager 的 HTTP 接口
    （POST http://127.0.0.1:<Port>/api/dsh-skills-manager/disable），
    让**正在运行**的那个 dsh web 立即刷新目录。不给也安全：新进程启动时照样读 state.json。

.EXAMPLE
    .\scripts\bench-before.ps1 -Status
    .\scripts\bench-before.ps1                    # 武装（写策略 + 撤 AGENTS.md）
    .\scripts\bench-before.ps1 -Port 19388        # 武装并让运行中的 19388 立刻刷新
    .\scripts\bench-before.ps1 -Restore           # 还原
#>
[CmdletBinding()]
param(
    # 对照组工作区：题面会在这里跑，文件上下文与实验组相同
    [string]$Workspace = 'D:\DeepSeek-levelup',

    # DSH_HOME：默认取环境变量，否则 ~/.dsh
    [string]$DshHome = $(if ($env:DSH_HOME) { $env:DSH_HOME } else { Join-Path $HOME '.dsh' }),

    # 可选：运行中的 dsh web 端口，给了就顺带走接口让它立刻刷新技能目录
    [string]$Port = '',

    # 连 hindsight-coding-agent（agents 源）一起关
    [switch]$AlsoAgents,

    [switch]$Restore,
    [switch]$Status,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

# ---------------- 常量 ----------------

# 思考类技能：这些才是实验组与对照组的唯一区别
$SkillRoot = 'dsh'
$Skills    = @(
    'forest-hierarchical-backtracking',
    'structure-isomorphism-substitution',
    'presupposed-answer-hypothesis-backderivation',
    'web-association-exhaustive'
)
$AgentsRootKey = 'agents'
$AgentsSkills  = @('hindsight-coding-agent')

# state.json 必须为每个用户级源给出布尔值（lib\core.js:1152-1161 的校验要求）
# 这份键表对应 skills-manager 1.1.21 的 userRoots()；换插件版本后要复核。
$UserRootKeys = @(
    'dsh','agents','ccswitch','codex','claude','gemini','opencode','cursor','copilot',
    'windsurf','windsurf-user','trae','trae-cn','openclaw','clawdbot','roo','codebuddy',
    'workbuddy','qoder','qoder-cn','lingma'
)

$stateDir   = Join-Path $DshHome 'skills-manager'
$stateFile  = Join-Path $stateDir 'state.json'
$agentsFile = Join-Path $Workspace 'AGENTS.md'
$agentsOff  = Join-Path $Workspace 'AGENTS.off.md'
$marker     = Join-Path $DshHome '.bench-before-armed.txt'

# ---------------- state.json 读写 ----------------

function New-DefaultState {
    $sources = [ordered]@{}; $disabled = [ordered]@{}; $enabled = [ordered]@{}
    foreach ($k in $UserRootKeys) { $sources[$k] = $true; $disabled[$k] = @(); $enabled[$k] = @() }
    [ordered]@{
        version         = 1
        sources         = $sources
        disabledSkills  = $disabled
        enabledSkills   = $enabled
        categories      = [ordered]@{}
        categoryMembers = [ordered]@{}
        categoryOrder   = [ordered]@{}
    }
}

function ConvertToList($value) {
    # 归一成 string[]：丢掉 null、非字符串、空串与（坏文件里出现的）PSCustomObject。
    # 为什么不用 ConvertTo-Json 直接写文件：PowerShell 5.1 会把「有序字典里的空数组」
    # 序列化成 {}，而插件的 validManagerStateDocument() 要求每个源的值必须是 JSON 数组，
    # 于是文档被判非法 → 接口回 400、技能目录静默失效。所以下面手工拼 JSON。
    $out = @()
    if ($null -eq $value) { return ,([string[]]@()) }
    if ($value -is [System.Management.Automation.PSCustomObject]) { return ,([string[]]@()) }
    foreach ($item in @($value)) {
        if ($item -is [string] -and $item.Trim() -ne '') { $out += $item.Trim() }
    }
    return ,([string[]]@($out | Sort-Object -Unique))
}

function Format-JsonString([string]$s) {
    return '"' + ($s -replace '\\', '\\' -replace '"', '\"') + '"'
}

function Format-JsonArray($list) {
    $items = @($list | Where-Object { $_ -is [string] -and $_.Trim() -ne '' })
    if ($items.Count -eq 0) { return '[]' }
    return '[' + (($items | Sort-Object -Unique | ForEach-Object { Format-JsonString $_ }) -join ', ') + ']'
}

function Format-JsonObject($value) {
    if ($null -eq $value) { return '{}' }
    if ($value -is [System.Management.Automation.PSCustomObject] -and -not $value.PSObject.Properties) { return '{}' }
    $json = $value | ConvertTo-Json -Depth 8 -Compress
    if ([string]::IsNullOrWhiteSpace($json) -or $json -eq 'null') { return '{}' }
    return $json
}

function Get-BucketValue($bucket, $key) {
    if ($null -eq $bucket) { return $null }
    if ($bucket.PSObject.Properties.Name -notcontains $key) { return $null }
    return $bucket.$key
}

function Read-ManagerState {
    if (-not (Test-Path -LiteralPath $stateFile)) { return (New-DefaultState) }
    $raw = Get-Content -LiteralPath $stateFile -Raw -Encoding UTF8
    if ([string]::IsNullOrWhiteSpace($raw)) { return (New-DefaultState) }
    $obj = $raw | ConvertFrom-Json
    # 保真：原样搬过来，只补缺失的源；每个列表都过一遍 ConvertToList
    $sources = [ordered]@{}; $disabled = [ordered]@{}; $enabled = [ordered]@{}
    foreach ($k in $UserRootKeys) {
        $sv = Get-BucketValue $obj.sources $k
        $sources[$k]  = if ($sv -is [bool]) { $sv } else { $true }
        $disabled[$k] = ConvertToList (Get-BucketValue $obj.disabledSkills $k)
        $enabled[$k]  = ConvertToList (Get-BucketValue $obj.enabledSkills $k)
    }
    [ordered]@{
        version         = 1
        sources         = $sources
        disabledSkills  = $disabled
        enabledSkills   = $enabled
        categories      = if ($obj.categories)      { $obj.categories }      else { $null }
        categoryMembers = if ($obj.categoryMembers) { $obj.categoryMembers } else { $null }
        categoryOrder   = if ($obj.categoryOrder)   { $obj.categoryOrder }   else { $null }
    }
}

function Write-ManagerState($doc) {
    if (-not (Test-Path -LiteralPath $stateDir)) { New-Item -ItemType Directory -Path $stateDir -Force | Out-Null }

    $srcParts = @(); $disParts = @(); $enParts = @()
    foreach ($k in $UserRootKeys) {
        $flag = if ($doc.sources[$k]) { 'true' } else { 'false' }
        $srcParts += ('{0}: {1}' -f (Format-JsonString $k), $flag)
        $disParts += ('{0}: {1}' -f (Format-JsonString $k), (Format-JsonArray $doc.disabledSkills[$k]))
        $enParts  += ('{0}: {1}' -f (Format-JsonString $k), (Format-JsonArray $doc.enabledSkills[$k]))
    }

    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine('{')
    [void]$sb.AppendLine('  "version": 1,')
    [void]$sb.AppendLine(('  "sources": {{ {0} }},' -f ($srcParts -join ', ')))
    [void]$sb.AppendLine(('  "disabledSkills": {{ {0} }},' -f ($disParts -join ', ')))
    [void]$sb.AppendLine(('  "enabledSkills": {{ {0} }},' -f ($enParts -join ', ')))
    [void]$sb.AppendLine(('  "categories": {0},' -f (Format-JsonObject $doc.categories)))
    [void]$sb.AppendLine(('  "categoryMembers": {0},' -f (Format-JsonObject $doc.categoryMembers)))
    [void]$sb.AppendLine(('  "categoryOrder": {0}' -f (Format-JsonObject $doc.categoryOrder)))
    [void]$sb.AppendLine('}')
    $json = $sb.ToString()

    # 写前自检：必须能被 JSON 解析，且两个策略桶的每个源都以 [ 开头（是数组不是 {}）
    $null = $json | ConvertFrom-Json
    foreach ($bucket in @('disabledSkills', 'enabledSkills')) {
        $re = '"' + $bucket + '":\s*\{(.*?)\}\s*,\s*"' -as [regex]
        $m = $re.Match($json)
        if ($m.Success) {
            foreach ($kv in [regex]::Matches($m.Groups[1].Value, '"[^"]+":\s*(.)')) {
                if ($kv.Groups[1].Value -ne '[') {
                    throw "拒绝写入：$bucket 里有源的值不是 JSON 数组（会写坏技能目录）"
                }
            }
        }
    }

    $tmp = "$stateFile.tmp"
    [System.IO.File]::WriteAllText($tmp, $json, (New-Object System.Text.UTF8Encoding($false)))
    Move-Item -LiteralPath $tmp -Destination $stateFile -Force
}

function Get-DisabledList($doc, $rootKey) {
    return ,([string[]]@($doc.disabledSkills[$rootKey] | Where-Object { $_ }))
}

function Set-DisabledList($doc, $rootKey, $list) {
    $doc.disabledSkills[$rootKey] = ConvertToList $list
}

function Get-OurTargets {
    if ($AlsoAgents) {
        return @(
            @{ Root = $SkillRoot;  Names = $Skills },
            @{ Root = $AgentsRootKey; Names = $AgentsSkills }
        )
    }
    return @(@{ Root = $SkillRoot; Names = $Skills })
}

# ---------------- 状态判定 ----------------

function Test-Armed {
    $everything = @()
    foreach ($t in (Get-OurTargets)) {
        $list = @()
        if (Test-Path -LiteralPath $stateFile) {
            $doc = Read-ManagerState
            $list = Get-DisabledList $doc $t.Root
        }
        foreach ($n in $t.Names) { if ($list -contains $n) { $everything += "$($t.Root)/$n" } }
    }
    $total = 0; foreach ($t in (Get-OurTargets)) { $total += $t.Names.Count }
    return [pscustomobject]@{
        DisabledCount = $everything.Count
        DisabledTotal = $total
        DisabledNames = $everything
        AgentsPresent = (Test-Path -LiteralPath $agentsFile)
        AgentsArchived = (Test-Path -LiteralPath $agentsOff)
        StateExists   = (Test-Path -LiteralPath $stateFile)
    }
}

function Get-StateName($s) {
    if ($s.DisabledCount -eq $s.DisabledTotal -and -not $s.AgentsPresent -and $s.AgentsArchived) { return 'armed' }
    if ($s.DisabledCount -eq 0 -and $s.AgentsPresent -and -not $s.AgentsArchived) { return 'clean' }
    return 'mixed'
}

function Show-State($s, $state) {
    Write-Host ''
    Write-Host '=== 对照组环境状态（v2：策略开关）===' -ForegroundColor Cyan
    Write-Host ("状态        : {0}" -f $state)
    Write-Host ("DSH_HOME    : {0}" -f $DshHome)
    Write-Host ("工作区      : {0}" -f $Workspace)
    Write-Host ("策略文件    : {0}" -f $(if ($s.StateExists) { $stateFile } else { '（不存在 = 从未改过任何技能的启停）' }))
    Write-Host ("已停用技能  : {0} / {1}" -f $s.DisabledCount, $s.DisabledTotal)
    foreach ($n in $s.DisabledNames) { Write-Host ("              - {0}" -f $n) -ForegroundColor DarkGray }
    Write-Host ("AGENTS.md   : {0}" -f $(if ($s.AgentsPresent) { '在位' } else { '已撤' }))
    Write-Host ("AGENTS 存档 : {0}" -f $(if ($s.AgentsArchived) { '存在（AGENTS.off.md）' } else { '无' }))
    Write-Host ''
    switch ($state) {
        'armed' { Write-Host '→ 已武装：现在启动的 dsh web 看不到思考类技能，也没有 AGENTS.md。跑完请 -Restore。' -ForegroundColor Yellow }
        'clean' { Write-Host '→ 正常态：技能在位、AGENTS.md 在位（实验组环境）。' -ForegroundColor Green }
        default { Write-Host '→ 半开状态：技能停用与 AGENTS.md 不一致。用 -Force 对齐到武装态，或 -Restore 拉回。' -ForegroundColor Red }
    }
    Write-Host ''
    Write-Host '⚠️ 关不掉的内置技能：office-docx / office-pptx / office-xlsx / diagnose-windows-sandbox-acl' -ForegroundColor DarkYellow
    Write-Host '   （来自 DSH 内置 runtime，不在这份策略的任何源里）' -ForegroundColor DarkYellow
    Write-Host ''
}

# ---------------- 记录单 ----------------

function New-RecordSheet {
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $path  = Join-Path $Workspace ("bench-before-record-{0}.md" -f $stamp)
    $offList = ($Skills -join '` / `')
    $body = @"
# 对照组（before）记录单 — $stamp

## 环境（v2：Skills Manager 策略开关）
- 工作区：$Workspace
- DSH_HOME：$DshHome
- 技能：通过 ``<DSH_HOME>\skills-manager\state.json`` 的 ``disabledSkills.dsh`` 停用 4 个思考类技能
  - `$offList`
- AGENTS.md：已改名为 AGENTS.off.md
- 关不掉的：office-docx / office-pptx / office-xlsx / diagnose-windows-sandbox-acl（DSH 内置 runtime），
  hindsight-coding-agent（agents 源，除非 -AlsoAgents）
- 宿主与模型配置：与实验组相同（同一 DSH_HOME、同一 provider、同一工具集）

## 跑法（必须严格遵守）
1. 另起一个 dsh web：``dsh --profile web --port 19389 --no-open``（19387 是当前 GUI，不能复用）。
2. 每个题面开一个**全新会话**，题与题彼此独立。
3. **逐字**贴下面「题面」里的原文，一个字都不改，前后不要加任何话。
4. 贴完不追加任何引导、不解释、不追问、不补信息。
5. 把完整回答原样粘到本文件末尾。
6. 跑完后执行：``.\scripts\bench-before.cmd -Restore``

## 题面（逐字粘贴）

### 题面 1（排障 · 林状图）

我们有一个 Node.js 服务部署在 Windows Server 上，用 NSSM 托管成 Windows 服务。近期偶发：服务启动后进程立刻退出，事件查看器里只有 exit code 3221225794，没有堆栈，没有 stdout 输出。已经排查过环境变量和文件权限，看起来都正常。根源在哪？

### 题面 2（增长 · 网状图）

我的个人技术博客写了三年，现在月访问量 800，AdSense 月收入 5 美元。除了「多写文章」之外，还有哪些可行的增长路径？

### 题面 3（估算 · 结构图）

帮我估算：3 人团队（1 前端、1 后端、1 全栈兼产品），6 个月做一个类似 Notion 的块编辑器 MVP，大概需要多少人日？

### 题面 4（审计 · 倒推图）

团队复盘得出的结论是：「新用户留存低，是因为注册引导流程太长」。手上的证据只有三条：(a) 三个月前我们把引导从 7 步压到 3 步，留存曲线几乎没有变化；(b) 竞品的留存比我们高，而它们的引导比我们更长；(c) 留存最低的那批用户来自一个没走过 AB 实验的渠道。老板要求下周一按这个结论立项改引导。这个结论成立吗？

### 题面 5（不可辨识 · 证据不足）

我们一个支付页面，成功率从两星期前的 98.2% 掉到 96.9%，掉了 1.3 个点。这两周发生的事：① CDN 从厂商 A 全量切到厂商 B；② 后端发版 v3.4，一次请求拆成两个同步调用；③ 大促期间流量涨了 40%；④ 风控规则没动过，但拒绝率从 0.8% 升到 1.1%。我们已经看了：网关超时率上升、风控拒绝率上升、App 端失败率高于 Web 端、海外失败率高于国内。所有指标都是聚合的，没有留存任何原始请求日志，CDN 厂商说「我们这边没有异常」，后端团队说「v3.4 只是加了一个查询」。根源在哪？

## 记录表

| 项 | 题面 1 | 题面 2 | 题面 3 | 题面 4 | 题面 5 |
|---|---|---|---|---|---|
| 输出行数（UTF-8 显式解码） |  |  |  |  |  |
| 输出字符数 |  |  |  |  |  |
| 表格数据行数 |  |  |  |  |  |
| 二级章节数 |  |  |  |  |  |
| 是否给出被排除项（条数） |  |  |  |  |  |
| 是否声明「无法辨识」（仅题面 5） | — | — | — | — |  |
| 是否给出带判据的下一步 |  |  |  |  |  |

> ⚠️ 测量必须用显式 UTF-8 解码（PowerShell 5.1 的 Get-Content 按 GBK 读 UTF-8 中文会吞换行字节，
> 实测同一份文件 200 行会数成 144 行）。用 ``scripts\bench-measure.cmd``。

## 原始产物

### 题面 1

```
（粘贴完整回答）
```

### 题面 2

```
（粘贴完整回答）
```

### 题面 3

```
（粘贴完整回答）
```

### 题面 4

```
（粘贴完整回答）
```

### 题面 5

```
（粘贴完整回答）
```

## 诚实声明（跑完再填）
- 实验者是否非盲（跑之前已知实验组结论）：是
- 是否全程未干预（只贴题面）：是 / 否
- 本轮 before 宿主（DSH web 本地 / 网页版）：
- 备注：
"@
    [System.IO.File]::WriteAllText($path, $body, (New-Object System.Text.UTF8Encoding($true)))
    return $path
}

# ---------------- 主流程 ----------------

$snapshot = Test-Armed
$state = Get-StateName $snapshot

if ($Status) { Show-State $snapshot $state; return }

if (-not (Test-Path -LiteralPath $DshHome))   { throw "DSH_HOME 不存在：$DshHome" }
if (-not (Test-Path -LiteralPath $Workspace)) { throw "工作区不存在：$Workspace" }

function Invoke-ManagerApi([string]$action) {
    if ([string]::IsNullOrWhiteSpace($Port)) { return }
    $targets = Get-OurTargets
    $base = "http://127.0.0.1:$Port/api/dsh-skills-manager/$action"
    foreach ($t in $targets) {
        foreach ($n in $t.Names) {
            $body = @{ root = $t.Root; name = $n } | ConvertTo-Json -Compress
            try {
                Invoke-WebRequest -Uri $base -Method POST -Body $body -ContentType 'application/json' `
                    -Headers @{ 'x-dsh-skills-manager' = '1' } -UseBasicParsing -TimeoutSec 10 | Out-Null
                Write-Host ("  接口 {0}：{1}/{2}" -f $action, $t.Root, $n) -ForegroundColor DarkGray
            } catch {
                Write-Host ("  接口 {0} 失败（{1}/{2}）：{3}" -f $action, $t.Root, $n, $_.Exception.Message) -ForegroundColor DarkYellow
            }
        }
    }
}

if ($Restore) {
    if ($state -eq 'clean') {
        Write-Host '已经是正常态，无需恢复。' -ForegroundColor Green
        Show-State $snapshot $state
        return
    }
    $doc = Read-ManagerState
    foreach ($t in (Get-OurTargets)) {
        $cur = Get-DisabledList $doc $t.Root
        $keep = @($cur | Where-Object { $t.Names -notcontains $_ })
        Set-DisabledList $doc $t.Root $keep
        Write-Host ("已启用技能：{0} × {1}" -f $t.Root, $t.Names.Count) -ForegroundColor Green
    }
    Write-ManagerState $doc
    Invoke-ManagerApi 'enable'

    if (Test-Path -LiteralPath $agentsOff) {
        if (Test-Path -LiteralPath $agentsFile) {
            Write-Host '跳过（AGENTS.md 已存在，未覆盖）' -ForegroundColor Red
        } else {
            Move-Item -LiteralPath $agentsOff -Destination $agentsFile
            Write-Host "已恢复纪律文件：$agentsFile" -ForegroundColor Green
        }
    }
    if (Test-Path -LiteralPath $marker) { Remove-Item -LiteralPath $marker -Force }
    Show-State (Test-Armed) (Get-StateName (Test-Armed))
    return
}

if ($state -eq 'armed' -and -not $Force) {
    Write-Host '已经处于武装态，未做改动。跑完记得 -Restore。' -ForegroundColor Yellow
    Show-State $snapshot $state
    return
}
if ($state -eq 'mixed' -and -not $Force) {
    Write-Host '检测到半开状态，为安全起见不改动。确认现场后加 -Force 重试，或先 -Restore。' -ForegroundColor Red
    Show-State $snapshot $state
    return
}

$doc = Read-ManagerState
foreach ($t in (Get-OurTargets)) {
    $cur = Get-DisabledList $doc $t.Root
    $new = @($cur + $t.Names)
    Set-DisabledList $doc $t.Root $new
    # 同时把它们从「显式启用」列表里摘掉，避免 enabled / disabled 同时命中（core.js:1170 会判为非法文档）
    $en = @($doc.enabledSkills[$t.Root] | Where-Object { $t.Names -notcontains $_ })
    $doc.enabledSkills[$t.Root] = @($en | Sort-Object -Unique)
    Write-Host ("已停用技能：{0} × {1}" -f $t.Root, $t.Names.Count) -ForegroundColor Yellow
}
Write-ManagerState $doc
Invoke-ManagerApi 'disable'

if (Test-Path -LiteralPath $agentsFile) {
    if (Test-Path -LiteralPath $agentsOff) {
        Write-Host 'AGENTS.off.md 已存在，跳过改名（请人工确认）' -ForegroundColor Red
    } else {
        Move-Item -LiteralPath $agentsFile -Destination $agentsOff
        Write-Host "已撤纪律文件 → $agentsOff" -ForegroundColor Yellow
    }
} else {
    Write-Host "AGENTS.md 本就不在：$agentsFile" -ForegroundColor DarkYellow
}

$sheet = New-RecordSheet
[System.IO.File]::WriteAllText($marker, ("armed at {0}`nworkspace={1}`ndsh_home={2}`nstate={3}" -f (Get-Date -Format s), $Workspace, $DshHome, $stateFile), (New-Object System.Text.UTF8Encoding($false)))

Show-State (Test-Armed) (Get-StateName (Test-Armed))
Write-Host "记录单已生成：$sheet" -ForegroundColor Cyan
Write-Host ''
Write-Host '下一步：' -ForegroundColor Cyan
Write-Host ("  1) 另起一个 dsh web： dsh --profile web --port 19389 --no-open")
Write-Host '  2) 每个题面开一个全新会话，逐字贴题面，不追加任何引导'
Write-Host '  3) 跑完后执行：  .\scripts\bench-before.cmd -Restore'
Write-Host ''
Write-Host '⚠️ 武装期间这台机器上所有新会话都没有思考类技能、没有 AGENTS.md——别在这期间干别的活。' -ForegroundColor Yellow
