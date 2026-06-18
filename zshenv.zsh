eval export ${${(f)"$(cat ${XDG_CONFIG_HOME:-~/.config}/environment.d/*)"}:#\#*}

ZDOTDIR=${XDG_CONFIG_HOME:-~/.config}/zsh

. "$HOME/.local/bin/env"

# Vite+ bin (https://viteplus.dev)
. "$HOME/.vite-plus/env"
