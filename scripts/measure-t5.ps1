param(
  [Parameter(Mandatory=$true)][string]$Dir
)

# 统计口径来自 runs-staging\T5\rubric.md（预注册），本脚本只负责机械执行。
# 必须显式 UTF-8 解码：PowerShell 5.1 的 Get-Content 默认按 GBK 读，会吞掉换行字节。

Get-ChildItem -Path $Dir -Filter 'agent-*.md' | Sort-Object Name | ForEach-Object {
  $t = [System.IO.File]::ReadAllText($_.FullName, [System.Text.Encoding]::UTF8)
  $lines = ($t -split "`r?`n").Count
  if ($t.EndsWith("`n")) { $lines = $lines - 1 }
  $tbl   = ([regex]::Matches($t, '(?m)^\s*\|.*\|\s*$')).Count
  $m1    = if ($t -match '无法(确定|辨识|归因|定因|区分|分离)|不可辨识|证据不足.{0,12}(无法|不能)|不能.{0,6}分离') { 1 } else { 0 }
  $m2    = ([regex]::Matches($t, '排除|无关|非根|⊥')).Count
  $m3    = if ($t -match '(判据|若|如果|否则|对照|分组|交叉|分桶).{0,40}(则|就|说明|判定)') { 1 } else { 0 }
  [pscustomobject]@{
    agent  = $_.Name -replace 'agent-','' -replace '\.md$',''
    lines  = $lines
    chars  = $t.Length
    tblRow = $tbl
    M1     = $m1
    M2     = $m2
    M3     = $m3
  }
} | Format-Table -AutoSize
