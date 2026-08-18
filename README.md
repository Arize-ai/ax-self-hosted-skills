# Arize AX Self-hosted Skills

Agent Skills that guide AI coding agents in operating and troubleshooting **self-hosted Arize AX**.

Works with Cursor, Claude Code, Codex, GitHub Copilot, Windsurf, and [40+ other agents](https://github.com/vercel-labs/skills#supported-agents).

### Option 1: npx (recommended)

Install all skills non-interactively — this is what the agent runs for the prompt above:

```bash
npx skills add Arize-ai/ax-self-hosted-skills --skill "*" --yes
```

Want to hand-pick skills, agent, and scope yourself? Drop the flags for the interactive wizard:

```bash
npx skills add Arize-ai/ax-self-hosted-skills
```

Both auto-detect your agent (Cursor, Claude Code, Codex, etc.) and symlink skills into place.

### Option 2: git clone

**macOS / Linux:**
```bash
git clone https://github.com/Arize-ai/ax-self-hosted-skills.git
cd ax-self-hosted-skills
./install.sh --project ~/my-project
```

**Windows (PowerShell):**
```powershell
git clone https://github.com/Arize-ai/ax-self-hosted-skills.git
cd ax-self-hosted-skills
.\install.ps1 -Project ~\my-project
```

The installer only symlinks (or copies) skills into your agent's skills directory. It does **not** install Arize AX or the `ax` CLI. Use `--global` / `-Global` instead to install to `~/.<agent>/skills/`.

## Prerequisites

Required on the machine where the agent runs the skill scripts:

| Tool | Why |
|---|---|
| `kubectl` | Read-only cluster access (`get`, `describe`, `logs`, `port-forward`, …) |
| `curl` | HTTP GETs against Prometheus / Alertmanager |
| `jq` | JSON parsing in the shell helpers |
| `python3` | `catalog-lookup.py`, `docs-search.py`, `distribution.py` |

Also required for a useful investigation session:

- `kubectl` context pointed at the self-hosted Arize cluster
- An **unpacked Arize distribution** that matches the cluster release (contains `arize.sh` and `docs/`)
- Network reachability to Prometheus / Alertmanager (ingress URL or local port-forward)

## Environment variables

Set these in the shell before (or while) running the skill:

| Variable | Required | Purpose |
|---|---|---|
| `ARIZE_DISTRIBUTION_ROOT` | **Yes** (or pass `--distribution-root`) | Path to the unpacked distribution for this cluster. Alias: `ARIZE_DIST`. Must contain `arize.sh` and `docs/troubleshooting/selfhosted-alerts-table.csv`. |
| `ARIZE_NAMESPACE` | Recommended | Application namespace where Prometheus / Alertmanager run (used by `open-ports.sh`) |
| `OPERATOR_NS` | Optional | Operator namespace for version checks (default: `arize-operator`) |
| `PROM` / `PROM_URL` | When querying Prometheus | Prometheus base URL, e.g. `http://localhost:9090/prometheus` |
| `AM` / `AM_URL` | When querying Alertmanager | Alertmanager base URL, e.g. `http://localhost:9093/alertmanager` |
| `ARIZE_SKILL_TMP` | Optional | Scratch dir for PID files / JSON dumps (default: `/tmp/arize-alerts-troubleshoot`) |
| `CURL_INSECURE` | Optional | Set to `1` to force `curl -k` for non-localhost HTTPS (or pass `--insecure`) |

Example:

```bash
export ARIZE_DISTRIBUTION_ROOT="/path/to/unpacked/arize-distribution"
export ARIZE_NAMESPACE="arize"
export OPERATOR_NS="arize-operator"
export PROM="http://localhost:9090/prometheus"
export AM="http://localhost:9093/alertmanager"
```

## Available Skills

| Skill | Path | Purpose |
|---|---|---|
| `arize-alerts-troubleshoot` | [`skills/arize-alerts-troubleshoot/`](skills/arize-alerts-troubleshoot/) | Diagnose firing self-hosted alerts using read-only kubectl / Prometheus / Alertmanager access and the local distribution docs |

Each skill lives under `skills/<name>/` with a `SKILL.md` entrypoint, optional
`references/`, and helper `scripts/`.
