#!/usr/bin/env -S zsh -f

emulate -L zsh
setopt errexit nounset pipefail

if [[ $OSTYPE != linux* ||
  -e /etc/zsh/zshenv || -h /etc/zsh/zshenv ||
  -e /etc/zshenv || -h /etc/zshenv ||
  ! -x /usr/bin/zsh || ! -x /usr/bin/stty ]]; then
  print -r -- 'skipping upstream smoke evidence: Linux fixture startup inputs/tools are not qualified'
  exit 0
fi

readonly repo_root=${0:A:h:h}
readonly zsh_bin=${commands[zsh]:A}
PATH=/usr/bin:/bin
readonly -a utilities=(env mktemp mkdir ln chmod grep wc sed sleep rm cp)
for utility in $utilities; do
  (( ${+commands[$utility]} )) ||
    { print -ru2 -- "upstream smoke evidence requires $utility"; exit 1 }
done
(( $+commands[cat] && $+commands[cmp] && $+commands[tr] )) ||
  { print -ru2 -- 'upstream smoke evidence requires cat, cmp, and tr'; exit 1 }

tmpdir=$(mktemp -d "${TMPDIR:-/tmp}/upstream-smoke-evidence.XXXXXX")
readonly tmpdir
integer smoke_pid=0
trap 'if (( smoke_pid > 0 )); then
  kill -TERM -- $smoke_pid 2>/dev/null || true
  sleep 0.1
  kill -KILL -- $smoke_pid 2>/dev/null || true
  wait $smoke_pid 2>/dev/null || true
fi
rm -rf -- "$tmpdir"' EXIT
trap 'exit 1' HUP INT TERM

function fail {
  print -ru2 -- "upstream smoke evidence test failed: $1"
  exit 1
}

mkdir -p -- "$tmpdir/bin" "$tmpdir/home" "$tmpdir/scratch" "$tmpdir/evidence"
for utility in $utilities; do
  ln -s -- "${commands[$utility]:A}" "$tmpdir/bin/$utility"
done
print -r -- "$repo_root" >"$tmpdir/expected-repo"
cat >"$tmpdir/bin/git" <<'SH'
#!/bin/sh
fixture_root=${0%/bin/git}
if [ "$#" -eq 1 ] && [ "$1" = --version ]; then
  printf '%s\n' 'git version 0.0.offline-fixture'
  exit 0
fi
if [ "$#" -eq 4 ] && [ "$1" = -C ] &&
  [ "$3" = rev-parse ] && [ "$4" = HEAD ]; then
  IFS= read -r expected_repo <"$fixture_root/expected-repo" || exit 97
  if [ "$2" = "$expected_repo" ]; then
    printf '%s\n' '1111111111111111111111111111111111111111'
    exit 0
  fi
fi
printf '%s\n' "$0" >"${0%/*}/unexpected-call"
exit 97
SH
cat >"$tmpdir/bin/zsh" <<'SH'
#!/bin/sh
if [ "$#" -ne 1 ] || [ "$1" != -i ]; then
  printf '%s\n' "$0" >"${0%/*}/unexpected-call"
  exit 97
fi
printf '%s\n' 'OFFLINE_STARTUP_BEGIN'
i=0
while [ "$i" -lt 250 ]; do
  printf '%s\n' 'offline startup padding'
  i=$((i + 1))
done
printf '%s\n' 'OFFLINE_STARTUP_END'
exit 17
SH
chmod +x "$tmpdir/bin/git" "$tmpdir/bin/zsh"
cp -- "$tmpdir/bin/zsh" "$tmpdir/failing-startup"

# Compare all fixture content independently of the PTY's newline rendering.
{
  print -rn -- $'OFFLINE_STARTUP_BEGIN\n'
  repeat 250 print -rn -- $'offline startup padding\n'
  print -rn -- $'OFFLINE_STARTUP_END\n'
} >"$tmpdir/expected.stdout"

env -i HOME=$tmpdir/home ZDOTDIR=$tmpdir/home PATH=$tmpdir/bin \
  TMPDIR=$tmpdir/scratch UPSTREAM_SMOKE_PROMPT_TIMEOUT_SECONDS=1 \
  UPSTREAM_SMOKE_EVIDENCE_DIR=$tmpdir/evidence \
  "$zsh_bin" -f "$repo_root/tests/upstream-smoke.zsh" \
  >"$tmpdir/smoke.stdout" 2>"$tmpdir/smoke.stderr" &
