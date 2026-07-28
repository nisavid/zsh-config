#!/usr/bin/env -S zsh -f

emulate -L zsh
setopt errexit nounset pipefail

readonly repo_root=${0:A:h:h}
readonly zsh_bin=${commands[zsh]:A}
tmpdir=$(mktemp -d)
readonly tmpdir
trap 'rm -rf -- $tmpdir' EXIT

function fail {
  print -ru2 -- "startup-matrix test failed: $1"
  return 1
}

function fixture_git {
  env GIT_CONFIG_COUNT=0 GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 \
    git "$@"
}

function copy_tracked_checkout {
  local source=$1
  local destination=$2
  local manifest=$tmpdir/tracked-checkout-paths
  local entry
  local indexed_mode
  local relative_path

  fixture_git -c safe.directory="$source" \
    -C "$source" ls-files -s -z >"$manifest" || return
  mkdir -p -- "$destination" || return
  while IFS= read -r -d '' entry; do
    indexed_mode=${entry%% *}
    relative_path=${entry#*$'\t'}
    case $indexed_mode in
      100644|100755)
        [[ -f $source/$relative_path && ! -L $source/$relative_path ]] ||
          continue
        ;;
      120000)
        [[ -L $source/$relative_path ]] || continue
        ;;
      *)
        fail "unsupported tracked fixture mode: $indexed_mode"
        return 1
        ;;
    esac
    mkdir -p -- "$destination/${relative_path:h}" || return
    cp -a -- "$source/$relative_path" \
      "$destination/$relative_path" || return
  done <"$manifest"
}

function count_entry {
  local needle=$1
  shift
  integer count=0
  local entry
  for entry in "$@"; do
    [[ $entry == $needle ]] && (( ++count ))
  done
  REPLY=$count
}

tracked_copy_source=$tmpdir/tracked-copy-source
tracked_copy_destination=$tmpdir/tracked-copy-destination
mkdir -p -- "$tracked_copy_source"
fixture_git -C "$tracked_copy_source" init --quiet --initial-branch=main
print -r -- 'ignored.local' >"$tracked_copy_source/.gitignore"
print -r -- indexed >"$tracked_copy_source/tracked"
print -r -- deleted >"$tracked_copy_source/deleted"
print -r -- collision >"$tracked_copy_source/collision"
ln -s -- missing-target "$tracked_copy_source/dangling"
print -r -- ignored >"$tracked_copy_source/ignored.local"
fixture_git -C "$tracked_copy_source" add -- \
  .gitignore collision dangling deleted tracked
print -r -- working-tree >"$tracked_copy_source/tracked"
print -r -- untracked >"$tracked_copy_source/untracked.local"
rm -f -- "$tracked_copy_source/deleted" "$tracked_copy_source/collision"
mkdir -p -- "$tracked_copy_source/collision"
print -r -- operator-secret >"$tracked_copy_source/collision/untracked.local"
copy_tracked_checkout "$tracked_copy_source" "$tracked_copy_destination" ||
  fail 'could not construct the tracked-copy regression fixture'
[[ -r $tracked_copy_destination/tracked ]] ||
  fail 'tracked-checkout copying omitted a tracked working-tree file'
[[ $(<$tracked_copy_destination/tracked) == working-tree ]] ||
  fail 'tracked-checkout copying ignored modified tracked content'
[[ ! -e $tracked_copy_destination/ignored.local ]] ||
  fail 'tracked-checkout copying included an ignored working-tree file'
[[ ! -e $tracked_copy_destination/untracked.local ]] ||
  fail 'tracked-checkout copying included an untracked working-tree file'
[[ ! -e $tracked_copy_destination/deleted ]] ||
  fail 'tracked-checkout copying recreated a deleted tracked file'
[[ ! -e $tracked_copy_destination/collision ]] ||
  fail 'tracked-checkout copying included a tracked-file directory replacement'
[[ -L $tracked_copy_destination/dangling ]] &&
  [[ $(readlink -- "$tracked_copy_destination/dangling") == missing-target ]] ||
  fail 'tracked-checkout copying did not preserve a dangling tracked symlink'
[[ ! -e $tracked_copy_destination/.git ]] ||
  fail 'tracked-checkout copying included source Git metadata'

forced_owner_destination=$tmpdir/forced-owner-destination
GIT_TEST_ASSUME_DIFFERENT_OWNER=1 \
  copy_tracked_checkout \
    "$tracked_copy_source" "$forced_owner_destination" ||
  fail 'tracked-checkout copying did not trust the exact source checkout'
[[ $(<$forced_owner_destination/tracked) == working-tree ]] ||
  fail 'forced-owner copying did not preserve modified tracked content'

gitlink_destination=$tmpdir/gitlink-destination
gitlink_log=$tmpdir/gitlink.log
fixture_git -C "$tracked_copy_source" update-index \
  --add --info-only \
  --cacheinfo 160000,1111111111111111111111111111111111111111,gitlink
mkdir -p -- "$tracked_copy_source/gitlink"
print -r -- operator-secret >"$tracked_copy_source/gitlink/untracked.local"
if copy_tracked_checkout \
  "$tracked_copy_source" "$gitlink_destination" 2>"$gitlink_log"; then
  fail 'tracked-checkout copying accepted an unsupported gitlink'
fi
grep -Fq 'unsupported tracked fixture mode: 160000' "$gitlink_log" ||
  fail 'tracked-checkout copying did not report an unsupported gitlink'
[[ ! -e $gitlink_destination/gitlink ]] ||
  fail 'tracked-checkout copying imported an unsupported gitlink directory'

fixture_home=$tmpdir/home
fixture_config=$fixture_home/.config
fixture_zdotdir=$fixture_config/zsh
fixture_bin=$tmpdir/bin
fixture_fpath=$tmpdir/fpath
homebrew_prefix=$fixture_home/homebrew
shim_dir=$fixture_home/.local/lib/secret-exec/bin
local_bin=$fixture_home/.local/bin
lmstudio_bin=$fixture_home/.lmstudio/bin
kde_src=$fixture_home/src/kde
kde_bin=$kde_src/kdesrc-build
krew_root=$fixture_home/.local/share/krew
krew_bin=$krew_root/bin
orb_bin=$fixture_home/.orbstack/bin
orb_shell=$fixture_home/.orbstack/shell
orb_completions=$orb_shell/completions/zsh
vite_home=$fixture_home/.vite-plus
vite_bin=$vite_home/bin
bun_bin=$fixture_home/.bun/bin
pnpm_home=$fixture_home/pnpm
pnpm_bin=$pnpm_home/bin
cargo_bin=$fixture_home/.cargo/bin
go_bin=$fixture_home/go/bin
appimage_bin=$local_bin/appimage
pyenv_bin=$fixture_home/.local/share/pyenv/bin
zi_home=$fixture_home/.local/share/zi
zi_bin=$zi_home/bin
zi_polaris_bin=$zi_home/polaris/bin
zi_polaris_sbin=$zi_home/polaris/sbin
rustup_bin=$homebrew_prefix/opt/rustup/bin
homebrew_bin=$homebrew_prefix/bin
homebrew_sbin=$homebrew_prefix/sbin

mkdir -p -- \
  $fixture_config/environment.d $fixture_zdotdir $fixture_bin $fixture_fpath \
  $shim_dir $lmstudio_bin $kde_bin $krew_bin \
  $orb_bin $orb_completions $vite_bin $bun_bin $pnpm_bin \
  $cargo_bin $go_bin $pyenv_bin $zi_bin \
  $zi_polaris_bin $zi_polaris_sbin $rustup_bin $homebrew_bin $homebrew_sbin

print -rl -- \
  'function compdef { : }' \
  'typeset -g ZI_TEST_COMPINIT_RAN=1' \
  >$fixture_fpath/compinit

ln -s -- $repo_root/zshenv.zsh $fixture_home/.zshenv
ln -s -- $repo_root/zprofile.zsh $fixture_zdotdir/zprofile.zsh
ln -s -- zprofile.zsh $fixture_zdotdir/.zprofile
ln -s -- $repo_root/.zshrc $fixture_zdotdir/.zshrc
ln -s -- $repo_root/environment.zsh $fixture_zdotdir/environment.zsh
ln -s -- $repo_root/profiles.zsh $fixture_zdotdir/profiles.zsh
ln -s -- $repo_root/startup.zsh $fixture_zdotdir/startup.zsh

print -rl -- \
  "XDG_CONFIG_HOME=$fixture_config" \
  "XDG_DATA_HOME=$fixture_home/.local/share" \
  "HOMEBREW_PREFIX=$homebrew_prefix" \
  "KDE_SRC=$kde_src" \
  "KREW_ROOT=$krew_root" \
  "PNPM_HOME=$pnpm_home" \
  "GOBIN=$go_bin" \
  "PATH=\$PATH:$homebrew_bin:/usr/bin::/usr/bin" \
  >$fixture_config/environment.d/00-fixture.conf

print -rl -- "#!$zsh_bin" 'exit 0' >$shim_dir/k9s
print -rl -- "#!$zsh_bin" 'exit 0' >$homebrew_bin/k9s
print -rl -- \
  "#!$zsh_bin" \
  "print -r -- ${(q)fixture_home}/fixture-man:${(q)fixture_home}/fixture-man-extra" \
  >$fixture_bin/manpath
