#!/usr/bin/env -S zsh -f

emulate -L zsh
setopt errexit nounset pipefail

readonly loader=${0:A:h:h}/zshenv.zsh
grep -Fxq '# secret-exec-environment-loader-v1' $loader
tmpdir=$(mktemp -d)
readonly tmpdir
trap 'rm -rf -- $tmpdir' EXIT

function fail {
  print -ru2 -- "zshenv test failed: $1"
  return 1
}

function write_lines {
  local file=$1
  shift
  mkdir -p -- ${file:h}
  print -rl -- "$@" >$file
}

function test_public_expansion_and_order {
  emulate -L zsh
  setopt nounset

  local root=$tmpdir/public
  mkdir -p -- $root/home
  write_lines $root/environment.d/00-base.conf \
    'BASE=/opt/base' \
    'PATH=$BASE/bin:${PATH:-}' \
    'NESTED=${UNSET_VALUE:-${HOME}/fallback}' \
    'BRACE_DEFAULT=${UNSET_VALUE:-"a}b"}' \
    "SINGLE='space ; * literal'" \
    'DOUBLE="quoted \"segment\""' \
    'ESCAPED=hello\ world' \
    'DEFINED_EMPTY=' \
    'COLON_DEFAULT=${DEFINED_EMPTY:-fallback}' \
    'DASH_DEFAULT=${DEFINED_EMPTY-fallback}'
  write_lines $root/environment.d/10-later.conf \
    'BASE=/srv' \
    'PATH=$BASE/sbin:$PATH' \
    'COMPOSED=${BASE}/share:${NESTED}' \
    $'CRLF_VALUE=trimmed\r'

  local HOME=$root/home XDG_CONFIG_HOME=$root PATH=/usr/bin:/bin
  unset UNSET_VALUE
  source $loader

  [[ $BASE == /srv ]] || { fail 'later files must override earlier variables'; return 1 }
  [[ $PATH == /srv/sbin:/opt/base/bin:/usr/bin:/bin ]] ||
    { fail 'expansion must use values established by earlier assignments'; return 1 }
  [[ $NESTED == $root/home/fallback ]] || { fail 'nested defaults must expand'; return 1 }
  [[ $BRACE_DEFAULT == 'a}b' ]] || { fail 'quoted fallback braces must remain literal'; return 1 }
  [[ $SINGLE == 'space ; * literal' ]] || { fail 'single quotes must remain literal'; return 1 }
  [[ $DOUBLE == 'quoted "segment"' ]] || { fail 'double-quoted escapes must expand'; return 1 }
  [[ $ESCAPED == 'hello world' ]] || { fail 'backslash escapes must expand'; return 1 }
  [[ $COLON_DEFAULT == fallback ]] || { fail 'colon default must treat empty as unset'; return 1 }
  [[ -z $DASH_DEFAULT ]] || { fail 'dash default must preserve an existing empty value'; return 1 }
  [[ $COMPOSED == /srv/share:$root/home/fallback ]] || { fail 'braced values must compose'; return 1 }
  [[ $CRLF_VALUE == trimmed ]] || { fail 'CRLF assignments must not retain a carriage return'; return 1 }
  env | grep -Fxq -- 'BASE=/srv' || { fail 'accepted base assignment must be exported'; return 1 }
  env | grep -Fxq -- 'PATH=/srv/sbin:/opt/base/bin:/usr/bin:/bin' ||
    { fail 'accepted path assignment must be exported'; return 1 }
  env | grep -Fxq -- "COMPOSED=/srv/share:$root/home/fallback" ||
    { fail 'accepted composed assignment must be exported'; return 1 }
  (( ! ${+functions[__zshenv_expand_value]} && ! ${+functions[__zshenv_reject_definition]} )) ||
    { fail 'loader helpers must not remain in the shell'; return 1 }
}

