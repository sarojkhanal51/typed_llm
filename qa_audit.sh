#!/usr/bin/env bash
#
# qa_audit.sh — release-readiness audit for the typed_llm monorepo.
#
# Runs every gate that stands between the working tree and a publish, writes a
# machine-readable summary plus a log per check, and exits non-zero if any
# check FAILs.
#
#   ./qa_audit.sh              # audit every package
#   ./qa_audit.sh typed_llm    # audit one package
#
# Output:
#   .qa_report/summary.tsv          STATUS<TAB>CHECK<TAB>SCOPE<TAB>DETAIL<TAB>LOG
#   .qa_report/<check>.<scope>.log  full output of each check
#   .qa_report/lowest_coverage.log  per-file line coverage, worst first
#
# Severities:
#   FAIL  blocks a release. Exit code 1.
#   WARN  needs a human decision; does not block.
#   PASS  clean.
#   SKIP  not applicable to this package.
#
# Tunables (environment):
#   COVERAGE_MIN=90      minimum per-package line coverage %
#   COVERAGE_FILE_MIN=75 minimum per-file line coverage % for files under test
#   STRICT_WARN=0        set to 1 to make WARN block like FAIL
#
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$REPO_ROOT"

REPORT_DIR="$REPO_ROOT/.qa_report"
SUMMARY="$REPORT_DIR/summary.tsv"

COVERAGE_MIN="${COVERAGE_MIN:-90}"
COVERAGE_FILE_MIN="${COVERAGE_FILE_MIN:-75}"
STRICT_WARN="${STRICT_WARN:-0}"

FAIL_COUNT=0
WARN_COUNT=0
PASS_COUNT=0
SKIP_COUNT=0

if [[ -t 1 ]]; then
  C_RED=$'\033[31m'; C_YEL=$'\033[33m'; C_GRN=$'\033[32m'
  C_DIM=$'\033[2m';  C_BLD=$'\033[1m';  C_OFF=$'\033[0m'
else
  C_RED=""; C_YEL=""; C_GRN=""; C_DIM=""; C_BLD=""; C_OFF=""
fi

rm -rf "$REPORT_DIR"
mkdir -p "$REPORT_DIR"
printf 'STATUS\tCHECK\tSCOPE\tDETAIL\tLOG\n' > "$SUMMARY"

# Python helpers live in files rather than inline heredocs: a heredoc nested
# inside $(...) is mis-parsed by bash 3.2, which is what macOS ships.
HELPER_DESC="$REPORT_DIR/_pubspec_description.py"
HELPER_COV="$REPORT_DIR/_lcov_summary.py"
HELPER_OUTDATED="$REPORT_DIR/_outdated_summary.py"

cat > "$HELPER_OUTDATED" <<'PY'
"""Print "<stale> <bump>" for a `dart pub outdated --json` report.

stale = direct deps behind what `pub upgrade` would pick under the existing
        constraints (a lockfile that has drifted; free to fix).
bump  = direct deps where only a wider constraint would reach the newer
        version (a major-version decision; informational).
"""
import json
import sys

try:
    data = json.load(open(sys.argv[1]))
except Exception:
    print('? ?')
    raise SystemExit(0)


def version(entry, key):
    value = entry.get(key) or {}
    return value.get('version')


stale, bump = [], []
for entry in data.get('packages', []):
    current = version(entry, 'current')
    upgradable = version(entry, 'upgradable')
    resolvable = version(entry, 'resolvable')
    if not current:
        continue
    if upgradable and upgradable != current:
        stale.append('%s %s -> %s' % (entry['package'], current, upgradable))
    elif resolvable and resolvable != current:
        bump.append('%s %s -> %s (needs a constraint change)'
                    % (entry['package'], current, resolvable))

for line in stale:
    print('STALE  ' + line, file=sys.stderr)
for line in bump:
    print('BUMP   ' + line, file=sys.stderr)
print('%d %d' % (len(stale), len(bump)))
PY

