# Agent Skills

A collection of reusable agent skills. Currently home to one skill:

## [`create-github-project-issues`](skills/create-github-project-issues/)

Bulk-create GitHub issues from a plan, backlog, or task list and place them on a GitHub Project board — with assignee, issue type (Feature/Bug/Task), and status — using a single `gh`-based script.

- Extracts-ready: feed it a simple `title|body` tasks file (e.g. from `grep "^### Task" plan.md`)
- Creates **real issues** (not draft items), so assignees and org issue types work
- Adds each issue to an org project and sets its `Status` single-select field
- Preflight-checks `gh` auth scopes and tells you the exact `gh auth refresh` command if `project` scope is missing

### Requirements

- [`gh`](https://cli.github.com/) CLI, authenticated with `repo`, `read:org`, and `project` scopes:

  ```bash
  gh auth refresh -s read:project -s project -h github.com
  ```

### Quick start

```bash
# tasks file: one issue per line — title|body
cat > /tmp/tasks.txt << 'EOF'
Create database schema and models|Foundation tables, enums, and models.
Build token endpoint|POST /api/v1/token with distinguishable 403 on mismatch.
EOF

create_issues.sh \
  --repo OWNER/REPO --project 36 --owner ORG \
  --prefix "[MyProject]" --assignee USER \
  --type Feature --status "Todo" \
  --tasks /tmp/tasks.txt
```

Run with `--dry-run` first to preview. Full flags and gotchas are documented in the [SKILL.md](skills/create-github-project-issues/SKILL.md).

## Installation

Install with the Agent Skills CLI (single skill):

```bash
npx skills add iz-ahmad/agent-skills --skill create-github-project-issues
```

Or manually copy the skill folder into your agent's skills directory:

```bash
git clone https://github.com/iz-ahmad/agent-skills.git
cp -r agent-skills/skills/create-github-project-issues ~/.agents/skills/
```

Works with any agent that reads SKILL.md-style skills.

## License

MIT