fnm_multishell_bin=$fixture_home/.local/state/fnm_multishell/bin
fnm_refreshed_bin=$fixture_home/.local/state/fnm_multishell_refreshed/bin
fnm_partial_bin=$fixture_home/.local/state/fnm-partial/bin
mkdir -p -- $fnm_multishell_bin $fnm_refreshed_bin $fnm_partial_bin
print -rl -- \
  "#!$zsh_bin" \
  'function print_valid_env {' \
  '  local fnm_dir=${1:-$HOME/.local/share/fnm}' \
  '  local multishell=${FNM_MULTISHELL_VALUE:-$HOME/.local/state/fnm_multishell}' \
  '  local path_prefix=${FNM_PATH_PREFIX-$multishell/bin}' \
  '  local omit=${FNM_OMIT_NAME:-}' \
  '  [[ $omit == PATH ]] || print -r -- "export PATH=\"$path_prefix:\$PATH\""' \
  '  [[ $omit == FNM_MULTISHELL_PATH ]] || print -r -- "export FNM_MULTISHELL_PATH=\"$multishell\""' \
  '  [[ $omit == FNM_VERSION_FILE_STRATEGY ]] || print -r -- '\''export FNM_VERSION_FILE_STRATEGY="local"'\''' \
  '  [[ $omit == FNM_DIR ]] || print -r -- "export FNM_DIR=\"$fnm_dir\""' \
  '  [[ $omit == FNM_LOGLEVEL ]] || print -r -- '\''export FNM_LOGLEVEL="info"'\''' \
  '  [[ $omit == FNM_NODE_DIST_MIRROR ]] || print -r -- '\''export FNM_NODE_DIST_MIRROR="https://nodejs.org/dist"'\''' \
  '  [[ $omit == FNM_COREPACK_ENABLED ]] || print -r -- '\''export FNM_COREPACK_ENABLED="false"'\''' \
  '  [[ $omit == FNM_RESOLVE_ENGINES ]] || print -r -- '\''export FNM_RESOLVE_ENGINES="true"'\''' \
  '  [[ $omit == FNM_ARCH ]] || print -r -- '\''export FNM_ARCH="arm64"'\''' \
  '  print -r -- rehash' \
  '}' \
  'case ${FNM_TEST_MODE:-success} in' \
  '  (empty) exit 17 ;;' \
  '  (success-empty) exit 0 ;;' \
  '  (partial)' \
  '    print -r -- "export PATH=\"$HOME/.local/state/fnm-partial/bin:\$PATH\""' \
  '    exit 17' \
  '    ;;' \
  '  (return)' \
  '    print_valid_env' \
  '    print -r -- "return 23"' \
  '    ;;' \
  '  (exit)' \
  '    print_valid_env' \
  '    print -r -- "exit 23"' \
  '    ;;' \
  '  (quoted-exit)' \
  '    print_valid_env' \
  '    print -r -- '\''print -r -- "exit 23"'\''' \
  '    ;;' \
  '  (expanded-exit)' \
  '    print_valid_env' \
  '    print -r -- '\''${:-exit 23}'\''' \
  '    ;;' \
  '  (literal-exit)' \
  '    print_valid_env "$HOME/.local/share/fnm-exit-literal"' \
  '    ;;' \
  '  (missing-key)' \
  '    FNM_OMIT_NAME=FNM_ARCH print_valid_env' \
  '    ;;' \
  '  (mismatched-path)' \
  '    FNM_PATH_PREFIX=$HOME/.local/state/fnm-wrong/bin print_valid_env' \
  '    ;;' \
  '  (empty-path)' \
  '    FNM_PATH_PREFIX= print_valid_env' \
  '    ;;' \
  '  (refresh)' \
  '    FNM_MULTISHELL_VALUE=$HOME/.local/state/fnm_multishell_refreshed print_valid_env' \
  '    ;;' \
  '  (*) print_valid_env ;;' \
  'esac' \
  >$fixture_bin/fnm
chmod +x $shim_dir/k9s $homebrew_bin/k9s $fixture_bin/fnm $fixture_bin/manpath

# Match OrbStack's real, non-idempotent initializer. The startup contract must
# never source this mixed PATH/fpath bundle.
print -rl -- \
  'typeset -gi ORBSTACK_LOAD_COUNT=${ORBSTACK_LOAD_COUNT:-0}' \
  '(( ORBSTACK_LOAD_COUNT++ ))' \
  'export PATH="$PATH":$HOME/.orbstack/bin' \
  'fpath+=$HOME/.orbstack/shell/completions/zsh' \
  >$orb_shell/init.zsh

print -rl -- \
  '#!/bin/sh' \
  'export VP_HOME="$HOME/.vite-plus"' \
  'export PATH="$VP_HOME/bin:$PATH"' \
  'vp() { command vp "$@"; }' \
  'if [ -n "$ZSH_VERSION" ] && [ "${ZI_TEST_COMPINIT_RAN:-0}" = 1 ] && type compdef >/dev/null 2>&1; then' \
  '  typeset -g VITE_COMPLETION_LOADED=1' \
  'fi' \
  '[[ ${VITE_TEST_FAIL:-0} == 1 ]] && return 19' \
  >$vite_home/env

print -rl -- \
  "typeset -gA ZI=( PLUGINS_DIR ${(q)zi_home}/plugins )" \
  'function zi {' \
  '  local argument candidate condition atinit atload has id_as pick plugin_dir' \
  '  integer completion_init=0 defer=0' \
  '  for argument in "$@"; do' \
  '    case $argument in' \
  '      (wait|wait2|wait:*) defer=1 ;;' \
  '      (atinit:*) atinit=${argument#atinit:} ;;' \
  '      (atload:*) atload=${argument#atload:} ;;' \
  '      (atload=+*) atload=${argument#atload=+} ;;' \
  '      (has:*) has=${argument#has:} ;;' \
  '      (if:*) condition=${argument#if:} ;;' \
  '      (id-as:*) id_as=${argument#id-as:} ;;' \
  '      (pick:*) pick=${argument#pick:} ;;' \
  '      (system-completions) completion_init=1 ;;' \
  '      (/*) candidate=$argument ;;' \
  '    esac' \
  '  done' \
  '  [[ -z $has || $has != ${ZI_TEST_FORCE_MISSING_COMMAND:-} ]] || return 0' \
  '  [[ -z $has ]] || (( $+commands[$has] )) || return 0' \
  '  [[ -z $condition ]] || eval "$condition" || return 0' \
  '  [[ $id_as == completion-init ]] && completion_init=1' \
  '  if (( defer && completion_init )); then' \
  '    typeset -g ZI_TEST_WAIT1_ATLOAD=$atload' \
  '    return 0' \
  '  fi' \
  '  if (( defer )) && [[ $id_as == (fnm|vite-plus) ]]; then' \
  '    typeset -g ZI_TEST_DEFERRED_CANDIDATE=$candidate' \
  '    typeset -g ZI_TEST_DEFERRED_ATLOAD=$atload' \
  '    return 0' \
  '  fi' \
  '  if [[ -n $atinit ]]; then' \
  '    plugin_dir=$ZI[PLUGINS_DIR]/${id_as//\//---}' \
  '    mkdir -p -- "$plugin_dir"' \
  '    ( cd -- "$plugin_dir" && eval "$atinit" ) || return' \
  '  fi' \
  '  [[ -z $pick || ! -r $plugin_dir/$pick ]] || source "$plugin_dir/$pick"' \
  '  [[ -z $candidate || ! -r $candidate ]] || source "$candidate"' \
  '  [[ -z $atload ]] || eval "$atload"' \
  '}' \
  'function zi_test_run_deferred {' \
  '  if [[ -n ${ZI_TEST_WAIT1_ATLOAD:-} ]]; then' \
  '    eval "$ZI_TEST_WAIT1_ATLOAD"' \
  '    unset ZI_TEST_WAIT1_ATLOAD' \
  '  fi' \
  '  [[ -z ${ZI_TEST_DEFERRED_CANDIDATE:-} || ! -r $ZI_TEST_DEFERRED_CANDIDATE ]] ||' \
  '    source "$ZI_TEST_DEFERRED_CANDIDATE"' \
  '  [[ -z ${ZI_TEST_DEFERRED_ATLOAD:-} ]] || eval "$ZI_TEST_DEFERRED_ATLOAD"' \
  '  unset ZI_TEST_DEFERRED_CANDIDATE ZI_TEST_DEFERRED_ATLOAD' \
  '}' \
  'unfunction compdef 2>/dev/null' \
  'unset _comps 2>/dev/null' \
  'function zicompinit_fast {' \
  '  function compdef { : }' \
  '  typeset -g ZI_TEST_COMPINIT_RAN=1' \
  '}' \
  'function zicdreplay { : }' \
  >$zi_bin/zi.zsh

readonly initial_path=$fixture_bin:/usr/bin:$homebrew_bin:/usr/bin::/bin
probe_cwd=$tmpdir/probe-cwd
mkdir -p -- $probe_cwd
readonly probe_cwd

function shell_probe {
  local shell_flags=$1
  (
    cd -- $probe_cwd
    env -i \
      HOME=$fixture_home \
      PATH=$initial_path \
      SSH_CONNECTION=fixture \
      TERM=dumb \
      TERM_PROGRAM=CodexTest \
      WARP_COMPAT=1 \
      $zsh_bin $shell_flags \
      'local entry
     (( $+functions[zi_test_run_deferred] )) && zi_test_run_deferred
     integer empty_count=0 shim_count=0 system_count=0 orb_count=0
     integer local_bin_count=0 appimage_count=0 orb_completion_count=0
     for entry in $path; do
       [[ -n $entry ]] || (( empty_count++ ))
       [[ $entry == $HOME/.local/lib/secret-exec/bin ]] && (( shim_count++ ))
       [[ $entry == $HOME/.local/bin ]] && (( local_bin_count++ ))
       [[ $entry == $HOME/.local/bin/appimage ]] && (( appimage_count++ ))
       [[ $entry == /usr/bin ]] && (( system_count++ ))
       [[ $entry == $HOME/.orbstack/bin ]] && (( orb_count++ ))
     done
     for entry in $fpath; do
       [[ $entry == $HOME/.orbstack/shell/completions/zsh ]] &&
         (( orb_completion_count++ ))
     done
     print -r -- "PATH_FIRST=$path[1]"
     print -r -- "K9S=${commands[k9s]:A}"
     print -r -- "EMPTY_COUNT=$empty_count"
     print -r -- "SHIM_COUNT=$shim_count"
     print -r -- "LOCAL_BIN_COUNT=$local_bin_count"
     print -r -- "APPIMAGE_COUNT=$appimage_count"
     print -r -- "SYSTEM_COUNT=$system_count"
     print -r -- "ORB_COUNT=$orb_count"
     print -r -- "ORB_COMPLETION_COUNT=$orb_completion_count"
     print -r -- "ORB_LOADS=${ORBSTACK_LOAD_COUNT:-0}"
     print -r -- "VP_FUNCTION=${+functions[vp]}"
     print -r -- "VP_COMPLETION=${VITE_COMPLETION_LOADED:-0}"
     print -r -- "DEFERRED_HELPERS=${+functions[__zshrc_repair_deferred_path]}:${+functions[__zshrc_init_fnm]}"
     print -r -- "PNPM_HOME=$PNPM_HOME"
     print -r -- "KREW_ROOT=$KREW_ROOT"
     print -r -- "KDE_SRC=$KDE_SRC"
     if (( ${path[(I)/usr/local/bin]} )); then
       print -r -- "PATH_HELPER=present"
     else
       print -r -- "PATH_HELPER=absent"
     fi'
  )
}

