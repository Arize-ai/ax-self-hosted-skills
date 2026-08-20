# Reaching cluster APIs

Parameterized by **kube context + namespace + local HTTP URLs**.

Ad-hoc cluster reads **must** go through `$SKILL_ROOT/scripts/safe-kubectl.sh`
(allowlisted verbs, `-n` / `-A` required except cluster-scoped). Prefer
`open-ports.sh` for Prometheus/Alertmanager tunnels.

## Discover services

```bash
"$SKILL_ROOT/scripts/safe-kubectl.sh" --context <context> -n <namespace> get svc prometheus alertmanager
"$SKILL_ROOT/scripts/safe-kubectl.sh" --context <context> -n <namespace> get pods -l 'app in (prometheus,alertmanager)'
```

Typical Services in the **application** namespace:

| Service | Port | Env after forward |
|---|---|---|
| `prometheus` | 9090 | `PROM=http://localhost:9090/prometheus` |
| `alertmanager` | 9093 | `AM=http://localhost:9093/alertmanager` |

### Subpaths (important)

On-prem Prometheus and Alertmanager usually serve their HTTP APIs under
**`/prometheus`** and **`/alertmanager`**. A bare `http://localhost:9090/` often
returns a redirect (`Found` → `/prometheus`) or `404 page not found` for
`/api/v1/...`.

Always include the subpath in `--url` / `$PROM` / `$AM`, or let the helper
scripts auto-detect it:

```bash
export PROM="http://localhost:9090/prometheus"
export AM="http://localhost:9093/alertmanager"

# Probe (expect HTTP 200 + JSON):
curl -s -o /dev/null -w "%{http_code}\n" "$PROM/api/v1/query?query=up"
curl -s -o /dev/null -w "%{http_code}\n" "$AM/api/v2/status"
```

`prom-alerts.sh` and `am-query.sh` will try the `/prometheus` or
`/alertmanager` subpath automatically if a bare host root returns non-200.

## Preferred access order

1. **Configured ingress / UI URLs** — if `values.yaml` (or ConfigMap
   `arizeapp`) exposes Prometheus or
   Alertmanager (`alertsBaseUrl`, monitoring ingress, etc.), use those HTTPS
   bases directly (still include any `/prometheus` or `/alertmanager` path the
   ingress uses). `prom-alerts.sh` / `am-query.sh` verify TLS for non-localhost
   HTTPS; pass `--insecure` (or `CURL_INSECURE=1`) only when you must skip
   verification. Localhost port-forwards still use `-k` automatically.
2. **Port-forward** (typical default):

   ```bash
   "$SKILL_ROOT/scripts/safe-kubectl.sh" --context <context> -n <namespace> \
     port-forward svc/prometheus 9090:9090
   "$SKILL_ROOT/scripts/safe-kubectl.sh" --context <context> -n <namespace> \
     port-forward svc/alertmanager 9093:9093
   export PROM="http://localhost:9090/prometheus"
   export AM="http://localhost:9093/alertmanager"
   ```

   Or run `$SKILL_ROOT/scripts/open-ports.sh --namespace <namespace>` (prints
   the subpath exports).

3. **kubectl proxy** (optional Kubernetes API HTTP access):

   ```bash
   "$SKILL_ROOT/scripts/safe-kubectl.sh" proxy --port=8080
   export KUBE_PROXY="http://localhost:8080"
   ```

4. **In-cluster DNS** — only when the agent runs inside the cluster:

   ```text
   http://prometheus.<namespace>.svc.cluster.local:9090/prometheus
   http://alertmanager.<namespace>.svc.cluster.local:9093/alertmanager
   ```

## Additional forwards

Open these only when investigation needs them (still read-only):

| Service | Typical port | Why |
|---|---|---|
| Grafana | 3000 | Dashboard annotations / explore |
| Druid broker / router | chart-specific | ADB query health |
| App-server | chart-specific | UI / GraphQL health |

