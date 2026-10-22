#!/usr/bin/env bash
# Focused prompt warning and install marker lifecycle tests. Uses fake CLI/code
# executables and isolated homes; never invokes the real VS Code CLI.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
pass() { printf '  ok  %s\n' "$*"; }

require() { command -v "$1" >/dev/null || fail "missing required command: $1"; }
require jq
require bash
require zsh

expected_rainbow=$(printf '\033[38;5;196mc\033[38;5;208mh\033[38;5;226mr\033[38;5;46mo\033[38;5;51mm\033[38;5;21ma\033[38;5;93mt\033[38;5;196mi\033[38;5;208mc\033[38;5;226ml\033[38;5;46mi\033[0m')
for shell in bash zsh; do
  # shellcheck disable=SC2016 # The child shell expands $1, not this test script.
  label=$("$shell" -c 'source "$1"; _chromaticli_rainbow_name' _ "$ROOT/hook.$shell")
  [[ "$label" == "$expected_rainbow" ]] || fail "$shell rainbow warning label did not match the fixed ANSI palette"
  pass "$shell fixed ANSI rainbow warning label"
done
if command -v fish >/dev/null; then
  # shellcheck disable=SC2016 # Fish expands $argv[1] in its child process.
  label=$(fish -c 'source $argv[1]; _chromaticli_rainbow_name' "$ROOT/hook.fish")
  [[ "$label" == "$expected_rainbow" ]] || fail 'fish rainbow warning label did not match the fixed ANSI palette'
  pass 'fish fixed ANSI rainbow warning label'
else
  echo '  skip fish rainbow label test (fish is not installed)'
fi

VERSION=$(sed -n 's/^CHROMATICLI_VERSION="\([^"]*\)".*/\1/p' "$ROOT/chromaticli")

run_hook_case() {
  local shell=$1 scenario=$2 marker_state=$3 reported=$4 expected=$5 path_kind=${6:-managed}
  local dir="$WORK/$shell-$scenario"
  mkdir -p "$dir/.config/chromaticli"
  local hookdir="$dir/.config/chromaticli"
  if [[ "$shell" == zsh ]]; then hookdir=$(cd "$hookdir" && pwd -P); fi
  cp "$ROOT/hook.$shell" "$dir/.config/chromaticli/hook.$shell"
  local cli_dir="$dir/.config/chromaticli"
  if [[ "$path_kind" == source ]]; then
    cli_dir="$dir/.local/bin"
    mkdir -p "$cli_dir"
  fi
  mkdir -p "$dir/conflict"
  cat > "$dir/conflict/chromaticli" <<EOF
#!/usr/bin/env bash
printf 'conflict\\n' >> '$dir/conflict-calls'
printf 'chromaticli 9.9.9\\n'
EOF
  chmod +x "$dir/conflict/chromaticli"
  cat > "$cli_dir/chromaticli" <<EOF
#!/usr/bin/env bash
printf 'call\\n' >> '$dir/version-calls'
case "\$1" in
  --version)
    [[ '${reported}' != FAIL ]] || exit 1
    printf '%s\\n' '${reported}' ;;
  install)
    [[ "\${2:-}" == --force ]] || exit 5
    [[ "\${CHROMATICLI_LIBEXEC:-}" == '$hookdir' ]] || exit 4
    printf '%s\\n' "\${CHROMATICLI_LIBEXEC}" >> '$dir/install-calls' ;;
  *) exit 3 ;;
esac
EOF
  chmod +x "$cli_dir/chromaticli"
  case "$marker_state" in
    missing) ;;
    current) printf '{"schema":1,"version":"%s"}\n' "$VERSION" > "$dir/.config/chromaticli/install-version.json" ;;
    stale) printf '{"schema":1,"version":"0.0.1"}\n' > "$dir/.config/chromaticli/install-version.json" ;;
    invalid) printf '{"schema":99,"version":"0.0.1"}\n' > "$dir/.config/chromaticli/install-version.json" ;;
  esac
  if [[ "$shell" == bash ]]; then
    cat > "$dir/.config/chromaticli/run.sh" <<'EOF'
#!/usr/bin/env bash
export HOME="$CASE_HOME" XDG_CONFIG_HOME="$CASE_HOME/.config" PATH="$CASE_HOME/conflict:$PATH"
source "$CASE_HOME/.config/chromaticli/hook.bash" >/dev/null 2>&1 || :
_chromaticli_apply() { :; }
_chromaticli_check_install_version
_chromaticli_check_install_version
EOF
    CASE_HOME="$dir" bash "$dir/.config/chromaticli/run.sh" > "$dir/out" 2>&1
  else
    cat > "$dir/.config/chromaticli/run.zsh" <<'EOF'