smoke_pid=$!
integer ticks=0 smoke_status=0
while kill -0 -- $smoke_pid 2>/dev/null; do
  sleep 0.05
  (( ++ticks < 200 )) || fail 'offline smoke exceeded ten seconds'
done
wait $smoke_pid || smoke_status=$?
smoke_pid=0

[[ ! -e $tmpdir/bin/unexpected-call ]] ||
  fail 'the fixture received an unexpected upstream or process call'
(( smoke_status == 1 )) ||
  fail "startup failure must retain exit status 1; found $smoke_status"
grep -Fq 'upstream smoke failed: interactive startup 1 exited before reaching a prompt' \
  "$tmpdir/smoke.stderr" || fail 'the fixture did not reach the selected failure path'
[[ -f $tmpdir/evidence/startup-1.stdout && ! -h $tmpdir/evidence/startup-1.stdout ]] ||
  fail 'startup failure must retain a regular transcript outside the disposable fixture'
tr -d '\r' <"$tmpdir/evidence/startup-1.stdout" >"$tmpdir/observed.stdout"
cmp -s -- "$tmpdir/expected.stdout" "$tmpdir/observed.stdout" ||
  fail 'startup failure must retain the complete available transcript'

print -r -- 'upstream smoke failure evidence checks passed'

mkdir -p -- "$tmpdir/success-scratch" "$tmpdir/success-evidence"
cat >"$tmpdir/bin/git" <<'SH'
#!/bin/sh
reject() {
  printf '%s\n' "$0" >"${0%/*}/unexpected-call"
  exit 97
}
if [ "$#" -eq 1 ] && [ "$1" = --version ]; then
  printf '%s\n' 'git version 0.0.offline-fixture'
  exit 0
fi
[ "$#" -eq 4 ] && [ "$1" = -C ] &&
  [ "$3" = rev-parse ] && [ "$4" = HEAD ] || reject
fixture_root=${0%/bin/git}
IFS= read -r expected_repo <"$fixture_root/expected-repo" || reject
if [ "$2" = "$expected_repo" ]; then
  printf '%s\n' '1111111111111111111111111111111111111111'
  exit 0
fi
case "$2" in
  "$fixture_root/success-scratch/"*/home/.local/share/zi/bin) ;;
  *) reject ;;
esac
relative=${2#"$fixture_root/success-scratch/"}
relative=${relative%/home/.local/share/zi/bin}
case "$relative" in ''|.|..|*/*) reject ;; esac
printf '%s\n' '0123456789012345678901234567890123456789'
SH
cat >"$tmpdir/bin/zsh" <<'SH'
#!/bin/sh
if [ -e /etc/zsh/zshenv ] || [ -L /etc/zsh/zshenv ] ||
  [ -e /etc/zshenv ] || [ -L /etc/zshenv ]; then
  printf '%s\n' "$0" >"${0%/*}/unexpected-call"
  exit 97
fi
exec /usr/bin/zsh -f "${0%/*}/successful-startup" "$@"
SH
cat >"$tmpdir/bin/successful-startup" <<'SH'
#!/usr/bin/zsh -f
set -eu
readonly unexpected_call=${0%/*}/unexpected-call
reject() {
  printf '%s\n' "$0" >"$unexpected_call"
  exit 97
}
[ "$#" -eq 1 ] && [ "$1" = -i ] || reject
fixture_root=${0%/bin/successful-startup}
startup_root=${HOME%/home}
[ "$HOME" = "$startup_root/home" ] || reject
case "$startup_root" in
  "$fixture_root/success-scratch/"*) ;;
  *) reject ;;
esac
relative=${startup_root#"$fixture_root/success-scratch/"}
case "$relative" in ''|.|..|*/*) reject ;; esac
/usr/bin/mkdir -p -- "$HOME/.local/share/zi/bin"
printf '%s\n' '# Offline presence fixture; never sourced.' >"$HOME/.local/share/zi/bin/zi.zsh"
/usr/bin/stty -echo
ordinal=1
if [ -f "$fixture_root/successful-startups" ]; then
  IFS= read -r previous <"$fixture_root/successful-startups" || reject
  [ "$previous" = 1 ] || reject
  ordinal=2
