---
name: arize-self-hosted-install
description: >-
  Guides first-time customers through an Arize AX on-prem or self-hosted
  install: selecting or downloading a distribution tarball, preparing
  values.yaml, running arize.sh, and validating Kubernetes. Use for "on-prem
  install", "self-hosted install", distribution, arize.sh, or values.yaml
  requests. Does not provision infrastructure.
metadata:
  author: arize
  version: "1.0"
compatibility: >-
  Requires macOS or Linux, public internet access for documentation and
  downloads, and eventually curl, kubectl, Helm 3, openssl, Docker, tar, a
  supported cloud CLI, and an Arize AI distribution JWT.
---

# Arize Self-Hosted Installation

Guide a customer from no Arize knowledge to a validated Arize AX installation.
Explain each phase before asking them to run anything. Arize AX is installed on
Kubernetes from a release-specific distribution containing `arize.sh`, a Helm
chart, offline documentation, examples, and optional Terraform modules.

## Safety and source-of-truth rules

- **Infrastructure is guidance-only:** never run Terraform/OpenTofu or cloud
  provisioning. Prepare configuration only, then wait for the platform team.
- **Distribution gate:** use only the exact path or release the user selects;
  never search for, rank, or choose local distributions.
- **Kubernetes gate:** show local kubeconfig identity, then obtain explicit
  confirmation before contacting the API or inspecting cluster state.
- **Customer-cluster scope:** run every direct kubectl operation through the
  bundled [safe kubectl wrapper](scripts/safe-kubectl.sh), only for the
  user-confirmed customer-owned target. The wrapper permits validation and
  localhost tunnels but rejects `delete` and other mutations. Release-owned
  `arize.sh` and Helm perform installation separately after the mutation gate.
  Never use this workflow against the Arize-managed fleet.
- **Mutation gate:** show and confirm the exact install target and command
  immediately before changing the cluster.
- **Local tunnel gate:** prefer the release-owned `arize.sh open-ports`; disclose
  that it replaces matching local port-forward processes and confirm first.
- Keep secrets out of chat and shell history. Treat `values.yaml` as sensitive,
  mode `600`, and keep it out of source control.
- The selected distribution's offline docs and chart schema override public
  guidance. Never invent release fields, defaults, paths, or commands.

The [installation reference](references/REFERENCE.md) owns all commands,
platform links, field mappings, and detailed checks.

## Interaction rules

- Assume the user is new to Arize and Kubernetes. Define unfamiliar terms in one
  sentence and ask one manageable group of questions at a time.
- Maintain and show this progress checklist. Do not skip a gate because a later
  answer appears available.
- At each gate, report what is confirmed, what is missing, and the next action.
- If the platform, network model, distribution version, cluster, or sizing is
  uncertain, stop and ask. Never guess.

```text
Progress:
- [ ] 1. Understand the installation and collect starting state
- [ ] 2. Obtain and verify the Arize distribution
- [ ] 3. Select platform/network type and prepare or confirm infrastructure (guidance-only)
- [ ] 4. Verify workstation and Kubernetes access
- [ ] 5. Build and review values.yaml
- [ ] 6. Confirm target and install Arize
- [ ] 7. Validate workloads, ingress, ingestion, alerts, and UI
```

## Workflow

### 1. Orient and collect starting state

Briefly explain that the distribution installs the Arize operator, which then
manages Arize workloads in the customer's Kubernetes cluster. Ask:

1. Do they already have an **unpacked** Arize distribution? If yes, request its
   exact directory path and ask them to confirm that this is the release to use.
   Do not search their filesystem, inspect candidate distributions, or select
   one based on its filename, version, location, or modification time.
2. Which platform: AWS/EKS, GCP/GKE, Azure/AKS, IBM/IKS, OpenShift, Rancher/bare
   metal, single-host development, or another Kubernetes environment?
3. Is the environment connected, semi-restricted, or air-gapped?
4. Is prerequisite infrastructure complete, incomplete, or unknown?

### 2. Obtain and verify the distribution

Follow the distribution gate in the
[installation reference](references/REFERENCE.md). For an existing unpack,
validate the exact user-selected path and compare its chart version with the
current release. Otherwise require distribution access, let the user choose
latest (recommended) or an exact older version, and confirm safe download and
extraction locations. Stop if the JWT, selection, or path is missing.

### 3. Select the documented path and gate infrastructure

Open the platform hub, deployment-type page, prerequisites page, and the
release-matched pages listed in the
[installation reference](references/REFERENCE.md). Explain what the platform
team must provide.
If infrastructure is incomplete or unknown and the platform is AWS, GCP, or
Azure, ask whether the user wants guidance using the Terraform modules in their
selected distribution. If they opt in, follow the reference's `main.tf`
workflow; never run Terraform. Otherwise provide the prerequisite checklist and
links. Do not continue until the user confirms infrastructure is ready.

### 4. Verify workstation and cluster access

Follow the two-part Kubernetes gate in the
[installation reference](references/REFERENCE.md): check local tools and
kubeconfig identity, stop for target confirmation, then run release-matched
read-only access and capacity checks. Existing Arize resources never substitute
for user confirmation.

### 5. Build `values.yaml`

Build `values.yaml` from the selected platform walkthrough, release chart
schema, and offline docs using the
[installation reference](references/REFERENCE.md). Confirm cloud mapping,
sizing, infrastructure outputs, encoding, and ingress. Keep secrets outside
chat, then run only local, non-secret-bearing checks.

### 6. Install with an explicit confirmation gate

Present the reference's exact target summary and install command, then obtain
explicit confirmation. During installation, monitor the operator, pre-check,
and pre-upgrade logs. Treat failed pre-checks as blockers; do not bypass them.

### 7. Validate and hand off

Follow the reference's workload, ingress, UI, HTTP/gRPC ingestion, and
Prometheus checks. If alerts fire, hand off to `arize-alerts-troubleshoot`.
Finish with confirmed settings, results, unresolved items, and documentation
used.