function expect_probe {
  local label=$1 shell_flags=$2 expected_interactive=$3
  local stdout_file=$tmpdir/$label.stdout
  local stderr_file=$tmpdir/$label.stderr

  shell_probe $shell_flags >$stdout_file 2>$stderr_file ||
    fail "$label startup exited non-zero"

  grep -Fq "PATH_FIRST=$shim_dir" $stdout_file || {
    sed -n '1,120p' $stdout_file >&2
    sed -n '1,160p' $stderr_file >&2
    fail "$label must put the managed shim directory first"
  }
  grep -Fxq "K9S=${shim_dir:A}/k9s" $stdout_file ||
    fail "$label must resolve k9s through the managed shim"
  grep -Fxq 'EMPTY_COUNT=0' $stdout_file ||
    fail "$label must remove empty PATH entries"
  grep -Fxq 'SHIM_COUNT=1' $stdout_file ||
    fail "$label must keep exactly one shim PATH entry"
  grep -Fxq 'LOCAL_BIN_COUNT=1' $stdout_file ||
    fail "$label must reserve the owned local-bin root before bootstrap"
  grep -Fxq 'APPIMAGE_COUNT=1' $stdout_file ||
    fail "$label must reserve the owned AppImage root before bootstrap"
  grep -Fxq 'SYSTEM_COUNT=1' $stdout_file ||
    fail "$label must clean duplicate inherited system PATH entries"
  grep -Fxq 'ORB_COUNT=1' $stdout_file ||
    fail "$label must expose OrbStack exactly once without sourcing its bundle"
  grep -Fxq 'ORB_LOADS=0' $stdout_file ||
    fail "$label must not source OrbStack's mixed initializer"
  grep -Fxq "ORB_COMPLETION_COUNT=$expected_interactive" $stdout_file ||
    fail "$label has the wrong OrbStack fpath cardinality"
  grep -Fxq "VP_FUNCTION=$expected_interactive" $stdout_file ||
    fail "$label has the wrong Vite+ wrapper availability"
  grep -Fxq "VP_COMPLETION=$expected_interactive" $stdout_file ||
    fail "$label has the wrong Vite+ completion availability"
  grep -Fxq 'DEFERRED_HELPERS=0:0' $stdout_file ||
    fail "$label leaked deferred startup helpers into the shell namespace"
  if grep -Fq 'command not found: compdef' $stderr_file; then
    fail "$label inherited ambient completion state before fixture compinit"
  fi
  grep -Fxq "PNPM_HOME=$pnpm_home" $stdout_file ||
    fail "$label must export PNPM_HOME"
  grep -Fxq "KREW_ROOT=$krew_root" $stdout_file ||
    fail "$label must export KREW_ROOT"
  grep -Fxq "KDE_SRC=$kde_src" $stdout_file ||
    fail "$label must export KDE_SRC"

  if (( expected_interactive )); then
    grep -Fq 'zsh startup: removed exact duplicate PATH entry: /usr/bin' $stderr_file ||
      fail "$label must surface inherited duplicate cleanup"
    grep -Fq 'zsh startup: removed unsafe empty PATH entry' $stderr_file || {
      sed -n '1,180p' $stderr_file >&2
      fail "$label must surface empty-entry cleanup"
    }
  else
    if grep -Fq 'zsh startup:' $stderr_file; then
      fail "$label must not emit routine diagnostics in noninteractive startup"
    fi
  fi

  if [[ $OSTYPE == darwin* && $label == *-login ]]; then
    grep -Fxq 'PATH_HELPER=present' $stdout_file ||
      fail "$label must exercise macOS path_helper"
  fi
  return 0
}

expect_probe noninteractive-nonlogin -c 0
expect_probe interactive-nonlogin -ic 1
expect_probe noninteractive-login -lc 0
expect_probe interactive-login -lic 1
[[ ! -e $probe_cwd/init.zsh ]] ||
  fail 'interactive startup wrote a plugin cache into the shell working directory'
grep -Fq 'export -aT MANPATH' $zi_home/plugins/manpath/init.zsh ||
  fail 'interactive startup did not generate the MANPATH cache in its owned plugin directory'
grep -Fq "$fixture_home/fixture-man" $zi_home/plugins/manpath/init.zsh ||
  fail 'interactive startup did not use the fixture-owned manpath command'

vite_failure_stdout=$tmpdir/vite-failure.stdout
vite_failure_stderr=$tmpdir/vite-failure.stderr
env -i \
  HOME=$fixture_home \
  PATH=$initial_path \
  SSH_CONNECTION=fixture \
  TERM=dumb \
  TERM_PROGRAM=CodexTest \
  VITE_TEST_FAIL=1 \
  WARP_COMPAT=1 \
  $zsh_bin -ic \
  'zi_test_run_deferred
   print -r -- "PATH_FIRST=$path[1]"' \
  >$vite_failure_stdout 2>$vite_failure_stderr ||
  fail 'a deferred Vite+ source failure made the shell unusable'
grep -Fxq "PATH_FIRST=$shim_dir" $vite_failure_stdout ||
  fail 'a deferred Vite+ source failure displaced the managed shim'
grep -Fq 'Vite+ is installed but failed to load from' $vite_failure_stderr ||
  fail 'a deferred Vite+ source failure was silent'

mv -- $vite_home/env $tmpdir/vite-env.saved
fnm_deferred_stdout=$tmpdir/fnm-deferred.stdout
env -i \
  HOME=$fixture_home \
  PATH=$initial_path \
  SSH_CONNECTION=fixture \
  TERM=dumb \
  TERM_PROGRAM=CodexTest \
  WARP_COMPAT=1 \
  $zsh_bin -ic \
  'zi_test_run_deferred
   print -r -- "$path[1]"
   print -r -- "DEFERRED_HELPERS=${+functions[__zshrc_repair_deferred_path]}:${+functions[__zshrc_init_fnm]}"
   print -r -- "FNM_STATE=$FNM_DIR:${chpwd_functions[(I)_fnm_autoload_hook]}"' \
  >$fnm_deferred_stdout ||
  fail 'the deferred fnm startup branch failed without Vite+'
grep -Fxq $shim_dir $fnm_deferred_stdout ||
  fail 'deferred fnm setup displaced the managed shim directory'
grep -Fxq 'DEFERRED_HELPERS=0:0' $fnm_deferred_stdout ||
  fail 'deferred fnm setup leaked helpers into the shell namespace'
grep -Fxq "FNM_STATE=$fixture_home/.local/share/fnm:1" $fnm_deferred_stdout ||
  fail 'deferred fnm setup did not install its validated environment and chpwd hook'

fnm_refresh_stdout=$tmpdir/fnm-refresh.stdout
fnm_refresh_stderr=$tmpdir/fnm-refresh.stderr
env -i \
  HOME=$fixture_home \
  PATH=$initial_path \
  SSH_CONNECTION=fixture \
  TERM=dumb \
  TERM_PROGRAM=CodexTest \
  WARP_COMPAT=1 \
  $zsh_bin -ic \
  'local deferred_candidate=$ZI_TEST_DEFERRED_CANDIDATE
   local deferred_atload=$ZI_TEST_DEFERRED_ATLOAD
   zi_test_run_deferred
   export FNM_TEST_MODE=refresh
   ZI_TEST_DEFERRED_CANDIDATE=$deferred_candidate
   ZI_TEST_DEFERRED_ATLOAD=$deferred_atload
   zi_test_run_deferred
   integer hook_count=0 old_count=0 refreshed_count=0
   local entry
   for entry in $path; do
     [[ $entry == $HOME/.local/state/fnm_multishell/bin ]] &&
       (( ++old_count ))
     [[ $entry == $HOME/.local/state/fnm_multishell_refreshed/bin ]] &&
       (( ++refreshed_count ))
   done
   for entry in $chpwd_functions; do
     [[ $entry == _fnm_autoload_hook ]] &&
       (( ++hook_count ))
   done
   print -r -- "PATH_FIRST=$path[1]"
   print -r -- "OLD_FNM_COUNT=$old_count"
   print -r -- "REFRESHED_FNM_COUNT=$refreshed_count"
   print -r -- "FNM_MULTISHELL_PATH=$FNM_MULTISHELL_PATH"
   print -r -- "FNM_HOOK_COUNT=$hook_count"' \
  >$fnm_refresh_stdout 2>$fnm_refresh_stderr ||
  fail 'replaying deferred fnm setup made the shell unusable'
grep -Fxq "PATH_FIRST=$shim_dir" $fnm_refresh_stdout ||
  fail 'replaying deferred fnm setup displaced the managed shim'
! grep -Fq 'fnm generated shell environment output' $fnm_refresh_stderr ||
  fail 'replaying deferred fnm setup diagnosed its own installed hook'
grep -Fxq 'OLD_FNM_COUNT=0' $fnm_refresh_stdout ||
  fail 'replaying deferred fnm setup retained the stale multishell path'
grep -Fxq 'REFRESHED_FNM_COUNT=1' $fnm_refresh_stdout ||
  fail 'replaying deferred fnm setup did not install one refreshed multishell path'
grep -Fxq "FNM_MULTISHELL_PATH=$fixture_home/.local/state/fnm_multishell_refreshed" \
  $fnm_refresh_stdout ||
  fail 'replaying deferred fnm setup retained stale exported state'
grep -Fxq 'FNM_HOOK_COUNT=1' $fnm_refresh_stdout ||
  fail 'replaying deferred fnm setup did not retain exactly one hook'

fnm_literal_stdout=$tmpdir/fnm-literal-exit.stdout
fnm_literal_stderr=$tmpdir/fnm-literal-exit.stderr
env -i \
  FNM_TEST_MODE=literal-exit \
  HOME=$fixture_home \
  PATH=$initial_path \
  SSH_CONNECTION=fixture \
  TERM=dumb \
  TERM_PROGRAM=CodexTest \
  WARP_COMPAT=1 \
  $zsh_bin -ic \
  'zi_test_run_deferred
   print -r -- "PATH_FIRST=$path[1]"
   print -r -- "FNM_DIR=$FNM_DIR"' \
  >$fnm_literal_stdout 2>$fnm_literal_stderr ||
  fail 'the deferred fnm literal-exit payload made the shell unusable'
