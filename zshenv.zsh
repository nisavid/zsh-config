eval export ${${(f)"$(cat ${XDG_CONFIG_HOME:-~/.config}/environment.d/*)"}:#\#*}

ZDOTDIR=${XDG_CONFIG_HOME:-~/.config}/zsh
