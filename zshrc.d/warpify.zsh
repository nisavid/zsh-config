
# Auto-Warpify
function {
  typeset TERM_PRORAM
  (( WARP_COMPAT )) && {
    [[ "$-" == *i* ]] && {
      printf 'P$f{"hook": "SourcedRcFileForWarp", "value": { "shell": "zsh", "uname": "Linux" }}'
      setopt no_correct
    }
  }
}