cat > "$HELPER_DESC" <<'PY'
"""Print a pubspec's description as a single line (folded scalars included)."""
import re
import sys

source = open(sys.argv[1]).read()
folded = re.search(r'^description:\s*>-\s*\n((?:[ \t]+.*\n)+)', source, re.M)
if folded:
    print(' '.join(l.strip() for l in folded.group(1).strip().splitlines()))
else:
    plain = re.search(r'^description:\s*(.+)$', source, re.M)
    print(plain.group(1).strip().strip('"\'') if plain else '')
PY

cat > "$HELPER_COV" <<'PY'
"""Summarise an lcov file: append per-file coverage, print totals as KEY=VALUE."""
import sys

lcov_path, package, out_path = sys.argv[1], sys.argv[2], sys.argv[3]

records, current = [], None
for line in open(lcov_path):
    line = line.strip()
    if line.startswith('SF:'):
        current = {'file': line[3:], 'lf': 0, 'lh': 0}
    elif line.startswith('LF:') and current:
        current['lf'] = int(line[3:])
    elif line.startswith('LH:') and current:
        current['lh'] = int(line[3:])
    elif line == 'end_of_record' and current:
        records.append(current)
        current = None

total_lf = sum(r['lf'] for r in records)
total_lh = sum(r['lh'] for r in records)
total_pct = (100.0 * total_lh / total_lf) if total_lf else 0.0

for r in records:
    r['pct'] = (100.0 * r['lh'] / r['lf']) if r['lf'] else 100.0
records.sort(key=lambda r: (r['pct'], -r['lf']))

with open(out_path, 'a') as fh:
    fh.write('\n# %s - total %.1f%% (%d/%d lines)\n'
             % (package, total_pct, total_lh, total_lf))
    for r in records:
        name = r['file'].split('/lib/')[-1]
        fh.write('%6.1f%%  %5d/%-5d  lib/%s\n' % (r['pct'], r['lh'], r['lf'], name))

print('TOTAL_PCT=%.1f' % total_pct)
covered = [r for r in records if r['lf'] > 0]
if covered:
    worst = covered[0]
    print('WORST_FILE=%s' % worst['file'].split('/lib/')[-1])
    print('WORST_PCT=%.1f' % worst['pct'])
PY

# record <status> <check> <scope> <detail> [logfile]
record() {
  local status="$1" check="$2" scope="$3" detail="$4" log="${5:-}"
  local rel="${log#"$REPO_ROOT"/}"
  printf '%s\t%s\t%s\t%s\t%s\n' "$status" "$check" "$scope" "$detail" "$rel" >> "$SUMMARY"
  case "$status" in
    FAIL) FAIL_COUNT=$((FAIL_COUNT + 1)); printf '%s  FAIL%s  %-22s %-18s %s\n' "$C_RED" "$C_OFF" "$check" "$scope" "$detail" ;;
    WARN) WARN_COUNT=$((WARN_COUNT + 1)); printf '%s  WARN%s  %-22s %-18s %s\n' "$C_YEL" "$C_OFF" "$check" "$scope" "$detail" ;;
    PASS) PASS_COUNT=$((PASS_COUNT + 1)); printf '%s  PASS%s  %-22s %-18s %s\n' "$C_GRN" "$C_OFF" "$check" "$scope" "$detail" ;;
    SKIP) SKIP_COUNT=$((SKIP_COUNT + 1)); printf '%s  SKIP  %-22s %-18s %s%s\n' "$C_DIM" "$check" "$scope" "$detail" "$C_OFF" ;;
  esac
}

section() { printf '\n%s== %s%s\n' "$C_BLD" "$1" "$C_OFF"; }
logfile() { printf '%s/%s.%s.log' "$REPORT_DIR" "$1" "$2"; }

# Package metadata -------------------------------------------------------------

