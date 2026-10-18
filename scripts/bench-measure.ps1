#Requires -Version 5.1
<#
.SYNOPSIS
    从磁盘实测对比表的数字（行数／字符／表格行／章节／负边条数／8 因子命中），不采信任何自述。

.DESCRIPTION
    LLM 自述的行数与实际磁盘内容经常不一致（实测过一例：自述 161 行，实际 212 行）。
    所以对照实验的所有量化指标一律由本脚本数，人工不参与。

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\bench-measure.ps1 -Path .\docs\benchmark\after-v2
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Path,

    # 额外统计题面 1 的 8 因子真因关键词命中
    [switch]$Factors
)

$ErrorActionPreference = 'Stop'

$negativePattern = '负边|已排除|排除项|无关项|不成立|退化|不作为|已剪枝|剪枝理由|not an issue|ruled out'

$factorGroups = [ordered]@{
    '1 码值语义' = 'STATUS_DLL_INIT_FAILED|0xC0000142|3221225794 是|DLL_INIT'
    '2 DllMain阶段' = 'DllMain|入口点|DLL_PROCESS_ATTACH'
    '3 Session0' = 'Session 0|Session0|窗口站|window station'
    '4 桌面堆' = 'SharedSection|桌面堆|desktop heap'
    '5 影子DLL' = '影子|DLL 搜索|搜索顺序|SearchPath|shadow'
    '6 AppInit注入' = 'AppInit|注入|hook'
    '7 SxS' = 'SxS|side-by-side|并行配置|清单文件'
    '8 令牌/完整性' = '受限令牌|完整性级别|integrity level|WRITE_RESTRICTED|低完整性'
}

$files = Get-ChildItem -LiteralPath $Path -Filter '*.md' -File | Sort-Object Name
if ($files.Count -eq 0) { throw "目录下没有 .md 文件：$Path" }

Write-Host ''
Write-Host '| 文件 | 行数 | 字符 | 表格数据行 | 章节 | 负边相关行 |' -ForegroundColor Cyan
Write-Host '|---|---|---|---|---|---|'
$rows = @()
foreach ($f in $files) {
    $text  = Get-Content -LiteralPath $f.FullName -Raw -Encoding UTF8
    $lines = Get-Content -LiteralPath $f.FullName -Encoding UTF8
    $lineCount = @($lines).Count
    $charCount = $text.Length
    $tableRows = @($lines | Where-Object { $_ -match '^\s*\|' }).Count
    $headings  = @($lines | Where-Object { $_ -match '^#{1,6}\s' }).Count
    $negLines  = @($lines | Where-Object { $_ -match $negativePattern }).Count
    Write-Host ("| {0} | {1} | {2} | {3} | {4} | {5} |" -f $f.Name, $lineCount, $charCount, $tableRows, $headings, $negLines)
    $rows += [pscustomobject]@{ File = $f; Text = $text; Lines = $lineCount; Chars = $charCount }
}

if ($Factors) {
    Write-Host ''
    Write-Host '### 题面 1 的 8 因子真因命中（在 -Path 下所有文件中统计）' -ForegroundColor Cyan
    foreach ($name in $factorGroups.Keys) {
        $pattern = $factorGroups[$name]
        $hit = 0
        foreach ($r in $rows) {
            $hit += ([regex]::Matches($r.Text, $pattern, 'IgnoreCase')).Count
        }
        $mark = if ($hit -gt 0) { '✅' } else { '❌' }
        Write-Host ("{0} {1,-14} 命中次数={2}" -f $mark, $name, $hit)
    }
}

Write-Host ''
Write-Host '说明：负边相关行是「按关键词粗筛的候选行」，最终条数仍需人工读一遍确认（一条负边可能跨多行）。' -ForegroundColor DarkGray
