<#
.SYNOPSIS
  同步「结构模式库」：工作区源 → 仓库 tree/ → 已安装技能 tree/。

.DESCRIPTION
  规范链路（单向，只在一个地方改）：

    1. 源文件   <workspace>\structure-tree\
    2. 仓库     <repo>\structure-isomorphism-pointmass-substitution\tree\
    3. 安装位   $HOME\.dsh\skills\structure-isomorphism-pointmass-substitution\tree\

  为什么要有它：库有三份拷贝，改源不同步就会漂；漂了以后「本机技能读哪份」取决于
  AGENTS.md 规则 11 的取树顺序，静默读到旧版比读不到更糟。

  同步前先过三道闸（不通过直接 exit 2，不写任何文件）：
    · 源里必须有 index.md
    · 节点文件数 ≥ 12（12 基，少于这个数说明缺文件）
    · 索引里不得出现机器绝对路径（`C:\`）与「同上目录」；任何节点不得写死 `C:\Users\`

  只增改、不删除：目标里多出的文件只告警，由人决定。

.PARAMETER Check
  只比对不回写。有漂移 exit 1，完全一致 exit 0。可放进提交前检查。

.PARAMETER NoInstall
  跳过安装位，只写仓库（发布机 / CI 用）。

.EXAMPLE
  pwsh -File scripts\sync-tree.ps1 -Check

.EXAMPLE
  pwsh -File scripts\sync-tree.ps1
#>
[CmdletBinding()]
param(
    [switch]$Check,
    [switch]$NoInstall
)

$ErrorActionPreference = 'Stop'

$repo   = Split-Path $PSScriptRoot -Parent
$wsRoot = Split-Path $repo -Parent
$source = Join-Path $wsRoot 'structure-tree'

$targets = @(
    (Join-Path $repo 'structure-isomorphism-pointmass-substitution\tree')
)
if (-not $NoInstall) {
    $targets += Join-Path $env:USERPROFILE '.dsh\skills\structure-isomorphism-pointmass-substitution\tree'
}

function Get-TreeMap {
    param([string]$Dir)
    $map = @{}
    if (-not (Test-Path $Dir)) { return $map }
    Get-ChildItem -Path $Dir -Filter *.md -File | ForEach-Object {
        $map[$_.Name] = (Get-FileHash -Path $_.FullName -Algorithm SHA256).Hash
    }
    return $map
}

# ---------- 闸门 ----------
if (-not (Test-Path $source)) {
    Write-Host "闸门拒绝：源目录不存在 $source" -ForegroundColor Red
    exit 2
}

$indexPath = Join-Path $source 'index.md'
if (-not (Test-Path $indexPath)) {
    Write-Host "闸门拒绝：源里没有 index.md" -ForegroundColor Red
    exit 2
}

$srcMap = Get-TreeMap $source
$nodeCount = @($srcMap.Keys | Where-Object { $_ -ne 'index.md' }).Count
if ($nodeCount -lt 12) {
    Write-Host "闸门拒绝：节点只有 $nodeCount 个（应 ≥ 12 基），疑似缺文件" -ForegroundColor Red
    exit 2
}

$problems = @()
$indexText = Get-Content -Path $indexPath -Raw -Encoding utf8
if ($indexText -match '[A-Za-z]:\\')  { $problems += '索引里出现机器绝对路径（C:\ 之类），分发后必断链' }
if ($indexText -match '同上目录')      { $problems += '索引里出现「同上目录」，跨目录引用会断链' }
foreach ($name in $srcMap.Keys) {
    $body = Get-Content -Path (Join-Path $source $name) -Raw -Encoding utf8
    if ($body -match 'C:\\Users\\') { $problems += "$name 写死了 C:\Users\ 路径" }
}
if ($problems.Count -gt 0) {
    $problems | ForEach-Object { Write-Host "闸门拒绝：$_" -ForegroundColor Red }
    exit 2
}

$version = if ($indexText -match '树版本\*\*：\s*(v[0-9.]+)') { $Matches[1] } else { 'v?' }
Write-Host ("源  {0}   版本 {1}   文件 {2}（节点 {3}）" -f $source, $version, $srcMap.Count, $nodeCount)

# ---------- 同步 ----------
$changedTotal = 0

foreach ($target in $targets) {
    Write-Host ""
    Write-Host ("目标 {0}" -f $target)

    $tgtMap = Get-TreeMap $target
    $added = @(); $changed = @(); $same = 0

    foreach ($name in $srcMap.Keys) {
        if (-not $tgtMap.ContainsKey($name))      { $added += $name }
        elseif ($tgtMap[$name] -ne $srcMap[$name]) { $changed += $name }
        else                                       { $same++ }
    }
    $extra = @($tgtMap.Keys | Where-Object { -not $srcMap.ContainsKey($_) })

    if ($added.Count -eq 0 -and $changed.Count -eq 0) {
        Write-Host ("  一致（{0} 个文件）" -f $same) -ForegroundColor Green
    }
    else {
        $changedTotal += $added.Count + $changed.Count
        foreach ($n in $added)   { Write-Host "  + $n" }
        foreach ($n in $changed) { Write-Host "  ~ $n" }
        if (-not $Check) {
            if (-not (Test-Path $target)) { New-Item -ItemType Directory -Path $target -Force | Out-Null }
            foreach ($n in @($added + $changed)) {
                Copy-Item -Path (Join-Path $source $n) -Destination (Join-Path $target $n) -Force
            }
            Write-Host "  → 已写入"
        }
    }

    if ($extra.Count -gt 0) {
        Write-Host ("  ! 目标多出 {0} 个源里没有的文件（不自动删除）：{1}" -f $extra.Count, ($extra -join ', ')) -ForegroundColor Yellow
    }
}

# ---------- 收尾 ----------
Write-Host ""

if ($Check) {
    if ($changedTotal -gt 0) {
        Write-Host ("漂移 {0} 个文件（-Check 未回写）。跑一次不带 -Check 的同步即可。" -f $changedTotal) -ForegroundColor Yellow
        exit 1
    }
    Write-Host "三处完全一致。" -ForegroundColor Green
    exit 0
}

$ok = $true
foreach ($target in $targets) {
    $m = Get-TreeMap $target
    if ($m.Count -ne $srcMap.Count) { $ok = $false; continue }
    foreach ($k in $srcMap.Keys) {
        if ($m[$k] -ne $srcMap[$k]) { $ok = $false }
    }
}

if ($ok) {
    Write-Host "校验通过：源 / 仓库 / 安装位 逐文件 SHA256 一致。" -ForegroundColor Green
    exit 0
}

Write-Host "校验失败：同步后仍有不一致，请检查写入权限。" -ForegroundColor Red
exit 1