function test_executable_and_malformed_syntax_is_rejected {
  emulate -L zsh
  setopt nounset

  local root=$tmpdir/rejected
  local parse_log=$root/parse.log
  local sentinel=$root/executed
  mkdir -p -- $root/home
  write_lines $root/environment.d/00-rejected.conf \
    "EXEC_DOLLAR=\$(touch ${(q)sentinel}.dollar)" \
    "EXEC_BACKTICK=\`touch ${(q)sentinel}.backtick\`" \
    "EXEC_SEPARATOR=value; touch ${(q)sentinel}.separator" \
    "EXEC_REDIRECT=value > ${(q)sentinel}.redirect" \
    "EXEC_ARITHMETIC=\$((1 + 1))" \
    'SAFE_DEFAULT=already-set' \
    "EXEC_HIDDEN=\${SAFE_DEFAULT:-\$(touch ${(q)sentinel}.hidden)}" \
    'SPECIAL_POSITIONAL=$1' \
    'SPECIAL_STATUS=$?' \
    'SPECIAL_PID=$$' \
    'SPECIAL_LENGTH=${#SAFE_DEFAULT}' \
    '1INVALID=value' \
    'NO_EQUALS' \
    'UNTERMINATED="value' \
    'STRAY_BRACE=value}' \
    'AFTER_REJECT=loaded'

  local HOME=$root/home XDG_CONFIG_HOME=$root PATH=/usr/bin:/bin
  source $loader 2>$parse_log || true

  [[ ! -e $sentinel.dollar ]] || { fail 'dollar command substitution executed'; return 1 }
  [[ ! -e $sentinel.backtick ]] || { fail 'backtick command substitution executed'; return 1 }
  [[ ! -e $sentinel.separator ]] || { fail 'command separator executed'; return 1 }
  [[ ! -e $sentinel.redirect ]] || { fail 'redirection executed'; return 1 }
  [[ ! -e $sentinel.hidden ]] || { fail 'hidden command substitution executed'; return 1 }
  (( ! ${+EXEC_DOLLAR} )) || { fail 'rejected dollar substitution was exported'; return 1 }
  (( ! ${+EXEC_BACKTICK} )) || { fail 'rejected backtick substitution was exported'; return 1 }
  (( ! ${+EXEC_SEPARATOR} )) || { fail 'rejected command separator was exported'; return 1 }
  (( ! ${+EXEC_REDIRECT} )) || { fail 'rejected redirection was exported'; return 1 }
  (( ! ${+EXEC_ARITHMETIC} )) || { fail 'rejected arithmetic expansion was exported'; return 1 }
  (( ! ${+EXEC_HIDDEN} )) || { fail 'rejected hidden substitution was exported'; return 1 }
  (( ! ${+SPECIAL_POSITIONAL} )) || { fail 'positional parameter expansion was exported'; return 1 }
  (( ! ${+SPECIAL_STATUS} )) || { fail 'status parameter expansion was exported'; return 1 }
  (( ! ${+SPECIAL_PID} )) || { fail 'PID parameter expansion was exported'; return 1 }
  (( ! ${+SPECIAL_LENGTH} )) || { fail 'parameter length expansion was exported'; return 1 }
  (( ! ${+NO_EQUALS} )) || { fail 'line without assignment was exported'; return 1 }
  (( ! ${+UNTERMINATED} )) || { fail 'unterminated quote was exported'; return 1 }
  (( ! ${+STRAY_BRACE} )) || { fail 'stray parameter brace was exported'; return 1 }
  (( $(grep -Fc 'expected NAME=VALUE assignment' $parse_log) == 2 )) ||
    { fail 'every malformed assignment must emit a rejection diagnostic'; return 1 }
  (( $(grep -Fc 'unsupported or malformed value syntax' $parse_log) == 12 )) ||
    { fail 'every executable or malformed value must emit a rejection diagnostic'; return 1 }
  (( $(wc -l <$parse_log) == 14 )) ||
    { fail 'the rejection log must contain exactly one diagnostic per rejected definition'; return 1 }
  [[ $AFTER_REJECT == loaded ]] || { fail 'a rejected line prevented later valid assignments'; return 1 }
}

function test_pre_enabled_xtrace_hides_values {
  emulate -L zsh
  setopt nounset

  local root=$tmpdir/trace
  local trace_log=$root/trace.log
  local canary=ZSHENV_TRACE_CANARY_7f31d
  local zsh_path=${commands[zsh]:A}
  mkdir -p -- $root/home/.config
  ln -s -- $loader $root/home/.zshenv
  write_lines $root/home/.config/environment.d/00-trace.conf \
    "TRACE_VALUE=$canary" \
    "TRACE_COMPOSED=prefix-\${TRACE_VALUE}"

  local trace_status
  if env -i HOME=$root/home PATH=/usr/bin:/bin EXPECTED_CANARY=$canary "$zsh_path" -x -c \
    'print -r -- TRACE_RESTORED_MARKER >/dev/null; set +x
     [[ $TRACE_VALUE == $EXPECTED_CANARY ]] || exit 11
     [[ $TRACE_COMPOSED == "prefix-$EXPECTED_CANARY" ]] || exit 12
     [[ $ZDOTDIR == $HOME/.config/zsh ]] || exit 13' \
    2>$trace_log; then
    trace_status=0
  else
    trace_status=$?
  fi
  case $trace_status in
    0) ;;
    11) fail 'TRACE_VALUE was not populated from environment.d'; return 1 ;;
    12) fail 'TRACE_COMPOSED was not expanded from a prior assignment'; return 1 ;;
    13) fail 'ZDOTDIR was not set as expected'; return 1 ;;
    *) fail 'traced startup failed before validating definitions'; return 1 ;;
  esac

  grep -Fq TRACE_RESTORED_MARKER $trace_log ||
    { fail 'the loader must restore caller tracing after startup'; return 1 }
  if LC_ALL=C grep -Fq -- $canary $trace_log; then
    fail 'pre-enabled xtrace exposed a loaded value'
    return 1
  fi
}

