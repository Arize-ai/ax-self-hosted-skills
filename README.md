# Arize AX Self-hosted Skills

Agent Skills that guide AI coding agents in installing, operating, and troubleshooting **self-hosted Arize AX**.

Works with Cursor, Claude Code, Codex, GitHub Copilot, Windsurf, and [40+ other agents](https://github.com/vercel-labs/skills#supported-agents).

## Self-Hosted Skills Quick Start

Install Arize AX on your own Kubernetes cluster - give your coding agent this prompt:

> Install Arize self-hosted skills from https://github.com/Arize-ai/ax-self-hosted-skills and use the arize-self-hosted-install skill to guide me through installing Arize AX on my cluster.

Or, after installing the skills, launch it directly in Claude Code:

```bash
claude "/arize-self-hosted-install"
```

Troubleshoot an existing Arize self-hosted deployment - give your coding agent this prompt:

> Install Arize self-hosted skills from https://github.com/Arize-ai/ax-self-hosted-skills and use the arize-alerts-troubleshoot skill to diagnose the alerts currently firing on my cluster. 


## Installation

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

## Installation skill

`arize-self-hosted-install` walks a first-time customer through an Arize AX
self-hosted install, one confirmed step at a time:

1. Select an existing unpacked distribution, or download the latest (or a
   specific) release using an Arize-issued JWT.
2. Choose the documented platform path (AWS, GCP, Azure, IBM, OpenShift,
   Rancher/bare metal, single host). For AWS, GCP, and Azure it can help
   prepare a `main.tf` from the bundled Terraform modules, but it never runs
   Terraform or cloud provisioning.
3. Confirm the exact Kubernetes context before contacting the cluster.
4. Build `values.yaml`, with secrets kept out of chat and out of the agent's
   view (see below).
5. Run `./arize.sh install` only after you approve the target and command,
   while monitoring the operator, pre-check, and pre-upgrade logs.
6. Validate workloads, ingress, HTTP and gRPC trace ingestion, and firing
   Prometheus alerts, handing off to `arize-alerts-troubleshoot` if any fire.

### Secret handling

When building `values.yaml`, the agent asks you to choose one of two options:

- **Super secret (recommended when the agent must not see secrets).** The
  agent gives you a script to run yourself. It creates the `arize` and
  `arize-operator` namespaces, a Secret holding the JWT, Postgres password,
  generated cipher key, and any cloud storage credential, and the
  `hub-json-key` registry pull secret in both namespaces. `values.yaml` then
  contains only `secretCreation`, `createNamespaces: false`, and
  `customPullSecret`, with no secret values.
- **Placeholders.** The agent writes `values.yaml` with placeholders and gives
  you the commands to generate each base64 value. You fill them in locally; the
  agent then checks only for leftover placeholder tokens.

The agent never prints the JWT, never reads Kubernetes Secret objects, and
never opens `values.yaml` after it contains secrets.

### Prerequisites

- `curl`, `kubectl`, Helm 3, `openssl`, `tar`, and Docker (for image
  verification or mirroring), plus your cloud CLI for kubeconfig access.
- An Arize-issued JWT exported as `JWT` in the agent's shell before any
  download. The agent checks only that it is set.
- Infrastructure that meets the platform prerequisites (cluster, node
  capacity for your Arize-approved `clusterSizing`, storage classes, and
  object storage buckets).

Direct `kubectl` calls go through the skill's
[`safe-kubectl.sh`](skills/arize-self-hosted-install/scripts/safe-kubectl.sh),
which requires an explicit confirmed `KUBE_CONTEXT`, binds port-forwards to
localhost, and rejects `delete`, other mutations, and Secret reads. Cluster
changes come only from the release's `arize.sh` and Helm, after your approval.

## Troubleshooting skill

### Prerequisites

Required on the machine where the agent runs the skill scripts:

| Tool | Why |
|---|---|
| `kubectl` | Read-only cluster access via `safe-kubectl.sh` (`get`, `describe`, `logs`, `port-forward`, …) |
| `curl` | HTTP GETs against Prometheus / Alertmanager |
| `jq` | JSON parsing in the shell helpers |
| `python3` | `catalog-lookup.py`, `docs-search.py`, `distribution.py` |
| `tar` | Read `Chart.yaml` from `arize-operator-chart.tgz` during version check |

Also required for a useful investigation session:

- `kubectl` context pointed at the self-hosted Arize cluster
- An **unpacked Arize distribution** that matches the cluster release (contains `arize.sh` and `docs/`)
- Network reachability to Prometheus / Alertmanager (ingress URL or local port-forward)

### Environment variables

Set these in the shell before (or while) running the skill:

| Variable | Required | Purpose |
|---|---|---|
| `ARIZE_DISTRIBUTION_ROOT` | **Yes** (or pass `--distribution-root`) | Path to the unpacked distribution for this cluster. Alias: `ARIZE_DIST`. Must contain `arize.sh` and `docs/troubleshooting/selfhosted-alerts-table.csv`. |
| `ARIZE_NAMESPACE` | Recommended | Application namespace where Prometheus / Alertmanager run (used by `open-ports.sh`) |
| `OPERATOR_NS` | Optional | Operator namespace for version checks (default: `arize-operator`) |
| `KUBE_CONTEXT` | Optional | kube context for `safe-kubectl.sh` / `preflight.sh` if not current-context |
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
| `arize-self-hosted-install` | [`skills/arize-self-hosted-install/`](skills/arize-self-hosted-install/) | Guide a first-time install: select or download a distribution, prepare `values.yaml`, run `arize.sh`, and validate the deployment, without provisioning infrastructure |
| `arize-docs-validator` | [`skills/arize-docs-validator/`](skills/arize-docs-validator/) | Check self-hosting docs (source or live site) for broken images, broken links, and missing diagrams |

Each skill lives under `skills/<name>/` with a `SKILL.md` entrypoint, optional
`references/`, and helper `scripts/`.
