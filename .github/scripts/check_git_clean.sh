#!/usr/bin/env bash
set -euo pipefail

# Usage: check_git_clean.sh [--allow-untracked] [--require-upstream] [--branch BRANCH]
# Examples:
#   ./check_git_clean.sh
#   ./check_git_clean.sh --allow-untracked
#   ./check_git_clean.sh --require-upstream --branch main

ALLOW_UNTRACKED=false
REQUIRE_UPSTREAM=false
BRANCH=""

# parse args (simple)
while [[ $# -gt 0 ]]; do
  case "$1" in
    --allow-untracked) ALLOW_UNTRACKED=true; shift ;;
    --require-upstream) REQUIRE_UPSTREAM=true; shift ;;
    --branch) BRANCH="$2"; shift 2 ;;
    -h|--help) echo "Usage: $0 [--allow-untracked] [--require-upstream] [--branch BRANCH]"; exit 0 ;;
    *) echo "Unknown arg: $1"; exit 2 ;;
  esac
done

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

# 1) ensure inside a git repository
if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  fail "Not inside a Git repository."
fi

# If branch specified, check we are on that branch
if [[ -n "$BRANCH" ]]; then
  cur_branch=$(git symbolic-ref --short HEAD 2>/dev/null || git rev-parse --short HEAD)
  if [[ "$cur_branch" != "$BRANCH" ]]; then
    fail "Current branch is '$cur_branch', expected '$BRANCH'."
  fi
fi

# Refresh index (plumbing) so git notices changes in working tree
# This is plumbing-level: updates the cached stat info used by 'git diff --quiet'
git update-index -q --refresh

# 2) check staged changes (index vs HEAD)
if ! git diff --cached --quiet; then
  echo
  echo "Uncommitted staged changes detected (index != HEAD)."
  echo "Run 'git status --porcelain' to inspect."
  echo
  git --no-pager status --porcelain
  fail "Please commit or stash staged changes before running CI."
fi

# 3) check unstaged changes (working tree vs index)
if ! git diff --quiet; then
  echo
  echo "Unstaged changes detected (working tree != index)."
  echo "Run 'git status --porcelain' to inspect."
  echo
  git --no-pager status --porcelain
  fail "Please stash/commit or discard unstaged changes before running CI."
fi

# 4) check untracked files
if [[ "$ALLOW_UNTRACKED" != "true" ]]; then
  # list untracked files, ignoring files in .gitignore via --exclude-standard
  untracked=$(git ls-files --others --exclude-standard)
  if [[ -n "$untracked" ]]; then
    echo
    echo "Untracked files present:"
    echo "$untracked"
    fail "Please add/ignore or remove untracked files before running CI, or pass --allow-untracked."
  fi
fi

# 5) check upstream synchronization (optional)
if [[ "$REQUIRE_UPSTREAM" == "true" ]]; then
  # find upstream of current branch
  # git rev-parse --abbrev-ref @{u} fails if no upstream
  if ! upstream=$(git rev-parse --abbrev-ref --symbolic-full-name @{u} 2>/dev/null); then
    fail "No upstream configured for current branch. Set upstream (git push -u ...) or don't use --require-upstream."
  fi

  # get ahead/behind counts
  # output format: "<behind> <ahead>"
  read behind ahead < <(git rev-list --left-right --count "${upstream}...HEAD" 2>/dev/null || echo "0 0")

  if [[ "$behind" -ne 0 ]]; then
    echo "Local branch is behind upstream by $behind commits."
    fail "Please pull/rebase to synchronize with upstream before running CI."
  fi
  if [[ "$ahead" -ne 0 ]]; then
    echo "Local branch has $ahead commits not pushed to upstream."
    fail "Please push commits before running CI (or don't use --require-upstream)."
  fi
fi

echo "OK: working tree is clean."
exit 0
