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
- Large boards: use `--limit 300` on `item-list` (default truncates at 30).

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
| `--status NAME` | no | single-select project Status value (e.g. Todo) |
| `--dry-run` | no | show what would be created |

Safe to re-run: it creates new issues each time (no dedup); check the project
first if unsure. Adding `Source:` links to the plan doc in bodies is
recommended for traceability.
