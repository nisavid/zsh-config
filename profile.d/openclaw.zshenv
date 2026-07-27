function {
  local openclaw_compile_cache=/var/tmp/openclaw-compile-cache
  [[ -w $openclaw_compile_cache(#qN-/) ]] &&
    export NODE_COMPILE_CACHE=$openclaw_compile_cache
}

export OPENCLAW_NO_RESPAWN=1

function {
  local homebrew_prefix=${HOMEBREW_PREFIX:-}
  if [[ -z $homebrew_prefix && -d /home/linuxbrew/.linuxbrew ]]; then
    homebrew_prefix=/home/linuxbrew/.linuxbrew
  fi
  [[ -n $homebrew_prefix ]] || return 0

  export HOMEBREW_PREFIX=$homebrew_prefix
  export HOMEBREW_CELLAR=$homebrew_prefix/Cellar
  export HOMEBREW_REPOSITORY=$homebrew_prefix/Homebrew
}
