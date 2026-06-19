# Apply environment.d definitions in file order so that later entries (e.g.
# PATH prepends in higher-numbered files) build on earlier ones instead of
# clobbering them.  A single `eval export …` would expand every `$PATH` to the
# same original value, so only the last PATH= assignment would survive.
() {
  emulate -L zsh
  local file def
  for file in ${XDG_CONFIG_HOME:-~/.config}/environment.d/*(N); do
    for def in ${(f)"$(<$file)"}; do
      [[ -z $def || $def == '#'* ]] && continue
      eval "export $def"
    done
  done
}

ZDOTDIR=${XDG_CONFIG_HOME:-~/.config}/zsh

. "$HOME/.local/bin/env"

# Vite+ bin (https://viteplus.dev)
. "$HOME/.vite-plus/env"
