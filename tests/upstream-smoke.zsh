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

(( $+commands[git] )) || fail 'git is required'
zmodload zsh/zpty || fail 'zsh/zpty is required'
autoload -Uz is-at-least
is-at-least 5.9 || fail "Zsh 5.9 or newer is required; found $ZSH_VERSION"
readonly prompt_timeout_seconds=${UPSTREAM_SMOKE_PROMPT_TIMEOUT_SECONDS:-300}
[[ $prompt_timeout_seconds == <1-> ]] ||
  fail 'UPSTREAM_SMOKE_PROMPT_TIMEOUT_SECONDS must be a positive integer'
readonly prompt_timeout_ticks=$(( prompt_timeout_seconds * 20 ))

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
  zpty -b $name "${(@q)startup_argv}"

  local chunk
  integer ticks=0
  while zpty -t $name && ! grep -Fq $prompt_marker $output 2>/dev/null; do
    while zpty -r $name chunk; do
      print -rn -- $chunk >>$output
    done
    sleep 0.05
    (( ++ticks < prompt_timeout_ticks )) ||
      fail "interactive startup $ordinal did not reach a prompt within ${prompt_timeout_seconds} seconds"
  done
  zpty -t $name ||
    fail "interactive startup $ordinal exited before reaching a prompt"

  # Advance several prompt cycles so Zi's ordered wait queues can drain.
  integer prompt_cycle
  for prompt_cycle in 1 2 3; do
    zpty -w $name ':'
    sleep 3
    while zpty -r $name chunk; do
      print -rn -- $chunk >>$output
    done
  done
  zpty -w $name $command_text
  zpty -w $name exit

  ticks=0
  while zpty -t $name; do
    while zpty -r $name chunk; do
      print -rn -- $chunk >>$output
    done
    sleep 0.05
    (( ++ticks < 1200 )) ||
      fail "interactive startup $ordinal did not exit within one minute"
  done
  while zpty -r $name chunk; do
    print -rn -- $chunk >>$output
  done

  grep -Fq 'SMOKE_READY=1' $output || fail "interactive startup $ordinal did not load Zi"
  grep -Fq 'SMOKE_COMPDEF=1' $output || fail "interactive startup $ordinal did not initialize compdef"
  grep -Fq "SMOKE_PATH_FIRST=$shim_dir" $output ||
    fail "interactive startup $ordinal displaced the secret-exec shim"
  grep -Fq "SMOKE_K9S=${shim_dir:A}/k9s" $output ||
    fail "interactive startup $ordinal resolved k9s outside the shim"
  grep -Fq 'SMOKE_SHIM_COUNT=1' $output ||
    fail "interactive startup $ordinal produced duplicate managed PATH entries"
  grep -Fq 'SMOKE_EXIT=clean' $output ||
    fail "interactive startup $ordinal did not reach clean exit"
}

run_startup 1
[[ -r $fixture_home/.local/share/zi/bin/zi.zsh ]] ||
  fail 'the first startup did not install real Zi'
zi_head_before=$(git -C $fixture_home/.local/share/zi/bin rev-parse HEAD)
run_startup 2
zi_head_after=$(git -C $fixture_home/.local/share/zi/bin rev-parse HEAD)
[[ $zi_head_after == $zi_head_before ]] ||
  fail 'the second startup unexpectedly replaced the Zi checkout'

print -r -- 'upstream Zi smoke checks passed'