fi
printf '%s\n' "$ordinal" >"$fixture_root/successful-startups"
printf '%s\n' "OFFLINE_SUCCESS_STARTUP_$ordinal"
i=0
while [ "$i" -lt 250 ]; do
  printf '%s\n' 'offline successful startup padding'
  i=$((i + 1))
done
read_timeout=1
if [ -r "$fixture_root/mixed-tail" ]; then
  printf '%s\n' "$HOME" >"$fixture_root/mixed-home"
  print -rn -- "$(<"$fixture_root/mixed-tail")"
  read_timeout=5
else
  printf '%s\n' '__UPSTREAM_SMOKE_PROMPT__'
fi
i=0
while [ "$i" -lt 3 ]; do
  IFS= read -r -t "$read_timeout" line || reject
  [ "$line" = : ] || reject
  printf '%s\n' '__UPSTREAM_SMOKE_PROMPT__'
  i=$((i + 1))
done
IFS= read -r -t "$read_timeout" line || reject
case "$line" in
  *'SMOKE_READY='*'SMOKE_COMPDEF='*'SMOKE_EXIT=clean'*) ;;
  *) reject ;;
esac
printf '%s\n' 'SMOKE_READY=1' 'SMOKE_COMPDEF=1' \
  "SMOKE_PATH_FIRST=$HOME/.local/lib/secret-exec/bin" \
  "SMOKE_K9S=$HOME/.local/lib/secret-exec/bin/k9s" \
  'SMOKE_SHIM_COUNT=1' 'SMOKE_EXIT=clean' '__UPSTREAM_SMOKE_PROMPT__'
IFS= read -r -t "$read_timeout" line || reject
[ "$line" = exit ] || reject
printf '%s\n' "OFFLINE_SUCCESS_EXIT_$ordinal"
exit 0
SH

env -i HOME=$tmpdir/home ZDOTDIR=$tmpdir/home PATH=$tmpdir/bin \
  TMPDIR=$tmpdir/success-scratch UPSTREAM_SMOKE_PROMPT_TIMEOUT_SECONDS=1 \
  UPSTREAM_SMOKE_EVIDENCE_DIR=$tmpdir/success-evidence \
  "$zsh_bin" -f "$repo_root/tests/upstream-smoke.zsh" \
  >"$tmpdir/success.stdout" 2>"$tmpdir/success.stderr" &
smoke_pid=$!
ticks=0
smoke_status=0
while kill -0 -- $smoke_pid 2>/dev/null; do
  sleep 0.05
  (( ++ticks < 200 )) || fail 'offline successful smoke exceeded ten seconds'
done
wait $smoke_pid || smoke_status=$?
smoke_pid=0

[[ ! -e $tmpdir/bin/unexpected-call ]] ||
  fail 'the success fixture received an unexpected upstream or process call'
(( smoke_status == 0 )) ||
  fail "successful smoke must retain exit status 0; found $smoke_status"
grep -Fxq 'upstream Zi smoke checks passed' "$tmpdir/success.stdout" ||
  fail 'the fixture did not reach the successful command exit'
for ordinal in 1 2; do
  transcript=$tmpdir/success-evidence/startup-$ordinal.stdout
  [[ -f $transcript && ! -h $transcript ]] ||
    fail "successful smoke must retain startup-$ordinal.stdout outside the disposable fixture"
  {
    print -r -- "OFFLINE_SUCCESS_STARTUP_$ordinal"
    repeat 250 print -r -- 'offline successful startup padding'
    repeat 4 print -r -- '__UPSTREAM_SMOKE_PROMPT__'
    print -rl -- 'SMOKE_READY=1' 'SMOKE_COMPDEF=1' \
      'SMOKE_PATH_FIRST=FIXTURE_SHIM' 'SMOKE_K9S=FIXTURE_K9S' \
      'SMOKE_SHIM_COUNT=1' 'SMOKE_EXIT=clean' '__UPSTREAM_SMOKE_PROMPT__'
    print -r -- "OFFLINE_SUCCESS_EXIT_$ordinal"
  } >"$tmpdir/success-expected.stdout"
  tr -d '\r' <"$transcript" |
    sed -e 's|^SMOKE_PATH_FIRST=.*$|SMOKE_PATH_FIRST=FIXTURE_SHIM|' \
      -e 's|^SMOKE_K9S=.*$|SMOKE_K9S=FIXTURE_K9S|' >"$tmpdir/success-observed.stdout"
  cmp -s -- "$tmpdir/success-expected.stdout" "$tmpdir/success-observed.stdout" ||
    fail "successful smoke must retain the complete startup-$ordinal.stdout transcript"
