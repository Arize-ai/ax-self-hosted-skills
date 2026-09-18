# Arize Self-Hosted Installation Reference

Use this reference while following the gates in the main skill. Public pages
provide the current installation route; the extracted distribution's offline
documentation and chart schema remain authoritative for its release.

## Contents

- [Public documentation map](#public-documentation-map)
- [1. Distribution gate](#1-distribution-gate)
- [2. Platform and infrastructure gate](#2-platform-and-infrastructure-gate)
- [3. Workstation and Kubernetes access gate](#3-workstation-and-kubernetes-access-gate)
- [4. `values.yaml` workflow](#4-valuesyaml-workflow)
- [5. Installation confirmation](#5-installation-confirmation)
- [6. Validation and completion](#6-validation-and-completion)

## Public documentation map

### Start here

- [Self-hosting overview](https://arize.com/docs/ax/selfhosting)
- [Installation flow](https://arize.com/docs/ax/selfhosting/getting-started/overview)
- [Prerequisites](https://arize.com/docs/ax/selfhosting/getting-started/prerequisites)
- [Download and unpack the distribution](https://arize.com/docs/ax/selfhosting/getting-started/download-and-unpack-the-distribution)
- [On-Premise Releases](https://arize.com/docs/ax/selfhosting/on-premise-releases)
- [Deployment types](https://arize.com/docs/ax/selfhosting/getting-started/deployment-types)
- [Installation by platform](https://arize.com/docs/ax/selfhosting/installation)
- [External Postgres requirements](https://arize.com/docs/ax/selfhosting/installation/external-postgres-requirements)
- [Configuring ingress and endpoints](https://arize.com/docs/ax/selfhosting/installation/ingress/configuring-endpoints)
- [Fresh reinstall cleanup](https://arize.com/docs/ax/selfhosting/advanced/fresh-reinstall-cleanup)
- [Validate the deployment](https://arize.com/docs/ax/selfhosting/installation/validate-deployment)

### Platform routes

| Platform | Hub | Existing infrastructure | Bundled Terraform guidance | `values.yaml` walkthrough | Ingress |
|---|---|---|---|---|---|
| AWS / EKS | [AWS installation](https://arize.com/docs/ax/selfhosting/installation/installation-on-aws) | [EKS cluster and AWS resources](https://arize.com/docs/ax/selfhosting/installation/aws/cluster-existing-eks) | [AWS Terraform](https://arize.com/docs/ax/selfhosting/installation/aws/cluster-terraform) | [AWS detailed walkthrough](https://arize.com/docs/ax/selfhosting/installation/aws/install-arize-detailed) | [AWS load balancer](https://arize.com/docs/ax/selfhosting/installation/aws/ingress-aws-load-balancer) |
| GCP / GKE | [GCP installation](https://arize.com/docs/ax/selfhosting/installation/installation-on-gcp) | [GKE cluster and resources](https://arize.com/docs/ax/selfhosting/installation/gcp/cluster-existing-gke) | [GCP Terraform](https://arize.com/docs/ax/selfhosting/installation/gcp/cluster-terraform) | [GCP detailed walkthrough](https://arize.com/docs/ax/selfhosting/installation/gcp/install-arize-detailed) | [GCP load balancer](https://arize.com/docs/ax/selfhosting/installation/gcp/ingress-gcp-load-balancer) |
| Azure / AKS | [Azure installation](https://arize.com/docs/ax/selfhosting/installation/installation-on-azure) | [AKS cluster and resources](https://arize.com/docs/ax/selfhosting/installation/azure/cluster-existing-aks) | [Azure Terraform](https://arize.com/docs/ax/selfhosting/installation/azure/cluster-terraform) | [Azure detailed walkthrough](https://arize.com/docs/ax/selfhosting/installation/azure/install-arize-detailed) | [Azure load balancer](https://arize.com/docs/ax/selfhosting/installation/azure/ingress-azure-load-balancer) |
| IBM / IKS | [IBM Cloud installation](https://arize.com/docs/ax/selfhosting/installation/installation-on-ibm-cloud) | [IKS cluster and resources](https://arize.com/docs/ax/selfhosting/installation/ibm/cluster-existing-iks) | No bundled IBM module; use platform-team infrastructure | [IBM detailed walkthrough](https://arize.com/docs/ax/selfhosting/installation/ibm/install-arize-detailed) / [quick start](https://arize.com/docs/ax/selfhosting/installation/ibm/install-arize-quickstart) | [IBM ingress](https://arize.com/docs/ax/selfhosting/installation/ibm/ingress-ibm-cloud) |
| OpenShift | [OpenShift installation](https://arize.com/docs/ax/selfhosting/installation/installation-on-openshift) | [OpenShift cluster and resources](https://arize.com/docs/ax/selfhosting/installation/openshift/cluster-existing-openshift) | No bundled OpenShift module; use platform-team infrastructure | [OpenShift detailed walkthrough](https://arize.com/docs/ax/selfhosting/installation/openshift/install-arize-detailed) / [quick start](https://arize.com/docs/ax/selfhosting/installation/openshift/install-arize-quickstart) | [OpenShift ingress](https://arize.com/docs/ax/selfhosting/installation/openshift/ingress-openshift) |
| Rancher / bare metal | [Rancher installation](https://arize.com/docs/ax/selfhosting/installation/installation-on-rancher-bare-metal) | [Cluster and storage](https://arize.com/docs/ax/selfhosting/installation/rancher-bare-metal/cluster-and-storage) / [compatibility](https://arize.com/docs/ax/selfhosting/installation/bare-metal-compatibility) | No bundled Rancher/bare-metal module; use platform-team infrastructure | [Rancher/bare-metal install](https://arize.com/docs/ax/selfhosting/installation/rancher-bare-metal/install-arize) | [Endpoint configuration](https://arize.com/docs/ax/selfhosting/installation/ingress/configuring-endpoints) |
| Single host | [Single-host installation](https://arize.com/docs/ax/selfhosting/installation/installation-on-single-host) | Development/testing only | Not a production provisioning path | [Single-host install](https://arize.com/docs/ax/selfhosting/installation/installation-on-single-host) | [Endpoint configuration](https://arize.com/docs/ax/selfhosting/installation/ingress/configuring-endpoints) |
| Other Kubernetes | [Installation overview](https://arize.com/docs/ax/selfhosting/installation) | [Prerequisites](https://arize.com/docs/ax/selfhosting/getting-started/prerequisites) | Ask Arize AI to confirm support before proceeding | Use release-matched offline docs | [Other ingress controllers](https://arize.com/docs/ax/selfhosting/installation/ingress/other-controllers) |

Do not claim that an unlisted Kubernetes platform or configuration is supported.
Ask the user to confirm it with Arize AI.

## 1. Distribution gate

### If the distribution is already unpacked

Ask for the exact unpack directory and confirm that this is the distribution
the user wants evaluated for the installation, then:

```bash
export ARIZE_DISTRIBUTION_ROOT="<exact-directory-provided-by-user>"

test -f "$ARIZE_DISTRIBUTION_ROOT/arize.sh"
test -f "$ARIZE_DISTRIBUTION_ROOT/arize-operator-chart.tgz"
test -f "$ARIZE_DISTRIBUTION_ROOT/index.html"
test -d "$ARIZE_DISTRIBUTION_ROOT/docs"
test -d "$ARIZE_DISTRIBUTION_ROOT/terraform"
```

Do not search the machine, inspect nearby archives or directories, or choose
among multiple releases. Do not describe a candidate as the customer's
distribution merely because it exists or appears newest. If any check fails,
ask for the correct directory or a fresh download.

Use the root `index.html` as the distribution's offline documentation entry
point. If a distribution README names another local path, check that it exists
before using it. Report a stale path instead of guessing the intended file.

Inspect the release-owned entry points without changing anything:

```bash
cd "$ARIZE_DISTRIBUTION_ROOT"
./arize.sh help
ls -la index.html terraform/README.md
tar -xOf arize-operator-chart.tgz '*/Chart.yaml' \
  | grep -E '^(appVersion|version):'
```

If the tar member path differs, list names first and identify `Chart.yaml`
without extracting over the working directory:

```bash
tar -tf arize-operator-chart.tgz
```

Use `Chart.yaml`'s `appVersion` as the distribution version, falling back to
`version` if `appVersion` is absent. If neither field supplies an unambiguous
semantic version, stop and ask; do not infer the version from `arize.sh` or the
directory or archive name.

Open the
[On-Premise Releases](https://arize.com/docs/ax/selfhosting/on-premise-releases)
page and compare the chart version with the version in the first release
heading:

- If they match, tell the user that their selected distribution is current and
  continue without creating a directory or downloading anything.
- If the selected distribution is older, report both versions and ask whether
  to continue with the selected version or download the latest version
  (**recommended**). Enter the download workflow only if the user chooses it.
- If the version cannot be determined reliably or the release information
  conflicts, stop and ask rather than inferring from filenames.

### If the distribution must be downloaded

The credential is a JWT issued by Arize AI. The user may call it a license key.
If they do not have one, they must contact their Arize representative. Do not
accept it in chat.

Before any download preparation, check only whether `JWT` is already exported
and non-empty:

```bash
if [[ -n "${JWT:-}" ]]; then
  printf 'JWT is exported.\n'
else
  printf 'JWT is not exported.\n'
fi
```

Never run `env`, `printenv JWT`, `echo "$JWT"`, or another command that reveals
the value. Never open an interactive `read` prompt for the credential. If the
check reports that it is missing, stop and ask the user to export `JWT`
privately in the same shell using their approved secret-handling process, then
tell you when it is ready. Do not provide or run a command containing the
literal key, and do not continue until the presence check succeeds.

Before creating a directory or downloading anything:

1. Open the [On-Premise Releases](https://arize.com/docs/ax/selfhosting/on-premise-releases)
   page and identify the version in the first release heading. Do not rely on a
   version remembered from an earlier run.
2. Tell the user the current latest version and ask whether they want:
   - that version (**recommended**), or
   - a specific older version.
3. If they choose an older version, ask for the exact `x.y.z` version and
   verify that it appears on the releases page. Do not choose an older version
   for them.
4. Run `pwd`, show the absolute path, and ask whether that is where they want
   the distribution downloaded. If not, ask for the exact destination and
   `cd` there. Do not infer a destination from nearby release files.

Do not continue until the user has explicitly selected a version and confirmed
the download directory.

#### Download the latest release

Tell the user that `get_latest.sh` downloads and automatically unpacks the
distribution as `arize-distribution-<version>` beneath the confirmed current
directory. Ask them to confirm that this parent directory and generated
subdirectory are acceptable before running:

```bash
: "${JWT:?JWT is not exported; stop and ask the user to set it privately}"
curl -H "Authorization: Bearer $JWT" \
  "https://ch.hub.arize.com/dist/get_latest.sh" | sh -
unset JWT
```

The command consumes the previously exported value without displaying it and
then removes it from the shell. After download, use the actual directory
created by the script, not a predicted version path.

#### Download a specific older release

Set `VERSION` only to the exact version selected by the user. Download its
tarball into the confirmed download directory:

```bash
VERSION=x.y.z
URL=https://ch.hub.arize.com/dist
: "${JWT:?JWT is not exported; stop and ask the user to set it privately}"
curl -H "Authorization: Bearer $JWT" \
  "$URL/distributions/arize-distribution-$VERSION.tar" \
  --output "arize-distribution-$VERSION.tar"
unset JWT
```

The versioned tarball has no enclosing top-level directory. Require a dedicated
empty extraction directory so its files are not scattered among unrelated
files. Suggest
`<confirmed-download-directory>/arize-distribution-$VERSION`, show that exact
path, and ask the user to confirm it. Do not extract directly into Downloads,
the home directory, or another non-empty directory.

For a new confirmed directory, create it without `-p` so the command fails
rather than silently reusing an existing path. Move the tarball there and
extract using the relative tarball path:

```bash
EXTRACT_DIR="<confirmed-download-directory>/arize-distribution-$VERSION"
mkdir "$EXTRACT_DIR"
mv "<confirmed-download-directory>/arize-distribution-$VERSION.tar" \
  "$EXTRACT_DIR/"
cd "$EXTRACT_DIR"
tar -xvf "./arize-distribution-$VERSION.tar"
```

If the chosen extraction directory already exists, stop and verify with the
user that it is empty or choose a new empty directory; never clear it
automatically.

For either route, set `ARIZE_DISTRIBUTION_ROOT` to the resulting unpack
directory and verify the four required paths above. A successful download does
not replace the user's explicit selection of that release.

## 2. Platform and infrastructure gate

First classify the network:

- **Connected:** cluster and install workstation can reach required Arize and
  image-registry endpoints.
- **Semi-restricted:** some access is constrained; images may need mirroring.
- **Air-gapped:** use the distribution's documented offline transfer workflow.

Then confirm the platform team has supplied:

- A supported Kubernetes cluster sized for the Arize-approved `clusterSizing`.
- Base and ArizeDB node capacity, with the required labels or a documented
  shared-node-pool configuration.
- Two object-storage locations: one for Gazette and one for ArizeDB.
- A non-NFS block storage class and the platform-specific CSI support.
- Workload identity/IAM access, or the documented key-based fallback.
- Required namespaces or permission for the Helm chart to create them.
- Registry reachability or a prepared private-registry/image-mirroring path.
- Required outbound network access or approved offline artifacts.
- Ingress/load balancer, DNS, TLS, and the intended application hostname, if
  these are expected before install.
- The exact cluster name, region/project/account identifiers, bucket/container
  names, identity details, storage classes, registry hostname, organization
  name, and sizing value needed for `values.yaml`.

If infrastructure is incomplete or unknown on AWS, GCP, or Azure, ask:

```text
Would you like to use the Terraform modules included in your selected Arize
distribution? I can guide you through preparing main.tf, but I will not run
Terraform or provision infrastructure.
```

If they decline, provide the prerequisite checklist and platform links, then
wait for their platform team. For other platforms, do not generalize the AWS,
GCP, or Azure modules; follow only their documented infrastructure route.

### Optional Terraform `main.tf` workflow

Enter this workflow only after the user opts in. Open the public platform
Terraform page and the selected distribution's single
`terraform/README.md`. That README contains cloud-specific sections and inline
`main.tf` samples; do not assume there are platform-specific READMEs or separate
example files.

The distribution separates optional network modules from cluster modules:

- AWS uses `terraform/aws_vpc` and `terraform/aws_cluster`.
- GCP uses `terraform/gcp_vpc` and `terraform/gcp_cluster`.
- Azure uses `terraform/azure_vpc` and `terraform/azure_cluster`.

Verify these directories exist in the selected release before using them. Do
not substitute a similarly named path from another release.

Follow this sequence:

1. Ask whether the customer is supplying an existing network or wants the
   bundled VPC module as well as the cluster module. Do not add a VPC module
   automatically. The release README says its VPC Terraform is not intended for
   production use; tell the user to involve their networking team and follow
   organizational security policy.
2. Read the matching cloud's VPC section only when selected, then read its
   cluster section and inline `main.tf` sample. Do not mix modules or variables
   from another cloud.
3. Run `pwd`, show the current directory, and ask for the exact directory where
   the user wants `main.tf`.
4. Ask whether that directory already has a `main.tf`. If it does, read and
   review it; do not replace or substantially restructure it without explicit
   confirmation.
5. For every selected module, inspect its `variables.tf`, provider requirements
   in `main.tf`, and output declarations across its `.tf` files. Treat a
   variable without a default as mandatory even when the README sample omits
   it. Ask for every unknown required non-secret value.
6. Use the README sample as a starting point, not a complete schema. Include
   only the selected release's documented modules and verified variables; do
   not invent registry modules, versions, variables, or defaults.
7. Replace `<path-to-arize-terraform-code>` with a valid path relative to the
   confirmed `main.tf` directory that resolves to the selected module
   directory. Do not copy the placeholder, assume adjacency, or use a path that
   has not been checked.
8. Use the Arize-approved sizing value consistently: the Terraform module's
   `profile` corresponds to the later `clusterSizing` value. Do not infer it
   from node count or choose it for the user.
9. Use clearly named placeholders for unresolved non-secret values. Keep cloud
   credentials, JWTs, keys, passwords, and other secrets out of `main.tf` and
   chat; direct the user to their approved environment or secret process.
10. Verify that every distribution-local path cited by the README actually
    exists before using it. Report a stale or conflicting reference instead of
    guessing its intended target.
11. Review the resulting file with the user. Use only outputs verified in the
    selected module source when explaining how they satisfy the prerequisite
    checklist and map to later `values.yaml` fields.

This workflow prepares configuration only. Never run or offer to run
`terraform` or `tofu`, including `fmt`, `init`, `validate`, `plan`, `apply`,
`import`, or `destroy`. Never run cloud provisioning commands directly. Hand
the reviewed `main.tf` to the user or their platform team and stop until they
confirm that provisioning completed and provide the required outputs.

## 3. Workstation and Kubernetes access gate

### Safe kubectl scope

This workflow targets only a customer-owned Kubernetes cluster for a
self-hosted installation. Run every direct kubectl operation through the
install skill's [safe kubectl wrapper](scripts/safe-kubectl.sh). It permits the
validation, identity, status, log, wait, and localhost port-forward operations
used here while rejecting `delete` and every other unneeded mutation.
Release-owned `arize.sh` and Helm perform installation outside the wrapper only
after explicit confirmation. Never use this workflow against the Arize-managed
fleet.

Set the skill paths before running checks:

```bash
SKILL_ROOT="<path-to-arize-self-hosted-install>"
SAFE_KUBECTL="$SKILL_ROOT/scripts/safe-kubectl.sh"
```

Do not run any Kubernetes API command until the user confirms the
customer-owned target as described below. After confirmation, set
`KUBE_CONTEXT` to that exact context; the wrapper refuses API calls without an
explicit context.

Check local tools:

```bash
curl --version
"$SAFE_KUBECTL" version --client
helm version
openssl version
docker --version
tar --version
```

Docker may be optional for a fully connected install, but is expected for image
verification or mirroring. Follow the distribution's version requirements when
they differ from public guidance.

If kubeconfig is not configured, show the appropriate local credential command
from the platform documentation:

```bash
# AWS
aws eks update-kubeconfig --region <region> --name <cluster-name>

# GCP
gcloud container clusters get-credentials <cluster-name> \
  --region <region> --project <project-id>

# Azure
az aks get-credentials --resource-group <resource-group> \
  --name <cluster-name>
```

These commands configure local cluster credentials; they must not create or
change the cluster. For IBM, OpenShift, Rancher, or another platform, use only
the access command supplied by its public platform page or the user's platform
administrator.

First inspect only local kubeconfig data. This does not contact the Kubernetes
API:

```bash
"$SAFE_KUBECTL" context
```

Show the context, cluster name, and API server to the user, then ask:

```text
kubectl is configured for context <context>, cluster <cluster-name>, at
<api-server>. Is this the exact Kubernetes cluster where you intend to install
Arize AX? Please confirm, or provide the correct context.
```

Stop here until the user explicitly confirms. Do not run `cluster-info`,
`auth whoami`, `get`, `describe`, `logs`, namespace checks, Helm queries, or any
other command that contacts the Kubernetes API. Existing Arize resources are
not proof that the target is correct.

After confirmation, verify API access and identity:

```bash
export KUBE_CONTEXT="<exact-confirmed-context>"
"$SAFE_KUBECTL" cluster-info
"$SAFE_KUBECTL" auth whoami
"$SAFE_KUBECTL" get nodes
"$SAFE_KUBECTL" get storageclass
"$SAFE_KUBECTL" get nodes --show-labels
```

`auth whoami` is not available on every Kubernetes version. If it is
unsupported, continue with the other confirmed-target checks.

## 4. `values.yaml` workflow

Work from the unpack directory:

```bash
cd "$ARIZE_DISTRIBUTION_ROOT"
umask 077
touch values.yaml
chmod 600 values.yaml
```

Use this precedence:

1. The selected release's chart schema and offline `docs/`.
2. The selected platform's public detailed walkthrough and quick start.
3. General public prerequisites.

Inspect the chart without replacing files in the distribution:

```bash
mkdir -p /tmp/arize-chart-review
tar -xzf arize-operator-chart.tgz -C /tmp/arize-chart-review
find /tmp/arize-chart-review -type f \
  \( -name values.yaml -o -name values.schema.json \) -print
```

Remove the temporary chart review directory when finished. Do not print secret
values while inspecting `values.yaml`.

### Shared inputs

Confirm each key exists in the release schema before using it:

- `hubJwt`: Arize distribution/runtime JWT, base64-encoded.
- `clusterName`: exact platform-specific cluster identifier.
- `cloud`: the chart schema allows `gcp`, `aws`, `azure`, `oci`, `minio`, and
  `ceph`. Use `gcp`, `aws`, or `azure` for those hyperscalers. IBM,
  OpenShift, Rancher/bare-metal, and single-host installations use `ceph`.
  Use `oci` or `minio` only when the matching release documentation applies.
- `gazetteBucket` and `druidBucket`: plain bucket/container names.
- `postgresPassword` and `cipherKey`: generated and base64-encoded according to
  the release schema.
- `organizationName`: plain organization name.
- `clusterSizing`: exact value approved by Arize AI and matched to capacity.
- `appBaseUrl`: final user-facing HTTPS URL.
- `pullRegistry` and, when required by image mirroring, `pushRegistry`.
- Storage-class, shared-node-pool, telemetry, ingress, proxy, and certificate
  settings required by the chosen environment.

Supported sizing profile names are `nonha`, `small1b`, and `medium2b`, The primary
capacity manifests shipped in the distribution are
`docs/sizing_nonha.csv`, `docs/sizing_small1b.csv`, and
`docs/sizing_medium2b.csv`. For one of those profiles, cross-check node count,
labels, CPU, and memory against the matching CSV before accepting the user's
answer. Do not treat a similarly named file as proof that another profile is
supported.

The CSV is a validation aid, not a sizing selector. Do not infer
`clusterSizing` from node count or choose a profile for the user. If their
Arize-approved profile has no matching CSV, use the release documentation and
ask Arize AI to confirm capacity.

If `postgresAuthMode` is changed from the documented default or the customer
uses external Postgres, follow the
[external Postgres requirements](https://arize.com/docs/ax/selfhosting/installation/external-postgres-requirements).
Use the
[endpoint configuration guide](https://arize.com/docs/ax/selfhosting/installation/ingress/configuring-endpoints)
when collecting ingress mode, hostnames, ports, TLS, DNS, and `appBaseUrl`.

### Platform-specific inputs

AWS usually requires:

- `cloud: "aws"`, region, and the EKS cluster ARN shape documented for
  `clusterName`.
- S3 bucket names and server-side encryption configuration.
- IRSA role ARN, or confirmation that the node role has required permissions.
- AWS EBS storage classes when defaults are unsuitable.

GCP usually requires:

- `cloud: "gcp"`, `gcpProject`, and the documented GKE `clusterName`.
- GCS bucket names and `gcpServiceAccountName`.
- Workload Identity settings, or a base64-encoded service-account JSON key.
- GCP storage classes when defaults are unsuitable.

Azure usually requires:

- `cloud: "azure"` and the AKS cluster name.
- Blob container names and `azureStorageAccountName`.
- Azure Workload Identity tenant/client settings, or a base64-encoded storage
  account key.
- Azure CSI storage classes when defaults are unsuitable.

For all other platforms, derive fields only from the matching public page,
offline release docs, and chart schema.

### Secret handling

Have the user create secret values outside chat. When `values.yaml` contains
the placeholders `<HUB_JWT_BASE64>`, `<POSTGRES_PASSWORD_BASE64>`, and
`<CIPHER_KEY_BASE64>`, explain each mapping and include these commands for the
user to run locally:

```bash
# <HUB_JWT_BASE64>: base64 of the raw Arize JWT
printf '%s' "$JWT" | base64 | tr -d '\n'; printf '\n'

# <POSTGRES_PASSWORD_BASE64>: base64 of the database password
printf '%s' "$POSTGRES_PASSWORD" | base64 | tr -d '\n'; printf '\n'

# <CIPHER_KEY_BASE64>: base64 of a random 32-character cipher source
cat /dev/urandom | LC_ALL=C tr -dc 'a-zA-Z0-9' | head -c 32 | base64
```

The cipher command is the command documented in the distribution's offline
Helm guide. `JWT` and `POSTGRES_PASSWORD` must already be set privately in the
user's shell; if either is missing, stop and ask the user to export it using
their approved secret-handling process. Do not substitute literal secrets into
the commands, run the commands for the user, capture their output, or ask the
user to paste the results into chat. The generated base64 strings remain
secret values and must be inserted into `values.yaml` locally.

Do not assume that every field is encoded: bucket names, organization names,
service-account emails, registry hosts, and URLs are normally plain text. The
release schema and platform walkthrough decide each field.

Create a structurally complete file with clearly named placeholders, then have
the user replace secret placeholders through their approved process. Tell them
to reply `ready` only after all three values are saved. Then check for
unresolved placeholders without displaying surrounding values:

```bash
grep -En '<[A-Z0-9_-]+>' values.yaml
```

Run a local chart check:

```bash
helm lint --quiet arize-operator-chart.tgz -f values.yaml
```

If the chart or release docs prescribe another non-mutating validation command,
prefer that command. Treat validation output as sensitive and do not paste it
into chat. Do not render secret-bearing manifests into chat or a world-readable
directory.

## 5. Installation confirmation

Before installation, present:

```text
Kubernetes context:
Distribution directory and version:
Platform and region/project:
Application namespace:
Operator namespace:
Cluster sizing:
Image source/registry:
values.yaml path:
Command:
```

Confirm that:

- The user recognizes the context and cluster.
- Infrastructure is complete.
- `values.yaml` passed local checks and contains no placeholders.
- Secrets were supplied outside chat and the file mode is `600`.
- The selected command matches the release's offline docs.

The usual recommended command is:

```bash
cd "$ARIZE_DISTRIBUTION_ROOT"
./arize.sh install
```

This mutates the Kubernetes cluster. Run it only after explicit confirmation of
the exact summary and command. Also disclose that this release invokes
`open-ports` after installation, replacing matching local port-forward
processes before opening its standard ports. Do not use `-y` or another
non-interactive flag unless the user explicitly requests it. If the release
docs require image verification or mirroring first, follow those
distribution-owned steps and confirm each mutation separately.

### Monitor installation logs

While installation is running, and immediately after it completes or stops,
list the pods in the configured operator namespace. In the standard
configuration, all three relevant pod types run in `arize-operator`:

```bash
"$SAFE_KUBECTL" get pods -n <operator-namespace>
"$SAFE_KUBECTL" logs -n <operator-namespace> \
  pod/arize-op-arize-operator-operator-0
"$SAFE_KUBECTL" logs -n <operator-namespace> \
  pod/<pre-check-pod> --all-containers
"$SAFE_KUBECTL" logs -n <operator-namespace> \
  pod/<pre-upgrade-pod> --all-containers
```

Use the exact pre-check and pre-upgrade pod names returned by the wrapper's
`get` command;
their generated names may vary. If the standard operator pod name is absent,
identify the operator pod from that same namespace rather than guessing.

Review all three log streams. The operator should eventually report
`Success - completed reconcile run`. Any failed pre-check blocks installation
until its underlying issue is resolved. Report the failing check and relevant
log details; do not force installation by setting `skipPreChecks`,
`skipPreCheckList`, `skipPreUpgrade`, or `skipPreUpgradeList`.

After resolving the reported issue, use the release-documented retry path. If a
partial installation must be discarded rather than resumed, show the
[fresh reinstall cleanup guide](https://arize.com/docs/ax/selfhosting/advanced/fresh-reinstall-cleanup)
and explain that it is destructive. Never perform cleanup merely because a
pre-check failed; require explicit confirmation that the user intends to delete
the existing Arize AX resources and data. It is rare that a full cleanup would be required. 
In almost all cases this should be avoided.

## 6. Validation and completion

Use configured namespace values; defaults are commonly `arize` and
`arize-operator`, but never assume an override:

```bash
"$SAFE_KUBECTL" get pods -n <application-namespace>
"$SAFE_KUBECTL" get pods -n <operator-namespace>
"$SAFE_KUBECTL" get deployments,statefulsets -n <application-namespace>
"$SAFE_KUBECTL" get deployments -n <operator-namespace>
```

For unhealthy workloads:

```bash
"$SAFE_KUBECTL" -n <namespace> describe pod <pod-name>
"$SAFE_KUBECTL" -n <namespace> logs <pod-name>
```

Then:

1. Verify ingress objects and endpoints using the selected platform guide.
2. Verify DNS resolves to the intended ingress/load balancer.
3. Open the exact `appBaseUrl` from `values.yaml`.
4. Confirm the UI loads and the release-documented bootstrap/login flow works.
5. Follow the [SDK usage guide](https://arize.com/docs/ax/selfhosting/guides/sdk-usage)
   only after the deployment is healthy.

### Validate trace ingestion

The selected distribution includes SDK v8 trace samples under
`examples/sdk/v8/`. Verify these exact files exist:

- `examples/sdk/v8/trace_sample_http_v8.py` for OTLP over HTTP.
- `examples/sdk/v8/trace_sample_grpc_v8.py` for OTLP over gRPC.

Read each script's header for its release-matched dependencies, endpoint
variables, and TLS configuration. Have the user set `SPACE_ID` and `API_KEY`
privately in their environment; never receive or print those values in chat.

If ingress is configured, tell the user that each script sends a test trace and
obtain confirmation before running both:

```bash
cd "$ARIZE_DISTRIBUTION_ROOT/examples/sdk/v8"
python3 trace_sample_http_v8.py
python3 trace_sample_grpc_v8.py
```

Use `SINGLE_HOST` for a single-host ingress or the scripts' documented
multi-endpoint variables when HTTP and gRPC use separate hosts. A successful
script exit is not sufficient: confirm that both `test-trace-http` and
`test-trace-grpc` appear in the Arize UI.

### Check for firing alerts

Use the port-forwards that `./arize.sh install` opened when they are still
running. Otherwise prefer the release-owned command:

```bash
cd "$ARIZE_DISTRIBUTION_ROOT"
./arize.sh open-ports
```

Before running it, tell the user that it kills matching existing port-forward
processes, then opens the app on `4040`, Prometheus on `9090`, Alertmanager on
`9093`, Grafana on `3000`, and other release services. Obtain confirmation
because it replaces those local processes.

Open Prometheus at `http://localhost:9090` and check for alerts in the `Firing`
state. If any are firing, invoke the `arize-alerts-troubleshoot` skill included
in this repository with the same user-selected distribution and confirmed
Kubernetes target. Do not diagnose or remediate those alerts inside the
installation workflow.

If infrastructure work remains, return it as a platform-team checklist with
documentation links. Do not execute it.
