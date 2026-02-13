# Secret leak remediation runbook

Use this runbook whenever secret scanning detects a potential leak.

## 1. Contain immediately

- Stop distributing logs/artifacts containing the leaked value.
- Revoke or disable the exposed credential as quickly as possible.
- If production impact is possible, escalate to the incident channel immediately.

## 2. Rotate credentials

- Create a replacement secret in the approved secret manager.
- Update dependent systems and deployments.
- Verify workloads are running with the new credential.

## 3. Remove leaked material from repository state

- Remove the leaked value from working tree files.
- If already committed, rewrite history using approved tooling (for example, `git filter-repo` or BFG) following organizational policy.
- Force-push rewritten branches only after team coordination.

## 4. Verify cleanup

- Re-run secret scanning locally (`pre-commit run --all-files`).
- Confirm CI secret scanning job passes.
- Search commit history and tags to confirm the leaked value is no longer present.

## 5. Document and prevent recurrence

- Record timeline, impact, and rotated assets.
- Add/adjust detection rules if the leak bypassed existing checks.
- Update docs/tests/workflows to prevent the same class of leak.

## Handy command checklist

```bash
# Run local secret scan
pre-commit run --all-files

# Validate file exclusion policy
scripts/check-sensitive-files-excluded.sh

# Find suspicious env/config files tracked by git
git ls-files | rg '(^|/)\.env($|\.)|(^|/)config/.*(secret|secrets)'
```
