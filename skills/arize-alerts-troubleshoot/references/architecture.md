# Arize Self-Hosted — Architecture Primer

Read this before diagnosing alerts. For diagrams and full prose, open the HTML
in `$ARIZE_DISTRIBUTION_ROOT` (see `distribution.md`).

## What Arize is

Self-hosted **Arize AX** is an ML/LLM observability platform: teams send
predictions, actuals, and traces into their cluster; Arize stores and serves
them for UI, monitors, and evaluations.

Install model: **Helm Operator chart** + **`values.yaml`** → **Arize Operator**
reconciles workloads into Kubernetes.

## Data path (simplified)

```text
Clients / SDK / OTEL
        ↓
   receiver          (ingest API)
        ↓
   gazette           (durable stream / journals; etcd for journal state)
        ↓
   ┌────────────────────────────────────────────┐
   │ realtimeingestion │ modeldiscovery │      │
   │ joinerv2 │ druidloader / druidloaderv2 …   │
   └────────────────────────────────────────────┘
        ↓
   object storage + ADB/Druid (historicals, broker, indexing, compaction)
        ↓
   app-server / metricscalculator / alerting   (UI + monitors)
```

**Postgres** holds operational metadata (models, monitors, users) — not the
primary observability event store.

## Monitoring stack (where alerts come from)

| Component | Role |
|---|---|
| **prometheus** | Scrapes metrics; evaluates alert rules shipped with the release |
| **alertmanager** | Fires / routes / silences alerts |
| **grafana** | Dashboards for ingestion, Druid, Gazette, etc. |
| **datagenerator + prober** | Synthetic traffic + pipeline health checks |
| **loki / promtail / tempo / otel-collector** | Optional logs/traces (if enabled) |

Platform alerts are **Prometheus rules**, not the product “monitors” UI (those
are evaluated by the `alerting` service).

## Namespaces (typical)

Exact names depend on `values.yaml`. Common pattern:

| Namespace | Contents |
|---|---|
| Operator namespace (often `arize-operator`) | Arize Operator StatefulSet |
| Application namespace (chosen at install; often `arize`) | receiver, gazette, druid*, app-server, prometheus, alertmanager, … |

Always confirm with `safe-kubectl.sh -A get ns` / install notes for the cluster.

## Alert severity (self-hosted)

| Severity | Meaning |
|---|---|
| **none** | No action (e.g. DeadMansSwitch heartbeat — expected to fire) |
| **warning** | Attention, not immediate |
| **page-biz-hours** | Urgent during business hours |
| **page** | Urgent anytime |

## Component cheat sheet

Use the catalog’s `component` label and Resolution first. If you need “what
does this pod do?”, open:

`$ARIZE_DISTRIBUTION_ROOT/docs/operations/operational-guide.html`

High-traffic alert areas:

| Area | Typical workloads | Failure symptoms |
|---|---|---|
| Operator | `arize-operator` | Install/reconcile stuck |
| Receiving | `receiver`, `gazette`, `etcd` | Ingest errors, journal lag |
| Ingestion | `druidloader*`, `joinerv2`, `realtimeingestion`, … | Lag, stalled shards |
| ADB / Druid | `druid-historical*`, `druid-broker`, … | Query slow/fail, cache full |
| UI / access | `app-server`, `auth` | UI down or login failures |
| Product monitors | `alerting`, `email` | Monitor / notification issues |
| Export | `byob*`, `flightserver` | Export lag / failures |
