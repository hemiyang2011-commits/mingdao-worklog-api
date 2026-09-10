#!/usr/bin/env bash
# mingdao-worklog-api 一键卸载 (macOS / Linux)
#
# 用法：
#   curl -fsSL https://raw.githubusercontent.com/hemiyang2011-commits/mingdao-worklog-api/main/installer/uninstall.sh | bash
#
# 开关：
#   --remove-config   删除 config.json（默认保留）
#   --remove-dir      删除整个 skill 目录
#   --restore-hooks   恢复 git core.hooksPath
#   --unattended      全自动按 default-yes
#   --no-confirm      全自动按 default-no
#
set -euo pipefail

SKILL_NAME="mingdao-worklog-api"
TARGET_DIR="$HOME/.workbuddy/skills/$SKILL_NAME"
REMOVE_CONFIG=0
REMOVE_DIR=0
RESTORE_HOOKS=0
UNATTENDED=0
NO_CONFIRM=0

PY_BIN=""
for cand in python3 python; do
    if command -v "$cand" >/dev/null 2>&1; then
        PY_BIN="$cand"
        break
    fi
done
[[ -z "$PY_BIN" ]] && { echo "需要 python3"; exit 1; }

while [[ $# -gt 0 ]]; do
    case "$1" in
        --remove-config) REMOVE_CONFIG=1; shift ;;
        --remove-dir)    REMOVE_DIR=1; shift ;;
        --restore-hooks) RESTORE_HOOKS=1; shift ;;
        --unattended)    UNATTENDED=1; shift ;;
        --no-confirm)    NO_CONFIRM=1; shift ;;
        *)               echo "未知参数：$1"; exit 1 ;;
    esac
done

yes() {
    if   [[ "$UNATTENDED" -eq 1 ]]; then return 0
    elif [[ "$NO_CONFIRM" -eq 1 ]]; then return 1
    fi
    local prompt="$1"
    local ans
    read -rp "  $prompt (Y/n) " ans
    [[ -z "$ans" || "$ans" =~ ^[Yy] ]]
}

printf '\n=== mingdao-worklog-api 一键卸载 (Unix) ===\n'
printf 'Target: %s\n\n' "$TARGET_DIR"

# 1. symlink
printf '\033[36m[1/5] 移除 symlink\033[0m\n'
for link in \
    "$HOME/.claude/skills/$SKILL_NAME" \
    "$HOME/.codex/skills/$SKILL_NAME" \
    "$HOME/.agents/skills/$SKILL_NAME" \
    "$HOME/.config/opencode/skills/$SKILL_NAME" \
    "$HOME/.gemini/config/skills/$SKILL_NAME"; do
    if [[ -L "$link" ]]; then
        rm "$link" && printf '  \033[32m✓\033[0m %s\n' "$link"
    elif [[ -e "$link" ]]; then
        printf '  \033[33m⚠\033[0m %s 存在但不是 symlink，跳过\n' "$link"
    else
        printf '  - %s (不存在)\n' "$link"
    fi
done

# 2. AGENTS 声明
printf '\n\033[36m[2/5] 移除 AGENTS 声明\033[0m\n'
# 使用 perl 多行删除，比 sed 跨平台兼容
for f in "$HOME/.claude/CLAUDE.md" "$HOME/.codex/AGENTS.md" "$HOME/.agents/AGENTS.md"; do
    if [[ ! -f "$f" ]]; then printf '  - %s (不存在)\n' "$f"; continue; fi
    if ! grep -q "WORKLOG_MINGDAO_BEGIN" "$f"; then printf '  - %s (无声明)\n' "$f"; continue; fi
    # 删除 WORKLOG_MINGDAO_BEGIN..WORKLOG_MINGDAO_END（含前后空行）
    "$PY_BIN" - "$f" <<'PYEOF' 2>/dev/null
import re, sys, pathlib
p = pathlib.Path(sys.argv[1])
t = p.read_text(encoding="utf-8")
new = re.sub(r"\n*<!--\s*WORKLOG_MINGDAO_BEGIN\s*-->.*?<!--\s*WORKLOG_MINGDAO_END\s*-->\n*",
             "\n", t, count=1, flags=re.DOTALL)
if new != t: p.write_text(new, encoding="utf-8"); print("  ✓", sys.argv[1])
PYEOF
done

# 3. hook
printf '\n\033[36m[3/5] 移除 commit-msg hook\033[0m\n'
HOOK="$HOME/.git_hooks/commit-msg"
if [[ -f "$HOOK" ]]; then
    if head -5 "$HOOK" | grep -q "worklog-hook"; then
        rm -f "$HOOK"
        printf '  \033[32m✓\033[0m %s\n' "$HOOK"
    else
        printf '  \033[33m⚠\033[0m %s 不是本 skill 的 hook\n' "$HOOK"
    fi
else
    printf '  - %s (不存在)\n' "$HOOK"
fi

# 4. 恢复 hooksPath
printf '\n\033[36m[4/5] 恢复 git core.hooksPath\033[0m\n'
CUR="$(git config --global core.hooksPath 2>/dev/null || true)"
if [[ "$CUR" == "$HOME/.git_hooks" ]]; then
    if [[ "$RESTORE_HOOKS" -eq 1 ]] || yes "  当前 core.hooksPath 指向本 skill 目录，要 unset 吗"; then
        git config --global --unset core.hooksPath && printf '  \033[32m✓\033[0m 已 unset core.hooksPath\n'
    else
        printf '  - 保留\n'
    fi
elif [[ -n "$CUR" ]]; then
    printf '  - 指向别处（%s），不动\n' "$CUR"
else
    printf '  - 未设置\n'
fi

# 5. config / dir
printf '\n\033[36m[5/5] 删除 config.json / skill 目录\033[0m\n'
CFG="$TARGET_DIR/config.json"
if [[ -f "$CFG" ]]; then
    if [[ "$REMOVE_CONFIG" -eq 1 ]] || yes "  删除 $CFG (含凭证)?"; then
        rm -f "$CFG" && printf '  \033[32m✓\033[0m 已删除 %s\n' "$CFG"
    else
        printf '  - 保留\n'
    fi
fi
if [[ -d "$TARGET_DIR" ]]; then
    if [[ "$REMOVE_DIR" -eq 1 ]] || yes "  删除整个 skill 目录 $TARGET_DIR ?"; then
        rm -rf "$TARGET_DIR" && printf '  \033[32m✓\033[0m 已删除\n'
    else
        printf '  - 保留\n'
    fi
fi

printf '\n\033[32m=== 卸载完成 ===\033[0m\n'
printf '想重装：curl -fsSL .../installer/install.sh | bash\n\n'
