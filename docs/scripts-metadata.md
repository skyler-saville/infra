# Script Metadata Standard and Index

This repository uses an **adjacent YAML metadata file** for every shell script (`*.sh`) to make incident-time ownership and recovery details easy to locate.

## Metadata file format

For a script at:

- `path/to/script.sh`

create a metadata file at:

- `path/to/script.sh.metadata.yaml`

Required schema:

```yaml
owner_team: <team-or-owner>
purpose: <what this script does>
risk_level: <low|medium|high|critical>
preconditions:
  - <required runtime condition>
rollback_steps:
  - <how to recover or revert>
runbooks:
  - <url-or-repo-doc-path>
```

### Field guidance

- `owner_team`: Team/person responsible for operation and incident response.
- `purpose`: One-sentence description of script intent.
- `risk_level`: Operational risk of incorrect use.
- `preconditions`: Conditions that must be true before running.
- `rollback_steps`: Deterministic rollback path if execution causes issues.
- `runbooks`: Canonical remediation docs (URLs or local docs paths).

## Script metadata index

| Script | Metadata | Owner/team | Risk |
|---|---|---|---|
| `scripts/scaffold-script.sh` | `scripts/scaffold-script.sh.metadata.yaml` | `platform-infra` | `medium` |
| `scripts/check-sensitive-files-excluded.sh` | `scripts/check-sensitive-files-excluded.sh.metadata.yaml` | `platform-security` | `low` |
| `deploy-tools/bin/deploy-project.sh` | `deploy-tools/bin/deploy-project.sh.metadata.yaml` | `platform-release` | `high` |
| `deploy-tools/bin/compose-remote.sh` | `deploy-tools/bin/compose-remote.sh.metadata.yaml` | `platform-release` | `high` |
| `deploy-tools/bin/ssh-project.sh` | `deploy-tools/bin/ssh-project.sh.metadata.yaml` | `platform-infra` | `medium` |
| `lib/common.sh` | `lib/common.sh.metadata.yaml` | `platform-infra` | `medium` |
| `lib/env-loader.sh` | `lib/env-loader.sh.metadata.yaml` | `platform-infra` | `high` |

Keep this index in sync whenever new `*.sh` files are added.
