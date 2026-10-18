#Requires -Version 5.1
<#
  state.ps1 - print the REAL state of a skills repo (git + installed copies + tree)

  Usage:
    .\scripts\state.cmd                  # overview
    .\scripts\state.cmd -Verify          # overview + exit 1 if repo != installed
    .\scripts\state.cmd -Repo <path>     # point at another repo (e.g. dsh-ordinary-thinking)
    .\scripts\state.cmd -Verify -RequireInstalled   # also fail when a skill is not installed at all

  Why a .cmd wrapper: this machine forbids running .ps1 directly (execution policy),
  so always invoke state.cmd, never state.ps1.
#>
[CmdletBinding()]
param(
  [string]$Repo = 'D:\DeepSeek-levelup\dsh-thinking-models',
  [switch]$Verify,
  [switch]$RequireInstalled
)

$ErrorActionPreference = 'Stop'

$install = Join-Path $env:USERPROFILE '.dsh\skills'

# Discover skill ids: any directory in the repo that contains a SKILL.md.
# This makes the script repo-agnostic (works for dsh-ordinary-thinking too).
$ids = @()
if (Test-Path -LiteralPath $Repo) {
  $ids = @(Get-ChildItem -LiteralPath $Repo -Directory |
           Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'SKILL.md') } |
           Select-Object -ExpandProperty Name | Sort-Object)
}
if ($ids.Count -eq 0) {
  $ids = @(
    'forest-hierarchical-backtracking',
    'web-association-exhaustive',
    'formula-pointmass-substitution',
    'presupposed-answer-hypothesis-backderivation'
  )
}

function Read-Utf8([string]$p) {
  if (Test-Path -LiteralPath $p) {
    return [System.IO.File]::ReadAllText($p, [System.Text.Encoding]::UTF8)
  }
  return $null
}

function Hash12([string]$p) {
  if (-not (Test-Path -LiteralPath $p)) { return '(missing)' }
  return (Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash.Substring(0, 12).ToLower()
}

if (-not (Test-Path -LiteralPath $Repo)) {
  Write-Host "repo path not found: $Repo" -ForegroundColor Red
  exit 1
}

Write-Host '=== REPO ===' -ForegroundColor Cyan
Write-Host "path    : $Repo"
Push-Location $Repo
try {
  Write-Host ('remote  : ' + (git remote get-url origin 2>$null))
  Write-Host ('branch  : ' + (git rev-parse --abbrev-ref HEAD))
  Write-Host ('head    : ' + (git rev-parse --short HEAD) + '  ' + (git log -1 --format='%s'))
  Write-Host ('tags    : ' + ((git tag) -join ', '))
  $dirty = @(git status --porcelain)
  Write-Host ('dirty   : ' + $dirty.Count + ' file(s)')
  foreach ($d in $dirty) { Write-Host "          $d" }
  $ver = Read-Utf8 (Join-Path $Repo 'VERSION')
  if ($ver) { Write-Host ('VERSION : ' + $ver.Trim()) }
} finally {
  Pop-Location
}

$bad = 0

Write-Host ''
Write-Host '=== SKILLS (repo <-> installed) ===' -ForegroundColor Cyan
foreach ($id in $ids) {
  $rp = Join-Path $Repo (Join-Path $id 'SKILL.md')
  $ip = Join-Path $install (Join-Path $id 'SKILL.md')
  if (-not (Test-Path -LiteralPath $rp)) { continue }
  $rh = Hash12 $rp
  $ih = Hash12 $ip
  # NONE = 该技能没有装进 DSH（例如另一个仓库的模拟版技能，故意不装）
  $mark = if ($ih -eq '(missing)') { 'NONE' } elseif ($rh -eq $ih) { 'OK  ' } else { 'DIFF' }
  if ($mark -eq 'DIFF') { $bad++ }
  if ($mark -eq 'NONE' -and $RequireInstalled) { $bad++ }
  $color = switch ($mark) { 'OK  ' { 'Gray' } 'DIFF' { 'Red' } default { 'Yellow' } }
  Write-Host ('{0} {1,-46} repo={2} installed={3}' -f $mark, $id, $rh, $ih) -ForegroundColor $color
}

Write-Host ''
Write-Host '=== KNOWLEDGE TREE ===' -ForegroundColor Cyan
$treedir = Join-Path $Repo 'forest-hierarchical-backtracking\tree'
if (Test-Path -LiteralPath $treedir) {
  $treeInstall = Join-Path $install 'forest-hierarchical-backtracking\tree'
  foreach ($f in (Get-ChildItem -LiteralPath $treedir -Filter *.md | Sort-Object Name)) {
    $rh = Hash12 $f.FullName
    $ih = Hash12 (Join-Path $treeInstall $f.Name)
    if ($rh -ne $ih) { $bad++ }
    $txt = Read-Utf8 $f.FullName
    $verLine = (($txt -split "`r?`n") | Where-Object { $_ -match 'v\d+' } | Select-Object -First 1)
    if ($verLine) { $verLine = ($verLine -replace '^\s*[#>\-\|\*]+\s*', '').Trim() }
    $mark = if ($rh -eq $ih) { 'OK  ' } else { 'DIFF' }
    Write-Host ('{0} {1,-28} {2} | {3}' -f $mark, $f.Name, $rh, $verLine)
  }
} else {
  Write-Host 'tree dir not present in this repo (optional)' -ForegroundColor DarkGray
}

if ($Verify) {
  Write-Host ''
  Write-Host '=== VERIFY ===' -ForegroundColor Cyan
  Write-Host ('AGENTS.md present : ' + (Test-Path -LiteralPath 'D:\DeepSeek-levelup\AGENTS.md'))
  Write-Host ('skills.off exists : ' + (Test-Path -LiteralPath (Join-Path $env:USERPROFILE '.dsh\skills.off')))
  if ($bad -gt 0) {
    Write-Host "RESULT: $bad mismatch(es) - sync repo -> installed before commit/push" -ForegroundColor Red
    exit 1
  }
  Write-Host 'RESULT: repo and installed copies are identical' -ForegroundColor Green
}