grep -Fxq "PATH_FIRST=$shim_dir" $fnm_literal_stdout ||
  fail 'the deferred fnm literal-exit payload displaced the managed shim'
grep -Fxq "FNM_DIR=$fixture_home/.local/share/fnm-exit-literal" $fnm_literal_stdout ||
  fail 'the deferred fnm parser rejected a benign value containing exit'
! grep -Fq 'fnm ' $fnm_literal_stderr ||
  fail 'the deferred fnm parser diagnosed a valid literal-exit payload'

fnm_options_stdout=$tmpdir/fnm-options.stdout
fnm_options_stderr=$tmpdir/fnm-options.stderr
env -i \
  HOME=$fixture_home \
  PATH=$initial_path \
  SSH_CONNECTION=fixture \
  TERM=dumb \
  TERM_PROGRAM=CodexTest \
  WARP_COMPAT=1 \
  $zsh_bin -ic \
  'setopt SH_WORD_SPLIT KSH_ARRAYS
   zi_test_run_deferred
   if [[ -o SH_WORD_SPLIT && -o KSH_ARRAYS ]]; then
     options_preserved=1
   else
     options_preserved=0
   fi
   unsetopt SH_WORD_SPLIT KSH_ARRAYS
   print -r -- "OPTIONS_PRESERVED=$options_preserved"
   print -r -- "PATH_FIRST=${path[1]}"
   print -r -- "FNM_DIR=$FNM_DIR"
   print -r -- "FNM_HOOK=${chpwd_functions[(I)_fnm_autoload_hook]}"' \
  >$fnm_options_stdout 2>$fnm_options_stderr ||
  fail 'ambient options made the deferred fnm action unusable'
grep -Fxq 'OPTIONS_PRESERVED=1' $fnm_options_stdout ||
  fail 'deferred fnm option isolation changed the caller option state'
grep -Fxq "PATH_FIRST=$shim_dir" $fnm_options_stdout ||
  fail 'ambient options displaced the managed shim after deferred fnm setup'
grep -Fxq "FNM_DIR=$fixture_home/.local/share/fnm" $fnm_options_stdout ||
  fail 'ambient options broke a valid fnm environment'
grep -Fxq 'FNM_HOOK=1' $fnm_options_stdout ||
  fail 'ambient options broke deferred fnm hook installation'
! grep -Fq 'fnm ' $fnm_options_stderr ||
  fail 'ambient options caused a valid fnm environment diagnostic'

for fnm_collision_mode in \
  readonly \
  non-scalar \
  hook-readonly \
  hook-failure \
  hook-late-failure \
  hook-autoloaded \
  hook-traced \
  hook-disabled \
  hook-warn \
  hook-warn-shadow
do
  fnm_collision_stdout=$tmpdir/fnm-$fnm_collision_mode.stdout
  fnm_collision_stderr=$tmpdir/fnm-$fnm_collision_mode.stderr
  env -i \
    FNM_COLLISION_MODE=$fnm_collision_mode \
    HOME=$fixture_home \
    PATH=$initial_path \
    SSH_CONNECTION=fixture \
    TERM=dumb \
    TERM_PROGRAM=CodexTest \
    WARP_COMPAT=1 \
    $zsh_bin -ic \
    'case $FNM_COLLISION_MODE in
       (readonly) readonly FNM_DIR=before ;;
       (non-scalar) typeset -ga FNM_DIR=( before ) ;;
       (hook-readonly) typeset -gra chpwd_functions=( existing_hook ) ;;
       (hook-failure) function add-zsh-hook { return 19 } ;;
       (hook-late-failure)
         typeset -ga chpwd_functions=( before middle after )
         function add-zsh-hook {
           case $1 in
             (-h) return 0 ;;
             (-D) chpwd_functions=( mutated ); return 0 ;;
             (*) return 19 ;;
           esac
         }
         ;;
       (hook-autoloaded)
         autoload -Uz _fnm_autoload_hook
         fnm_hook_metadata_before=$(typeset -fp _fnm_autoload_hook)
         ;;
       (hook-traced)
         function _fnm_autoload_hook {
           if [[ -f .node-version || -f .nvmrc || -f package.json ]]; then
             fnm use --silent-if-unchanged
           fi
         }
         functions -T _fnm_autoload_hook
         fnm_hook_metadata_before=$(typeset -fp _fnm_autoload_hook)
         ;;
       (hook-disabled)
         function _fnm_autoload_hook {
           if [[ -f .node-version || -f .nvmrc || -f package.json ]]; then
             fnm use --silent-if-unchanged
           fi
         }
         disable -f _fnm_autoload_hook
         fnm_hook_body_before=$dis_functions[_fnm_autoload_hook]
         ;;
       (hook-warn)
         function _fnm_autoload_hook {
           if [[ -f .node-version || -f .nvmrc || -f package.json ]]; then
             fnm use --silent-if-unchanged
           fi
         }
         functions -W _fnm_autoload_hook
         ;;
       (hook-warn-shadow)
         function _fnm_autoload_hook {
           if [[ -f .node-version || -f .nvmrc || -f package.json ]]; then
             fnm use --silent-if-unchanged
           fi
         }
         functions -W _fnm_autoload_hook
         function functions {
           return 0
         }
         ;;
     esac
     zi_test_run_deferred
     integer multishell_count=0
     local entry
     for entry in $path; do
       [[ $entry == $HOME/.local/state/fnm_multishell/bin ]] &&
         (( ++multishell_count ))
     done
     print -r -- "PATH_FIRST=${path[1]}"
     print -r -- "FNM_MULTISHELL_COUNT=$multishell_count"
     print -r -- "FNM_MULTISHELL_SET=${+FNM_MULTISHELL_PATH}"
     print -r -- "FNM_DIR_TYPE=${parameters[FNM_DIR]-}"
     print -r -- "FNM_DIR_VALUE=${FNM_DIR-}"
     print -r -- "FNM_HOOK_FUNCTION=${+functions[_fnm_autoload_hook]}"
     print -r -- "FNM_DISABLED_HOOK=${+dis_functions[_fnm_autoload_hook]}"
     print -r -- "FNM_HOOK_COUNT=${chpwd_functions[(I)_fnm_autoload_hook]:-0}"
     print -r -- "CHPWD_STATE=${(j.:.)chpwd_functions}"
     local -a warn_functions=( ${(f)"$(builtin functions +W)"} )
     print -r -- "FNM_HOOK_WARNED=${warn_functions[(I)_fnm_autoload_hook]:-0}"
     if [[ $FNM_COLLISION_MODE == (hook-autoloaded|hook-traced) ]]; then
       if [[ $(typeset -fp _fnm_autoload_hook) == $fnm_hook_metadata_before ]]; then
         print -r -- "FNM_HOOK_METADATA_PRESERVED=1"
       else
         print -r -- "FNM_HOOK_METADATA_PRESERVED=0"
       fi
     elif [[ $FNM_COLLISION_MODE == hook-disabled ]]; then
       if [[ $dis_functions[_fnm_autoload_hook] == $fnm_hook_body_before ]]; then
         print -r -- "FNM_HOOK_METADATA_PRESERVED=1"
       else
         print -r -- "FNM_HOOK_METADATA_PRESERVED=0"
       fi
     fi' \
    >$fnm_collision_stdout 2>$fnm_collision_stderr ||
    fail "the deferred fnm $fnm_collision_mode collision made the shell unusable"
  grep -Fxq "PATH_FIRST=$shim_dir" $fnm_collision_stdout ||
    fail "the deferred fnm $fnm_collision_mode collision skipped final PATH repair"
  grep -Fxq 'FNM_MULTISHELL_COUNT=0' $fnm_collision_stdout ||
    fail "the deferred fnm $fnm_collision_mode collision partially mutated PATH"
  grep -Fxq 'FNM_MULTISHELL_SET=0' $fnm_collision_stdout ||
    fail "the deferred fnm $fnm_collision_mode collision partially exported fnm state"
  if [[ $fnm_collision_mode == (hook-autoloaded|hook-traced|hook-warn|hook-warn-shadow) ]]; then
    grep -Fxq 'FNM_HOOK_FUNCTION=1' $fnm_collision_stdout ||
      fail "the deferred fnm $fnm_collision_mode collision changed hook metadata"
    if [[ $fnm_collision_mode == (hook-autoloaded|hook-traced) ]]; then
      grep -Fxq 'FNM_HOOK_METADATA_PRESERVED=1' $fnm_collision_stdout ||
        fail "the deferred fnm $fnm_collision_mode collision changed hook metadata"
    else
      grep -Fxq 'FNM_HOOK_WARNED=1' $fnm_collision_stdout ||
        fail 'the deferred fnm warn-attributed hook collision changed hook metadata'
    fi
  elif [[ $fnm_collision_mode == hook-disabled ]]; then
    grep -Fxq 'FNM_HOOK_FUNCTION=0' $fnm_collision_stdout &&
      grep -Fxq 'FNM_DISABLED_HOOK=1' $fnm_collision_stdout &&
      grep -Fxq 'FNM_HOOK_METADATA_PRESERVED=1' $fnm_collision_stdout ||
      fail 'the deferred fnm disabled-hook collision changed hook state'
  else
    grep -Fxq 'FNM_HOOK_FUNCTION=0' $fnm_collision_stdout ||
      fail "the deferred fnm $fnm_collision_mode collision leaked its hook function"
  fi
  grep -Fxq 'FNM_HOOK_COUNT=0' $fnm_collision_stdout ||
    fail "the deferred fnm $fnm_collision_mode collision installed its hook"
  case $fnm_collision_mode in
    (readonly)
      grep -Fxq 'FNM_DIR_TYPE=scalar-readonly' $fnm_collision_stdout &&
        grep -Fxq 'FNM_DIR_VALUE=before' $fnm_collision_stdout ||
        fail 'the deferred fnm readonly collision changed the existing parameter'
      ;;
    (non-scalar)
      grep -Fxq 'FNM_DIR_TYPE=array' $fnm_collision_stdout ||
        fail 'the deferred fnm non-scalar collision changed the existing parameter type'
      ;;
    (hook-late-failure)
      grep -Fxq 'CHPWD_STATE=before:middle:after' $fnm_collision_stdout ||
        fail 'the deferred fnm late hook-install failure did not roll back hook order'
      ;;
  esac
  case $fnm_collision_mode in
    (readonly|non-scalar|hook-readonly|hook-autoloaded|hook-traced|hook-disabled|hook-warn|hook-warn-shadow)
      grep -Fq 'fnm generated shell environment output that conflicts with existing shell parameter state' \
        $fnm_collision_stderr ||
        fail "the deferred fnm $fnm_collision_mode collision was not diagnosed"
      ;;
    (hook-failure|hook-late-failure)
      grep -Fq 'fnm generated shell environment output that could not be applied safely' \
        $fnm_collision_stderr ||
        fail "the deferred fnm $fnm_collision_mode hook-install failure was not diagnosed"
      ;;
  esac
