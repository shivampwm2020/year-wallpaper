#!/usr/bin/env bash
# One-shot: build, then create a PRIVATE GitHub repo and push, using the gh CLI.
#
#   ./PUBLISH.sh
#
# Requires the GitHub CLI, authenticated once with:  gh auth login
# Install if needed:                                brew install gh
set -euo pipefail

REPO="$(cd "$(dirname "$0")" && pwd)"
GH_USER="shivampwm2020"
GH_REPO="year-wallpaper"

cd "$REPO"

# --- 0. check gh is present and authenticated ------------------------------
if ! command -v gh >/dev/null 2>&1; then
  echo "gh CLI not found." >&2
  echo "  brew install gh      # or: https://cli.github.com" >&2
  echo "  gh auth login" >&2
  exit 1
fi

if ! gh auth status >/dev/null 2>&1; then
  echo "gh is installed but not logged in. Run:" >&2
  echo "  gh auth login" >&2
  exit 1
fi

echo "==> gh authenticated as $(gh api user --jq .login 2>/dev/null || echo '?')"

# --- 1. clear a stale lock from an interrupted git run ----------------------
if [[ -e .git/index.lock ]]; then
  echo "Removing stale .git/index.lock left by an interrupted git run"
  rm -f .git/index.lock
fi

# --- 2. compile before publishing anything ---------------------------------
echo
# If the repo already has commits, skip the rebuild so a re-run is quick.
# On first run there is no HEAD, so build.
if ! git rev-parse HEAD >/dev/null 2>&1; then
  echo "==> Building (this proves the source compiles)"
  ./scripts/build.sh
else
  echo "==> Repo already has commits; skipping rebuild"
fi

# --- 3. git init + first commit --------------------------------------------
echo
echo "==> Initialising repository"
if [[ ! -d .git ]]; then
  git init -q
fi
# git init may have created a 'master' HEAD depending on version
if git symbolic-ref HEAD >/dev/null 2>&1; then
  git symbolic-ref HEAD refs/heads/main
fi
git add -A
git -c user.name="$(git config --global user.name || echo "$GH_USER")" \
    -c user.email="$(git config --global user.email || echo "$GH_USER@users.noreply.github.com")" \
    commit -q -m "YearWallpaper: a wallpaper that fills in as the year passes" 2>/dev/null \
  || echo "   (nothing new to commit)"

echo "   $(git rev-list --count HEAD) commit, $(git ls-files | wc -l | tr -d ' ') files"

# --- 4. create the private repo if needed, and push -------------------------
echo
if git remote get-url origin >/dev/null 2>&1; then
  echo "==> Remote 'origin' already set: $(git remote get-url origin)"
  echo "==> Pushing"
  git push -u origin main
else
  echo "==> Creating private repo $GH_USER/$GH_REPO and pushing"
  # --source=. sets 'origin' for us; --push pushes the current branch.
  # If the repo already exists on GitHub, gh errors out -- so fall back to
  # attaching to it rather than failing the whole script.
  if gh repo create "$GH_REPO" --private --source=. --remote=origin --push \
       --description "macOS wallpaper: a year in pixels, one cell per day"; then
    :
  else
    echo
    echo "gh repo create failed -- it may already exist on GitHub. Trying to attach:"
    gh repo view "$GH_USER/$GH_REPO" >/dev/null 2>&1 || {
      echo "Cannot see $GH_USER/$GH_REPO either. Check the error above." >&2
      exit 1
    }
    git remote add origin "https://github.com/$GH_USER/$GH_REPO.git"
    git push -u origin main
  fi
fi

echo
echo "Done: $(gh repo view "$GH_USER/$GH_REPO" --json url --jq .url 2>/dev/null || echo "https://github.com/$GH_USER/$GH_REPO")"
gh repo view "$GH_USER/$GH_REPO" --json visibility --jq '"Visibility: " + .visibility' 2>/dev/null || true
