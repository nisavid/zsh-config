
eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv zsh)"

function {
  local openclaw_completions=~/.openclaw/completions/openclaw.zsh
  [[ -r $openclaw_completions ]] && source $openclaw_completions
}

alias cdoc='cd ~/.openclaw/workspace'
#alias clawup='sudo apt update && sudo apt full-upgrade -y && pnpm self-update && pnpm -g up && pnpm -g approve-builds && clawhub update --all && openclaw gateway restart && openclaw doctor --fix'
alias clawup='sudo apt update && sudo apt full-upgrade -y && brew update && brew upgrade && pnpm self-update && pnpm -g up && pnpm -g approve-builds && openclaw update && openclaw doctor --fix'