done

for fnm_failure_mode in \
  empty \
  partial \
  success-empty \
  return \
  exit \
  quoted-exit \
  expanded-exit \
  missing-key \
  mismatched-path \
  empty-path
do
  fnm_failure_stdout=$tmpdir/fnm-$fnm_failure_mode.stdout
  fnm_failure_stderr=$tmpdir/fnm-$fnm_failure_mode.stderr
  env -i \
    FNM_TEST_MODE=$fnm_failure_mode \
    HOME=$fixture_home \
    PATH=$initial_path \
    SSH_CONNECTION=fixture \
    TERM=dumb \
    TERM_PROGRAM=CodexTest \
    WARP_COMPAT=1 \
    $zsh_bin -ic \
    'zi_test_run_deferred
     integer multishell_count=0 partial_count=0
     local entry
     for entry in $path; do
       [[ $entry == $HOME/.local/state/fnm_multishell/bin ]] &&
         (( ++multishell_count ))
       [[ $entry == $HOME/.local/state/fnm-partial/bin ]] &&
         (( ++partial_count ))
     done
     print -r -- "PATH_FIRST=$path[1]"
     print -r -- "FNM_MULTISHELL_COUNT=$multishell_count"
     print -r -- "FNM_PARTIAL_COUNT=$partial_count"
     print -r -- "FNM_DIR_SET=${+FNM_DIR}"' \
    >$fnm_failure_stdout 2>$fnm_failure_stderr ||
    fail "the deferred fnm $fnm_failure_mode-output failure made the shell unusable"
  grep -Fxq "PATH_FIRST=$shim_dir" $fnm_failure_stdout ||
    fail "the deferred fnm $fnm_failure_mode-output failure displaced the managed shim"
  grep -Fxq 'FNM_MULTISHELL_COUNT=0' $fnm_failure_stdout ||
    fail "the deferred fnm $fnm_failure_mode-output failure mutated PATH"
  grep -Fxq 'FNM_DIR_SET=0' $fnm_failure_stdout ||
    fail "the deferred fnm $fnm_failure_mode-output failure applied part of its payload"
  case $fnm_failure_mode in
    (empty|partial)
      grep -Fxq 'FNM_PARTIAL_COUNT=0' $fnm_failure_stdout ||
        fail "the deferred fnm $fnm_failure_mode-output failure applied incomplete output"
      grep -Fq 'fnm is available but failed to generate shell environment output' \
        $fnm_failure_stderr ||
        fail "the deferred fnm $fnm_failure_mode-output failure was silent"
      ;;
    (success-empty)
      grep -Fq 'fnm produced no shell environment output' $fnm_failure_stderr ||
        fail 'the deferred fnm successful empty output was accepted'
      ;;
    (return|exit|quoted-exit|expanded-exit|missing-key|mismatched-path|empty-path)
      grep -Fq 'fnm generated unsupported shell environment output' \
        $fnm_failure_stderr ||
        fail "the deferred fnm $fnm_failure_mode payload was not rejected explicitly"
      ;;
  esac
done
mv -- $tmpdir/vite-env.saved $vite_home/env

cp -- $zi_bin/zi.zsh $tmpdir/zi.zsh.saved
print -rl -- \
  'function zi { typeset -g PARTIAL_ZI_CALLED=1; return 0 }' \
  'return 17' \
  >$zi_bin/zi.zsh
partial_zi_stdout=$tmpdir/partial-zi.stdout
partial_zi_stderr=$tmpdir/partial-zi.stderr
env -i \
  FPATH=$fixture_fpath \
  HOME=$fixture_home \
  MANPATH=/fixture/custom/man \
  PATH=$initial_path \
  TERM=dumb \
  TERM_PROGRAM=CodexTest \
  WARP_COMPAT=1 \
  $zsh_bin -ic \
  'print -r -- "PARTIAL_ZI_CALLED=${PARTIAL_ZI_CALLED:-0}"
   print -r -- "ZI_FUNCTION=${+functions[zi]}"
   print -r -- "VP_FUNCTION=${+functions[vp]}"
   print -r -- "VP_COMPLETION=${VITE_COMPLETION_LOADED:-0}"
   print -r -- "MANPATH=${MANPATH-unset}"' \
  >$partial_zi_stdout 2>$partial_zi_stderr ||
  fail 'a partial Zi load made the repair shell unusable'
grep -Fxq 'PARTIAL_ZI_CALLED=0' $partial_zi_stdout ||
  fail 'startup invoked a partially loaded Zi implementation'
grep -Fxq 'ZI_FUNCTION=0' $partial_zi_stdout ||
  fail 'startup retained a partially loaded Zi entrypoint'
grep -Fxq 'VP_FUNCTION=1' $partial_zi_stdout ||
  fail 'a partial Zi load did not select the Vite+ fallback'
grep -Fxq 'VP_COMPLETION=1' $partial_zi_stdout ||
  fail 'a partial Zi load did not initialize fallback completions'
grep -Fxq 'MANPATH=/fixture/custom/man' $partial_zi_stdout ||
  fail 'a partial Zi load discarded the inherited MANPATH'
grep -Fq 'Zi is installed but failed to load from' $partial_zi_stderr ||
  fail 'a partial Zi load did not surface feature degradation'
mv -- $tmpdir/zi.zsh.saved $zi_bin/zi.zsh

no_manpath_stdout=$tmpdir/no-manpath.stdout
env -i \
  HOME=$fixture_home \
  MANPATH=/fixture/custom/man \
  PATH=$initial_path \
  TERM=dumb \
  TERM_PROGRAM=CodexTest \
  WARP_COMPAT=1 \
  ZI_TEST_FORCE_MISSING_COMMAND=manpath \
  $zsh_bin -ic 'print -r -- "MANPATH=${MANPATH-unset}"' \
  >$no_manpath_stdout 2>$tmpdir/no-manpath.stderr ||
  fail 'successful Zi startup without manpath made the shell unusable'
grep -Fxq 'MANPATH=/fixture/custom/man' $no_manpath_stdout ||
  fail 'successful Zi startup without manpath discarded the inherited MANPATH'

[[ -L $repo_root/.zprofile && $(readlink $repo_root/.zprofile) == zprofile.zsh ]] ||
  fail '.zprofile must be a direct symlink to zprofile.zsh'

function expect_platform_defaults {
  local platform=$1 expected_pnpm_home=$2
  local platform_home=$tmpdir/platform-${platform//[^A-Za-z0-9]/-}
  mkdir -p -- $platform_home/.local/share/pnpm/bin
  local output
  output=$(
    env -i HOME=$platform_home PATH=/usr/bin:/bin $zsh_bin -f -c \
      'source "$1" test "$2"; print -r -- "$PNPM_HOME"' \
      -- $repo_root/startup.zsh $platform
  )
  [[ $output == $expected_pnpm_home ]] ||
    fail "$platform selected the wrong portable PNPM_HOME"
}

expect_platform_defaults darwin24 $tmpdir/platform-darwin24/Library/pnpm
expect_platform_defaults linux-gnu $tmpdir/platform-linux-gnu/.local/share/pnpm
expect_platform_defaults linux-gnu-wsl $tmpdir/platform-linux-gnu-wsl/.local/share/pnpm

duplicate_home=$tmpdir/task-owned-duplicate
mkdir -p -- $duplicate_home/.local/bin
duplicate_log=$tmpdir/task-owned-duplicate.stderr
env -i \
  HOME=$duplicate_home \
  PATH=/usr/bin:/bin \
  GOBIN=$duplicate_home/.local/bin \
  $zsh_bin -fic \
  'source "$1" test "$OSTYPE"' \
  -- $repo_root/startup.zsh \
  2>$duplicate_log ||
  fail 'interactive startup failed while checking duplicate managed PATH entries'
grep -Fq 'zsh startup: duplicate managed PATH entry:' $duplicate_log ||
  fail 'interactive startup must surface duplicates in the managed PATH list'

canonical_home=$tmpdir/canonical-duplicate
mkdir -p -- $canonical_home/real-bin
ln -s -- real-bin $canonical_home/link-bin
canonical_log=$tmpdir/canonical-duplicate.stderr
env -i \
  HOME=$canonical_home \
  PATH=$canonical_home/real-bin:$canonical_home/link-bin:/usr/bin:/bin \
  $zsh_bin -fic \
  'source "$1" test "$OSTYPE"' \
  -- $repo_root/startup.zsh \
  2>$canonical_log ||
  fail 'interactive startup failed while checking canonical-equivalent PATH entries'
grep -Fq 'zsh startup: canonically equivalent PATH entries:' $canonical_log ||
  fail 'interactive startup must surface canonical-equivalent PATH entries without rewriting them'

launcher_home=$tmpdir/launcher
mkdir -p -- \
  $launcher_home/.local/lib/secret-exec/bin \
  $launcher_home/.local/bin \
  $launcher_home/.orbstack/bin \
  $launcher_home/.vite-plus/bin
launcher_path=$(
  env -i \
    HOME=$launcher_home \
    PATH=/usr/local/bin:/usr/bin:/bin:/usr/bin \
    $zsh_bin -f -c \
    'source "$1" launcher "$OSTYPE"; print -r -- "$PATH"' \
    -- $repo_root/startup.zsh
) || fail 'launcher startup failed while checking the core PATH'
[[ :$launcher_path: == *:$launcher_home/.local/lib/secret-exec/bin:* ]] ||
  fail 'launcher core PATH must contain secret-exec shims'
[[ :$launcher_path: == *:$launcher_home/.local/bin:* ]] ||
  fail 'launcher core PATH must contain the portable local bin'
[[ :$launcher_path: == *:$launcher_home/.orbstack/bin:* ]] ||
  fail 'launcher core PATH must contain OrbStack when present'
[[ :$launcher_path: != *:$launcher_home/.vite-plus/bin:* ]] ||
  fail 'launcher core PATH must exclude the full developer toolchain'
count_entry /usr/bin ${(s.:.)launcher_path}
(( REPLY == 1 )) ||
  fail 'launcher core PATH must clean duplicate inherited entries'

list_home=$tmpdir/list-policy
list_real=$list_home/real
list_link=$list_home/link
list_orb_completions=$list_home/.orbstack/shell/completions/zsh
mkdir -p -- $list_real $list_orb_completions
ln -s -- real $list_link
list_stdout=$tmpdir/list-policy.stdout
list_stderr=$tmpdir/list-policy.stderr
env -i \
  HOME=$list_home \
  PATH=/usr/bin:/bin \
  INFOPATH=$list_real:$list_real::$list_link: \
  $zsh_bin -fic \
  'fpath=(
     "$HOME/.orbstack/shell/completions/zsh"
     "$HOME/.orbstack/shell/completions/zsh"
     "$HOME/real"
     "$HOME/real"
     "$HOME/link"
   )
   source "$1" zshrc-final "$OSTYPE"
   integer orb_count=0 real_count=0
   local entry
   for entry in "$fpath[@]"; do
     [[ $entry == "$HOME/.orbstack/shell/completions/zsh" ]] && (( orb_count++ ))
     [[ $entry == "$HOME/real" ]] && (( real_count++ ))
   done
   print -r -- "INFOPATH=$INFOPATH"
   print -r -- "ORB_FPATH_COUNT=$orb_count"
   print -r -- "REAL_FPATH_COUNT=$real_count"' \
  -- $repo_root/startup.zsh \
  >$list_stdout 2>$list_stderr ||
  fail 'interactive startup failed while checking colon-list and fpath cleanup'