#!/usr/bin/env zsh
export HOME="$CASE_HOME" XDG_CONFIG_HOME="$CASE_HOME/.config" PATH="$CASE_HOME/conflict:$PATH"
source "$CASE_HOME/.config/chromaticli/hook.zsh" >/dev/null 2>&1 || :
_chromaticli_apply() { :; }
_chromaticli_check_install_version
_chromaticli_check_install_version
EOF
    CASE_HOME="$dir" zsh "$dir/.config/chromaticli/run.zsh" > "$dir/out" 2>&1
  fi
  local warnings calls
  warnings=$(grep -c '^\[WARN\]: chromaticli:' "$dir/out" || true)
  calls=0
  [[ ! -f "$dir/version-calls" ]] || calls=$(wc -l < "$dir/version-calls" | tr -d ' ')
  case "$expected" in
    stale)
      [[ "$warnings" == 1 ]] || fail "$shell/$scenario expected exactly one stale warning"
      [[ "$(head -n 1 "$dir/out")" == "" ]] || fail "$shell/$scenario warning did not have a leading blank line"
      ;;
    current) [[ "$warnings" == 0 ]] || fail "$shell/$scenario warned for a current marker" ;;
    unverifiable)
      [[ "$warnings" == 1 ]] || fail "$shell/$scenario expected one unverifiable warning"
      [[ "$(head -n 1 "$dir/out")" == "" ]] || fail "$shell/$scenario warning did not have a leading blank line"
      ;;
  esac
  # Calling the checker twice in one process must cache every outcome.
  [[ "$calls" == 1 || ( "$marker_state" == missing && "$calls" == 0 ) ]] \
    || fail "$shell/$scenario queried CLI $calls times"
  [[ ! -f "$dir/conflict-calls" ]] || fail "$shell/$scenario used the conflicting CLI from PATH"
  if [[ "$expected" == stale ]]; then
    if [[ "$path_kind" == source ]]; then
      grep -Fq "run \`chromaticli install --force\`" "$dir/out" \
        || fail "$shell/$scenario warning omitted the source checkout recovery command"
    else
      local recovery="run \`env CHROMATICLI_LIBEXEC=\"$hookdir\" \"$hookdir/chromaticli\" install --force\`"
      grep -Fq "$recovery" "$dir/out" \
        || fail "$shell/$scenario warning omitted the managed CLI recovery command"
      env CHROMATICLI_LIBEXEC="$hookdir" "$hookdir/chromaticli" install --force > "$dir/install-out" 2>&1 \
        || fail "$shell/$scenario managed recovery command failed against the fake CLI"
      grep -Fxq "$hookdir" "$dir/install-calls" \
        || fail "$shell/$scenario managed recovery did not preserve CHROMATICLI_LIBEXEC"
    fi
  fi
  pass "$shell $scenario warning and one-check cache"
}

for shell in bash zsh; do
  run_hook_case "$shell" missing missing "$VERSION" stale
  run_hook_case "$shell" current current "chromaticli $VERSION" current
  run_hook_case "$shell" stale stale "chromaticli $VERSION" stale
  run_hook_case "$shell" unparseable current 'not a version' unverifiable
  run_hook_case "$shell" unavailable current FAIL unverifiable
  run_hook_case "$shell" invalid invalid "chromaticli $VERSION" unverifiable
  run_hook_case "$shell" source-recovery stale "chromaticli $VERSION" stale source
done

if command -v fish >/dev/null; then
  run_fish_case() {
    local scenario=$1 marker_state=$2 reported=$3 expected=$4 path_kind=${5:-managed}
    local dir="$WORK/fish-$scenario"
    mkdir -p "$dir/.config/chromaticli"
    cp "$ROOT/hook.fish" "$dir/.config/chromaticli/hook.fish"
    local cli_dir="$dir/.config/chromaticli"
    if [[ "$path_kind" == source ]]; then
      cli_dir="$dir/.local/bin"
      mkdir -p "$cli_dir"
    fi
    mkdir -p "$dir/conflict"
    cat > "$dir/conflict/chromaticli" <<EOF
#!/usr/bin/env bash
printf 'conflict\\n' >> '$dir/conflict-calls'
printf 'chromaticli 9.9.9\\n'
EOF
    chmod +x "$dir/conflict/chromaticli"
    cat > "$cli_dir/chromaticli" <<EOF
#!/usr/bin/env bash
printf 'call\\n' >> '$dir/version-calls'
case "\$1" in
  --version)
    [[ '${reported}' != FAIL ]] || exit 1
    printf '%s\\n' '${reported}' ;;
  install)
    [[ "\${2:-}" == --force ]] || exit 5
    [[ "\${CHROMATICLI_LIBEXEC:-}" == '$dir/.config/chromaticli' ]] || exit 4
    printf '%s\\n' "\${CHROMATICLI_LIBEXEC}" >> '$dir/install-calls' ;;
  *) exit 3 ;;
