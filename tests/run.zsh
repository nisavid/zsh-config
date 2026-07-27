#!/usr/bin/env -S zsh -f

emulate -L zsh
setopt errexit nounset pipefail

readonly tests_dir=${0:A:h}
readonly zsh_bin=${commands[zsh]:A}
readonly -a tests=(
  path-order.zsh
  pprint-file.zsh
  profile-phases.zsh
  startup-matrix.zsh
  zshenv.zsh
)

autoload -Uz is-at-least
is-at-least 5.9 ||
  { print -ru2 -- "tests require Zsh 5.9 or newer; found $ZSH_VERSION"; exit 1 }

for test_file in $tests; do
  print -r -- "running tests/$test_file"
  $zsh_bin -f $tests_dir/$test_file
done

print -r -- 'all hermetic tests passed'