grep -Fxq "INFOPATH=$list_real::$list_link" $list_stdout ||
  fail 'colon-list policy must preserve one default entry while removing exact duplicates'
grep -Fxq 'ORB_FPATH_COUNT=1' $list_stdout ||
  fail 'fpath policy must keep one managed completion entry'
grep -Fxq 'REAL_FPATH_COUNT=1' $list_stdout ||
  fail 'fpath policy must remove exact inherited duplicates'
grep -Fq 'zsh startup: removed exact duplicate INFOPATH entry:' $list_stderr ||
  fail 'interactive startup must surface colon-list duplicate cleanup'
grep -Fq 'zsh startup: removed exact duplicate fpath entry:' $list_stderr ||
  fail 'interactive startup must surface fpath duplicate cleanup'
grep -Fq 'zsh startup: canonically equivalent INFOPATH entries:' $list_stderr ||
  fail 'interactive startup must surface canonical-equivalent colon-list entries'
grep -Fq 'zsh startup: canonically equivalent fpath entries:' $list_stderr ||
  fail 'interactive startup must surface canonical-equivalent fpath entries'

arithmetic_path='x$(print -ru2 ARITHMETIC_PATH_SUBSCRIPT_EXECUTED)'
arithmetic_path_log=$tmpdir/arithmetic-path.stderr
env -i \
  HOME=$fixture_home \
  PATH=$arithmetic_path:/usr/bin:/bin \
  BIN_HOME=$arithmetic_path \
  $zsh_bin -f -c 'source "$1" zshenv "$OSTYPE"' -- $repo_root/startup.zsh \
  2>$arithmetic_path_log ||
  fail 'managed PATH handling rejected a literal arithmetic-subscript token'
if grep -Fq ARITHMETIC_PATH_SUBSCRIPT_EXECUTED $arithmetic_path_log; then
  fail 'managed PATH handling evaluated a literal associative-array key'
fi

arithmetic_home=$tmpdir/'x$(print -ru2 ARITHMETIC_FPATH_SUBSCRIPT_EXECUTED)'
mkdir -p -- $arithmetic_home/.orbstack/shell/completions/zsh
arithmetic_fpath_log=$tmpdir/arithmetic-fpath.stderr
env -i \
  HOME=$arithmetic_home \
  PATH=/usr/bin:/bin \
  $zsh_bin -f -c \
  'fpath=( "$HOME/.orbstack/shell/completions/zsh" "$HOME/.orbstack/shell/completions/zsh" )
   source "$1" zshrc-final "$OSTYPE"' \
  -- $repo_root/startup.zsh \
  2>$arithmetic_fpath_log ||
  fail 'managed fpath handling rejected a literal arithmetic-subscript token'
if grep -Fq ARITHMETIC_FPATH_SUBSCRIPT_EXECUTED $arithmetic_fpath_log; then
  fail 'managed fpath handling evaluated a literal associative-array key'
fi

pattern_home=$tmpdir/pattern-paths
mkdir -p -- $pattern_home/target
ln -s -- target $pattern_home/globx
ln -s -- target $pattern_home/'glob*'
pattern_log=$tmpdir/pattern-paths.stderr
env -i \
  HOME=$fixture_home \
  PATH=$pattern_home/globx:$pattern_home/'glob*':/usr/bin:/bin \
  $zsh_bin -fic \
  'fpath=( "$2/globx" "$2/glob*" )
   source "$1" zshrc-final "$OSTYPE"' \
  -- $repo_root/startup.zsh $pattern_home \
  2>$pattern_log ||
  fail 'managed path handling rejected a literal glob token'
grep -Fxq \
  "zsh startup: canonically equivalent PATH entries: $pattern_home/globx and $pattern_home/glob*" \
  $pattern_log ||
  fail 'a literal glob token suppressed canonical PATH diagnostics'
grep -Fxq \
  "zsh startup: canonically equivalent fpath entries: $pattern_home/globx and $pattern_home/glob*" \
  $pattern_log ||
  fail 'a literal glob token suppressed canonical fpath diagnostics'

missing_interactive_log=$tmpdir/missing-interactive-policy.stderr
mv -- $fixture_zdotdir/startup.zsh $tmpdir/startup.zsh.saved
integer missing_interactive_status=0
env -i \
  HOME=$fixture_home \
  PATH=$initial_path \
  SSH_CONNECTION=fixture \
  TERM=dumb \
  TERM_PROGRAM=CodexTest \
  WARP_COMPAT=1 \
  $zsh_bin -ic ':' \
  2>$missing_interactive_log ||
  missing_interactive_status=$?
mv -- $tmpdir/startup.zsh.saved $fixture_zdotdir/startup.zsh
(( missing_interactive_status == 0 )) ||
  fail 'a missing interactive startup policy made the shell unusable'
grep -Fq 'zsh startup: required policy is missing:' $missing_interactive_log ||
  fail 'a missing interactive startup policy did not surface degradation'
if grep -Eq 'mkdir: *:|mkdir:.*(missing operand|No such file or directory)' \
  $missing_interactive_log; then
  fail 'a missing interactive startup policy attempted an empty directory path'
fi

missing_home=$tmpdir/missing-login-policy
missing_zdotdir=$missing_home/.config/zsh
mkdir -p -- $missing_zdotdir
ln -s -- $repo_root/zshenv.zsh $missing_home/.zshenv
ln -s -- $repo_root/environment.zsh $missing_zdotdir/environment.zsh
ln -s -- $repo_root/profiles.zsh $missing_zdotdir/profiles.zsh
ln -s -- $repo_root/startup.zsh $missing_zdotdir/startup.zsh
missing_log=$tmpdir/missing-login-policy.stderr
env -i HOME=$missing_home PATH=/usr/bin:/bin $zsh_bin -lc ':' 2>$missing_log ||
  fail 'a missing login policy must preserve a usable shell'
grep -Fq 'zsh startup: required login policy is missing:' $missing_log ||
  fail 'a missing login policy must surface degraded startup'

update_origin=$tmpdir/update-origin
copy_tracked_checkout "$repo_root" "$update_origin" ||
  fail 'could not construct the tracked update-origin fixture'
fixture_git -C $update_origin init --quiet --initial-branch=main
mkdir -p -- \
  $update_origin/profile.d \
  $update_origin/zshrc.d \
  $fixture_zdotdir/profile.d
mkdir -p -- $fixture_zdotdir/zshrc.d
print -r -- 'typeset -g TRACKED_PROFILE_SOURCE=installed' \
  >$fixture_zdotdir/profile.d/tracked.zshrc
print -r -- 'typeset -g MODIFIED_PROFILE_SOURCE=installed' \
  >$fixture_zdotdir/profile.d/modified.zshrc
fixture_git -C $fixture_zdotdir init --quiet --initial-branch=main
fixture_git -C $fixture_zdotdir add -- \
  profile.d/modified.zshrc \
  profile.d/tracked.zshrc
fixture_git -C $fixture_zdotdir \
  -c user.name='Zsh Config Test' \
  -c user.email='zsh-config-test@example.invalid' \
  commit --quiet -m 'test: track installed profile'
print -r -- 'typeset -g MODIFIED_PROFILE_SOURCE=local' \
  >$fixture_zdotdir/profile.d/modified.zshrc
print -r -- 'typeset -g TRACKED_PROFILE_SOURCE=checkout' \
  >$update_origin/profile.d/tracked.zshrc
print -r -- 'typeset -g MODIFIED_PROFILE_SOURCE=checkout' \
  >$update_origin/profile.d/modified.zshrc
print -r -- 'typeset -g UPDATE_PROFILE_SOURCE=checkout' \
  >$update_origin/profile.d/host-local.zshrc
print -r -- 'typeset -g UPDATE_PROFILE_SOURCE=local' \
  >$fixture_zdotdir/profile.d/host-local.zshrc
print -rl -- \
  'typeset -g LEGACY_MATCH_LOCAL=1' \
  'typeset -g LEGACY_MATCH_ORDER="${LEGACY_MATCH_ORDER:-}legacy,"' \
  >$fixture_zdotdir/zshrc.d/legacy-match.local.zsh
cp -a -- \
  $fixture_zdotdir/zshrc.d/legacy-match.local.zsh \
  $update_origin/zshrc.d/legacy-match.local.zsh
print -r -- 'typeset -g SOLO_LEGACY_VERSION=1' \
  >$fixture_zdotdir/zshrc.d/solo.local.zsh
cp -a -- \
  $fixture_zdotdir/zshrc.d/solo.local.zsh \
  $update_origin/zshrc.d/solo.local.zsh
print -rl -- \
  'typeset -g NEW_LOCAL_PROFILE=1' \
  'typeset -g LEGACY_MATCH_ORDER="${LEGACY_MATCH_ORDER:-}new-local"' \
  >$fixture_zdotdir/profile.d/legacy-match.local.zshrc
