# mingdao-worklog-api 一键安装脚本 (Windows PowerShell 5+)
#
# 用法：
#   # 标准用法（线上安装，从 GitHub 拉）
#   irm https://raw.githubusercontent.com/hemiyang2011-commits/mingdao-worklog-api/main/installer/install.ps1 | iex
#
#   # 指定仓库 / 跳过凭证环节（CI / 离线）
#   $env:REPO_URL = "https://github.com/hemiyang2011-commits/mingdao-worklog-api.git"
#   $env:MINGDAO_APPKEY = "..."
#   $env:MINGDAO_SECRETKEY = "..."
#   irm ...install.ps1 | iex
#
#   # 本地开发（从本地目录拷，不走 git）
#   .\installer\install.ps1 -LocalSource "C:\path\to\this\repo"
#
# 设计原则：
#   - AGENTS.md 声明 + commit-msg hook 双触发，但 hook 单独询问是否装
#   - 安装到所有当前存在的 agent 工具配置目录（探测），不强制创建空目录
#   - junction 一源五用，文件集中管理
#   - 凭证输入不回显，使用 SecureString
#   - 不破坏用户已有 config.json（已存在则保留，仅在 --force-config 时覆盖）

[CmdletBinding()]
param(
    [string]$LocalSource = "",
    [string]$TargetDir   = "",          # 测试用：覆盖默认 ~/.workbuddy/skills/<skill>
    [switch]$ForceConfig = $false,
    [switch]$NoHook      = $false,
    [switch]$Unattended  = $false       # 用环境变量跳过交互
)

$ErrorActionPreference = "Stop"
$ProgressPreference   = "SilentlyContinue"  # 关闭 irm 进度条

# ============== 常量 ==============
# 测试钩子：设置 $env:WORKLOG_TEST_HOME = "<sandbox>" 后，所有 home 路径都重定向（不污染真实工作区）
$H = if ($env:WORKLOG_TEST_HOME) { $env:WORKLOG_TEST_HOME } else { $HOME }
# 写入文件用无 BOM UTF-8（Python json.load + 多数 agent 工具不认 BOM）
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$SKILL_NAME   = "mingdao-worklog-api"
$TARGET_DIR   = if ($TargetDir) { $TargetDir } else { Join-Path $H ".workbuddy\skills\$SKILL_NAME" }
$REPO_URL     = if ($env:REPO_URL)     { $env:REPO_URL }     else { "https://github.com/hemiyang2011-commits/mingdao-worklog-api.git" }
$BRANCH       = if ($env:BRANCH)       { $env:BRANCH }       else { "main" }

# ============== 工具函数 ==============
function Write-Step($n, $msg) {
    Write-Host ""
    Write-Host "[$n/$((@($Steps).Count))] $msg" -ForegroundColor Cyan
}
function Write-OK($msg)   { Write-Host "  ✓ $msg" -ForegroundColor Green }
function Write-Warn($msg) { Write-Host "  ⚠ $msg" -ForegroundColor Yellow }
function Write-Err($msg)  { Write-Host "  ✗ $msg" -ForegroundColor Red }

function Test-Python {
    try { $v = & python --version 2>&1; if ($LASTEXITCODE -eq 0) { return "python" } } catch {}
    try { $v = & py -3 --version 2>&1; if ($LASTEXITCODE -eq 0) { return "py -3"   } } catch {}
    return $null
}
function Test-Git {
    try { $v = & git --version 2>&1; if ($LASTEXITCODE -eq 0) { return $true } } catch {}
    return $false
}