Do **not** port-forward everything by default — start with Prometheus
(+ Alertmanager).

## Namespace tips

- Operator workloads may live in `arize-operator` (or similar) while Prometheus
  / Alertmanager usually sit in the **application** namespace.
- If the namespace is unknown:

  ```bash
  "$SKILL_ROOT/scripts/safe-kubectl.sh" -A get pods | grep -E 'prometheus|alertmanager'
  ```

- Catalog Resolution steps that mention `kubectl -n arize-operator` refer to
  the **operator** namespace for that install — confirm before copying.

## When access fails

Distinguish **cluster access problems** from **Arize problems** before drawing any
conclusion. A failed read is not evidence about the cluster's health.

**First rule:** if the same `kubectl` command works in the operator's own
terminal but fails for the agent, the agent's shell is sandboxed or firewalled.
That is a **tooling** problem. Re-run with unrestricted network access before
mentioning VPN, cloud credentials, namespaces, or cluster health.
`preflight.sh` exits **5** for this case and prints the API endpoint it tried.

| Symptom | Meaning | Do this |
|---|---|---|
| `Unable to connect to the server: Forbidden` | The shell cannot reach the API server (sandboxed agent shell, network policy, proxy) | Re-run outside the sandbox / with full network access. Do not re-interpret as a namespace, credential, or install problem |
| DNS timeout on the API hostname (e.g. `*.eks.amazonaws.com`) | The shell's resolver is blocked, common in agent sandboxes with domain allowlists | Re-run with unrestricted network access before blaming VPN or credentials |
| `Unable to connect to the server: dial tcp ... i/o timeout` | No route / VPN down (or blocked shell) | Confirm the shell is unsandboxed, then restore connectivity |
| `error: You must be logged in to the server` | Expired or missing credentials | Re-authenticate, confirm `kubectl config current-context` |
| `configmaps "onprem-metadata" not found` | Wrong namespace, or install never reconciled | Confirm `--operator-namespace` |
| `check-version.sh` exits **3** | Cluster state unreadable | Treat version as unknown; do not claim a version mismatch |
| `check-version.sh` exits **1** | Real semver mismatch | Get the distribution matching `last-applied-release` |
| `preflight.sh` exits **5** | This shell has no network path to the API server | Re-run with full network access (sandbox off); only then investigate VPN/credentials |
| `preflight.sh` exits **3** | API server answered, but `onprem-metadata` was unreadable | Confirm operator namespace and ConfigMap read permission — not connectivity |

`check-version.sh` prints kubectl's own error. Read it before changing the
namespace: an access error and a missing ConfigMap need opposite fixes.

## Port-forward reliability

A port-forward is a child process of the shell that started it. If each command
runs in a separate shell, the tunnel can be reaped between steps, and the next
query fails with a connection error that looks like a broken cluster.

`open-ports.sh` handles this: it launches forwards with `nohup` + `disown`,
writes kubectl output to `${ARIZE_SKILL_TMP}/<service>-port-forward.log`, waits
until the port actually answers, and exits non-zero (printing the log) when a
forward dies on startup.

```bash
"$SKILL_ROOT/scripts/open-ports.sh" --namespace <namespace>   # start + verify
"$SKILL_ROOT/scripts/open-ports.sh" --status                  # re-check listeners
"$SKILL_ROOT/scripts/open-ports.sh" --stop                    # tear down
```

If forwards keep dying, run the forward and the query in the **same** shell
invocation, or use the ingress URLs instead. Re-check before each batch of
queries:

```bash
curl -s -o /dev/null -w "%{http_code}\n" "$PROM/api/v1/query?query=up"
```

## Safety while tunneling

- Port-forward and proxy are allowed; they only expose APIs locally.
- Still issue **GET-only** requests against those ports.
- Tear down background forwards when finished (`kill` the PIDs printed by
  `open-ports.sh`, or close the terminal jobs).
