#!/usr/bin/env bash
# mingdao-worklog-api 一键安装脚本 (macOS / Linux)
#
# 用法：
#   # 标准用法（线上安装，从 GitHub 拉）
#   curl -fsSL https://raw.githubusercontent.com/<USER>/mingdao-worklog-api/main/installer/install.sh | bash
#
#   # 跳过交互（CI / 离线）
#   REPO_URL=https://github.com/<USER>/mingdao-worklog-api.git \
#   MINGDAO_APPKEY=xxx MINGDAO_SECRETKEY=yyy \
#       curl -fsSL ... | bash
#
#   # 本地开发
#   ./installer/install.sh --local /path/to/this/repo
#
set -euo pipefail

# ============== 常量与默认值 ==============
SKILL_NAME="mingdao-worklog-api"
TARGET_DIR="$HOME/.workbuddy/skills/$SKILL_NAME"
REPO_URL="${REPO_URL:-https://github.com/<YOUR-GITHUB-USERNAME>/mingdao-worklog-api.git}"
BRANCH="${BRANCH:-main}"
LOCAL_SOURCE=""
FORCE_CONFIG=0
NO_HOOK=0
UNATTENDED="${UNATTENDED:-0}"

# ============== 参数解析 ==============
while [[ $# -gt 0 ]]; do
    case "$1" in
        --local)         LOCAL_SOURCE="$2"; shift 2 ;;
        --repo)          REPO_URL="$2"; shift 2 ;;
        --branch)        BRANCH="$2"; shift 2 ;;
        --force-config)  FORCE_CONFIG=1; shift ;;
        --no-hook)       NO_HOOK=1; shift ;;
        --unattended)    UNATTENDED=1; shift ;;
        -h|--help)
            sed -n '2,15p' "$0"
            exit 0
            ;;
        *)               echo "未知参数：$1"; exit 1 ;;
    esac
done

# ============== 工具函数 ==============
banner() {
    printf '\n=== mingdao-worklog-api 一键安装 (Unix) ===\n'
    printf 'Repo  : %s\n' "$REPO_URL"
    printf 'Target: %s\n' "$TARGET_DIR"
    printf '\n'
}
step() { printf '\n[%d/%d] %s\n' "$1" "$2" "$3"; }
ok()   { printf '  \033[32m✓\033[0m %s\n' "$1"; }
warn() { printf '  \033[33m⚠\033[0m %s\n' "$1"; }
err()  { printf '  \033[31m✗\033[0m %s\n' "$1"; }

PY=""
detect_python() {
    for cand in python3 python; do
        if command -v "$cand" >/dev/null 2>&1; then
            local v
            v=$("$cand" -c 'import sys; print(sys.version_info.major, sys.version_info.minor)')
            if [[ "$v" =~ ^[3-9]\.[0-9]+ ]]; then
                PY="$cand"
                return 0
            fi
        fi
    done
    return 1
}

# ============== 0. 横幅 ==============
banner

TOTAL_STEPS=8

# ============== 1. 工具检测 ==============
step 1 "$TOTAL_STEPS" "检测 python / git"
if ! detect_python; then
    err "未检测到 python3，请先安装（brew install python 或 apt install python3）"
    exit 1
fi
ok "Python: $PY ($($PY --version))"
if ! command -v git >/dev/null 2>&1; then
    warn "未检测到 git，若 LocalSource 为空且目标不存在会失败"
else
    ok "git: $(git --version | head -c 30)"
fi

# ============== 2. 凭证 ==============
step 2 "$TOTAL_STEPS" "获取明道云 appKey + secretKey"
APPKEY="${MINGDAO_APPKEY:-}"
SECRETKEY="${MINGDAO_SECRETKEY:-}"
if [[ "$UNATTENDED" -eq 0 ]]; then
    if [[ -z "$APPKEY" ]]; then
        printf '  在「明道云 → 应用 → 应用授权」获取 appKey + secretKey\n'
        printf '  appKey: '
        read -r APPKEY
    fi
    if [[ -z "$SECRETKEY" ]]; then
        printf '  secretKey (不回显): '
        read -rs SECRETKEY
        printf '\n'
    fi
fi
if [[ -z "$APPKEY" || -z "$SECRETKEY" ]]; then
    err "缺少 appKey 或 secretKey（可设环境变量 MINGDAO_APPKEY / MINGDAO_SECRETKEY 重试）"
    exit 1
fi
ok "appKey / secretKey 已接收（不回显）"

