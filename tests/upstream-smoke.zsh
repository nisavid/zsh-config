#!/usr/bin/env -S zsh -f

emulate -L zsh
setopt errexit nounset pipefail

readonly repo_root=${0:A:h:h}
zsh_bin=${commands[zsh]-}
[[ -z $zsh_bin ]] || zsh_bin=${zsh_bin:A}
readonly zsh_bin
tmpdir=''
smoke_phase=preflight
integer smoke_zpty_ready=0
function finish_smoke {
  emulate -L zsh
  local original_status=$1
  integer pty_cleanup_status=0 cleanup_status=0
  local fixture_cleanup_status=unavailable:not-created
  trap - EXIT
  local evidence_dir=${UPSTREAM_SMOKE_EVIDENCE_DIR:-}
  local result_file=$evidence_dir/result.txt
  local ordinal name output destination availability
  local -a records=(
    schema=upstream-smoke-evidence-v1
    "status=$original_status"
    "phase=$smoke_phase"
  )
  if (( smoke_zpty_ready )); then
    for ordinal in 1 2; do
      name=upstream-smoke-$ordinal
      if zpty -t "$name" 2>/dev/null; then
        drain_startup_output "$name" "$tmpdir/startup-$ordinal.stdout" || true
        if zpty -d "$name"; then
          :
        else
          pty_cleanup_status=$?
          print -ru2 -- "could not delete smoke PTY: $name"
        fi
      fi
    done
  fi
  if [[ -n $evidence_dir && -d $evidence_dir && ! -h $evidence_dir ]]; then
    for ordinal in 1 2; do
      output=$tmpdir/startup-$ordinal.stdout
      destination=$evidence_dir/startup-$ordinal.stdout
      availability=unavailable:not-produced
      if [[ -n $tmpdir && -f $output && ! -h $output && -r $output ]]; then
        if [[ -e $destination || -h $destination ]] ||
          ! cp -- "$output" "$destination"; then
          availability=unavailable:copy-failed
          print -ru2 -- "could not retain startup transcript: $destination"
        else
          availability=available
        fi
      fi
      records+=( "startup_$ordinal=$availability" )
    done
  fi
  if [[ -n $evidence_dir && -d $evidence_dir && ! -h $evidence_dir ]]; then
    local source_commit git_version zi_head_at_exit=unavailable:checkout-not-observed
    if source_commit=$(git -C "$repo_root" rev-parse HEAD 2>/dev/null) &&
      [[ ${#source_commit} == 40 && $source_commit != *[^0-9a-f]* ]]; then
      :
    else
      source_commit=unavailable:query-failed-or-invalid
    fi
    git_version=$(git --version 2>/dev/null) || git_version=unavailable:query-failed
    local zi_dir=$tmpdir/home/.local/share/zi/bin
    if [[ -n $tmpdir && -d $zi_dir && ! -h $zi_dir && -f $zi_dir/zi.zsh && ! -h $zi_dir/zi.zsh ]]; then
      zi_head_at_exit=$(git -C "$zi_dir" rev-parse HEAD 2>/dev/null) ||
        zi_head_at_exit=unavailable:query-failed
    fi
    local key value
    local -a identities=(
      source_commit "$source_commit"
      zsh_version "$ZSH_VERSION"
      zsh_command "$zsh_bin"
      git_version "$git_version"
      git_command "${commands[git]-unavailable:not-found}"
      platform "$OSTYPE"
      architecture "$MACHTYPE"
      zi_head_before "${zi_head_before-unavailable:not-observed}"
      zi_head_after "${zi_head_after-unavailable:not-observed}"
      zi_head_at_exit "$zi_head_at_exit"
      source_content unavailable:not-hashed
      dependency_inventory unavailable:not-collected
      runner_identity unavailable:not-provided
    )
    for key value in "${(@)identities}"; do
      if [[ -z $value || ${#value} -gt 160 || $value == *$'\n'* || $value == *$'\r'* ]]; then
        value=unavailable:unsupported-value
      fi
      case $key in
        source_commit|zi_head*)
          if [[ $value != unavailable:* &&
            ( ${#value} != 40 || $value == *[^0-9a-f]* ) ]]; then
            value=unavailable:invalid-commit
          fi
          ;;
      esac
      records+=( "$key=$value" )
    done
  fi
  cleanup_status=$pty_cleanup_status
  if [[ -n $tmpdir ]]; then
    fixture_cleanup_status=0
    rm -rf -- "$tmpdir" || fixture_cleanup_status=$?
    (( cleanup_status != 0 )) || cleanup_status=$fixture_cleanup_status
  fi
  records+=( "cleanup_status=$cleanup_status"
    "pty_cleanup_status=$pty_cleanup_status" "fixture_cleanup_status=$fixture_cleanup_status" )
  (( cleanup_status == 0 )) ||
    print -ru2 -- "upstream smoke cleanup failed: status $cleanup_status"
  if [[ -n $evidence_dir ]]; then
    if [[ ! -d $evidence_dir || -h $evidence_dir || -e $result_file || -h $result_file ]] ||
      ! print -rl -- "${(@)records}" >"$result_file"; then
      print -ru2 -- 'could not retain smoke result'
    fi
  fi
  exit $original_status
}
trap 'finish_smoke $?' EXIT
tmpdir=$(mktemp -d)
readonly tmpdir

function fail {
  print -ru2 -- "upstream smoke failed: $1"
  exit 1
}

function count_fixed_string_occurrences {
  emulate -L zsh
  setopt nounset err_return pipefail
  local needle=$1
  local input=$2
  integer count=0

  count=$(LC_ALL=C grep -Fo -- "$needle" "$input" 2>/dev/null | wc -l) || count=0
  REPLY=$count
}

function drain_startup_output {
  emulate -L zsh
  setopt nounset err_return pipefail
  local name=$1
  local output=$2
  local chunk

  while zpty -r "$name" chunk; do
    print -rn -- "$chunk" >>"$output"
  done
}

function service_startup_output {
  emulate -L zsh
  setopt nounset err_return pipefail
  local name=$1
  local output=$2
  local compinit_prompt=$3
  integer compinit_prompts_answered=$4
  integer compinit_prompt_count=0
  drain_startup_output "$name" "$output"
  count_fixed_string_occurrences "$compinit_prompt" "$output"
  compinit_prompt_count=$REPLY
  while (( compinit_prompts_answered < compinit_prompt_count )); do
    zpty -w "$name" y || fail_startup "$name" "$output" \
      "could not answer a compinit prompt for $name"
    (( ++compinit_prompts_answered ))
  done
  REPLY=$compinit_prompts_answered
}

function print_startup_diagnostics {
  emulate -L zsh
  setopt nounset err_return pipefail
  local output=$1
  [[ -r $output ]] || return 0

  integer line_count
  line_count=$(wc -l <"$output")
  (( line_count > 0 )) || line_count=1
  integer first_line=$(( line_count > 240 ? line_count - 239 : 1 ))
  print -ru2 -- "last startup transcript lines:"
  sed -n "${first_line},\$p" "$output" >&2
}

function fail_startup {
  emulate -L zsh
  setopt nounset err_return pipefail
  local name=$1
  local output=$2
  local message=$3

  drain_startup_output "$name" "$output"

  print_startup_diagnostics "$output"
  zpty -d "$name" || true
  fail "$message"
}

[[ -n $zsh_bin ]] || fail 'zsh startup command is required'
(( $+commands[git] )) || fail 'git is required'
zmodload zsh/zpty || fail 'zsh/zpty is required'
zmodload zsh/datetime || fail 'zsh/datetime is required'
smoke_zpty_ready=1
autoload -Uz is-at-least
is-at-least 5.9 || fail "Zsh 5.9 or newer is required; found $ZSH_VERSION"
readonly prompt_timeout_seconds=${UPSTREAM_SMOKE_PROMPT_TIMEOUT_SECONDS:-300}
[[ $prompt_timeout_seconds == <1-> ]] ||
  fail 'UPSTREAM_SMOKE_PROMPT_TIMEOUT_SECONDS must be a positive integer'
readonly prompt_timeout_ticks=$(( prompt_timeout_seconds * 20 ))
readonly phase_timeout_ticks=1200

smoke_phase=fixture
fixture_home=$tmpdir/home
fixture_zdotdir=$fixture_home/.config/zsh
fixture_bin=$tmpdir/bin
shim_dir=$fixture_home/.local/lib/secret-exec/bin
mkdir -p -- $fixture_zdotdir $fixture_bin $shim_dir

ln -s -- $repo_root/zshenv.zsh $fixture_home/.zshenv
for source_file in \
  zprofile.zsh zshrc.zsh environment.zsh profiles.zsh startup.zsh \
  p10k-fancy.zsh p10k-plain.zsh
do
  ln -s -- $repo_root/$source_file $fixture_zdotdir/$source_file
done
ln -s -- zprofile.zsh $fixture_zdotdir/.zprofile
print -rl -- \
  'source "$ZDOTDIR/zshrc.zsh"' \
  'PROMPT=__UPSTREAM_SMOKE_PROMPT__' \
  'RPROMPT=' \
  >$fixture_zdotdir/.zshrc
ln -s -- $repo_root/profile.d $fixture_zdotdir/profile.d

print -rl -- '#!/usr/bin/env zsh' 'exit 0' >$shim_dir/k9s
chmod +x $shim_dir/k9s

function run_startup {
  emulate -L zsh
  setopt nounset err_return pipefail
  local ordinal=$1
  local name=upstream-smoke-$ordinal
  local output=$tmpdir/startup-$ordinal.stdout
  local prompt_marker=__UPSTREAM_SMOKE_PROMPT__
  local compinit_prompt='Ignore insecure '
  local command_text='integer shim_count=0; local entry; for entry in $path; do [[ $entry == $HOME/.local/lib/secret-exec/bin ]] && (( ++shim_count )); done; print -r -- "SMOKE_READY=${+functions[zi]}"; print -r -- "SMOKE_COMPDEF=${+functions[compdef]}"; print -r -- "SMOKE_PATH_FIRST=$path[1]"; print -r -- "SMOKE_K9S=${commands[k9s]:A}"; print -r -- "SMOKE_SHIM_COUNT=$shim_count"; print -r -- "SMOKE_EXIT=clean"'

  local -a startup_argv=(
    env -i
    HOME=$fixture_home
    PATH=$fixture_bin:/usr/bin:/bin
    SSH_CONNECTION=fixture
    TERM=dumb
    TERM_PROGRAM=CodexUpstreamSmoke
    WARP_COMPAT=1
    $zsh_bin -i
  )
  smoke_phase=startup-$ordinal/prompt
  zpty -b "$name" "${(@q)startup_argv}"

  local REPLY
  integer compinit_prompts_answered=0
  integer ticks=0
  while zpty -t "$name"; do
    service_startup_output \
      "$name" "$output" "$compinit_prompt" "$compinit_prompts_answered"
    compinit_prompts_answered=$REPLY
    LC_ALL=C grep -Fq "$prompt_marker" "$output" 2>/dev/null && break
    sleep 0.05
    if (( ++ticks >= prompt_timeout_ticks )); then
      fail_startup "$name" "$output" \
        "interactive startup $ordinal did not reach a prompt within ${prompt_timeout_seconds} seconds"
    fi
  done
  zpty -t "$name" || fail_startup "$name" "$output" \
    "interactive startup $ordinal exited before reaching a prompt"

  smoke_phase=startup-$ordinal/deferred
  # Advance several prompt cycles so Zi's ordered wait queues can drain.
  integer prompt_cycle
  integer prompt_count_before=0
  integer prompt_count_after=0
  for prompt_cycle in 1 2 3; do
    count_fixed_string_occurrences "$prompt_marker" "$output"
    prompt_count_before=$REPLY
    zpty -w "$name" ':' || fail_startup "$name" "$output" \
      "could not advance deferred prompt cycle $prompt_cycle for $name"

    ticks=0
    while zpty -t "$name"; do
      service_startup_output \
        "$name" "$output" "$compinit_prompt" "$compinit_prompts_answered"
      compinit_prompts_answered=$REPLY
      count_fixed_string_occurrences "$prompt_marker" "$output"
      prompt_count_after=$REPLY
      (( prompt_count_after > prompt_count_before )) && break
      sleep 0.05
      if (( ++ticks >= phase_timeout_ticks )); then
        fail_startup "$name" "$output" \
          "interactive startup $ordinal did not finish deferred prompt cycle $prompt_cycle within one minute"
      fi
    done
    zpty -t "$name" || fail_startup "$name" "$output" \
      "interactive startup $ordinal exited during deferred prompt cycle $prompt_cycle"
  done

  smoke_phase=startup-$ordinal/completion
  integer completion_probe=0
  local completion_marker
  local -F completion_deadline=$(( EPOCHREALTIME + 60 ))
  while true; do
    completion_marker=__UPSTREAM_SMOKE_COMPDEF_$(( ++completion_probe ))__
    count_fixed_string_occurrences "$prompt_marker" "$output"
    prompt_count_before=$REPLY
    zpty -w "$name" "print -r -- \"$completion_marker=\${+functions[compdef]}\"" ||
      fail_startup "$name" "$output" "could not check completion readiness for $name"

    while zpty -t "$name"; do
      service_startup_output \
        "$name" "$output" "$compinit_prompt" "$compinit_prompts_answered"
      compinit_prompts_answered=$REPLY
      (( EPOCHREALTIME < completion_deadline )) ||
        fail_startup "$name" "$output" \
          "interactive startup $ordinal did not initialize compdef within one minute"
      count_fixed_string_occurrences "$prompt_marker" "$output"
      prompt_count_after=$REPLY
      if (( prompt_count_after > prompt_count_before )) &&
        { LC_ALL=C grep -Fq "$completion_marker=0" "$output" 2>/dev/null ||
          LC_ALL=C grep -Fq "$completion_marker=1" "$output" 2>/dev/null; }; then
        break
      fi
      sleep 0.05
    done
    zpty -t "$name" || fail_startup "$name" "$output" \
      "interactive startup $ordinal exited before completion initialized"
    LC_ALL=C grep -Fq "$completion_marker=1" "$output" 2>/dev/null && break
    sleep 0.05
  done

  count_fixed_string_occurrences "$prompt_marker" "$output"
  prompt_count_before=$REPLY
  smoke_phase=startup-$ordinal/probe
  zpty -w "$name" "$command_text" || fail_startup "$name" "$output" \
    "could not start the smoke probe for $name"

  ticks=0
  while zpty -t "$name"; do
    service_startup_output \
      "$name" "$output" "$compinit_prompt" "$compinit_prompts_answered"
    compinit_prompts_answered=$REPLY
    count_fixed_string_occurrences "$prompt_marker" "$output"
    prompt_count_after=$REPLY
    if LC_ALL=C grep -Fq 'SMOKE_EXIT=clean' "$output" 2>/dev/null &&
      (( prompt_count_after > prompt_count_before )); then
      break
    fi
    sleep 0.05
    if (( ++ticks >= phase_timeout_ticks )); then
      fail_startup "$name" "$output" \
        "interactive startup $ordinal did not finish the smoke probe within one minute"
    fi
  done
  zpty -t "$name" || fail_startup "$name" "$output" \
    "interactive startup $ordinal exited before finishing the smoke probe"

  smoke_phase=startup-$ordinal/exit
  zpty -w "$name" exit || fail_startup "$name" "$output" \
    "could not request a clean exit from $name"

  ticks=0
  while zpty -t "$name"; do
    service_startup_output \
      "$name" "$output" "$compinit_prompt" "$compinit_prompts_answered"
    compinit_prompts_answered=$REPLY
    sleep 0.05
    if (( ++ticks >= phase_timeout_ticks )); then
      fail_startup "$name" "$output" \
        "interactive startup $ordinal did not exit within one minute"
    fi
  done
  drain_startup_output "$name" "$output"

  smoke_phase=startup-$ordinal/assertions
  LC_ALL=C grep -Fq 'SMOKE_READY=1' "$output" ||
    fail_startup "$name" "$output" "interactive startup $ordinal did not load Zi"
  LC_ALL=C grep -Fq 'SMOKE_COMPDEF=1' "$output" ||
    fail_startup "$name" "$output" "interactive startup $ordinal did not initialize compdef"
  LC_ALL=C grep -Fq "SMOKE_PATH_FIRST=$shim_dir" "$output" ||
    fail_startup "$name" "$output" "interactive startup $ordinal displaced the secret-exec shim"
  LC_ALL=C grep -Fq "SMOKE_K9S=${shim_dir:A}/k9s" "$output" ||
    fail_startup "$name" "$output" "interactive startup $ordinal resolved k9s outside the shim"
  LC_ALL=C grep -Fq 'SMOKE_SHIM_COUNT=1' "$output" ||
    fail_startup "$name" "$output" "interactive startup $ordinal produced duplicate managed PATH entries"
  LC_ALL=C grep -Fq 'SMOKE_EXIT=clean' "$output" ||
    fail_startup "$name" "$output" "interactive startup $ordinal did not reach clean exit"
  zpty -d "$name" || true
}

run_startup 1
[[ -r $fixture_home/.local/share/zi/bin/zi.zsh ]] ||
  fail 'the first startup did not install real Zi'
smoke_phase=zi-head-before
zi_head_before=$(git -C "$fixture_home/.local/share/zi/bin" rev-parse HEAD)
run_startup 2
smoke_phase=zi-head-after
zi_head_after=$(git -C "$fixture_home/.local/share/zi/bin" rev-parse HEAD)
smoke_phase=zi-consistency
[[ $zi_head_after == $zi_head_before ]] ||
  fail 'the second startup unexpectedly replaced the Zi checkout'

smoke_phase=complete

print -r -- 'upstream Zi smoke checks passed'