esac
EOF
    chmod +x "$cli_dir/chromaticli"
    case "$marker_state" in
      missing) ;;
      current) printf '{"schema":1,"version":"%s"}\n' "$VERSION" > "$dir/.config/chromaticli/install-version.json" ;;
      stale) printf '{"schema":1,"version":"0.0.1"}\n' > "$dir/.config/chromaticli/install-version.json" ;;
      invalid) printf '{"schema":99,"version":"0.0.1"}\n' > "$dir/.config/chromaticli/install-version.json" ;;
    esac
    # shellcheck disable=SC2016 # Fish expands these variables in its child process.
    HOME="$dir" XDG_CONFIG_HOME="$dir/.config" PATH="$dir/conflict:$PATH" fish --no-config -c '
      source "$HOME/.config/chromaticli/hook.fish"
      functions -e _chromaticli_apply
      emit fish_prompt
      emit fish_prompt
    ' > "$dir/out" 2>&1
    local warnings calls
    warnings=$(grep -c '^\[WARN\]: chromaticli:' "$dir/out" || true)
    calls=0
    [[ ! -f "$dir/version-calls" ]] || calls=$(wc -l < "$dir/version-calls" | tr -d ' ')
    case "$expected" in
      stale)
        [[ "$warnings" == 1 ]] || fail "fish/$scenario expected one stale warning"
        [[ "$(head -n 1 "$dir/out")" == "" ]] || fail "fish/$scenario warning did not have a leading blank line"
        ;;
      current) [[ "$warnings" == 0 ]] || fail "fish/$scenario warned for a current marker" ;;
      unverifiable)
        [[ "$warnings" == 1 ]] || fail "fish/$scenario expected unverifiable warning"
        [[ "$(head -n 1 "$dir/out")" == "" ]] || fail "fish/$scenario warning did not have a leading blank line"
        ;;
    esac
    [[ "$calls" == 1 || ( "$marker_state" == missing && "$calls" == 0 ) ]] \
      || fail "fish/$scenario queried CLI $calls times"
    [[ ! -f "$dir/conflict-calls" ]] || fail "fish/$scenario used the conflicting CLI from PATH"
    if [[ "$expected" == stale ]]; then
      if [[ "$path_kind" == source ]]; then
        grep -Fq "run \`chromaticli install --force\`" "$dir/out" \
          || fail "fish/$scenario warning omitted the source checkout recovery command"
      else
        local recovery="run \`env CHROMATICLI_LIBEXEC=\"$dir/.config/chromaticli\" \"$dir/.config/chromaticli/chromaticli\" install --force\`"
        grep -Fq "$recovery" "$dir/out" \
          || fail "fish/$scenario warning omitted the managed CLI recovery command"
        env CHROMATICLI_LIBEXEC="$dir/.config/chromaticli" "$dir/.config/chromaticli/chromaticli" install --force > "$dir/install-out" 2>&1 \
          || fail "fish/$scenario managed recovery command failed against the fake CLI"
        grep -Fxq "$dir/.config/chromaticli" "$dir/install-calls" \
          || fail "fish/$scenario managed recovery did not preserve CHROMATICLI_LIBEXEC"
      fi
    fi
    pass "fish $scenario warning and one-check cache"
  }
  run_fish_case missing missing "$VERSION" stale
  run_fish_case current current "chromaticli $VERSION" current
  run_fish_case stale stale "chromaticli $VERSION" stale
  run_fish_case unparseable current 'not a version' unverifiable
  run_fish_case unavailable current FAIL unverifiable
  run_fish_case invalid invalid "chromaticli $VERSION" unverifiable
  run_fish_case source-recovery stale "chromaticli $VERSION" stale source
else
  printf '  skip fish hook cases (fish is not installed)\n'
fi
