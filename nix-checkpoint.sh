flag=${1:-}

root=$(git rev-parse --show-toplevel)
trap 'cd $(pwd)' EXIT
cd "$root" || exit
git add --all >/dev/null

system=$(nix eval --impure --raw --expr 'builtins.currentSystem')

flake_details=$(nix flake show --json)

packages=$(
  echo "$flake_details" |
    jq --raw-output ".packages[\"$system\"] | keys | .[]" 2>/dev/null ||
    true
)

create_snapshot() {
  start=$(date +%s)
  result=$(nix build --no-link --print-out-paths ".#$1")
  files=$(find -L "$result" -type f -printf '%P\n')
  for file in $files; do
    mkdir -p "$(dirname "$file")"
    cp -L "$result/$file" "$file"
    chmod 644 "$file"
  done
  echo "$snapshot created successfully in $(($(date +%s) - start))s"
}

snapshots=$(echo "$packages" | grep '^snapshot-' || true)
if [ -n "$snapshots" ]; then
  pids=""
  for snapshot in $snapshots; do
    create_snapshot "$snapshot" &
    pids="$pids $!"
  done
  for pid in $pids; do
    wait "$pid" || exit 1
  done
fi

if [ "$flag" = "--snapshot" ]; then
  git reset >/dev/null
  exit 0
fi

new_files=$(git diff --cached --name-only --diff-filter=A)
if [ -n "$new_files" ]; then
  echo "New file(s) detected!"
  echo
  echo "$new_files"
  echo
  printf "Are you sure this file(s) are neccessary? [y/n]: "
  read -r answer
  last_char=${answer#"${answer%?}"}
  if [ "$last_char" != "y" ]; then
    echo "Aborted"
    git reset >/dev/null
    exit 1
  fi
fi

git add --all >/dev/null

if [ "$flag" = "--no-fix" ]; then
  exit 0
fi

fix=$(
  echo "$flake_details" |
    jq --raw-output ".apps[\"$system\"][\"fix\"] | keys | .[]" 2>/dev/null ||
    true
)
if [ -n "$fix" ]; then
  start=$(date +%s)
  nix run ".#fix"
  echo "nix run .#fix finished successfully in $(($(date +%s) - start))s"
fi

if [ "$flag" = "--fix" ] || [ "$flag" = "--no-fmt" ]; then
  git reset >/dev/null
  exit 0
fi

auto-follow --in-place
auto-follow --check >/dev/null

has_formatter=$(echo "$flake_details" |
  jq ".formatter[\"$system\"]" 2>/dev/null || true)
if [ -n "$has_formatter" ] && [ "$has_formatter" != "null" ]; then
  start=$(date +%s)
  nix fmt
  echo "nix fmt finished successfully in $(($(date +%s) - start))s"
fi

if [ "$flag" = "--fmt" ] || [ "$flag" = "--no-check" ]; then
  git reset >/dev/null
  exit 0
fi

start=$(date +%s)
git add --all >/dev/null
nix flake check --quiet || (git reset >/dev/null && exit 1)
echo "nix flake check finished successfully in $(($(date +%s) - start))s"

if [ "$flag" = "--check" ] || [ "$flag" = "--no-commit" ]; then
  git reset >/dev/null
  exit 0
fi

start=$(date +%s)

timeout 10 ai-commit --auto-commit >/dev/null 2>&1 ||
  git commit --edit --message "checkpoint"

echo "Commit message generated successfully in $(($(date +%s) - start))s"

if [ "$flag" = "--commit" ] || [ "$flag" = "--no-push" ]; then
  exit 0
fi

start=$(date +%s)

git pull --quiet --rebase
git push --quiet

echo "Respository pushed successfully in $(($(date +%s) - start))s"

if [ "$flag" = "--push" ] || [ "$flag" = "--no-gcroot" ]; then
  exit 0
fi

# if "gcroot" is in packages
if [ -n "$(echo "$packages" | grep '^gcroot$' || true)" ]; then
  rm -rf .gcroot
  mkdir -p .gcroot
  branch_name=$(git branch --show-current)
  for gcroot in $gcroots; do
    nohup nix build --out-link ".gcroot/$branch_name" .#gcroot </dev/null >/dev/null 2>&1 &
  done

  # delete if there is gcroots for branch that doesn't exist locally anymore
  gcroots=$(find .gcroot -mindepth 1 -maxdepth 1)
  for gcroot in $gcroots; do
    branch_name=$(basename "$gcroot")
    if ! git show-ref --verify --quiet "refs/heads/$branch_name"; then
      echo "Deleting $gcroot"
      rm -rf "$gcroot"
    fi
  done
fi
