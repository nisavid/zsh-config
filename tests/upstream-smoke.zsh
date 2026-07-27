#!/usr/bin/env -S zsh -f

emulate -L zsh
setopt errexit nounset pipefail

readonly repo_root=${0:A:h:h}
readonly zsh_bin=${commands[zsh]:A}
tmpdir=$(mktemp -d)
readonly tmpdir
trap 'rm -rf -- $tmpdir' EXIT

function fail {
  print -ru2 -- "upstream smoke failed: $1"
  exit 1
}

function count_fixed_string_occurrences {
  local needle=$1
  local input=$2
  integer count=0

  count=$(grep -Fo -- "$needle" "$input" 2>/dev/null | wc -l) || count=0
  REPLY=$count
}

function drain_startup_output {
  local name=$1
  local output=$2
  local chunk

  while zpty -r "$name" chunk; do
    print -rn -- "$chunk" >>"$output"
  done
}

function service_startup_output {
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
  local output=$1
  [[ -r $output ]] || return

  integer line_count
  line_count=$(wc -l <"$output")
  (( line_count > 0 )) || line_count=1
  integer first_line=$(( line_count > 240 ? line_count - 239 : 1 ))
  print -ru2 -- "last startup transcript lines:"
  sed -n "${first_line},\$p" "$output" >&2
}

function fail_startup {
  local name=$1
  local output=$2
  local message=$3

  drain_startup_output "$name" "$output"
  print_startup_diagnostics "$output"
  zpty -d "$name" 2>/dev/null || true
  fail "$message"
}

(( $+commands[git] )) || fail 'git is required'
zmodload zsh/zpty || fail 'zsh/zpty is required'
autoload -Uz is-at-least
is-at-least 5.9 || fail "Zsh 5.9 or newer is required; found $ZSH_VERSION"
readonly prompt_timeout_seconds=${UPSTREAM_SMOKE_PROMPT_TIMEOUT_SECONDS:-300}
[[ $prompt_timeout_seconds == <1-> ]] ||
  fail 'UPSTREAM_SMOKE_PROMPT_TIMEOUT_SECONDS must be a positive integer'
readonly prompt_timeout_ticks=$(( prompt_timeout_seconds * 20 ))
readonly phase_timeout_ticks=1200

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
  zpty -b "$name" "${(@q)startup_argv}"

  local REPLY
  integer compinit_prompts_answered=0
  integer ticks=0
  while zpty -t "$name"; do
    service_startup_output \
      "$name" "$output" "$compinit_prompt" "$compinit_prompts_answered"
    compinit_prompts_answered=$REPLY
    grep -Fq "$prompt_marker" "$output" 2>/dev/null && break
    sleep 0.05
    if (( ++ticks >= prompt_timeout_ticks )); then
      fail_startup "$name" "$output" \
        "interactive startup $ordinal did not reach a prompt within ${prompt_timeout_seconds} seconds"
    fi
  done
  zpty -t "$name" || fail_startup "$name" "$output" \
    "interactive startup $ordinal exited before reaching a prompt"

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

  count_fixed_string_occurrences "$prompt_marker" "$output"
  prompt_count_before=$REPLY
  zpty -w "$name" "$command_text" || fail_startup "$name" "$output" \
    "could not start the smoke probe for $name"

  ticks=0
  while zpty -t "$name"; do
    service_startup_output \
      "$name" "$output" "$compinit_prompt" "$compinit_prompts_answered"
    compinit_prompts_answered=$REPLY
    count_fixed_string_occurrences "$prompt_marker" "$output"
    prompt_count_after=$REPLY
    if grep -Fq 'SMOKE_EXIT=clean' "$output" 2>/dev/null &&
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

  grep -Fq 'SMOKE_READY=1' "$output" ||
    fail_startup "$name" "$output" "interactive startup $ordinal did not load Zi"
  grep -Fq 'SMOKE_COMPDEF=1' "$output" ||
    fail_startup "$name" "$output" "interactive startup $ordinal did not initialize compdef"
  grep -Fq "SMOKE_PATH_FIRST=$shim_dir" "$output" ||
    fail_startup "$name" "$output" "interactive startup $ordinal displaced the secret-exec shim"
  grep -Fq "SMOKE_K9S=${shim_dir:A}/k9s" "$output" ||
    fail_startup "$name" "$output" "interactive startup $ordinal resolved k9s outside the shim"
  grep -Fq 'SMOKE_SHIM_COUNT=1' "$output" ||
    fail_startup "$name" "$output" "interactive startup $ordinal produced duplicate managed PATH entries"
  grep -Fq 'SMOKE_EXIT=clean' "$output" ||
    fail_startup "$name" "$output" "interactive startup $ordinal did not reach clean exit"
  zpty -d "$name" 2>/dev/null || true
}

run_startup 1
[[ -r $fixture_home/.local/share/zi/bin/zi.zsh ]] ||
  fail 'the first startup did not install real Zi'
zi_head_before=$(git -C "$fixture_home/.local/share/zi/bin" rev-parse HEAD)
run_startup 2
zi_head_after=$(git -C "$fixture_home/.local/share/zi/bin" rev-parse HEAD)
[[ $zi_head_after == $zi_head_before ]] ||
  fail 'the second startup unexpectedly replaced the Zi checkout'

print -r -- 'upstream Zi smoke checks passed'
