---
name: create-github-project-issues
description: Create GitHub issues from a plan/task list and add them to a GitHub Project (org) with assignee, issue type, and status via gh CLI. Use when the user asks to create issues/TODOs/tasks in a GitHub project board from a plan doc, backlog, or checklist, or mentions gh project item-add/item-edit, populating a project board, or bulk-creating issues.
---

# GitHub Project Issues

Bulk-create real GitHub issues from a plan/task list and place them on a GitHub
Project board with assignee, issue type, and status — all via `gh`.

## Quick start

```bash
# 1. Extract tasks from a plan doc (adjust the heading pattern as needed)
grep -n "^### Task" docs/plans/my-plan.md

# 2. Write a tasks file: one line per issue, format: title|body
cat > /tmp/tasks.txt << 'EOF'
Create database schema and models|Foundation tables, enums, models with factories.
Build token endpoint|POST /api/v1/token with distinguishable 403 on mismatch.
EOF

# 3. Run the script
~/.agents/skills/create-github-project-issues/scripts/create_issues.sh \
  --repo OWNER/REPO --project 36 --owner ORG \
  --prefix "[MyProject]" --assignee USER \
  --type Feature --status "Todo" \
  --tasks /tmp/tasks.txt
```

## Workflow

1. **Auth check** (script does this, but fix manually if it fails):
   ```bash
   gh auth status | grep scopes
   ```
   Needs `repo`, `read:org`, `project`. If `project` scope is missing, run:
   `gh auth refresh -s read:project -s project -h github.com`
   (device-code flow: user must open https://github.com/login/device and enter
   the one-time code; the code is printed by the command).
2. **Extract tasks** from the source doc (`grep "### Task"`, checklist items,
   or a user-provided list). Write one `title|body` line per issue to a file.
3. **Run `scripts/create_issues.sh`** — it resolves IDs, creates issues, sets
   issue type, adds them to the project, sets status, and prints a summary.
4. **Verify** (script prints per-issue status; spot-check with):
   ```bash
   gh project item-list 36 --owner ORG --limit 300
   gh api repos/OWNER/REPO/issues/N --jq '"\(.number) \(.assignees[].login) \(.type.name)"'
   ```

## Critical gotchas (learned the hard way)

- **Draft items vs real issues**: `gh project item-create --title/--body` makes
  DRAFT items — they cannot have assignees or issue types. For assignee/type,
  create real issues (`gh issue create`), then `gh project item-add --url`.
- **No `--type` flag** on `gh issue create`. Set it via GraphQL `updateIssue`
  with `issueTypeId` (org issue types from `organization.issueTypes`).
- **`item-edit` takes IDs, not names**: needs `--project-id` (project node ID
  from `gh project view N --format json --jq .id`), `--field-id`, and
  `--single-select-option-id` from `gh project field-list`. There is NO
  `--project` / `--field` / `--value` flag.
- **Project number is positional** for `item-create`, `item-add`,
  `item-delete` — not `--project N`.
- **`item-list` JSON can be stale/wrong** for assignee and type — verify via
  the repo issues REST API instead.
- Deleting draft items: `gh project item-delete N --owner ORG --id <item-id>`.
  **Destructive — the only delete in this workflow.** Only ever pass an item ID
  you just looked up via `item-list` and matched by exact title; never a
  guessed/recycled ID.
- Large boards: use `--limit 300` on `item-list` (default truncates at 30).

## Risks and safety rules

- **The script is create-only** — it never deletes, closes, or edits existing
  issues/items. The `updateIssue` GraphQL mutation is applied ONLY to issues
  the script just created; never reuse that snippet against existing issues
  (it would overwrite their type).
- **NOT idempotent** — re-running creates duplicate issues every time. Always
  `--dry-run` first, and check the project/board for existing equivalent
  issues before a real run.
- **Confirmation gate** — the script prompts before bulk-creating on a TTY and
  refuses to run non-interactively without `--yes`. Agents should always run
  `--dry-run` first and show the user the plan before passing `--yes`.
- **Partial failure has no rollback** — if run N of M issues fails mid-way,
  earlier issues stay created. Check the summary line; clean up manually only
  with explicit user approval.
- **Scope changes are auth-sensitive** — `gh auth refresh` only ADDS scopes
  via an interactive device flow; it does not rotate the token. Never ask for
  broader scopes than `read:project` + `project`.
- **Wrong target = real damage surface** — a wrong `--repo`/`--project` pair
  litters the wrong board. The pre-run echo shows resolved repo/project/issue
  count; read it before confirming.

## Portability notes (any project)

- **Org vs user-owned projects**: `--type` uses org issue types
  (`organization.issueTypes`) — orgs only. For a **user-owned** project,
  omit `--type` (and use `--owner <username>`).
- **Custom field names**: status field defaults to `Status`; override with
  `--status-field NAME` when the board uses a different single-select field.
- **Tasks file limits**: one issue per line; `|` separates title and body, so
  bodies cannot contain pipes or line breaks. Use `%0A` in body text if a
  line break is needed; anything richer needs manual issue creation.
- **Repo ≠ project owner is fine** — issues may live in any repo the token can
  write while the project is owned by another org/user.
- **macOS bash 3.2 compatible**; no Linux-only tools used. Windows requires
  WSL/git-bash.

## Script reference

`scripts/create_issues.sh` flags:

| Flag | Required | Notes |
|------|----------|-------|
| `--repo OWNER/REPO` | yes | where issues are created |
| `--project N` | yes | project number (positional-equivalent) |
| `--owner ORG` | yes | project owner (org login) |
| `--tasks FILE` | yes | `title\|body` lines |
| `--prefix TEXT` | no | prefixed to every title |
| `--assignee LOGIN` | no | set on every issue |
| `--type NAME` | no | org issue type (e.g. Feature, Bug, Task) |
| `--status NAME` | no | single-select status value (e.g. Todo) |
| `--status-field NAME` | no | status field name (default: `Status`) |
| `--dry-run` | no | show what would be created — always run this first |
| `--yes` / `-y` | no | skip confirmation (required non-interactively) |

The script is create-only and never modifies existing issues, but it is
**not idempotent** — re-running duplicates all issues. Dry-run first, and add
`Source:` links to the plan doc in bodies for traceability.
