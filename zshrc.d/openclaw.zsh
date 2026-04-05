
function {
  local openclaw_compile_cache=/var/tmp/openclaw-compile-cache
  [[ -w $openclaw_compile_cache(#qN-/) ]] || return
  export NODE_COMPILE_CACHE=$openclaw_compile_cache
}

export OPENCLAW_NO_RESPAWN=1

eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv zsh)"

alias cdoc='cd ~/.openclaw/workspace'
#alias clawup='sudo apt update && sudo apt full-upgrade -y && pnpm self-update && pnpm -g up && pnpm -g approve-builds && clawhub update --all && openclaw gateway restart && openclaw doctor --fix'
alias clawup='sudo apt update && sudo apt full-upgrade -y && brew update && brew upgrade && pnpm self-update && pnpm -g up && pnpm -g approve-builds && openclaw update && openclaw doctor --fix'

