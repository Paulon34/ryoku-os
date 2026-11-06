# First public push — Paulon34/ryoku-os

**Status:** prepared in Mission 004 · **Push not executed** until Paulo authorizes explicitly.

## Preconditions (verified Mission 004)

| Check | Expected |
|-------|----------|
| Local tip includes Missions 001–003 + prep | includes `412209b`; publish tip `28b7924`; local `main` == tip |
| GitHub repo | `https://github.com/Paulon34/ryoku-os` exists, owner `Paulon34`, **empty** |
| Remote `github` | HTTPS **without** embedded token: `https://github.com/Paulon34/ryoku-os.git` |
| Remote `origin` | Cursor temporary remote — **keep** (do not delete without confirming Cursor needs it) |
| Secrets in tree | None found in tracked files (see Mission 003.5 / 004 audits) |

## Exact proposed commands (DO NOT RUN until authorized)

From `/workspace`, after review of `cursor/ryoku-publish-prep-004` / local `main`:

```bash
# 1) Confirm tip and remotes (redact tokens if sharing logs)
cd /workspace
git status -sb
git log -5 --oneline --decorate
git remote -v | sed -E 's#(://[^:]+:)[^@]+@#\1[REDACTED]@#g'

# 2) Ensure local main points at the publish tip (already prepared locally in Mission 004)
git checkout main
git merge --ff-only cursor/ryoku-publish-prep-004   # or: git reset --hard <publish-tip-sha>
# Prefer ff-only merge from prep branch; do NOT force-push.

# 3) Auth to GitHub without embedding PATs in the remote URL
#    Option A — HTTPS + credential helper / gh:
gh auth login   # if not already; scopes: repo
#    Option B — SSH (then switch URL once):
# git remote set-url github git@github.com:Paulon34/ryoku-os.git

# 4) Confirm remote still empty
git ls-remote --heads github
# expect: no refs (empty repository)

# 5) First push (NO --force)
git push -u github main

# 6) Do NOT push Cursor origin unless intentionally syncing the tmp remote
# git push origin …   # skip unless Cursor workflow requires it
```

**Forbidden:** `git push --force`, `git push --force-with-lease` to `main` on first publish, rewriting history, deleting `origin` without confirmation.

## Post-push verification checklist

- [ ] `https://github.com/Paulon34/ryoku-os` shows commits through publish tip (001–003 + prep)
- [ ] Default branch `main`; README renders PT + link to EN
- [ ] Actions tab: workflow `ci` runs and is green (no QEMU/KVM required)
- [ ] Issues templates visible; security advisory link opens under `Paulon34/ryoku-os`
- [ ] No `x-access-token` or PAT appears in GitHub UI, Actions logs, or README
- [ ] Repo description/topics optional: `linux`, `rust`, `os`, `qemu` (manual)
- [ ] Settings → Branches: protect `main` (PR + status checks when ready)
- [ ] Settings → Code security: enable Dependabot / secret scanning if desired
- [ ] Confirm `ryoku-desktop` and `ryoku-nixos` remain **separate** repos (unchanged)
- [ ] Cursor `origin` still present locally if the Cloud Agent needs it

## Rollback note

If the first push is wrong but history is fine: fix forward with a new commit.  
If the empty repo received an accidental wrong tree: coordinate before any force-push (not default).