print -rl -- \
  'typeset -g LEGACY_MATCH_UPSTREAM=1' \
  'typeset -g LEGACY_MATCH_ORDER="${LEGACY_MATCH_ORDER:-}upstream,"' \
  >$update_origin/profile.d/legacy-match.zshrc
print -r -- '# Disabled by default.' \
  >$update_origin/profile.d/legacy-match.disabled
dangling_external=$tmpdir/dangling-local-profile-target
ln -s -- $dangling_external \
  $fixture_zdotdir/profile.d/dangling.local.zshrc
print -r -- 'typeset -g DANGLING_LEGACY_PROFILE=1' \
  >$fixture_zdotdir/zshrc.d/dangling.local.zsh
cp -a -- \
  $fixture_zdotdir/zshrc.d/dangling.local.zsh \
  $update_origin/zshrc.d/dangling.local.zsh
print -r -- 'typeset -g DANGLING_UPSTREAM_PROFILE=1' \
  >$update_origin/profile.d/dangling.zshrc
split_dangling_external=$tmpdir/dangling-split-profile-target
ln -s -- $split_dangling_external \
  $fixture_zdotdir/profile.d/split-dangling.zshrc
print -r -- 'typeset -g SPLIT_DANGLING_LEGACY_PROFILE=1' \
  >$fixture_zdotdir/zshrc.d/split-dangling.local.zsh
cp -a -- \
  $fixture_zdotdir/zshrc.d/split-dangling.local.zsh \
  $update_origin/zshrc.d/split-dangling.local.zsh
touch -t 203001010000 $update_origin/profile.d/host-local.zshrc
touch -t 202001010000 $fixture_zdotdir/profile.d/host-local.zshrc
fixture_git -C $update_origin add -- \
  profile.d/dangling.zshrc \
  profile.d/host-local.zshrc \
  profile.d/legacy-match.disabled \
  profile.d/legacy-match.zshrc \
  profile.d/modified.zshrc \
  profile.d/tracked.zshrc
fixture_git -C $update_origin \
  -c user.name='Zsh Config Test' \
  -c user.email='zsh-config-test@example.invalid' \
  commit --quiet -m 'test: create update origin'
update_log=$tmpdir/profile-update.stderr
env -i \
  GIT_CONFIG_COUNT=0 \
  GIT_CONFIG_GLOBAL=/dev/null \
  GIT_CONFIG_NOSYSTEM=1 \
  HOME=$fixture_home \
  PATH=$initial_path \
  ZDOTDIR_ORIGIN=$update_origin \
  TERM=dumb \
  TERM_PROGRAM=CodexTest \
  WARP_COMPAT=1 \
  $zsh_bin -ic 'zsh-config-update' \
  2>$update_log ||
  fail 'self-update failed while preserving a host-local profile'
grep -Fxq 'typeset -g UPDATE_PROFILE_SOURCE=local' \
  $fixture_zdotdir/profile.d/host-local.zshrc ||
  fail 'self-update let checkout mtime replace a host-local profile'
grep -Fxq 'typeset -g TRACKED_PROFILE_SOURCE=checkout' \
  $fixture_zdotdir/profile.d/tracked.zshrc ||
  fail 'self-update let a clean tracked profile override the current checkout'
grep -Fxq 'typeset -g MODIFIED_PROFILE_SOURCE=local' \
  $fixture_zdotdir/profile.d/modified.zshrc ||
  fail 'self-update discarded a modified tracked host profile'
[[ -e $fixture_zdotdir/profile.d/legacy-match.enabled ]] ||
  fail 'self-update did not preserve the legacy opt-in for a split profile'
grep -Fxq 'typeset -g NEW_LOCAL_PROFILE=1' \
  $fixture_zdotdir/profile.d/legacy-match.local.zshrc ||
  fail 'self-update overwrote an existing host-local split-profile supplement'
grep -Fxq 'typeset -g LEGACY_MATCH_LOCAL=1' \
  $fixture_zdotdir/profile.d/legacy-match.legacy.local.zshrc ||
  fail 'self-update discarded colliding legacy host-specific profile contents'
grep -Fxq 'typeset -g SOLO_LEGACY_VERSION=1' \
  $fixture_zdotdir/profile.d/solo.legacy.local.zshrc ||
  fail 'self-update did not use the reserved legacy-migration namespace'
[[ ! -e $fixture_zdotdir/profile.d/solo.zshrc ]] ||
  fail 'self-update made an unmatched legacy profile indistinguishable from a regular profile'
legacy_match_output=$(
  env -i ZDOTDIR=$fixture_zdotdir $zsh_bin -f -c \
    'source "$1" zshrc; print -r -- "${LEGACY_MATCH_UPSTREAM:-0}:${LEGACY_MATCH_LOCAL:-0}:${NEW_LOCAL_PROFILE:-0}:${LEGACY_MATCH_ORDER:-}"' \
    -- $fixture_zdotdir/profiles.zsh
) || fail 'migrated split and host-local profiles did not load'
[[ $legacy_match_output == 1:1:1:upstream,legacy,new-local ]] ||
  fail 'migrated host-local commands did not all execute after the split profile'
[[ -h $fixture_zdotdir/profile.d/dangling.local.zshrc ]] ||
  fail 'self-update replaced a dangling host-local profile symlink'
[[ ! -e $dangling_external ]] ||
  fail 'self-update followed a dangling host-local profile symlink outside the checkout'
grep -Fxq 'typeset -g DANGLING_LEGACY_PROFILE=1' \
  $fixture_zdotdir/profile.d/dangling.legacy.local.zshrc ||
  fail 'self-update did not preserve legacy contents beside a dangling local profile'
[[ -h $fixture_zdotdir/profile.d/split-dangling.zshrc ]] ||
  fail 'self-update replaced a dangling split-profile symlink'
[[ ! -e $split_dangling_external ]] ||
  fail 'self-update followed a dangling split-profile symlink outside the checkout'
grep -Fxq 'typeset -g SPLIT_DANGLING_LEGACY_PROFILE=1' \
  $fixture_zdotdir/profile.d/split-dangling.legacy.local.zshrc ||
  fail 'self-update did not preserve legacy contents beside a dangling split profile'

env -i \
  GIT_CONFIG_COUNT=0 \
  GIT_CONFIG_GLOBAL=/dev/null \
  GIT_CONFIG_NOSYSTEM=1 \
  HOME=$fixture_home \
  PATH=$initial_path \
  ZDOTDIR_ORIGIN=$update_origin \
  TERM=dumb \
  TERM_PROGRAM=CodexTest \
  WARP_COMPAT=1 \
  $zsh_bin -ic 'zsh-config-update' \
  >$tmpdir/profile-update-second.stdout \
  2>$tmpdir/profile-update-second.stderr ||
  fail 'second self-update failed while preserving migrated local profiles'
