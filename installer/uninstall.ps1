# mingdao-worklog-api 一键卸载 (Windows PowerShell 5+)
#
# 用法：
#   irm https://raw.githubusercontent.com/hemiyang2011-commits/mingdao-worklog-api/main/installer/uninstall.ps1 | iex
#
#   # 非交互（CI）
#   $env:UNATTENDED_REMOVE = "1"     # 全部按默认 Yes
#   $env:UNATTENDED_REMOVE = "0"     # 全部按默认 No
#   irm ...uninstall.ps1 | iex
#
# 行为：
#   - 默认保留 config.json（含你的 appKey/secretKey），免得下次还要重新填
#   - 默认不删 skill 目录（你可能想换分支或升级）
#   - 默认不恢复 git core.hooksPath（其它 hook 可能还要用）
#
# 通过 -RemoveConfig -RemoveDir -RestoreGitHooks 显式指定

[CmdletBinding()]
param(
    [switch]$RemoveConfig = $false,
    [switch]$RemoveDir    = $false,
    [switch]$RestoreGitHooks = $false,
    [switch]$Unattended   = $false
)

$ErrorActionPreference = "Stop"
$SKILL_NAME = "mingdao-worklog-api"
$TARGET_DIR = Join-Path $HOME ".workbuddy\skills\$SKILL_NAME"

function Yes($prompt) {
    if ($Unattended) {
        return ($env:UNATTENDED_REMOVE -ne "0")
    }
    $ans = Read-Host "$prompt (Y/n)"
    return ($ans -notin @("n","N","no","NO"))
}

Write-Host ""
Write-Host "=== mingdao-worklog-api 一键卸载 (Windows) ===" -ForegroundColor Yellow
Write-Host "目标目录：$TARGET_DIR"
Write-Host ""

# 1. junction / symlink
Write-Host "[1/5] 移除 agent 工具软链接" -ForegroundColor Cyan
$links = @(
    "$HOME\.claude\skills\$SKILL_NAME",
    "$HOME\.codex\skills\$SKILL_NAME",
    "$HOME\.agents\skills\$SKILL_NAME",
    "$HOME\.config\opencode\skills\$SKILL_NAME",
    "$HOME\.gemini\config\skills\$SKILL_NAME"
)
foreach ($l in $links) {
    if (Test-Path $l) {
        $item = Get-Item $l -Force
        if ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) {
            # junction（重解析点）
            & cmd /c rmdir "$l" 2>&1 | Out-Null
            if ($?) { Write-Host "  ✓ $l (junction)" -ForegroundColor Green }
            else    { Write-Host "  ⚠ 删除 junction 失败：$l" -ForegroundColor Yellow }
        } elseif ($item.Attributes -band [System.IO.FileAttributes]::Directory) {
            Remove-Item -Recurse -Force $l
            Write-Host "  ✓ $l (dir)" -ForegroundColor Green
        } else {
            Remove-Item -Force $l
            Write-Host "  ✓ $l" -ForegroundColor Green }
    } else {
        Write-Host "  - $l (不存在，跳过)"
    }
}

# 2. AGENTS.md / CLAUDE.md 声明
Write-Host ""
Write-Host "[2/5] 移除 AGENTS.md / CLAUDE.md 声明" -ForegroundColor Cyan
$declareFiles = @("$HOME\.claude\CLAUDE.md", "$HOME\.codex\AGENTS.md", "$HOME\.agents\AGENTS.md")
foreach ($f in $declareFiles) {
    if (-not (Test-Path $f)) { Write-Host "  - $f (不存在)"; continue }
    $content = Get-Content $f -Raw -Encoding UTF8
    # 删除 WORKLOG_MINGDAO_BEGIN .. WORKLOG_MINGDAO_END 块（含前后空行）
    $pattern = "(?s)\r?\n*<!--\s*WORKLOG_MINGDAO_BEGIN\s*-->.*?<!--\s*WORKLOG_MINGDAO_END\s*-->\r?\n*"
    $new = [regex]::Replace($content, $pattern, "`r`n", 1)
    if ($new -ne $content) {
        Set-Content -Path $f -Value $new -Encoding UTF8
        Write-Host "  ✓ 已清理声明 → $f" -ForegroundColor Green
    } else {
        Write-Host "  - 未发现声明 → $f"
    }
}

# 3. commit-msg hook
Write-Host ""
Write-Host "[3/5] 移除 commit-msg hook" -ForegroundColor Cyan
$hookPath = "$HOME\.git_hooks\commit-msg"
if (Test-Path $hookPath) {
    # 验证确实是本 skill 的 hook（避免删错）
    $firstLine = Get-Content $hookPath -TotalCount 5 -Encoding UTF8 | Out-String
    if ($firstLine -like "*worklog-hook*") {
        Remove-Item -Force $hookPath
        Write-Host "  ✓ 已删除 hook：$hookPath" -ForegroundColor Green
    } else {
        Write-Host "  ⚠ $hookPath 不是本 skill 的 hook，保留" -ForegroundColor Yellow
    }
} else {
    Write-Host "  - $hookPath (不存在)"
}

# 4. 恢复 git core.hooksPath
Write-Host ""
Write-Host "[4/5] 恢复 git core.hooksPath" -ForegroundColor Cyan
$current = & git config --global core.hooksPath 2>$null
if ($current -eq "$HOME\.git_hooks") {
    if ($RestoreGitHooks -or (Yes "  当前 core.hooksPath 指向本 skill 的 hook 目录，要 unset 吗")) {
        & git config --global --unset core.hooksPath
        Write-Host "  ✓ 已 unset core.hooksPath" -ForegroundColor Green
    } else {
        Write-Host "  - 保留现有 core.hooksPath"
    }
} elseif ($current) {
    Write-Host "  - core.hooksPath 指向别处（$current），不动"
} else {
    Write-Host "  - core.hooksPath 未设置，无需恢复"
}

# 5. 删除 config.json / skill 目录
Write-Host ""
Write-Host "[5/5] 删除 config.json / skill 目录（默认保留）" -ForegroundColor Cyan
$cfgPath = Join-Path $TARGET_DIR "config.json"
if (Test-Path $cfgPath) {
    if ($RemoveConfig -or (Yes "  删除 $cfgPath （含凭证）?")) {
        Remove-Item -Force $cfgPath
        Write-Host "  ✓ 已删除 $cfgPath" -ForegroundColor Green
    } else {
        Write-Host "  - 保留 $cfgPath"
    }
}
if (Test-Path $TARGET_DIR) {
    if ($RemoveDir -or (Yes "  删除整个 skill 目录 $TARGET_DIR ?")) {
        Remove-Item -Recurse -Force $TARGET_DIR
        Write-Host "  ✓ 已删除 $TARGET_DIR" -ForegroundColor Green
    } else {
        Write-Host "  - 保留 $TARGET_DIR"
    }
}

Write-Host ""
Write-Host "=== 卸载完成 ===" -ForegroundColor Green
Write-Host "  想重装：irm ...install.ps1 | iex"
Write-Host ""
