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
  for snapshot in $snapshots; do
    create_snapshot "$snapshot" &
  done
  wait
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
nix-fast-build --skip-cached --flake ".#checks.$system" || (git reset >/dev/null && exit 1)
nix flake check --quiet || (git reset >/dev/null && exit 1)
echo "nix flake check finished successfully in $(($(date +%s) - start))s"

if [ "$flag" = "--check" ] || [ "$flag" = "--no-commit" ]; then
  git reset >/dev/null
  exit 0
fi

start=$(date +%s)

openai_api_key=${OPENAI_API_KEY:-}
if [ -f ./openai_api_key ]; then
  openai_api_key="$(cat ./openai_api_key)"
fi

if [ -z "$openai_api_key" ]; then
  echo "OPENAI_API_KEY environment variable or openai_api_key file is required"
  exit 1
fi

OPENAI_API_KEY="$openai_api_key" \
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

nixosConfigurations=$(
  echo "$flake_details" |
    jq --raw-output ".nixosConfigurations | keys | .[]" 2>/dev/null ||
    true
)
package_gcroots=$(echo "$packages" | grep '^gcroot-' || true)
nixosConfiguration_gcroots=$(
  echo "$nixosConfigurations" |
    grep '^gcroot-' |
    sed 's/^/.nixosConfigurations./g' |
    sed 's/$/.config.system.build.toplevel/g' ||
    true
)
gcroots="$package_gcroots $nixosConfiguration_gcroots"
if [ -n "$gcroots" ]; then
  rm -rf .gcroot
  mkdir -p .gcroot
  for gcroot in $gcroots; do
    start=$(date +%s)
    nix build --out-link ".gcroot/$gcroot" .#"$gcroot"
    echo "GC root $gcroot created successfully in $(($(date +%s) - start))s"
  done
fi