# ============== 3. 拉取源文件 ==============
step 3 "$TOTAL_STEPS" "拉取 skill 源文件"
if [[ -n "$LOCAL_SOURCE" ]]; then
    if [[ ! -d "$LOCAL_SOURCE" ]]; then err "LocalSource 不存在：$LOCAL_SOURCE"; exit 1; fi
    if [[ -d "$TARGET_DIR" ]]; then
        warn "$TARGET_DIR 已存在，跳过拷贝"
    else
        mkdir -p "$TARGET_DIR"
        cp -R "$LOCAL_SOURCE"/. "$TARGET_DIR"/
        ok "已从 $LOCAL_SOURCE 拷贝到 $TARGET_DIR"
    fi
else
    if [[ -d "$TARGET_DIR/.git" || -f "$TARGET_DIR/SKILL.md" ]]; then
        ok "$TARGET_DIR 已存在，跳过 clone"
    else
        mkdir -p "$(dirname "$TARGET_DIR")"
        warn "git clone $REPO_URL ..."
        git clone --depth 1 --branch "$BRANCH" "$REPO_URL" "$TARGET_DIR"
    fi
fi
if [[ ! -f "$TARGET_DIR/scripts/worklog_api.py" ]]; then
    err "源目录缺 scripts/worklog_api.py，仓库结构异常"
    exit 1
fi
ok "skill 源文件已就位"

# ============== 4. config.json ==============
step 4 "$TOTAL_STEPS" "写入 config.json"
CFG="$TARGET_DIR/config.json"
EXAMPLE="$TARGET_DIR/config.example.json"
if [[ -f "$CFG" && "$FORCE_CONFIG" -eq 0 ]]; then
    warn "$CFG 已存在，未覆盖（用 --force-config 强制覆盖）"
else
    [[ -f "$EXAMPLE" ]] || { err "config.example.json 不存在"; exit 1; }
    APPKEY="$APPKEY" SECRETKEY="$SECRETKEY" EXAMPLE="$EXAMPLE" CFG="$CFG" "$PY" - <<'PYEOF'
import json, os
cfg = json.load(open(os.environ["EXAMPLE"], encoding="utf-8"))
cfg["appKey"]    = os.environ["APPKEY"]
cfg["secretKey"] = os.environ["SECRETKEY"]
import sys
sys.stderr.write("[ok] credentials injected\n")
with open(os.environ["CFG"], "w", encoding="utf-8") as f:
    json.dump(cfg, f, indent=2, ensure_ascii=False)
PYEOF
    ok "已写入 $CFG"
fi

# ============== 5. symlink ==============
step 5 "$TOTAL_STEPS" "创建 agent 工具 symlink"
declare -A LINKS=(
    ["$HOME/.claude/skills/mingdao-worklog-api"]="Claude Code"
    ["$HOME/.codex/skills/mingdao-worklog-api"]="OpenAI Codex"
    ["$HOME/.agents/skills/mingdao-worklog-api"]="通用（OpenCode/ZCode/Antigravity）"
    ["$HOME/.config/opencode/skills/mingdao-worklog-api"]="OpenCode 专用"
    ["$HOME/.gemini/config/skills/mingdao-worklog-api"]="Antigravity 专用"
)
for link in "${!LINKS[@]}"; do
    parent="$(dirname "$link")"
    tool="${LINKS[$link]}"
    [[ -d "$parent" ]] || continue
    if [[ -e "$link" || -L "$link" ]]; then
        ok "已存在 → $tool"
        continue
    fi
    if ln -s "$TARGET_DIR" "$link" 2>/dev/null; then
        ok "创建 → $tool  ($link)"
    else
        warn "创建失败 ($tool)：$link"
    fi
done

# ============== 6. AGENTS.md 声明 ==============
step 6 "$TOTAL_STEPS" "写入 AGENTS.md / CLAUDE.md 声明"
FRAG="$TARGET_DIR/installer/AGENTS.fragment.md"
if [[ ! -f "$FRAG" ]]; then
    warn "未找到 $FRAG，跳过声明"
else
    FRAG_BODY="$(cat "$FRAG")"
    # ~/.claude/CLAUDE.md（追加在 CODEGRAPH 块后）
    if [[ -f "$HOME/.claude/CLAUDE.md" ]]; then
        if grep -q "WORKLOG_MINGDAO_BEGIN" "$HOME/.claude/CLAUDE.md"; then
            warn "已声明，跳过 → $HOME/.claude/CLAUDE.md"
        else
            if grep -q "<!-- CODEGRAPH_END -->" "$HOME/.claude/CLAUDE.md"; then
                "$PY" - <<PYEOF
