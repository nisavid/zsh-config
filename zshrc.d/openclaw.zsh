
function {
  local openclaw_compile_cache=/var/tmp/openclaw-compile-cache
  [[ -w $openclaw_compile_cache(#qN-/) ]] || return
  export NODE_COMPILE_CACHE=$openclaw_compile_cache
}

export OPENCLAW_NO_RESPAWN=1

eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv zsh)"

alias cdoc='cd ~/.openclaw/workspace'
alias clawup='clawup-pre && clawup-self && clawup-post && clawup-restart'
alias clawup-pre='sudo apt update && sudo apt full-upgrade -y && brew update && brew upgrade && brew cleanup --prune=all && pnpm self-update && bun upgrade'
alias clawup-post='uv tool upgrade --all && pnpm --global upgrade --latest && pnpm --global approve-builds && skills update && openclaw skills update --all'
alias clawup-restart='openclaw gateway restart && openclaw doctor --fix'
alias clawup-self='openclaw update && openclaw gateway reinstall --force'
alias voc='v ~/.openclaw/openclaw.json'

