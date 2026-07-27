#!/usr/bin/env -S zsh -f

emulate -L zsh
setopt errexit extendedglob nounset pipefail

readonly repo_root=${0:A:h:h}
readonly zsh_bin=${commands[zsh]:A}
tmpdir=$(mktemp -d)
readonly tmpdir
trap 'rm -rf -- $tmpdir' EXIT

function fail {
  print -ru2 -- "pprint-file test failed: $1"
  return 1
}

fixture_home=$tmpdir/home
fixture_bin=$fixture_home/.local/lib/secret-exec/bin
fixture_data=$fixture_home/.local/share
fixture=$tmpdir/pf-glow-markdown-probe.md
mkdir -p -- $fixture_bin $fixture_data/zi/bin

print -rl -- \
  "#!$zsh_bin" \
  'print -r -- text/markdown' \
  >$fixture_bin/file
print -rl -- \
  "#!$zsh_bin" \
  'while (( $# )); do' \
  '  case $1 in' \
  '    (--style=*) shift ;;' \
  '    (*) break ;;' \
  '  esac' \
  'done' \
  'sed -e "s/^# //" -e "s/\\*\\*//g" -- "$1"' \
  >$fixture_bin/glow
print -rl -- \
  "#!$zsh_bin" \
  'typeset file_name input' \
  'while (( $# )); do' \
  '  case $1 in' \
  '    (--file-name=*) file_name=${1#--file-name=} ;;' \
  '    (--) shift; input=$1; break ;;' \
  '    (-*) ;;' \
  '    (*) input=$1 ;;' \
  '  esac' \
  '  shift' \
  'done' \
  'print -r -- "─────"' \
  'print -r -- "File: ${file_name:-$input}"' \
  'command cat -- "$input"' \
  >$fixture_bin/bat
print -rl -- \
  'function zi { : }' \
  'function zicompinit_fast { autoload -Uz compinit; compinit -D }' \
  'function zicdreplay { : }' \
  >$fixture_data/zi/bin/zi.zsh
chmod +x $fixture_bin/file $fixture_bin/glow $fixture_bin/bat

print -rl -- \
  '# PF_GLOW_MARKDOWN_PROBE' \
  '' \
  '**PF_GLOW_STRONG_PROBE**' \
  >$fixture

output=$(
  env -i \
    HOME=$fixture_home \
    PATH=/usr/bin:/bin \
    TERM=dumb \
    TERM_PROGRAM=CodexTest \
    WARP_COMPAT=1 \
    XDG_DATA_HOME=$fixture_data \
    ZDOTDIR=$repo_root \
    $zsh_bin -fic \
    'source "$1"
     BAT_PAGER=cat PAGER=false pprint-file "$2"
     print -r -- "GLOB_CAPTURE=$(strip-redirects command echo kept 2\>/tmp/discarded)"' \
    -- $repo_root/zshrc.zsh $fixture \
    2>$tmpdir/stderr
) || {
  sed -n '1,160p' $tmpdir/stderr >&2
  fail 'isolated interactive shell could not render the fixture'
}
plain=${output//$'\e'\[[0-9;]##m/}

[[ $plain == *PF_GLOW_MARKDOWN_PROBE* ]] ||
  { print -ru2 -- "isolated output: ${(q)plain}"
    fail 'the fake Markdown renderer output was not passed to bat'
  }
[[ $plain != *'# PF_GLOW_MARKDOWN_PROBE'* ]] ||
  fail 'pprint-file bypassed the fake Markdown renderer'
[[ $plain != *'**PF_GLOW_STRONG_PROBE**'* ]] ||
  fail 'pprint-file retained Markdown emphasis syntax'
[[ $plain == *'─────'* && $plain == *'File:'* ]] ||
  fail 'pprint-file did not preserve bat decorations'
typeset -a glob_capture_lines
glob_capture_lines=(${(M)${(f)plain}:#GLOB_CAPTURE=*})
(( $#glob_capture_lines == 1 )) ||
  fail 'extended-glob capture did not emit exactly one regression probe'
[[ $glob_capture_lines[1] == 'GLOB_CAPTURE=command echo kept' ]] ||
  fail 'extended-glob capture no longer removes a word redirection'
[[ $plain != *PF_PAGER_USED:* ]] ||
  fail 'pprint-file unexpectedly invoked an ambient pager'

print -r -- 'pprint-file checks passed'
