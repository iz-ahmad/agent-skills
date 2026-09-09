#!/bin/bash
# Bulk-create GitHub issues and add them to a GitHub Project with
# assignee, issue type, and status. See ../SKILL.md for usage.
#
# Tasks file format: one issue per line -> title|body
#   (body may contain no pipe characters; empty body allowed: "title|")

set -u

REPO="" PROJECT="" OWNER="" TASKS_FILE="" PREFIX="" ASSIGNEE="" TYPE_NAME="" STATUS_NAME="" STATUS_FIELD="Status" DRY_RUN=0 ASSUME_YES=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) REPO="$2"; shift 2 ;;
    --project) PROJECT="$2"; shift 2 ;;
    --owner) OWNER="$2"; shift 2 ;;
    --tasks) TASKS_FILE="$2"; shift 2 ;;
    --prefix) PREFIX="$2"; shift 2 ;;
    --assignee) ASSIGNEE="$2"; shift 2 ;;
    --type) TYPE_NAME="$2"; shift 2 ;;
    --status) STATUS_NAME="$2"; shift 2 ;;
    --status-field) STATUS_FIELD="$2"; shift 2 ;;
    --dry-run) DRY_RUN=1; shift ;;
    --yes|-y) ASSUME_YES=1; shift ;;
    *) echo "unknown flag: $1" >&2; exit 1 ;;
  esac
done

die() { echo "ERROR: $*" >&2; exit 1; }

[[ -n "$REPO" && -n "$PROJECT" && -n "$OWNER" && -n "$TASKS_FILE" ]] \
  || die "required: --repo OWNER/REPO --project N --owner ORG --tasks FILE"
[[ -f "$TASKS_FILE" ]] || die "tasks file not found: $TASKS_FILE"
command -v gh >/dev/null || die "gh CLI not installed"

# --- Preflight: auth scopes -------------------------------------------------
SCOPES=$(gh auth status 2>&1 | grep -i "scopes" || true)
echo "== Auth: ${SCOPES:-not logged in}"
MISSING=0
for s in repo read:org project; do
  echo "$SCOPES" | grep -qw "$s" || { echo "   missing scope: $s"; MISSING=1; }
done
[[ $MISSING -eq 1 ]] && die "run: gh auth refresh -s read:project -s project -h github.com (then re-run)"
gh project view "$PROJECT" --owner "$OWNER" >/dev/null 2>&1 || die "cannot access project $PROJECT owned by $OWNER"

# --- Resolve IDs -------------------------------------------------------------
echo "== Resolving IDs..."
PROJ_ID=$(gh project view "$PROJECT" --owner "$OWNER" --format json --jq .id)

TYPE_ID=""
if [[ -n "$TYPE_NAME" ]]; then
  TYPE_ID=$(gh api graphql -f query='query($o: String!) { organization(login: $o) { issueTypes(first: 50) { nodes { id name } } } }' -f o="$OWNER" \
    --jq ".data.organization.issueTypes.nodes[] | select(.name == \"$TYPE_NAME\") | .id" | head -1)
  [[ -n "$TYPE_ID" ]] || die "issue type '$TYPE_NAME' not found. Note: issue types are org-only — user-owned projects must omit --type"
fi

FIELD_ID="" OPT_ID=""
if [[ -n "$STATUS_NAME" ]]; then
  FIELD_ID=$(gh project field-list "$PROJECT" --owner "$OWNER" --format json \
    --jq ".fields[] | select(.name == \"$STATUS_FIELD\") | .id" | head -1)
  [[ -n "$FIELD_ID" ]] || die "project has no '$STATUS_FIELD' field (customize with --status-field NAME)"
  OPT_ID=$(gh project field-list "$PROJECT" --owner "$OWNER" --format json \
    --jq ".fields[] | select(.name == \"$STATUS_FIELD\") | .options[] | select(.name == \"$STATUS_NAME\") | .id" | head -1)
  [[ -n "$OPT_ID" ]] || die "option '$STATUS_NAME' not found on field '$STATUS_FIELD'"
fi

ASSIGNEE_FLAGS=()
[[ -n "$ASSIGNEE" ]] && ASSIGNEE_FLAGS=(--assignee "$ASSIGNEE")

COUNT=$(grep -c . "$TASKS_FILE")
echo "== Will create $COUNT issue(s) in $REPO, add to project $PROJECT ($OWNER), prefix='${PREFIX:-none}' assignee=${ASSIGNEE:-none} type=${TYPE_NAME:-none} status=${STATUS_NAME:-none} (field: $STATUS_FIELD)"
[[ $DRY_RUN -eq 1 ]] && echo "(dry-run; would create:)" && sed 's/|.*//' "$TASKS_FILE" && exit 0

# --- Confirmation gate: never bulk-create silently ---------------------------
if [[ $ASSUME_YES -ne 1 ]]; then
  if [[ -t 0 ]]; then
    read -r -p "Proceed? [y/N] " ANS
    [[ "$ANS" == "y" || "$ANS" == "Y" ]] || { echo "aborted"; exit 1; }
  else
    die "non-interactive shell: pass --yes to confirm bulk issue creation (try --dry-run first)"
  fi
fi

# --- Create issues -----------------------------------------------------------
OK=0; FAILED=0
while IFS='|' read -r TITLE BODY; do
  [[ -z "${TITLE// }" ]] && continue
  FULL_TITLE="${PREFIX:+$PREFIX }$TITLE"
  URL=$(gh issue create --repo "$REPO" --title "$FULL_TITLE" --body "${BODY:-}" "${ASSIGNEE_FLAGS[@]:-}" 2>&1)
  if [[ "$URL" != http* ]]; then echo "FAIL create: $FULL_TITLE -> $URL"; FAILED=$((FAILED+1)); continue; fi
  N=$(basename "$URL")

  if [[ -n "$TYPE_ID" ]]; then
    NODE=$(gh api "repos/$REPO/issues/$N" --jq .node_id)
    gh api graphql -f query='mutation($id:ID!,$tid:ID!){ updateIssue(input:{id:$id, issueTypeId:$tid}){ issue { number } } }' \
      -f id="$NODE" -f tid="$TYPE_ID" >/dev/null || echo "WARN: type not set on #$N"
  fi

  ITEM_ID=$(gh project item-add "$PROJECT" --owner "$OWNER" --url "$URL" --format json --jq .id)
  if [[ -z "$ITEM_ID" ]]; then echo "FAIL project-add #$N"; FAILED=$((FAILED+1)); continue; fi

  if [[ -n "$OPT_ID" ]]; then
    gh project item-edit --id "$ITEM_ID" --project-id "$PROJ_ID" \
      --field-id "$FIELD_ID" --single-select-option-id "$OPT_ID" >/dev/null \
      || echo "WARN: status not set on #$N"
  fi

  echo "OK #$N — $FULL_TITLE"
  OK=$((OK+1))
done < "$TASKS_FILE"

echo "== Done: $OK ok, $FAILED failed"
[[ $FAILED -eq 0 ]]
