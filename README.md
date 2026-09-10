# mingdao-worklog-api

> 在任意 agent 工具（Claude Code / OpenAI Codex / OpenCode / ZCode / Google Antigravity）里说一句"帮我写条工作日志"，自动写入你的明道云工作日志表。

本仓库封装了一份**直接调用明道云开放 API** 的 skill，**不依赖 `hap` CLI 登录**，也不要求登录明道云网页。

适用场景：开发者在工作流里频繁要写工作日志，嫌手动到明道云系统维护烦。

---

## ⚙️ 前置条件

> 安装脚本会自动检测并安装缺失依赖，**正常情况下你什么都不用装**。只有离线/受限环境才需要手动装。

| 依赖 | 最低版本 | 作用 | 装法 |
|---|---|---|---|
| **Python** | 3.8+ | 跑 `worklog_api.py` + `commit-msg` hook | 安装脚本自动装；离线时见下表 |
| **Git** | 任意 | 拉源 + commit-msg hook | Windows 装 [Git for Windows](https://git-scm.com) |
| **明道云 appKey + secretKey** | — | 调 API 用 | 在「明道云 → 应用 → 应用授权」获取 |

### 手动装 Python（仅当自动装失败时）

**推荐用 `uv`**（Astral 出品，~13MB 单 exe，跨平台一致，装好后 5 秒内可用）：

| 平台 | 一行命令 |
|---|---|
| **Windows** | `irm https://astral.sh/uv/install.ps1 \| iex` |
| **macOS** | `curl -LsSf https://astral.sh/uv/install.sh \| sh` |
| **Linux** | `curl -LsSf https://astral.sh/uv/install.sh \| sh` |

装完后 `uv run python --version` 验证；之后 hook / install 脚本会自动用 `uv run` 跑 Python 脚本。

**或者装完整 Python**：

| 平台 | 装法 |
|---|---|
| Windows | `winget install Python.Python.3.12` 或从 [python.org](https://www.python.org/downloads/) 下载 |
| macOS | `brew install python3` |
| Ubuntu / Debian | `sudo apt install python3` |
| CentOS / RHEL | `sudo yum install python3` |
| Arch | `sudo pacman -S python` |

---

## ✨ 核心特性

- **一行命令安装到任何 agent 工具**：Claude Code / Codex / OpenCode / ZCode / Antigravity 全部支持
- **AGENTS.md 声明方式触发**：agent 启动时读 SKILL.md 描述，判断该不该调
- **可选 commit-msg hook**：`git commit -m "fix #log 项目:资产OA #time=2h"` 自动写工作日志
- **老板本/员工本共享一份源**：通过 junction / symlink 链接，凭证只填一次
- **跨平台**：Windows PowerShell + macOS/Linux Bash
- **ownerid/caid 自动联动**：写工作日志时，拥有者字段自动从员工档案取 HAP accountId，创建人同步

---

## 🚀 一行安装

### Windows (PowerShell)

```powershell
irm https://raw.githubusercontent.com/hemiyang2011-commits/mingdao-worklog-api/main/installer/install.ps1 | iex
```

回车后会提示：

```
[2/8] 获取明道云 appKey + secretKey
  在「明道云 → 应用 → 应用授权」获取 appKey + secretKey
  appKey: 4989bba1409c354e
  secretKey (不回显): ********
```

### macOS / Linux

```bash
curl -fsSL https://raw.githubusercontent.com/hemiyang2011-commits/mingdao-worklog-api/main/installer/install.sh | bash
```

### 跳过交互（CI / 离线）

```bash
# bash
REPO_URL=https://github.com/hemiyang2011-commits/mingdao-worklog-api.git \
MINGDAO_APPKEY=xxx \
MINGDAO_SECRETKEY=yyy \
    curl -fsSL .../install.sh | bash

# PowerShell
$env:REPO_URL="https://github.com/hemiyang2011-commits/mingdao-worklog-api.git"
$env:MINGDAO_APPKEY="xxx"
$env:MINGDAO_SECRETKEY="yyy"
irm .../install.ps1 | iex
```

---

## 📦 安装脚本会做什么

| 步骤 | 行为 |
|---|---|
| 1 | 检测 `python3` / `git` 是否安装 |
| 2 | 询问 / 接收 appKey + secretKey（不回显） |
| 3 | git clone 到 `~/.workbuddy/skills/mingdao-worklog-api/`（已存在则 pull） |
| 4 | 写入 `config.json`（从 example + 凭证） |
| 5 | 在 5 个 agent 工具目录建 junction / symlink（探测式，仅对存在的工具生效） |
| 6 | 写入 `~/.claude/CLAUDE.md` / `~/.codex/AGENTS.md` / `~/.agents/AGENTS.md` 三份声明（追加在已有内容尾部） |
| 7 | 询问是否安装 git `commit-msg` hook（默认 Y） |
| 8 | 跑 `test-auth` 验证链路通 |

> ⚠️ 安装脚本是**幂等的**——重复跑会跳过已完成步骤，更新 hook / config 时需加 `--force-config` 才会覆盖。

---

## 🎯 触发机制（重点）

我们提供**双保险**：

### 1. AGENTS.md 声明（默认开启）

agent 工具启动时会读自己的 `CLAUDE.md` / `AGENTS.md`，里面有关于「工作日志」声明：

> **触发场景**：用户说"写条工作日志" / 完成业务工作后 / commit 前
> **默认行为**：agent 主动问"要不要写条日志"，用户说"写" → 调 skill

**好处**：用户**完全控制权**，不会被静默写日志。

### 2. git commit-msg hook（可选安装）

如果第 7 步选了 Y，会装一个 commit-msg hook：

```bash
git commit -m "修复XX bug #log 项目:资产OA #time=2h"
```

| tag | 含义 |
|---|---|
| `#log` | 触发写工作日志（必填） |
| `#time=Nh` 或 `工时:Nh` | 工时数字（必填，缺则跳过不阻断 commit） |
| `项目:XXX` | 项目名（必填，会模糊匹配） |
| `[skip-worklog]` | 跳过本次 commit 的工作日志 |
| `--no-verify` | git 自带机制跳过所有 hook |

第一个 commit message 行去掉 tags 后作为「工作内容」。

**跳过方法**：

```bash
git commit -m "docs: README排版 #log #time=1h [skip-worklog]"
# 或
git commit --no-verify -m "重构"
```

---

## 🛠 日常使用

### 在 agent 里说一句话

> "帮我写条工作日志：资产OA 系统 开发 1 小时"

agent 自动：
1. 项目按"资产OA 系统"模糊匹配
2. 员工走 config 默认（如杨浪）
3. owner 自动从员工档案取 = 你自己的 HAP accountId
4. 时段默认"全天"
5. 调 `add-row` → 拿回新 rowid → 报给你

### 命令行直接写（不进 agent）

```bash
python ~/.workbuddy/skills/mingdao-worklog-api/scripts/worklog_api.py \
    --config ~/.workbuddy/skills/mingdao-worklog-api/config.json \
    add-row \
    --date 2026-09-10 \
    --project-name "资产OA 系统" \
    --content "修复登录 bug" \
    --hours 2
```

### 替别人写

```bash
python ... add-row \
    --employee-name "陈剑灵" \
    --project-name "三农二期" \
    --content "..." --hours 3
```

---

## 📂 仓库结构

```
mingdao-worklog-api/
├── README.md
├── LICENSE                          MIT
├── .gitignore                       排除 config.json / __pycache__
├── SKILL.md                         agent 启动时读的 skill 描述（YAML frontmatter + Markdown）
├── scripts/
│   ├── worklog_api.py               主脚本（list-projects / list-employees / add-row / test-auth / sign）
│   └── match_project.py             模糊匹配项目名 / 员工名
├── references/
│   └── api_reference.md             API 字段 ID 速查（按本应用定制）
├── config.example.json              公开模板（**不含凭证**，可放心 commit）
└── installer/
    ├── install.ps1                  Windows 一键安装
    ├── install.sh                   macOS / Linux 一键安装
    ├── uninstall.ps1                Windows 一键卸载
    ├── uninstall.sh                 macOS / Linux 一键卸载
    ├── AGENTS.fragment.md           AGENTS.md 声明片段模板（被 install 脚本读取并 append 到用户配置）
    └── hooks/
        └── commit-msg               git commit-msg hook 脚本
```

---

## 🔧 配置 `config.json`

复制 `config.example.json` 为 `config.json`，最少填两项：

```json
{
  "appKey":    "你的明道云 AppKey",
  "secretKey": "你的明道云 SecretKey（直接当 sign 用，无需计算签名）"
}
```

**注意**：`config.json` 已被 `.gitignore` 排除，**绝不**入库。

### 可选字段

| 字段 | 默认行为 |
|---|---|
| `default_employee_name` | 不传员工参数时按这个名字自动模糊匹配。空则每次必传。 |
| `default_employee_rowid` | 比 `default_employee_name` 优先；找到 rowid 直接用，不走匹配。 |
| `default_owner_account_id` | 不传 `--owner-account-id` 时用这个；缺省自动从员工档案取。 |

---

## 🧹 卸载

```powershell
# Windows
irm .../installer/uninstall.ps1 | iex

# 默认保留 config.json（含凭证） + skill 目录（避免误删）
# 加 -RemoveConfig -RemoveDir 强制删
```

```bash
# macOS / Linux
curl -fsSL .../installer/uninstall.sh | bash
# 或：./installer/uninstall.sh --remove-config --remove-dir
```

---

## ❓ 疑难排查

| 现象 | 排查 |
|---|---|
| 安装完 `test-auth` 返回 `ok: true` 但 add-row `10005 数据操作无权限` | 你还没授权这个应用的 API 访问全部视图（在明道云后台 → 应用 → API 开发 → 授权 / 数据权限里勾上「获取行记录列表」） |
| `agent 没主动问我要不要写日志` | AGENTS.md 声明没被写到。看 `~/.claude/CLAUDE.md` 末尾是否含 `WORKLOG_MINGDAO_BEGIN` 块 |
| `commit 没自动写日志，但 commit 没报错` | 可能选了 `--no-verify` 或 commit message 没 `#log` tag |
| `agent 写出来了但内容错了` | 项目名模糊匹配有多个候选。看 stderr `score=xx reason=...` 选对的 |

---

## 🔒 安全

- `config.json`（含凭证）**不入 git**，已写进 `.gitignore`
- 安装脚本读取输入时不回显 secretKey
- `commit-msg` hook 不会把凭证写到 commit message
- 仓库公开，但凭证是**每个用户自己填**的；fork 后也不会继承他人的凭证

---

## 📜 License

MIT — see [LICENSE](LICENSE)