done

print -r -- 'upstream smoke success evidence checks passed'

[[ -f $tmpdir/success-evidence/result.txt ]] &&
  grep -Fxq 'status=0' "$tmpdir/success-evidence/result.txt" ||
  fail 'successful smoke must record status 0'
grep -Fxq 'phase=complete' "$tmpdir/success-evidence/result.txt" ||
  fail 'successful smoke must record its completed phase'

function run_evidence_case {
  emulate -L zsh
  setopt nounset err_return pipefail
  local name=$1 prompt_timeout=$2
  mkdir -p -- "$tmpdir/$name-scratch" "$tmpdir/$name-evidence"
  env -i HOME=$tmpdir/home ZDOTDIR=$tmpdir/home PATH=$tmpdir/bin \
    TMPDIR=$tmpdir/$name-scratch UPSTREAM_SMOKE_PROMPT_TIMEOUT_SECONDS=$prompt_timeout \
    UPSTREAM_SMOKE_EVIDENCE_DIR=$tmpdir/$name-evidence \
    "$zsh_bin" -f "$repo_root/tests/upstream-smoke.zsh" \
    >"$tmpdir/$name.stdout" 2>"$tmpdir/$name.stderr" &
  smoke_pid=$!
  integer ticks=0
  typeset -g case_status=0
  while kill -0 -- $smoke_pid 2>/dev/null; do
    sleep 0.05
    (( ++ticks < 200 )) || fail "$name smoke exceeded ten seconds"
  done
  wait $smoke_pid || case_status=$?
  smoke_pid=0
}

run_evidence_case early 0
(( case_status == 1 )) || fail 'pre-startup failure must preserve status 1'
[[ -f $tmpdir/early-evidence/result.txt ]] &&
  grep -Fxq 'status=1' "$tmpdir/early-evidence/result.txt" ||
  fail 'pre-startup failure must record status 1'
grep -Fxq 'phase=preflight' "$tmpdir/early-evidence/result.txt" ||
  fail 'pre-startup failure must identify the preflight phase'
for ordinal in 1 2; do
  grep -Fxq "startup_$ordinal=unavailable:not-produced" "$tmpdir/early-evidence/result.txt" ||
    fail 'pre-startup failure must identify unavailable transcripts'
  [[ ! -e $tmpdir/early-evidence/startup-$ordinal.stdout ]] ||
    fail 'pre-startup failure must not invent a transcript'
done
grep -Fxq 'status=1' "$tmpdir/evidence/result.txt" ||
  fail 'startup failure must record status 1'
grep -Fxq 'phase=startup-1/prompt' "$tmpdir/evidence/result.txt" ||
  fail 'startup failure must identify its prompt phase'
print -r -- 'upstream smoke ordinary exit record checks passed'

grep -Fxq 'source_commit=1111111111111111111111111111111111111111' "$tmpdir/success-evidence/result.txt" ||
  fail 'successful smoke must record its available source commit'
grep -Fxq 'git_version=git version 0.0.offline-fixture' "$tmpdir/success-evidence/result.txt" ||
  fail 'successful smoke must record its available Git version'
grep -Fxq "zsh_version=$ZSH_VERSION" "$tmpdir/success-evidence/result.txt" ||
  fail 'successful smoke must record its actual harness Zsh version'
grep -Fxq "platform=$OSTYPE" "$tmpdir/success-evidence/result.txt" ||
  fail 'successful smoke must record its platform'
grep -Fxq "architecture=$MACHTYPE" "$tmpdir/success-evidence/result.txt" ||
  fail 'successful smoke must record its architecture'
for identity in zi_head_before zi_head_after zi_head_at_exit; do
  grep -Fxq "$identity=0123456789012345678901234567890123456789" "$tmpdir/success-evidence/result.txt" ||
    fail 'successful smoke must record its available Zi heads'
done
for gap in 'dependency_inventory=unavailable:not-collected' \
  'source_content=unavailable:not-hashed' 'runner_identity=unavailable:not-provided'; do
  grep -Fxq "$gap" "$tmpdir/success-evidence/result.txt" ||
    fail 'successful smoke must identify identity gaps'
