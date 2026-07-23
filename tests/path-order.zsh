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
fixture_bin=$tmpdir/bin
homebrew_prefix=$tmpdir/homebrew
rustup_prefix=$tmpdir/rustup
shim_dir=$fixture_home/.local/lib/secret-exec/bin
mkdir -p -- $fixture_bin $homebrew_prefix/bin $rustup_prefix/bin $shim_dir

print -rl -- \
  '#!/usr/bin/env zsh' \
  'case $* in' \
  "  'shellenv zsh') print -r -- 'export PATH=$homebrew_prefix/bin:\$PATH' ;;" \
  "  '--prefix rustup') print -r -- ${(q)rustup_prefix} ;;" \
  "  '--prefix') print -r -- ${(q)homebrew_prefix} ;;" \
  '  *) exit 64 ;;' \
  'esac' >$fixture_bin/brew
print -rl -- '#!/usr/bin/env zsh' 'exit 0' >$shim_dir/k9s
print -rl -- '#!/usr/bin/env zsh' 'exit 0' >$homebrew_prefix/bin/k9s
chmod +x $fixture_bin/brew $shim_dir/k9s $homebrew_prefix/bin/k9s

path_setup=$tmpdir/path-setup.zsh
typeset -a setup_lines
while IFS= read -r line; do
  [[ $line == '# TODO: move to lazy init' ]] && break
  setup_lines+=($line)
done <$repo_root/zshrc.zsh
print -rl -- $setup_lines >$path_setup

HOME=$fixture_home
PATH=$shim_dir:$fixture_bin:/usr/bin:/bin
source $path_setup
rehash

[[ $path[1] == $shim_dir ]] ||
  fail 'the managed secret-exec shim directory must remain first on PATH'
[[ ${commands[k9s]:A} == ${shim_dir:A}/k9s ]] ||
  fail 'command lookup must prefer the managed k9s shim over Homebrew'

openclaw_setup=$tmpdir/openclaw.zsh
while IFS= read -r line; do
  if [[ $line == 'eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv zsh)"' ]]; then
    line="eval \"\$($fixture_bin/brew shellenv zsh)\""
  fi
  print -r -- $line
done <$repo_root/zshrc.d/openclaw.zsh >$openclaw_setup
function {
  setopt localoptions noerrexit
  source $openclaw_setup
}
rehash

[[ $path[1] == $shim_dir ]] ||
  fail 'later startup scripts must preserve the managed shim directory first on PATH'
[[ ${commands[k9s]:A} == ${shim_dir:A}/k9s ]] ||
  fail 'later startup scripts must not replace the managed k9s shim with Homebrew'

print -r -- 'path-order checks passed'