from pathlib import Path
p = Path("$HOME/.claude/CLAUDE.md")
t = p.read_text(encoding="utf-8")
marker = "<!-- CODEGRAPH_END -->"
body = """$(cat "$FRAG")"""
t = t.replace(marker, marker + "\n\n" + body, 1)
p.write_text(t, encoding="utf-8")
PYEOF
                ok "追加 → $HOME/.claude/CLAUDE.md"
            else
                printf '\n\n%s' "$FRAG_BODY" >> "$HOME/.claude/CLAUDE.md"
                ok "追加（尾部） → $HOME/.claude/CLAUDE.md"
            fi
        fi
    fi
    # ~/.codex/AGENTS.md
    if [[ -f "$HOME/.codex/AGENTS.md" ]]; then
        if grep -q "WORKLOG_MINGDAO_BEGIN" "$HOME/.codex/AGENTS.md" 2>/dev/null; then
            warn "已声明，跳过 → $HOME/.codex/AGENTS.md"
        else
            printf '\n\n%s' "$FRAG_BODY" >> "$HOME/.codex/AGENTS.md"
            ok "追加 → $HOME/.codex/AGENTS.md"
        fi
    fi
    # ~/.agents/AGENTS.md（新建或追加）
    if [[ -d "$(dirname "$HOME/.agents/AGENTS.md")" ]]; then
        AGENTS="$HOME/.agents/AGENTS.md"
        if [[ -f "$AGENTS" ]] && grep -q "WORKLOG_MINGDAO_BEGIN" "$AGENTS"; then
            warn "已声明，跳过 → $AGENTS"
        else
            if [[ -f "$AGENTS" ]]; then
                printf '\n\n%s' "$FRAG_BODY" >> "$AGENTS"
            else
                printf '%s' "$FRAG_BODY" > "$AGENTS"
            fi
            ok "写入 → $AGENTS"
        fi
    fi
fi

# ============== 7. commit-msg hook ==============
step 7 "$TOTAL_STEPS" "安装 commit-msg hook (可选)"
INSTALL_HOOK=0
if [[ "$NO_HOOK" -eq 1 ]]; then
    warn "--no-hook，跳过"
elif [[ "$UNATTENDED" -eq 1 ]]; then
    if [[ -z "${WORKLOG_NO_HOOK:-}" ]]; then INSTALL_HOOK=1; fi
else
    printf '  是否安装 git commit-msg hook？(Y/n) '
    read -r ans
    case "$ans" in
        ""|y|Y|yes|YES) INSTALL_HOOK=1 ;;
        *) ;;
    esac
fi
if [[ "$INSTALL_HOOK" -eq 1 ]]; then
    SRC="$TARGET_DIR/installer/hooks/commit-msg"
    DIR="$HOME/.git_hooks"
    DST="$DIR/commit-msg"
    [[ -f "$SRC" ]] || { err "hook 源缺失：$SRC"; exit 1; }
    mkdir -p "$DIR"
    cp "$SRC" "$DST"
    chmod +x "$DST"
    ok "hook 已复制到 $DST"
    git config --global core.hooksPath "$DIR" && ok "git config --global core.hooksPath 已设" \
        || warn "git config 设置失败，可手动执行：git config --global core.hooksPath '$DIR'"
fi

# ============== 8. test-auth ==============
step 8 "$TOTAL_STEPS" "运行 test-auth 验证"
cd "$TARGET_DIR"
if OUTPUT=$("$PY" scripts/worklog_api.py --config config.json test-auth 2>&1); then
    if echo "$OUTPUT" | grep -Eq '"ok":\s*true|worksheet_name'; then
        ok "test-auth 通过！"
    else
        warn "test-auth 返回异常（凭证可能未生效或网络问题）："
        echo "$OUTPUT"
    fi
else
    warn "test-auth 失败："
    echo "$OUTPUT"
fi

# ============== 完成 ==============
printf '\n\033[32m=========================================\n'
printf '  mingdao-worklog-api 安装完成\n'
printf '=========================================\033[0m\n\n'
printf '接下来可以：\n'
printf '  1. 在 agent 工具里说 "帮我写条工作日志"\n'
printf '  2. git commit -m "修复XX #log 项目:你的项目 #time=2h" 自动写日志\n'
printf '  3. 想卸载：运行 uninstall.sh\n\n'