function Read-Secret([string]$prompt) {
    Write-Host $prompt -NoNewline
    $secure = Read-Host -AsSecureString
    $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
    try {
        return [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr)
    } finally {
        [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
    }
}

# ============== 0. 横幅 ==============
Write-Host ""
Write-Host "=== mingdao-worklog-api 一键安装 (Windows) ===" -ForegroundColor Cyan
Write-Host "Skill 源：$REPO_URL"
Write-Host "目标：$TARGET_DIR"
Write-Host ""

$Steps = @(
    "检测 Python / Git",
    "获取明道云 appKey + secretKey",
    "拉取 skill 源文件",
    "写入 config.json",
    "创建 agent 工具 junction",
    "写入 AGENTS.md / CLAUDE.md 声明",
    "安装 commit-msg hook (可选)",
    "运行 test-auth 验证"
)
$stepIdx = 0

# ============== 1. Python / Git ==============
$stepIdx++
Write-Step $stepIdx "检测 Python / Git"
$python = Test-Python
if (-not $python) {
    Write-Err "未检测到 python。请先安装 Python 3.8+（https://python.org）"
    exit 1
}
Write-OK "Python: $python"
if (-not (Test-Git)) {
    Write-Warn "未检测到 git。若 LocalSource 为空且目标目录不存在会失败。可安装 git for windows 或用 -LocalSource。"
} else {
    Write-OK "Git 已安装"
}

# ============== 2. 凭证 ==============
$stepIdx++
Write-Step $stepIdx "获取明道云 appKey + secretKey"
$appKey   = $env:MINGDAO_APPKEY
$secretKey = $env:MINGDAO_SECRETKEY

if (-not $Unattended -and (-not $appKey -or -not $secretKey)) {
    Write-Host "  (在另一台明道云 → 应用 → 应用授权获取 appKey + secretKey)"
    Write-Host "  (输入不回显；如不想现在填可 Ctrl+C 中断后用环境变量 MINGDAO_APPKEY / MINGDAO_SECRETKEY 重跑)"
    if (-not $appKey)   { $appKey   = Read-Host "  appKey" }
    if (-not $secretKey){ $secretKey = Read-Secret "  secretKey (不回显)" }
}
if (-not $appKey -or -not $secretKey) { Write-Err "缺少 appKey 或 secretKey"; exit 1 }
Write-OK "appKey/secretKey 已接收（不回显）"

# ============== 3. 拉取源文件 ==============
$stepIdx++
Write-Step $stepIdx "拉取 skill 源文件"

if ($LocalSource) {
    if (-not (Test-Path $LocalSource)) { Write-Err "LocalSource 不存在：$LocalSource"; exit 1 }
    if (Test-Path $TARGET_DIR) {
        Write-Warn "$TARGET_DIR 已存在，跳过拷贝（用 -ForceConfig 或手动删除后再装）"
    } else {
        New-Item -ItemType Directory -Path $TARGET_DIR -Force | Out-Null
        Copy-Item -Path (Join-Path $LocalSource "*") -Destination $TARGET_DIR -Recurse -Force
        Write-OK "已从 $LocalSource 拷贝到 $TARGET_DIR"
    }
} else {
    if (Test-Path $TARGET_DIR) {
        Write-Host "  目录已存在，git pull 更新..."
        Push-Location $TARGET_DIR
        try { & git pull --ff-only 2>&1 | Out-Null; if ($LASTEXITCODE -ne 0) { throw } }
        catch { Write-Warn "git pull 失败，使用现有目录继续" }
        Pop-Location
    } else {
        New-Item -ItemType Directory -Path (Split-Path $TARGET_DIR) -Force | Out-Null
        Write-Host "  git clone $REPO_URL ..."
        & git clone --depth 1 --branch $BRANCH $REPO_URL $TARGET_DIR
        if ($LASTEXITCODE -ne 0) { Write-Err "git clone 失败"; exit 1 }
    }
    Write-OK "skill 源文件已就位"
}

if (-not (Test-Path (Join-Path $TARGET_DIR "scripts\worklog_api.py"))) {
    Write-Err "源文件目录里找不到 scripts\worklog_api.py，源仓库结构异常"; exit 1
}

# ============== 4. config.json ==============
$stepIdx++
Write-Step $stepIdx "写入 config.json"
$configPath = Join-Path $TARGET_DIR "config.json"
$examplePath = Join-Path $TARGET_DIR "config.example.json"

if ((Test-Path $configPath) -and -not $ForceConfig) {
    Write-Warn "$configPath 已存在，未覆盖（用 -ForceConfig 强制覆盖）"
} else {
    if (-not (Test-Path $examplePath)) { Write-Err "config.example.json 不存在"; exit 1 }
    $cfgJson = Get-Content $examplePath -Raw -Encoding UTF8 | ConvertFrom-Json
    $cfgJson.appKey    = $appKey
    $cfgJson.secretKey = $secretKey
    # 写入用 utf8 without BOM（Python json.load 不认 BOM；PowerShell Set-Content -Encoding UTF8 默认加 BOM）
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    $jsonText = $cfgJson | ConvertTo-Json -Depth 10
    [System.IO.File]::WriteAllText($configPath, $jsonText, $utf8NoBom)
    Write-OK "已写入 $configPath（无 BOM）"
}

# ============== 5. junction ==============
$stepIdx++
Write-Step $stepIdx "创建 agent 工具 junction"
$links = @(
    @{ Path = "$H\.claude\skills";        Tool = "Claude Code"   },
    @{ Path = "$H\.codex\skills";         Tool = "OpenAI Codex"  },
    @{ Path = "$H\.agents\skills";        Tool = "通用（OpenCode/ZCode/Antigravity）" },
    @{ Path = "$H\.config\opencode\skills"; Tool = "OpenCode 专用" },
    @{ Path = "$H\.gemini\config\skills"; Tool = "Google Antigravity 专用" }
)
foreach ($l in $links) {
    $parent = $l.Path
    $link   = Join-Path $parent $SKILL_NAME
    if (-not (Test-Path $parent)) { continue }  # 探测：本机未装该工具就跳过
    if (Test-Path $link) {
        Write-OK "  已存在 → $Tool"
    } else {
        try {
            New-Item -ItemType Junction -Path $link -Target $TARGET_DIR -Force | Out-Null
            Write-OK "  创建 → $Tool  ($link)"
        } catch {
            Write-Warn "  创建失败 ($Tool)：$_"
        }
    }
}

# ============== 6. AGENTS.md 声明 ==============
$stepIdx++
Write-Step $stepIdx "写入 AGENTS.md / CLAUDE.md 声明"
$fragmentPath = Join-Path $TARGET_DIR "installer\AGENTS.fragment.md"
if (-not (Test-Path $fragmentPath)) {
    Write-Warn "未找到 $fragmentPath，跳过声明"
} else {
    $fragment = Get-Content $fragmentPath -Raw -Encoding UTF8
    $candidates = @(
        @{ Path = "$H\.claude\CLAUDE.md";        Type = "append"; Marker = "<!-- CODEGRAPH_END -->" },
        @{ Path = "$H\.codex\AGENTS.md";         Type = "append"; Marker = "<!-- CODEGRAPH_END -->" },
        @{ Path = "$H\.agents\AGENTS.md";        Type = "create"; Marker = $null                   }
    )
    foreach ($c in $candidates) {
        $f = $c.Path
        if ($c.Type -eq "append" -and -not (Test-Path $f)) { continue }   # 仅探测到才追加
        if ($c.Type -eq "create" -and -not (Test-Path (Split-Path $f))) { continue }
        if ((Test-Path $f) -and (Select-String -Path $f -Pattern "WORKLOG_MINGDAO_BEGIN" -Quiet)) {
            Write-Warn "  已声明，跳过 → $f"
            continue
        }
        $dir = Split-Path $f
        if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        if ($c.Type -eq "append" -and $c.Marker -and (Test-Path $f) -and (Select-String -Path $f -Pattern $c.Marker -Quiet)) {
            # 在 CODEGRAPH 块后追加（无 BOM）
            $content = Get-Content $f -Raw -Encoding UTF8
            $content = $content -replace [regex]::Escape($c.Marker), ($c.Marker + "`r`n`r`n" + $fragment)
            [System.IO.File]::WriteAllText($f, $content, $utf8NoBom)
        } else {
            # 全新写入 / 追加（无 BOM）
            if (Test-Path $f) {
                $cur = Get-Content $f -Raw -Encoding UTF8
                [System.IO.File]::WriteAllText($f, $cur + "`r`n`r`n" + $fragment, $utf8NoBom)
            } else {
                [System.IO.File]::WriteAllText($f, $fragment, $utf8NoBom)
            }
        }
        Write-OK "  写入 → $f"
    }
}

# ============== 7. commit-msg hook ==============
$stepIdx++
Write-Step $stepIdx "安装 commit-msg hook (可选)"
$installHook = $false
if ($NoHook) {
    Write-Warn "  -NoHook，跳过"
} elseif ($Unattended) {
    if ($env:WORKLOG_NO_HOOK) { Write-Warn "  环境变量 WORKLOG_NO_HOOK 跳过" } else { $installHook = $true }
} else {
    $ans = Read-Host "  是否安装 git commit-msg hook？(Y/n)"
    if ($ans -notin @("n","N","no","NO")) { $installHook = $true }
}
if ($installHook) {
    $hookSrc  = Join-Path $TARGET_DIR "installer\hooks\commit-msg"
    $hookDir  = "$H\.git_hooks"
    $hookDst  = Join-Path $hookDir "commit-msg"
    if (-not (Test-Path $hookSrc)) { Write-Err "  hook 源缺失：$hookSrc"; exit 1 }
    if (-not (Test-Path $hookDir)) { New-Item -ItemType Directory -Path $hookDir -Force | Out-Null }
    Copy-Item -Path $hookSrc -Destination $hookDst -Force
    Write-OK "  hook 已复制到 $hookDst"
    if ($env:WORKLOG_TEST_HOME) {
        Write-Warn "  测试模式（WORKLOG_TEST_HOME 已设置），跳过 git config --global 写入"
    } else {
        & git config --global core.hooksPath "$H\.git_hooks"
        if ($LASTEXITCODE -eq 0) {
            Write-OK "  git config --global core.hooksPath 已设"
        } else {
            Write-Warn "  git config 设置失败，可手动执行：git config --global core.hooksPath '$H\.git_hooks'"
        }
    }
}

# ============== 8. test-auth ==============
$stepIdx++
Write-Step $stepIdx "运行 test-auth 验证"
Push-Location $TARGET_DIR
try {
    # 用 cmd /c 调用 python，避免 PowerShell 5.1 Start-Process 的"PATH/Path"歧义
    $tmpOut = [System.IO.Path]::GetTempFileName()
    $tmpErr = [System.IO.Path]::GetTempFileName()
    $pythonExe = "python"
    if (-not (Get-Command python -ErrorAction SilentlyContinue)) {
        if (Get-Command py -ErrorAction SilentlyContinue) { $pythonExe = "py -3" }
    }
    $cmdLine = "$pythonExe scripts\worklog_api.py --config config.json test-auth > `"$tmpOut`" 2> `"$tmpErr`""
    cmd /c $cmdLine
    $exitCode = $LASTEXITCODE
    $stdoutTxt = ""
    $stderrTxt = ""
    if (Test-Path $tmpOut) { $stdoutTxt = Get-Content $tmpOut -Raw -Encoding UTF8 -ErrorAction SilentlyContinue }
    if (Test-Path $tmpErr) { $stderrTxt = Get-Content $tmpErr -Raw -Encoding UTF8 -ErrorAction SilentlyContinue }
    if ($exitCode -eq 0 -and ($stdoutTxt -match '"ok":\s*true' -or $stdoutTxt -match 'worksheet_name')) {
        Write-OK "test-auth 通过！"
    } else {
        Write-Warn "test-auth 返回 exit=$exitCode（建议手工核对 python 配置，可能不影响使用）"
        if ($stderrTxt) {
            $short = ($stderrTxt -split "`n")[0..3] -join "`n"
            Write-Host "    $short"
        }
        # 不让脚本整体 exit 1（test-auth 只是 sanity check，安装链路已完成）
    }
} catch {
    Write-Warn "test-auth 步骤本身异常，但安装已完成，可忽略：$_"
} finally {
    Pop-Location
}

# ============== 完成 ==============
Write-Host ""
Write-Host "============================================" -ForegroundColor Green
Write-Host "  mingdao-worklog-api 安装完成" -ForegroundColor Green
Write-Host "============================================" -ForegroundColor Green
Write-Host ""
Write-Host "接下来可以："
Write-Host "  1. 在 Claude Code / Codex / OpenCode / Antigravity 任一 agent 工具里说："
Write-Host "        '帮我写一条工作日志'"
Write-Host "  2. git commit -m '修复XX #log 项目:你的项目 #time=2h'（如装了 hook）自动写日志"
Write-Host "  3. 想卸载：运行 uninstall.ps1"
Write-Host ""
