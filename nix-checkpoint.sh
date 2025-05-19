root=$(git rev-parse --show-toplevel)
trap 'cd $(pwd)' EXIT
cd "$root" || exit
git add --all >/dev/null

system=$(nix eval --impure --raw --expr 'builtins.currentSystem')

start=$(date +%s)
flake_details=$(nix flake show --json)
echo "[$(($(date +%s) - start))s] nix flake show"

packages=$(
  echo "$flake_details" |
    jq --raw-output ".packages[\"$system\"] | keys | .[]" 2>/dev/null ||
    true
)

snapshots=$(echo "$packages" | grep '^snapshot-' || true)
if [ -n "$snapshots" ]; then
  for snapshot in $snapshots; do

    start=$(date +%s)
    result=$(nix build --no-link --print-out-paths ".#$snapshot")
    echo "[$(($(date +%s) - start))s] nix build .#$snapshot"

    files=$(find -L "$result" -type f -printf '%P\n')
    for file in $files; do
      mkdir -p "$(dirname "$file")"
      cp -L "$result/$file" "$file"
      chmod 644 "$file"
    done
  done
fi

new_files=$(git diff --cached --name-only --diff-filter=A)
new_files_hashed=$(echo "$new_files" | md5sum | cut -d' ' -f1)
if [ -n "$new_files" ] && [ ! -f "/tmp/$new_files_hashed" ]; then
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
  touch "/tmp/$new_files_hashed"
fi

git add --all >/dev/null

fix_apps=$(
  echo "$flake_details" |
    jq --raw-output ".apps[\"$system\"][\"fix\"] | keys | .[]" 2>/dev/null ||
    true
)
fix_packages=$(
  echo "$flake_details" |
    jq --raw-output ".packages[\"$system\"][\"fix\"] | keys | .[]" 2>/dev/null ||
    true
)
if [ -n "$fix_apps" ] || [ -n "$fix_packages" ]; then
  start=$(date +%s)
  nix run ".#fix"
  echo "[$(($(date +%s) - start))s] nix run .#fix"
fi

has_formatter=$(echo "$flake_details" |
  jq ".formatter[\"$system\"]" 2>/dev/null || true)
if [ -n "$has_formatter" ] && [ "$has_formatter" != "null" ]; then
  start=$(date +%s)
  nix fmt
  echo "[$(($(date +%s) - start))s] nix fmt"
fi

git add --all >/dev/null

start=$(date +%s)
nix flake check --quiet || (git reset >/dev/null && exit 1)
echo "[$(($(date +%s) - start))s] nix flake check"

start=$(date +%s)
timeout 10 ai-commit --auto-commit >/dev/null 2>&1 ||
  git commit --edit --message "checkpoint"
echo "[$(($(date +%s) - start))s] ai-commit"

rm "/tmp/$new_files_hashed" 2>/dev/null || true

start=$(date +%s)
git pull --quiet --rebase
echo "[$(($(date +%s) - start))s] git pull"

start=$(date +%s)
git push --quiet
echo "[$(($(date +%s) - start))s] git push"

gcroot_exists=$(
  echo "$flake_details" |
    jq --raw-output ".packages[\"$system\"] | has(\"gcroot\")"
)
if [ "$gcroot_exists" = "true" ]; then
  start=$(date +%s)
  nix build --out-link .gcroot .#gcroot
  echo "[$(($(date +%s) - start))s] nix build .#gcroot"
fi

notify-send --urgency=low "Finished running nix-checkpoint" >/dev/null 2>&1 || true
