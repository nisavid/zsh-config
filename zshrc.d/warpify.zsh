# Auto-Warpify
function {
  # Keep Warp's normal rc-sourced signal for already-compatible shells.
  (( WARP_COMPAT )) && {
    [[ "$-" == *i* ]] && {
      printf '\033P$f{"hook": "SourcedRcFileForWarp", "value": { "shell": "zsh", "uname": "Linux" }}\234'
      unsetopt correct correct_all
    }
  }

  # Warp's SSH bootstrap is pasted into the first interactive prompt and
  # defines helper functions such as `_find` and `_log`. This config normally
  # enables zsh's command correction, which can stop that bootstrap with:
  #
  #   zsh: correct '_log' to 'log' [nyae]?
  #
  # Disable command correction before that first prompt when this SSH session
  # has Warp's environment markers.
  [[ "$-" == *i* && -n ${SSH_TTY-} ]] && {
    (( ${+WARP_ENABLE_WAYLAND} || ${+WARP_IS_LOCAL_SHELL_SESSION} || ${+WARP_BOOTSTRAPPED} || ${+WARP_COMPAT} )) ||
      [[ ${TERM_PROGRAM-} == Warp ]]
  } && unsetopt correct correct_all
}