ALL_PACKAGES=()
for dir in "$REPO_ROOT"/packages/*/; do
  [[ -f "$dir/pubspec.yaml" ]] || continue
  ALL_PACKAGES+=("$(basename "$dir")")
done

if [[ $# -gt 0 ]]; then
  PACKAGES=("$@")
  for p in "${PACKAGES[@]}"; do
    if [[ ! -f "$REPO_ROOT/packages/$p/pubspec.yaml" ]]; then
      printf 'Unknown package: %s\nKnown: %s\n' "$p" "${ALL_PACKAGES[*]}" >&2
      exit 2
    fi
  done
else
  PACKAGES=("${ALL_PACKAGES[@]}")
fi

pkg_dir()        { printf '%s/packages/%s' "$REPO_ROOT" "$1"; }
is_publishable() { ! grep -qE "^publish_to:\s*'?none'?" "$(pkg_dir "$1")/pubspec.yaml"; }
is_flutter()     { grep -qE '^\s+flutter:\s*$' "$(pkg_dir "$1")/pubspec.yaml" \
                     && grep -qE '^\s+sdk:\s*flutter\s*$' "$(pkg_dir "$1")/pubspec.yaml"; }
has_tests()      { [[ -d "$(pkg_dir "$1")/test" ]] \
                     && [[ -n "$(find "$(pkg_dir "$1")/test" -name '*_test.dart' -print -quit 2>/dev/null)" ]]; }
# Analyzer/format driver: Flutter packages need the flutter wrapper.
sdk_bin()        { if is_flutter "$1"; then printf 'flutter'; else printf 'dart'; fi; }

pkg_version()    { sed -n 's/^version:[[:space:]]*//p' "$(pkg_dir "$1")/pubspec.yaml" | head -1 | tr -d '\r'; }

# 0. Preflight -----------------------------------------------------------------

section "Preflight"

if ! command -v dart >/dev/null 2>&1; then
  record FAIL toolchain repo "dart not on PATH"
  printf '\nCannot continue without the Dart SDK.\n' >&2
  exit 1
fi
record PASS toolchain repo "dart $(dart --version 2>&1 | sed -n 's/.*version: \([^ ]*\).*/\1/p')"

# Resolve first: everything downstream needs a package_config.
for pkg in "${PACKAGES[@]}"; do
  log="$(logfile pub_get "$pkg")"
  if (cd "$(pkg_dir "$pkg")" && "$(sdk_bin "$pkg")" pub get) > "$log" 2>&1; then
    record PASS pub_get "$pkg" "dependencies resolved" "$log"
  else
    record FAIL pub_get "$pkg" "dependency resolution failed" "$log"
  fi
done

# 1. Formatting ----------------------------------------------------------------

section "Formatting"

for pkg in "${PACKAGES[@]}"; do
  log="$(logfile format "$pkg")"
  if (cd "$(pkg_dir "$pkg")" && dart format --output=none --set-exit-if-changed .) > "$log" 2>&1; then
    record PASS format "$pkg" "already formatted" "$log"
  else
    changed="$(grep -c '^Changed ' "$log" 2>/dev/null || true)"
    record FAIL format "$pkg" "${changed:-?} file(s) need dart format" "$log"
  fi
done

# 2. Static analysis -----------------------------------------------------------

section "Static analysis"

for pkg in "${PACKAGES[@]}"; do
  log="$(logfile analyze "$pkg")"
  (cd "$(pkg_dir "$pkg")" && "$(sdk_bin "$pkg")" analyze --fatal-infos) > "$log" 2>&1
  if [[ $? -eq 0 ]]; then
    record PASS analyze "$pkg" "no issues (--fatal-infos)" "$log"
  else
    n="$(grep -cE '^\s+(error|warning|info) ' "$log" 2>/dev/null || true)"
    record FAIL analyze "$pkg" "${n:-?} analyzer issue(s)" "$log"
  fi
done

# 3. Lint suppressions ---------------------------------------------------------
# The team rule is to fix the cause, not silence the analyzer. Generated files
# are exempt: their contents are not hand-maintained.

section "Lint suppressions"

