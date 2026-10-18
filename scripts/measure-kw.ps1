# measure-kw.ps1 — 按预注册关键词表做机械计数（不做判断、不改文件）
# 用法: measure-kw.cmd -Task T7 -Dir D:\DeepSeek-levelup\runs-staging\T7
param(
  [Parameter(Mandatory=$true)][string]$Task,
  [Parameter(Mandatory=$true)][string]$Dir
)

$patterns = @{
  T7 = [ordered]@{
    K1 = '关闭重试|关掉重试|停掉重试|暂停重试|放回 ?2s|恢复到 ?2s|反向实验|对照实验|先停用重试|关掉重试'
    K2 = '正反馈|放大器|放大效应|雪崩|重试风暴|thundering|自我强化|自我放大'
    K3 = '方向反|结论相反|倒果为因|因果倒置|恰恰相反|反了|不是下游导致|归因方向错'
    K4 = '分位|p99|p95|直方图|分布|均值'
  }
  T8 = [ordered]@{
    K1 = '不是单一|没有单一|不是某个|分布问题|概率|随机|统计性|不是 ?bug|没有唯一'
    K2 = 'P50|中位|median|上限偏低|limit ?过低|按平均设|按中位设'
    K3 = 'P99|P95|压舱|balloon|余量|预留|提高 ?limit|上调 ?limit|分位数分配'
    K4 = '内存泄漏|memory ?leak'
  }
  T9 = [ordered]@{
    K1 = '不可行|不现实|降级|成本闸门|不可执行|18 ?人月|业务不批|暂不|不具备条件'
    K2 = '统一入参|入参边界|统一入口|剥离|独立服务|WAF|权限分离|最小权限|参数化|框架'
    K3 = '治标|症状|打补丁|补丁循环|救火|每个月|反复'
    K4 = '重写|换栈'
  }
  T10 = [ordered]@{
    K1 = '树外|知识树|org-process|未建|登记|临时树|覆盖不到|树里没有'
    K2 = '入口|准入|闸门|门禁|排期|交付|反馈|进入|流入'
    K3 = '拒绝权|否决|承诺权|入口不在|无权拒绝|上游派|谁决定|决策权|准入'
    K4 = '执行力|态度|责任心|人不行|能力不足|不够努力'
  }
}

if (-not $patterns.ContainsKey($Task)) { Write-Host "未知 Task: $Task"; exit 2 }
$p = $patterns[$Task]

$files = Get-ChildItem -Path $Dir -Filter 'agent-*.md' -ErrorAction SilentlyContinue | Sort-Object Name
if (-not $files) { Write-Host "目录里没有 agent-*.md: $Dir"; exit 1 }

$rows = @()
foreach ($f in $files) {
  $text = [System.IO.File]::ReadAllText($f.FullName, [System.Text.Encoding]::UTF8)
  $lineCount = ($text -split "`n").Count
  $tbl = ([regex]::Matches($text, '(?m)^\s*\|.*\|\s*$')).Count
  $o = [ordered]@{
    file   = $f.Name
    chars  = $text.Length
    lines  = $lineCount
    tblrows= $tbl
  }
  foreach ($k in $p.Keys) {
    $c = ([regex]::Matches($text, $p[$k], 'IgnoreCase')).Count
    $o[$k] = if ($c -gt 0) { "1 ($c)" } else { "0" }
  }
  $rows += [pscustomobject]$o
}

$rows | Format-Table -AutoSize | Out-String -Width 200 | Write-Host
Write-Host ("文件数: {0}  字符合计: {1}  字符中位: {2}" -f $files.Count, (($rows | Measure-Object chars -Sum).Sum), (($rows | Measure-Object chars | ForEach-Object { $_.Sum })))
