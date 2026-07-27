#!/usr/bin/env -S zsh -f

emulate -L zsh
setopt errexit nounset pipefail

readonly repo_root=${0:A:h:h}
tmpdir=$(mktemp -d)
readonly tmpdir
trap 'rm -rf -- $tmpdir' EXIT

function fail {
  print -ru2 -- "path-order test failed: $1"
  return 1
}

fixture_home=$tmpdir/home
homebrew_prefix=$tmpdir/homebrew
late_prefix=$tmpdir/late
shim_dir=$fixture_home/.local/lib/secret-exec/bin
mkdir -p -- $homebrew_prefix/bin $late_prefix/bin $shim_dir

print -rl -- '#!/usr/bin/env zsh' 'exit 0' >$shim_dir/k9s
print -rl -- '#!/usr/bin/env zsh' 'exit 0' >$homebrew_prefix/bin/k9s
chmod +x $shim_dir/k9s $homebrew_prefix/bin/k9s

HOME=$fixture_home
PATH=$shim_dir:/usr/bin:/bin
unset BIN_HOME APPIMAGE_HOME KREW_ROOT KDE_SRC VP_HOME PNPM_HOME
XDG_DATA_HOME=$fixture_home/.local/share
HOMEBREW_PREFIX=$homebrew_prefix
source $repo_root/startup.zsh zshenv "$OSTYPE"
rehash

[[ $path[1] == $shim_dir ]] ||
  fail 'the managed secret-exec shim directory must remain first on PATH'
[[ ${commands[k9s]:A} == ${shim_dir:A}/k9s ]] ||
  fail 'command lookup must prefer the managed k9s shim over Homebrew'

path=( $homebrew_prefix/bin $late_prefix/bin $path $homebrew_prefix/bin )
source $repo_root/startup.zsh zshrc-final "$OSTYPE"

[[ $path[1] == $shim_dir ]] ||
  fail 'the final startup phase must restore the managed shim directory first on PATH'
[[ ${commands[k9s]:A} == ${shim_dir:A}/k9s ]] ||
  fail 'the final startup phase must restore the managed k9s shim after later PATH changes'
integer homebrew_count=0 late_count=0
for path_entry in $path; do
  [[ $path_entry == $homebrew_prefix/bin ]] && (( ++homebrew_count ))
  [[ $path_entry == $late_prefix/bin ]] && (( ++late_count ))
done
(( homebrew_count == 1 )) ||
  fail 'the final startup phase must remove duplicate integration PATH entries'
(( late_count == 1 )) ||
  fail 'the final startup phase must preserve unique integration PATH entries'

print -r -- 'path-order checks passed'