log="$(logfile ignores repo)"
: > "$log"
while IFS= read -r f; do
  grep -nE '//[[:space:]]*ignore(_for_file)?:' "$f" >> "$log" 2>/dev/null \
    && sed -i.bak "s|^|${f#"$REPO_ROOT"/}:|" /dev/null 2>/dev/null || true
done < <(find "$REPO_ROOT/packages" -name '*.dart' \
           ! -name '*.g.dart' ! -name '*.freezed.dart' \
           ! -path '*/.dart_tool/*' ! -path '*/build/*' -print)
ignore_hits="$(grep -c . "$log" 2>/dev/null || true)"
if [[ "${ignore_hits:-0}" -eq 0 ]]; then
  record PASS lint_suppressions repo "no // ignore directives" "$log"
else
  record FAIL lint_suppressions repo "${ignore_hits} // ignore directive(s)" "$log"
fi

# 4. Dead code -----------------------------------------------------------------
# Two things the analyzer will not tell you:
#   (a) a lib/src file no entrypoint transitively reaches — dead on arrival
#       for consumers, since it ships in the archive but can never be imported;
#   (b) a declared dependency nothing imports.

section "Dead code"

for pkg in "${PACKAGES[@]}"; do
  dir="$(pkg_dir "$pkg")"
  log="$(logfile deadcode "$pkg")"
  : > "$log"
  [[ -d "$dir/lib" ]] || { record SKIP deadcode "$pkg" "no lib/ directory" "$log"; continue; }

  # Reachability from the package's public entrypoints (lib/*.dart), plus
  # bin/ and test/, following import/export/part directives.
  reachable="$(mktemp)"; queue="$(mktemp)"
  find "$dir/lib" -maxdepth 1 -name '*.dart' > "$queue" 2>/dev/null
  for extra in "$dir/bin" "$dir/test" "$dir/example"; do
    [[ -d "$extra" ]] && find "$extra" -name '*.dart' >> "$queue" 2>/dev/null
  done
  while [[ -s "$queue" ]]; do
    current="$(head -1 "$queue")"; sed -i.bak '1d' "$queue"; rm -f "$queue.bak"
    [[ -f "$current" ]] || continue
    grep -qxF "$current" "$reachable" 2>/dev/null && continue
    printf '%s\n' "$current" >> "$reachable"
    # Relative directives only; package: URIs self-resolve to lib/.
    while IFS= read -r ref; do
      [[ -n "$ref" ]] || continue
      case "$ref" in
        package:"$pkg"/*) resolved="$dir/lib/${ref#package:"$pkg"/}" ;;
        package:*|dart:*) continue ;;
        *)                resolved="$(cd "$(dirname "$current")" && printf '%s/%s' "$PWD" "$ref")" ;;
      esac
      printf '%s\n' "$resolved" >> "$queue"
    done < <(grep -hoE "^(import|export|part)[[:space:]]+['\"][^'\"]+['\"]" "$current" 2>/dev/null \
               | sed -E "s/^(import|export|part)[[:space:]]+['\"]//; s/['\"]$//")
  done

  orphans=0
  while IFS= read -r f; do
    grep -qxF "$f" "$reachable" 2>/dev/null && continue
    printf 'unreachable: %s\n' "${f#"$REPO_ROOT"/}" >> "$log"
    orphans=$((orphans + 1))
  done < <(find "$dir/lib" -name '*.dart' ! -name '*.g.dart' ! -name '*.freezed.dart')
  rm -f "$reachable" "$queue"

  # Declared-but-unimported dependencies. Several kinds are legitimately never
  # imported and must not be reported:
  #   - builders, wired through build.yaml and auto_apply (including this
  #     repo's own typed_llm_generator, and anything named *_generator/*_builder)
  #   - lint rule sets, referenced from analysis_options.yaml
  #   - the flutter SDK packages
  unused=0
  builder_deps='build|build_runner|build_test|build_config|source_gen|freezed|json_serializable|lints|flutter_lints|test|coverage|flutter_test|integration_test'
  while IFS= read -r dep; do
    [[ -n "$dep" ]] || continue
    [[ "$dep" =~ ^($builder_deps)$ ]] && continue
    [[ "$dep" =~ (_generator|_builder)$ ]] && continue
    [[ "$dep" == "flutter" || "$dep" == "flutter_web_plugins" ]] && continue
    if ! grep -rqE "(import|export)[[:space:]]+['\"]package:$dep/" \
         "$dir/lib" "$dir/bin" "$dir/test" "$dir/example" 2>/dev/null; then
      printf 'declared but never imported: %s\n' "$dep" >> "$log"
      unused=$((unused + 1))
    fi
  done < <(awk '
    /^(dependencies|dev_dependencies):[[:space:]]*$/ { in_deps=1; next }
    /^[a-zA-Z_]+:/ { in_deps=0 }
    in_deps && /^  [a-zA-Z0-9_]+:/ { gsub(/[: ]/,"",$1); print $1 }
  ' "$dir/pubspec.yaml")

  if [[ $orphans -eq 0 && $unused -eq 0 ]]; then
    record PASS deadcode "$pkg" "no orphan files or unused deps" "$log"
  elif [[ $orphans -gt 0 ]]; then
    record FAIL deadcode "$pkg" "$orphans unreachable lib file(s), $unused unused dep(s)" "$log"
  else
    record WARN deadcode "$pkg" "$unused declared-but-unimported dep(s)" "$log"
  fi
done

# 5. Tests ---------------------------------------------------------------------

section "Tests"

for pkg in "${PACKAGES[@]}"; do
  log="$(logfile test "$pkg")"
  if ! has_tests "$pkg"; then
    record SKIP test "$pkg" "no test/ suite" "$log"
    : > "$log"
    continue
  fi
  (cd "$(pkg_dir "$pkg")" && "$(sdk_bin "$pkg")" test --reporter expanded) > "$log" 2>&1
  if [[ $? -eq 0 ]]; then
    passed="$(grep -oE '\+[0-9]+' "$log" | tail -1 | tr -d '+')"
    skipped="$(grep -oE '~[0-9]+' "$log" | tail -1 | tr -d '~')"
    detail="${passed:-?} passed"
    [[ -n "${skipped:-}" && "${skipped:-0}" != "0" ]] && detail="$detail, ${skipped} skipped"
    record PASS test "$pkg" "$detail" "$log"
  else
    failed="$(grep -oE '\-[0-9]+' "$log" | tail -1 | tr -d '-')"
    record FAIL test "$pkg" "${failed:-?} test(s) failing" "$log"
  fi
done

# 6. Coverage ------------------------------------------------------------------

section "Coverage"

ensure_coverage_tool() {
  dart pub global list 2>/dev/null | grep -q '^coverage ' && return 0
  dart pub global activate coverage >/dev/null 2>&1
}

: > "$REPORT_DIR/lowest_coverage.log"
for pkg in "${PACKAGES[@]}"; do
  log="$(logfile coverage "$pkg")"
  if ! has_tests "$pkg"; then
    record SKIP coverage "$pkg" "no test/ suite" "$log"; : > "$log"; continue
  fi
  if is_flutter "$pkg"; then
    record SKIP coverage "$pkg" "flutter package" "$log"; : > "$log"; continue
  fi
  if ! ensure_coverage_tool; then
    record WARN coverage "$pkg" "could not activate package:coverage" "$log"; continue
  fi

  dir="$(pkg_dir "$pkg")"
  cov_dir="$dir/.qa_coverage"
  rm -rf "$cov_dir"
  {
    (cd "$dir" && dart test --coverage="$cov_dir" ) \
      && (cd "$dir" && dart pub global run coverage:format_coverage \
            --lcov --in="$cov_dir" --out="$cov_dir/lcov.info" \
            --report-on=lib --check-ignore)
  } > "$log" 2>&1

  if [[ ! -s "$cov_dir/lcov.info" ]]; then
    record WARN coverage "$pkg" "no lcov produced; see log" "$log"
    rm -rf "$cov_dir"; continue
  fi

  # Parse lcov: per-file LF (lines found) / LH (lines hit).
  python3 "$HELPER_COV" "$cov_dir/lcov.info" "$pkg" "$REPORT_DIR/lowest_coverage.log" >> "$log" 2>&1
  total_pct="$(grep -oE 'TOTAL_PCT=[0-9.]+' "$log" | tail -1 | cut -d= -f2)"
  worst_pct="$(grep -oE 'WORST_PCT=[0-9.]+' "$log" | tail -1 | cut -d= -f2)"
  worst_file="$(grep -oE 'WORST_FILE=.*' "$log" | tail -1 | cut -d= -f2-)"
  rm -rf "$cov_dir"

  if [[ -z "${total_pct:-}" ]]; then
    record WARN coverage "$pkg" "could not compute coverage" "$log"; continue
  fi
  if awk "BEGIN{exit !($total_pct < $COVERAGE_MIN)}"; then
    record FAIL coverage "$pkg" "${total_pct}% < ${COVERAGE_MIN}% minimum" "$log"
  elif [[ -n "${worst_pct:-}" ]] && awk "BEGIN{exit !($worst_pct < $COVERAGE_FILE_MIN)}"; then
    record WARN coverage "$pkg" "${total_pct}% total; worst file ${worst_pct}% (${worst_file})" "$log"
  else
    record PASS coverage "$pkg" "${total_pct}% line coverage" "$log"
  fi
done

# 7. Secrets -------------------------------------------------------------------
# Real credentials only. Placeholders that document the shape of a key are the
# point of the docs, so they must not trip the gate.

section "Secrets"

log="$(logfile secrets repo)"
: > "$log"
patterns=(
  'sk-[A-Za-z0-9]{32,}'
  'sk-ant-[A-Za-z0-9_-]{32,}'
  'AIza[0-9A-Za-z_-]{35}'
  'ghp_[A-Za-z0-9]{36}'
  'AKIA[0-9A-Z]{16}'
  '-----BEGIN [A-Z ]*PRIVATE KEY-----'
  'xox[baprs]-[A-Za-z0-9-]{10,}'
)
for pat in "${patterns[@]}"; do
  grep -rInE "$pat" "$REPO_ROOT/packages" "$REPO_ROOT"/*.md "$REPO_ROOT/.github" 2>/dev/null \
    | grep -vE '\.dart_tool/|/build/|\.qa_report/' \
    | grep -vEi "(sk-\.\.\.|sk-ant-\.\.\.|your-|example|placeholder|dummy|fake|redact|xxx|<key>|unused-or-)" \
    >> "$log" || true
done
secret_hits="$(grep -c . "$log" 2>/dev/null || true)"
if [[ "${secret_hits:-0}" -eq 0 ]]; then
  record PASS secrets repo "no credential-shaped strings" "$log"
else
  record FAIL secrets repo "${secret_hits} possible secret(s)" "$log"
fi

# Keys must never be committed via test fixtures or env files either.
log="$(logfile envfiles repo)"
find "$REPO_ROOT" -name '.env*' ! -name '.env.example' \
  ! -path '*/.git/*' ! -path '*/.dart_tool/*' > "$log" 2>/dev/null || true
if [[ -s "$log" ]]; then
  record FAIL secrets_envfiles repo "$(grep -c . "$log") .env file(s) present" "$log"
else
  record PASS secrets_envfiles repo "no .env files" "$log"
fi

# 8. Publish readiness ---------------------------------------------------------

section "Publish readiness"

for pkg in "${PACKAGES[@]}"; do
  log="$(logfile publish "$pkg")"
  if ! is_publishable "$pkg"; then
    record SKIP publish "$pkg" "publish_to: none" "$log"; : > "$log"; continue
  fi
  (cd "$(pkg_dir "$pkg")" && dart pub publish --dry-run) > "$log" 2>&1

  # `dart pub publish --dry-run` exits non-zero for *any* warning, including
  # two that say nothing about the package's publishability:
  #   - "checked-in files are modified in git" describes the working tree, and
  #     is always true mid-audit, before the fixes are committed;
  #   - "overridden in pubspec_overrides.yaml" is the intended monorepo setup,
  #     and that file is gitignored and absent from the archive.
  # So classify by which warnings are present, not by exit status alone. A run
  # that never got as far as building an archive is a real failure.
  real_warnings="$(grep -E '^\* ' "$log" 2>/dev/null \
                    | grep -viE 'modified in git|overridden in pubspec_overrides' \
                    | grep -c . || true)"
  built_archive=0
  grep -q 'Total compressed archive size' "$log" && built_archive=1

  if [[ $built_archive -eq 0 ]]; then
    record FAIL publish "$pkg" "dry-run did not produce an archive" "$log"
  elif [[ "${real_warnings:-0}" -gt 0 ]]; then
    record FAIL publish "$pkg" "${real_warnings} publish warning(s)" "$log"
  else
    record PASS publish "$pkg" "dry-run clean" "$log"
  fi
done

# The dirty tree is deliberately not a publish failure, but it is worth
# surfacing on its own: publishing from an uncommitted tree ships code that
# is in no commit.
log="$(logfile git_clean repo)"
git -C "$REPO_ROOT" status --porcelain > "$log" 2>&1 || true
dirty="$(grep -c . "$log" 2>/dev/null || true)"
if [[ "${dirty:-0}" -eq 0 ]]; then
  record PASS git_clean repo "working tree clean" "$log"
else
  record WARN git_clean repo "${dirty} uncommitted change(s)" "$log"
fi

# 9. Package metadata ----------------------------------------------------------
# The pub.dev scoring rules that are cheap to regress and invisible until the
# package is already live.

section "Package metadata"

for pkg in "${PACKAGES[@]}"; do
  dir="$(pkg_dir "$pkg")"
  log="$(logfile metadata "$pkg")"
  : > "$log"
  if ! is_publishable "$pkg"; then
    record SKIP metadata "$pkg" "publish_to: none" "$log"; continue
  fi

  problems=0
  version="$(pkg_version "$pkg")"

  desc="$(python3 "$HELPER_DESC" "$dir/pubspec.yaml")"
  len=${#desc}
  if (( len < 60 || len > 180 )); then
    printf 'description is %d chars; pub.dev wants 60-180\n' "$len" >> "$log"; problems=$((problems + 1))
  fi

  for field in homepage repository issue_tracker topics; do
    grep -qE "^$field:" "$dir/pubspec.yaml" || {
      printf 'pubspec missing: %s\n' "$field" >> "$log"; problems=$((problems + 1)); }
  done

  for f in README.md CHANGELOG.md LICENSE; do
    [[ -s "$dir/$f" ]] || { printf 'missing or empty: %s\n' "$f" >> "$log"; problems=$((problems + 1)); }
  done

  # pub.dev awards points for an example; accept any of its recognised forms.
  if [[ ! -e "$dir/example" ]]; then
    printf 'no example/ directory (pub.dev: -10 points)\n' >> "$log"; problems=$((problems + 1))
  fi

  # A release with no changelog entry reads as an unexplained version bump.
  if [[ -f "$dir/CHANGELOG.md" && -n "$version" ]]; then
    grep -qE "^#+[[:space:]]*\[?${version//./\\.}\]?" "$dir/CHANGELOG.md" \
      || { printf 'CHANGELOG.md has no entry for version %s\n' "$version" >> "$log"; problems=$((problems + 1)); }
  fi

  if [[ $problems -eq 0 ]]; then
    record PASS metadata "$pkg" "v$version, description ${len} chars" "$log"
  else
    record FAIL metadata "$pkg" "$problems metadata problem(s)" "$log"
  fi
done

# 10. Dependency freshness -----------------------------------------------------

section "Dependency freshness"

# "Behind latest" is the wrong bar for a library: a dependency can be pinned
# below latest by the declared SDK floor or by another package's constraint,
# and that is not something this repo can act on. What is actionable is a
# dependency resolvable to something newer *within the constraints we already
# declare* — that means the lockfile is simply stale.
for pkg in "${PACKAGES[@]}"; do
  log="$(logfile outdated "$pkg")"
  (cd "$(pkg_dir "$pkg")" && "$(sdk_bin "$pkg")" pub outdated --json) > "$log.json" 2>&1 || true
  (cd "$(pkg_dir "$pkg")" && "$(sdk_bin "$pkg")" pub outdated --no-dev-dependencies --no-transitive) > "$log" 2>&1 || true

  # pub's own vocabulary, which is easy to misread:
  #   upgradable — reachable by `pub upgrade` alone. A gap here means the
  #                lockfile is stale, and closing it costs nothing.
  #   resolvable — reachable only by *widening a constraint* in pubspec.yaml.
  #                A gap here is a major-version bump: a judgement call, not a
  #                defect, so it is reported but never drives the status.
  read -r stale_count bump_count <<< "$(python3 "$HELPER_OUTDATED" "$log.json" 2>> "$log")"
  if [[ "${stale_count:-?}" == "?" ]]; then
    record WARN outdated "$pkg" "could not parse pub outdated --json" "$log"
  elif [[ "${stale_count:-0}" -gt 0 ]]; then
    record WARN outdated "$pkg" \
      "${stale_count} stale lock entr(ies); ${bump_count} constraint bump(s) available" "$log"
  elif [[ "${bump_count:-0}" -gt 0 ]]; then
    record PASS outdated "$pkg" \
      "lock current; ${bump_count} optional constraint bump(s)" "$log"
  else
    record PASS outdated "$pkg" "all direct deps current" "$log"
  fi
done

# 11. Maintenance markers ------------------------------------------------------

section "Maintenance markers"

log="$(logfile todos repo)"
grep -rInE '(TODO|FIXME|HACK|XXX)[:( ]' "$REPO_ROOT/packages" --include='*.dart' --include='*.yaml' 2>/dev/null \
  | grep -vE '\.g\.dart|\.freezed\.dart|\.dart_tool/|/build/' > "$log" || true
todo_hits="$(grep -c . "$log" 2>/dev/null || true)"
if [[ "${todo_hits:-0}" -eq 0 ]]; then
  record PASS todos repo "no TODO/FIXME markers" "$log"
else
  record WARN todos repo "${todo_hits} TODO/FIXME/HACK marker(s)" "$log"
fi

# Summary ----------------------------------------------------------------------

printf '\n%s== Summary%s\n' "$C_BLD" "$C_OFF"
printf '  %sPASS %d%s   %sWARN %d%s   %sFAIL %d%s   %sSKIP %d%s\n' \
  "$C_GRN" "$PASS_COUNT" "$C_OFF" "$C_YEL" "$WARN_COUNT" "$C_OFF" \
  "$C_RED" "$FAIL_COUNT" "$C_OFF" "$C_DIM" "$SKIP_COUNT" "$C_OFF"
printf '  report: %s\n' "${SUMMARY#"$REPO_ROOT"/}"

if [[ $FAIL_COUNT -gt 0 ]]; then
  printf '\n%sFailing checks:%s\n' "$C_RED" "$C_OFF"
  awk -F'\t' '$1=="FAIL" {printf "  %-22s %-18s %s\n", $2, $3, $4}' "$SUMMARY"
  exit 1
fi
if [[ $WARN_COUNT -gt 0 && "$STRICT_WARN" == "1" ]]; then
  printf '\n%sWarnings, and STRICT_WARN=1.%s\n' "$C_YEL" "$C_OFF"
  exit 1
fi
exit 0
