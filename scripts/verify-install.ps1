# verify-install.ps1 — 空房校验：远端仓库装出来的东西，是否与本机安装位逐字节一致
# 用法: .\scripts\verify-install.cmd [-Repo <url|path>] [-Ref <branch|tag>] [-InstallDir <path>] [-KeepTemp]
#   退出码: 0 = 一致；1 = 有差异（缺失／内容不同／本机多出文件）；2 = 参数或环境问题
# 兼容 Windows PowerShell 5.1（本文件须以 UTF-8 with BOM 保存）

param(
    [string]$Repo = '',
    [string]$Ref = '',
    [string]$InstallDir = '',
    [switch]$KeepTemp
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot

if (-not $InstallDir) {
    $InstallDir = if ($env:DSH_THINKING_INSTALL_DIR) { $env:DSH_THINKING_INSTALL_DIR } else { Join-Path $env:USERPROFILE '.dsh\skills' }
}

if (-not $Repo) {
    $Repo = (git -C $root remote get-url origin 2>$null)
    if (-not $Repo) {
        Write-Host 'ERROR: 没有 -Repo，且本目录不是带 origin 的 git 克隆。' -ForegroundColor Red
        Write-Host '  用法: .\scripts\verify-install.cmd -Repo https://github.com/<owner>/<repo>' -ForegroundColor Yellow
        exit 2
    }
}

Write-Host '=== CLEAN-ROOM INSTALL CHECK ===' -ForegroundColor Cyan
Write-Host ("repo        : " + $Repo)
Write-Host ("ref         : " + $(if ($Ref) { $Ref } else { '(default branch)' }))
Write-Host ("install dir : " + $InstallDir)

$tmp = Join-Path ([System.IO.Path]::GetTempPath()) ('dtm-verify-' + (Get-Random))
try {
    $cloneArgs = @('clone', '--depth', '1', '--quiet')
    if ($Ref) { $cloneArgs += @('--branch', $Ref) }
    $cloneArgs += @($Repo, $tmp)
    git @cloneArgs 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-Host ("ERROR: clone 失败（ref=" + $Ref + "）。标签不存在？") -ForegroundColor Red
        exit 2
    }

    $head = git -C $tmp rev-parse --short HEAD 2>$null
    $verFile = Join-Path $tmp 'VERSION'
    $ver = if (Test-Path -LiteralPath $verFile) { (Get-Content -LiteralPath $verFile -Raw).Trim() } else { '(none)' }
    Write-Host ("cloned      : " + $head + "  VERSION " + $ver)
    Write-Host ''

    $skills = @(Get-ChildItem -LiteralPath $tmp -Directory | Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'SKILL.md') })
    if ($skills.Count -eq 0) {
        Write-Host 'ERROR: 克隆里没有任何含 SKILL.md 的目录。' -ForegroundColor Red
        exit 2
    }

    $problems = 0
    $totalFiles = 0
    foreach ($s in $skills) {
        $srcDir = $s.FullName
        $dstDir = Join-Path $InstallDir $s.Name
        $srcFiles = @(Get-ChildItem -LiteralPath $srcDir -Recurse -File)
        $totalFiles += $srcFiles.Count
        $issues = @()

        foreach ($f in $srcFiles) {
            $rel = $f.FullName.Substring($srcDir.Length + 1)
            $dst = Join-Path $dstDir $rel
            if (-not (Test-Path -LiteralPath $dst)) {
                $issues += "missing: $rel"
                continue
            }
            $h1 = (Get-FileHash -LiteralPath $f.FullName -Algorithm SHA256).Hash
            $h2 = (Get-FileHash -LiteralPath $dst -Algorithm SHA256).Hash
            if ($h1 -ne $h2) { $issues += "differs: $rel" }
        }

        # 本机多出来的文件 = 只存在于本机、公开仓库里没有的知识，必须先归位
        if (Test-Path -LiteralPath $dstDir) {
            foreach ($f in @(Get-ChildItem -LiteralPath $dstDir -Recurse -File)) {
                $rel = $f.FullName.Substring($dstDir.Length + 1)
                if (-not (Test-Path -LiteralPath (Join-Path $srcDir $rel))) {
                    $issues += "local-only: $rel"
                }
            }
        }

        if ($issues.Count -eq 0) {
            Write-Host ("OK      {0,-52} {1} file(s)" -f $s.Name, $srcFiles.Count) -ForegroundColor Green
        } else {
            $problems++
            Write-Host ("DRIFT   {0,-52} {1} file(s)" -f $s.Name, $srcFiles.Count) -ForegroundColor Red
            foreach ($i in $issues) { Write-Host ("          - " + $i) -ForegroundColor Red }
        }
    }

    Write-Host ''
    Write-Host ("repo files total: " + $totalFiles + "   skills: " + $skills.Count)
    if ($problems -eq 0) {
        Write-Host 'RESULT: 公开仓库能完整装出本机这一套（逐字节一致，无本机独有文件）' -ForegroundColor Green
        exit 0
    }
    Write-Host ("RESULT: " + $problems + " 个技能不一致 —— 先修行，再发版") -ForegroundColor Red
    exit 1
}
finally {
    if (Test-Path -LiteralPath $tmp) {
        if ($KeepTemp) {
            Write-Host ("kept temp copy: " + $tmp) -ForegroundColor Yellow
        } else {
            Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