done
grep -Fxq 'zi_head_at_exit=unavailable:checkout-not-observed' "$tmpdir/early-evidence/result.txt" ||
  fail 'pre-startup failure must identify its unavailable Zi checkout'
print -r -- 'upstream smoke available identity checks passed'

# Retained native tail: 363 bytes, seven markers, and no final LF.
{
  print -rn -- $'\x1bP$f{"hook": "SourcedRcFileForWarp", "value": { "shell": "zsh", "uname": "Darwin" }}\x9c%'
  printf '%78s' ''
  print -rn -- $'\r \r\r__UPSTREAM_SMOKE_PROMPT__\x1b[?2004h'
  repeat 6 print -rn -- $'\r\r__UPSTREAM_SMOKE_PROMPT__'
} >"$tmpdir/mixed-tail"
env -i HOME=$tmpdir/home ZDOTDIR=$tmpdir/home PATH=/usr/bin:/bin \
  LANG=C LC_CTYPE=C.UTF-8 "$zsh_bin" -f -c 'letter=é; [[ ${#letter} == 1 ]]' ||
  fail 'mixed-byte fixture requires an effective C.UTF-8 character locale'

# Model only the witnessed malformed final prompt line. Zsh's character
# decoding follows LC_ALL, LC_CTYPE, then LANG; the environment stays intact.
ln -s -- "${commands[grep]:A}" "$tmpdir/bin/real-grep"
rm -f -- "$tmpdir/bin/grep" "$tmpdir/successful-startups"
cat >"$tmpdir/bin/grep" <<'SH'
#!/usr/bin/zsh -f
emulate -L zsh
fixture_root=${0%/bin/grep}
letter=$'\xc3\xa9'
utf8_ctype=0
if [[ ${#letter} == 1 ]] && [[ $(printf '%d' "'$letter") == 233 ]]; then
  utf8_ctype=1
fi
unsetopt multibyte
input=
if (( $# == 3 )) && [[ $2 == __UPSTREAM_SMOKE_PROMPT__ ]]; then
  input=$3
elif (( $# == 4 )) && [[ $2 == -- && $3 == __UPSTREAM_SMOKE_PROMPT__ ]]; then
  input=$4
fi
if (( utf8_ctype )) && [[ ( $1 == -Fq || $1 == -Fo ) &&
  -n $input && -f $input && -r $fixture_root/mixed-tail ]]; then
  tail=$(<"$fixture_root/mixed-tail")
  content=$(<"$input")
  if [[ ${content##*$'\n'} == "$tail" &&
    ${content%"$tail"} != *'__UPSTREAM_SMOKE_PROMPT__'* ]]; then
    exit 1
  fi
fi
exec "$fixture_root/bin/real-grep" "$@"
SH
chmod +x "$tmpdir/bin/grep"
mkdir -p -- "$tmpdir/mixed-evidence"
env -i HOME=$tmpdir/home ZDOTDIR=$tmpdir/home PATH=$tmpdir/bin \
  LANG=C LC_CTYPE=C.UTF-8 TMPDIR=$tmpdir/success-scratch \
  UPSTREAM_SMOKE_PROMPT_TIMEOUT_SECONDS=1 \
  UPSTREAM_SMOKE_EVIDENCE_DIR=$tmpdir/mixed-evidence \
  "$zsh_bin" -f "$repo_root/tests/upstream-smoke.zsh" \
  >"$tmpdir/mixed.stdout" 2>"$tmpdir/mixed.stderr" &
smoke_pid=$!
ticks=0
smoke_status=0
while kill -0 -- $smoke_pid 2>/dev/null; do
  sleep 0.05
  (( ++ticks < 200 )) || fail 'mixed-byte smoke exceeded ten seconds'
done
wait $smoke_pid || smoke_status=$?
smoke_pid=0
[[ ! -e $tmpdir/bin/unexpected-call ]] ||
  fail 'the mixed-byte fixture received an unexpected call'
(( smoke_status == 0 )) ||
  fail "mixed-byte smoke must complete with exit status 0; found $smoke_status"
grep -Fxq 'upstream Zi smoke checks passed' "$tmpdir/mixed.stdout" ||
  fail 'mixed-byte smoke must reach the successful command exit'
for record in status=0 phase=complete startup_1=available startup_2=available \
  cleanup_status=0 pty_cleanup_status=0 fixture_cleanup_status=0; do
  grep -Fxq "$record" "$tmpdir/mixed-evidence/result.txt" ||
    fail "mixed-byte smoke must record $record"
done
IFS= read -r mixed_home <"$tmpdir/mixed-home" || fail 'mixed-byte fixture did not record its input home'
for ordinal in 1 2; do
  transcript=$tmpdir/mixed-evidence/startup-$ordinal.stdout
  [[ -f $transcript && ! -h $transcript ]] ||
    fail "mixed-byte smoke must retain startup-$ordinal.stdout"
  {
    print -r -- "OFFLINE_SUCCESS_STARTUP_$ordinal"
    repeat 250 print -r -- 'offline successful startup padding'
    print -rn -- "$(<"$tmpdir/mixed-tail")"
    repeat 3 print -r -- '__UPSTREAM_SMOKE_PROMPT__'
    print -rl -- 'SMOKE_READY=1' 'SMOKE_COMPDEF=1' \
      "SMOKE_PATH_FIRST=$mixed_home/.local/lib/secret-exec/bin" \
      "SMOKE_K9S=$mixed_home/.local/lib/secret-exec/bin/k9s" \
      'SMOKE_SHIM_COUNT=1' 'SMOKE_EXIT=clean' '__UPSTREAM_SMOKE_PROMPT__'
    print -r -- "OFFLINE_SUCCESS_EXIT_$ordinal"
  } | tr -d '\r' >"$tmpdir/mixed-expected.stdout"
  tr -d '\r' <"$transcript" >"$tmpdir/mixed-observed.stdout"
  cmp -s -- "$tmpdir/mixed-expected.stdout" "$tmpdir/mixed-observed.stdout" ||
    fail "mixed-byte smoke must retain the complete startup-$ordinal.stdout transcript"
done
typeset -a mixed_leftovers=( "$tmpdir/success-scratch"/*(ND) )
(( ${#mixed_leftovers} == 0 )) || fail 'mixed-byte smoke must remove its disposable fixture'
rm -f -- "$tmpdir/mixed-tail" "$tmpdir/bin/grep"
ln -s -- "${commands[grep]:A}" "$tmpdir/bin/grep"
print -r -- 'upstream smoke mixed-byte evidence checks passed'

cp -- "$tmpdir/failing-startup" "$tmpdir/bin/zsh"
rm -f -- "$tmpdir/bin/rm"
cat >"$tmpdir/bin/rm" <<'SH'
#!/bin/sh
reject() {
  printf '%s\n' "$0" >"${0%/*}/unexpected-call"
  exit 97
}
[ "$#" -eq 3 ] && [ "$1" = -rf ] && [ "$2" = -- ] || reject
fixture_root=${0%/bin/rm}
case "$3" in "$fixture_root/cleanup-scratch/"*) ;; *) reject ;; esac
relative=${3#"$fixture_root/cleanup-scratch/"}
case "$relative" in ''|.|..|*/*) reject ;; esac
exit 73
SH
chmod +x "$tmpdir/bin/rm"
run_evidence_case cleanup 1
(( case_status == 1 )) || fail 'cleanup failure must preserve the smoke failure status'
[[ ! -e $tmpdir/bin/unexpected-call ]] || fail 'cleanup fixture received an unexpected call'
grep -Fxq 'status=1' "$tmpdir/cleanup-evidence/result.txt" ||
  fail 'cleanup failure must retain the original status record'
tr -d '\r' <"$tmpdir/cleanup-evidence/startup-1.stdout" >"$tmpdir/cleanup-observed.stdout"
cmp -s -- "$tmpdir/expected.stdout" "$tmpdir/cleanup-observed.stdout" ||
  fail 'cleanup failure must retain the complete available transcript'
grep -Fxq 'cleanup_status=73' "$tmpdir/cleanup-evidence/result.txt" ||
  fail 'cleanup failure must record status 73'
grep -Fxq 'fixture_cleanup_status=73' "$tmpdir/cleanup-evidence/result.txt" ||
  fail 'cleanup failure must identify the failed fixture removal'
grep -Fq 'upstream smoke cleanup failed: status 73' "$tmpdir/cleanup.stderr" ||
  fail 'cleanup failure must remain visible on stderr'
print -r -- 'upstream smoke cleanup failure checks passed'