legacy_supplements=( $fixture_zdotdir/profile.d/legacy-match*.local.zshrc(N) )
(( $#legacy_supplements == 2 )) ||
  fail 'second self-update minted a duplicate legacy-profile supplement'
dangling_supplements=( $fixture_zdotdir/profile.d/dangling*.local.zshrc(N) )
(( $#dangling_supplements == 2 )) ||
  fail 'second self-update minted a duplicate dangling-profile supplement'
[[ ! -e $dangling_external ]] ||
  fail 'second self-update followed a dangling local-profile symlink'
[[ ! -e $split_dangling_external ]] ||
  fail 'second self-update followed a dangling split-profile symlink'

print -rl -- \
  'typeset -g LEGACY_MATCH_LOCAL=2' \
  'typeset -g LEGACY_MATCH_ORDER="${LEGACY_MATCH_ORDER:-}legacy-v2,"' \
  >$fixture_zdotdir/zshrc.d/legacy-match.local.zsh
print -r -- 'typeset -g SOLO_LEGACY_VERSION=2' \
  >$fixture_zdotdir/zshrc.d/solo.local.zsh
print -r -- 'typeset -g LEGACY_MATCH_LOCAL=0' \
  >$fixture_zdotdir/profile.d/legacy-match.legacy-9.local.zshrc
env -i \
  GIT_CONFIG_COUNT=0 \
  GIT_CONFIG_GLOBAL=/dev/null \
  GIT_CONFIG_NOSYSTEM=1 \
  HOME=$fixture_home \
  PATH=$initial_path \
  ZDOTDIR_ORIGIN=$update_origin \
  TERM=dumb \
  TERM_PROGRAM=CodexTest \
  WARP_COMPAT=1 \
  $zsh_bin -ic 'zsh-config-update' \
  >$tmpdir/profile-update-third.stdout \
  2>$tmpdir/profile-update-third.stderr ||
  fail 'third self-update failed after the legacy profile changed'
legacy_supplements=( $fixture_zdotdir/profile.d/legacy-match*.local.zshrc(N) )
(( $#legacy_supplements == 2 )) ||
  fail 'an edited legacy profile accumulated another migrated version'
grep -Fxq 'typeset -g LEGACY_MATCH_LOCAL=2' \
  $fixture_zdotdir/profile.d/legacy-match.legacy.local.zshrc ||
  fail 'self-update did not replace the prior migrated legacy version'
[[ ! -e $fixture_zdotdir/profile.d/legacy-match.legacy-9.local.zshrc ]] ||
  fail 'self-update retained an obsolete numbered legacy migration'
solo_supplements=( $fixture_zdotdir/profile.d/solo*.local.zshrc(N) )
(( $#solo_supplements == 1 )) ||
  fail 'an edited unmatched legacy profile accumulated another migrated version'
grep -Fxq 'typeset -g SOLO_LEGACY_VERSION=2' \
  $fixture_zdotdir/profile.d/solo.legacy.local.zshrc ||
  fail 'self-update did not replace an unmatched migrated legacy version'
legacy_match_output=$(
  env -i ZDOTDIR=$fixture_zdotdir $zsh_bin -f -c \
    'source "$1" zshrc; print -r -- "${LEGACY_MATCH_UPSTREAM:-0}:${LEGACY_MATCH_LOCAL:-0}:${NEW_LOCAL_PROFILE:-0}:${LEGACY_MATCH_ORDER:-}"' \
    -- $fixture_zdotdir/profiles.zsh
) || fail 'updated legacy and host-local profiles did not load'
[[ $legacy_match_output == 1:2:1:upstream,legacy-v2,new-local ]] ||
  fail 'an obsolete migrated legacy version still executed after the update'
solo_legacy_output=$(
  env -i ZDOTDIR=$fixture_zdotdir $zsh_bin -f -c \
    'source "$1" zshrc; print -r -- "${SOLO_LEGACY_VERSION:-0}"' \
    -- $fixture_zdotdir/profiles.zsh
) || fail 'updated unmatched legacy profile did not load'
[[ $solo_legacy_output == 2 ]] ||
  fail 'the current unmatched legacy profile did not execute exactly once'

rmdir -- $fixture_zdotdir/zshrc.d ||
  fail 'third self-update retained unexpected legacy-directory contents'
readable_migration_target=$tmpdir/readable-migration-target
print -r -- 'typeset -g READABLE_MIGRATION_SYMLINK_LOADED=1' \
  >$readable_migration_target
ln -s -- $readable_migration_target \
  $fixture_zdotdir/profile.d/origin-symlink.legacy.local.zshrc
mkdir -p -- $update_origin/zshrc.d
print -r -- 'typeset -g ORIGIN_SYMLINK_LEGACY_LOADED=1' \
  >$update_origin/zshrc.d/origin-symlink.local.zsh
env -i \
  GIT_CONFIG_COUNT=0 \
  GIT_CONFIG_GLOBAL=/dev/null \
  GIT_CONFIG_NOSYSTEM=1 \
  HOME=$fixture_home \
  PATH=$initial_path \
  ZDOTDIR_ORIGIN=$update_origin \
  TERM=dumb \
  TERM_PROGRAM=CodexTest \
  WARP_COMPAT=1 \
  $zsh_bin -ic \
  'zsh-config-update
   print -r -- "MIGRATION_PARAMETER_LEAKS=${+parameters[legacy_profile]}:${+parameters[legacy_name]}:${+parameters[existing_migrations]}"' \
  >$tmpdir/profile-update-fourth.stdout \
  2>$tmpdir/profile-update-fourth.stderr ||
  fail 'fourth self-update failed after live legacy sources were removed'
[[ ! -e $fixture_zdotdir/zshrc.d/legacy-match.local.zsh ]] ||
  fail 'self-update restored an obsolete origin-side matched legacy source'
[[ ! -e $fixture_zdotdir/zshrc.d/solo.local.zsh ]] ||
  fail 'self-update restored an obsolete origin-side unmatched legacy source'
[[ -f $fixture_zdotdir/zshrc.d/origin-symlink.local.zsh ]] ||
  fail 'a readable migration symlink discarded its origin-side legacy source'
[[ $(<$tmpdir/profile-update-fourth.stdout) ==
  *'MIGRATION_PARAMETER_LEAKS=0:0:0'* ]] || {
  sed -n '1,80p' $tmpdir/profile-update-fourth.stdout >&2
  fail 'origin-only migration cleanup leaked function parameters'
}
legacy_match_output=$(
  env -i ZDOTDIR=$fixture_zdotdir $zsh_bin -f -c \
    'source "$1" zshrc; print -r -- "${LEGACY_MATCH_UPSTREAM:-0}:${LEGACY_MATCH_LOCAL:-0}:${NEW_LOCAL_PROFILE:-0}:${LEGACY_MATCH_ORDER:-}"' \
    -- $fixture_zdotdir/profiles.zsh
) || fail 'fourth-update legacy and host-local profiles did not load'
[[ $legacy_match_output == 1:2:1:upstream,legacy-v2,new-local ]] ||
  fail 'fourth update executed an obsolete origin-side legacy version'
solo_legacy_output=$(
  env -i ZDOTDIR=$fixture_zdotdir $zsh_bin -f -c \
    'source "$1" zshrc; print -r -- "${SOLO_LEGACY_VERSION:-0}"' \
    -- $fixture_zdotdir/profiles.zsh
) || fail 'fourth-update unmatched legacy profile did not load'
[[ $solo_legacy_output == 2 ]] ||
  fail 'fourth update did not preserve exactly one current unmatched migration'
origin_symlink_output=$(
  env -i ZDOTDIR=$fixture_zdotdir $zsh_bin -f -c \
    'source "$1" zshrc
     print -r -- "${ORIGIN_SYMLINK_LEGACY_LOADED:-0}:${READABLE_MIGRATION_SYMLINK_LOADED:-0}"' \
    -- $fixture_zdotdir/profiles.zsh
) || fail 'origin-side legacy source beside a migration symlink did not load'
[[ $origin_symlink_output == 1:0 ]] ||
  fail 'a readable migration symlink displaced the loadable origin-side source'

no_cmp_zdotdir=$tmpdir/no-cmp-zdotdir
mkdir -p -- $no_cmp_zdotdir/profile.d $no_cmp_zdotdir/zshrc.d
print -r -- '(( NO_CMP_PROFILE_LOADS += 100 ))' \
  >$no_cmp_zdotdir/zshrc.d/example.local.zsh
print -r -- '(( NO_CMP_PROFILE_LOADS += 1 ))' \
  >$no_cmp_zdotdir/profile.d/example.legacy.local.zshrc
print -r -- '(( NO_CMP_COLLISION_LOADS += 100 ))' \
  >$no_cmp_zdotdir/zshrc.d/collision.local.zsh
print -r -- '(( NO_CMP_COLLISION_LOADS += 10 ))' \
  >$no_cmp_zdotdir/collision-base-target
print -r -- '(( NO_CMP_COLLISION_LOADS += 20 ))' \
  >$no_cmp_zdotdir/collision-numbered-target
ln -s -- $no_cmp_zdotdir/collision-base-target \
  $no_cmp_zdotdir/profile.d/collision.legacy.local.zshrc
ln -s -- $no_cmp_zdotdir/collision-numbered-target \
  $no_cmp_zdotdir/profile.d/collision.legacy-2.local.zshrc
print -r -- '(( NO_CMP_COLLISION_LOADS += 1 ))' \
  >$no_cmp_zdotdir/profile.d/collision.legacy-3.local.zshrc
print -r -- '(( ++NO_CMP_DUPLICATE_LOADS ))' \
  >$no_cmp_zdotdir/zshrc.d/duplicate.local.zsh
cp -- $no_cmp_zdotdir/zshrc.d/duplicate.local.zsh \
  $no_cmp_zdotdir/profile.d/duplicate.legacy.local.zshrc
cp -- $no_cmp_zdotdir/zshrc.d/duplicate.local.zsh \
  $no_cmp_zdotdir/profile.d/duplicate.zshrc
print -r -- '(( ++NO_CMP_NEAR_DUPLICATE_LOADS ))' \
  >$no_cmp_zdotdir/zshrc.d/near-duplicate.local.zsh
cp -- $no_cmp_zdotdir/zshrc.d/near-duplicate.local.zsh \
  $no_cmp_zdotdir/profile.d/near-duplicate.legacy.local.zshrc
print -rl -- '(( ++NO_CMP_NEAR_DUPLICATE_LOADS ))' '' \
  >$no_cmp_zdotdir/profile.d/near-duplicate.zshrc
no_cmp_profile_loads=$(
  env -i PATH=/missing ZDOTDIR=$no_cmp_zdotdir $zsh_bin -f -c \
    'typeset -gi NO_CMP_PROFILE_LOADS=0
     typeset -gi NO_CMP_COLLISION_LOADS=0
     typeset -gi NO_CMP_DUPLICATE_LOADS=0
     typeset -gi NO_CMP_NEAR_DUPLICATE_LOADS=0
     source "$1" zshrc
     print -r -- "$NO_CMP_PROFILE_LOADS:$NO_CMP_COLLISION_LOADS:$NO_CMP_DUPLICATE_LOADS:$NO_CMP_NEAR_DUPLICATE_LOADS"' \
    -- $fixture_zdotdir/profiles.zsh
) || fail 'profile migration required cmp to keep startup usable'
[[ $no_cmp_profile_loads == 1:1:1:2 ]] ||
  fail 'missing cmp or migration-slot collisions selected the wrong profile'

empty_update_zdotdir=$tmpdir/empty-update-target
copy_tracked_checkout "$repo_root" "$empty_update_zdotdir" ||
  fail 'could not construct the tracked empty-update fixture'
mkdir -p -- $empty_update_zdotdir/profile.d
rm -f -- $empty_update_zdotdir/profile.d/*(N)
fixture_git -C $empty_update_zdotdir init --quiet --initial-branch=main
env -i \
  GIT_CONFIG_COUNT=0 \
  GIT_CONFIG_GLOBAL=/dev/null \
  GIT_CONFIG_NOSYSTEM=1 \
  HOME=$fixture_home \
  PATH=$initial_path \
  ZDOTDIR=$empty_update_zdotdir \
  ZDOTDIR_ORIGIN=$update_origin \
  TERM=dumb \
  TERM_PROGRAM=CodexTest \
  WARP_COMPAT=1 \
  $zsh_bin -ic 'zsh-config-update' \
  2>$tmpdir/empty-profile-update.stderr ||
  fail 'self-update failed when the local profile directory was empty'
[[ -r $empty_update_zdotdir/profile.d/host-local.zshrc ]] ||
  fail 'self-update did not restore checkout profiles over an empty local profile directory'

print -rl -- "#!$zsh_bin" 'exit 17' >$fixture_bin/mktemp
chmod +x $fixture_bin/mktemp
print -r -- 'preserve-on-mktemp-failure' \
  >$empty_update_zdotdir/mktemp-failure-marker
integer mktemp_failure_status=0
env -i \
  GIT_CONFIG_COUNT=0 \
  GIT_CONFIG_GLOBAL=/dev/null \
  GIT_CONFIG_NOSYSTEM=1 \
  HOME=$fixture_home \
  PATH=$initial_path \
  ZDOTDIR=$empty_update_zdotdir \
  ZDOTDIR_ORIGIN=$update_origin \
  TERM=dumb \
  TERM_PROGRAM=CodexTest \
  WARP_COMPAT=1 \
  $zsh_bin -ic 'zsh-config-update' \
  2>$tmpdir/mktemp-failure-update.stderr ||
  mktemp_failure_status=$?
(( mktemp_failure_status != 0 )) ||
  fail 'self-update ignored temporary-directory creation failure'
grep -Fxq 'preserve-on-mktemp-failure' \
  $empty_update_zdotdir/mktemp-failure-marker ||
  fail 'self-update modified the checkout after temporary-directory creation failed'

print -r -- 'startup matrix checks passed'