function test_readonly_assignment_isolated {
  emulate -L zsh
  setopt nounset

  local root=$tmpdir/readonly
  local parse_log=$root/parse.log
  mkdir -p -- $root/home
  write_lines $root/environment.d/00-readonly.conf \
    'READONLY_VALUE=replaced' \
    'AFTER_READONLY=loaded'

  local HOME=$root/home XDG_CONFIG_HOME=$root PATH=/usr/bin:/bin
  local -r READONLY_VALUE=original
  source $loader 2>$parse_log

  [[ $READONLY_VALUE == original ]] || { fail 'read-only parameter was replaced'; return 1 }
  [[ $AFTER_READONLY == loaded ]] || { fail 'read-only rejection stopped later assignments'; return 1 }
  (( $(grep -Fc 'cannot replace a read-only parameter' $parse_log) == 1 )) ||
    { fail 'read-only assignment must emit one rejection diagnostic'; return 1 }
}

function test_parameter_expansion_ignores_loader_scratch_state {
  emulate -L zsh
  setopt nounset

  local root=$tmpdir/dynamic-scope
  mkdir -p -- $root/home
  write_lines $root/environment.d/00-collision.conf \
    'EXPANDED_SCRATCH_NAME=$output'

  local HOME=$root/home XDG_CONFIG_HOME=$root PATH=/usr/bin:/bin
  typeset -g output=managed-public-value
  source $loader

  [[ $EXPANDED_SCRATCH_NAME == managed-public-value ]] ||
    { fail 'parameter expansion observed loader scratch state'; return 1 }
  unset output
}

function test_non_scalar_assignment_is_rejected_without_evaluation {
  emulate -L zsh
  setopt nounset

  local root=$tmpdir/non-scalar
  local parse_log=$root/parse.log
  local sentinel=$root/evaluated
  mkdir -p -- $root/home
  write_lines $root/environment.d/00-non-scalar.conf \
    'TYPED_TARGET=$MALICIOUS_TYPED_VALUE' \
    'AFTER_TYPED_TARGET=loaded'

  local HOME=$root/home XDG_CONFIG_HOME=$root PATH=/usr/bin:/bin
  typeset -gi TYPED_TARGET=0
  typeset -g MALICIOUS_TYPED_VALUE="1+\$(touch ${(q)sentinel})"
  source $loader 2>$parse_log

  [[ ! -e $sentinel ]] || { fail 'typed assignment evaluated managed text'; return 1 }
  (( TYPED_TARGET == 0 )) || { fail 'typed parameter was replaced'; return 1 }
  [[ $AFTER_TYPED_TARGET == loaded ]] || { fail 'typed rejection stopped later assignments'; return 1 }
  (( $(grep -Fc 'cannot replace a non-scalar parameter' $parse_log) == 1 )) ||
    { fail 'typed assignment must emit one rejection diagnostic'; return 1 }
  unset TYPED_TARGET MALICIOUS_TYPED_VALUE
}

function test_existing_helpers_are_preserved {
  emulate -L zsh
  setopt nounset

  local root=$tmpdir/helpers
  mkdir -p -- $root/home
  write_lines $root/environment.d/00-helper.conf 'HELPER_VALUE=loaded'

  function __zshenv_reject_definition { return 17 }
  function __zshenv_expand_value { return 19 }
  local reject_definition=$functions[__zshenv_reject_definition]
  local expand_value=$functions[__zshenv_expand_value]
  local HOME=$root/home XDG_CONFIG_HOME=$root PATH=/usr/bin:/bin
  source $loader

  [[ $HELPER_VALUE == loaded ]] || { fail 'existing helper names prevented loading'; return 1 }
  [[ $functions[__zshenv_reject_definition] == $reject_definition ]] ||
    { fail 'existing rejection helper was not restored'; return 1 }
  [[ $functions[__zshenv_expand_value] == $expand_value ]] ||
    { fail 'existing expansion helper was not restored'; return 1 }
  unfunction __zshenv_reject_definition __zshenv_expand_value
}

integer failed=0
test_public_expansion_and_order || failed=1
test_executable_and_malformed_syntax_is_rejected || failed=1
test_pre_enabled_xtrace_hides_values || failed=1
test_readonly_assignment_isolated || failed=1
test_parameter_expansion_ignores_loader_scratch_state || failed=1
test_non_scalar_assignment_is_rejected_without_evaluation || failed=1
test_existing_helpers_are_preserved || failed=1
exit $failed
