# Zsh runtime configuration


## PATHS & VARIABLES


BIN_HOME=~/.local/bin
[[ -d $BIN_HOME ]] || mkdir --parents $BIN_HOME

APPIMAGE_HOME=~/.local/bin/appimage
[[ -d $APPIMAGE_HOME ]] || mkdir --parents $APPIMAGE_HOME

export PNPM_HOME=${XDG_DATA_HOME:-~/.local/share}/pnpm

export KDE_SRC=~/src/kde

function {
  local path_prefix_dirs=(
    $BIN_HOME
    $APPIMAGE_HOME
    ${GOBIN:-~/go/bin}
    $PNPM_HOME
    $KDE_SRC/kdesrc-build
  )

  integer i;
  for (( i = ${#path_prefix_dirs[@]}; i > 0; i-- )); do
    [[ -d $path_prefix_dirs[i] ]] || path_prefix_dirs[i]=()
  done

  path=( $path_prefix_dirs $path )
}

[[ -r /etc/grc.zsh ]] && source /etc/grc.zsh

# Load Instant Prompt
POWERLEVEL9K_INSTANT_PROMPT=verbose
function {
  readonly instant_prompt_src=${XDG_CACHE_HOME:-~/.cache}/p10k-instant-prompt-nisavid.zsh
  [[ -r $instant_prompt_src ]] && source $instant_prompt_src
}

# NOTE: From this point until “Load full prompt” near the end of this file,
# nothing should print any output.

print -v PPNAME /proc/$PPID/exe(N:P:t)
TMPPREFIX=${XDG_RUNTIME_DIR:-/tmp}/zsh

(( $+commands[bat] )) && export PAGER=bat

(( $+commands[lesspipe.sh] )) && export LESSOPEN='| lesspipe.sh %s'
(( $+commands[src-hilite-lesspipe.sh] )) && export LESSOPEN='| src-hilite-lesspipe.sh %s'
export LESS='--exit-follow-on-close --incsearch --ignore-case --line-numbers --LONG-PROMPT --modelines=5 --mouse'
LESS+=' --no-histdups --quiet --quit-if-one-screen --RAW-CONTROL-CHARS --show-preproc-errors --status-column --tabs=4'
LESS+=' --tilde --use-color --wheel-lines=3 --window=-4 --wordwrap'
export BAT_PAGER="less -FiMnqR~ -z-4 --incsearch --mouse --no-histdups --show-preproc-errors --status-column --use-color --wheel-lines=3 --wordwrap"

export GROFF_NO_SGR=1

#(( $+commands[bat] )) && export MANPAGER="sh -c 'col --no-backspaces --spaces | bat --language man --plain'"
(( $+commands[nvim] )) && export MANPAGER='nvim +Man!'
export MANROFFOPT='-c'
export MANWIDTH=$COLUMNS

export BROWSER=firefox

(( $+commands[nvim] )) && export EDITOR=nvim
export SYSTEMD_EDITOR=$EDITOR

export FZF_BASE=/usr/share/fzf
[[ $COLORTERM == *(24bit|truecolor)* ]] \
  && export FZF_DEFAULT_OPTS=" \
    --color=bg+:#313244,bg:#1e1e2e,spinner:#f5e0dc,hl:#f38ba8 \
    --color=fg:#cdd6f4,header:#f38ba8,info:#cba6f7,pointer:#f5e0dc \
    --color=marker:#f5e0dc,fg+:#cdd6f4,prompt:#cba6f7,hl+:#f38ba8"

export GLAMOUR_STYLE=${XDG_CONFIG_HOME:-~/.config}/glamour/catppuccin-mocha.json

if [[ -d ~/.gnupg ]] && (( $+commands[gpg-connect-agent] )); then
  export GPG_TTY=/dev/${(%):-%l}
  gpg-connect-agent UPDATESTARTUPTTY /bye >/dev/null
  #[[ -v SSH_CONNECTION ]] || export SSH_AUTH_SOCK=$XDG_RUNTIME_DIR/gnupg/S.gpg-agent.ssh
fi

function {
  readonly lg_config_dir=${XDG_CONFIG_HOME:-~/.config}/lazygit
  export LG_CONFIG_FILE=$lg_config_dir/catppuccin-mocha-sapphire.yml,$lg_config_dir/config.yml
}

[[ $COLORTERM == *(24bit|truecolor)* ]] \
  && export MICRO_TRUECOLOR=1


## TERMINAL


zmodload zsh/parameter
zmodload zsh/terminfo

function {
  readonly -aU terminfo_dirs=( ${(s<:>)TERMINFO_DIRS}(N-/:P) {/etc,/lib,/usr/share}/terminfo(N-/:P) )
  export TERMINFO_DIRS=${(j<:>)terminfo_dirs}
}

# Ensure that the terminal is in application mode when ZLE is active
if (( ${+terminfo[smkx]} && ${+terminfo[rmkx]} )); then
  autoload -Uz add-zle-hook-widget
  function zle_application_mode_start { echoti smkx }
  function zle_application_mode_stop { echoti rmkx }
  add-zle-hook-widget -Uz zle-line-init zle_application_mode_start
  add-zle-hook-widget -Uz zle-line-finish zle_application_mode_stop
fi

[[ $COLORTERM = *(24bit|truecolor)* ]] || zmodload zsh/nearcolor

bindkey -v


## ZI


typeset -A ZI=(
  HOME_DIR ${XDG_DATA_HOME:-~/.local/share}/zi
  CONFIG_DIR ${XDG_CONFIG_HOME:-~/.config}/zi
  CACHE_DIR ${XDG_CACHE_HOME:-~/.cache}/zi
)
ZI[BIN_DIR]=$ZI[HOME_DIR]/bin

[[ -r $ZI[BIN_DIR]/zi.zsh ]] && source $ZI[BIN_DIR]/zi.zsh
unset MANPATH

ZI_LIGHT=1
if (( $+functions[zi] )); then
  ## ZI | ZSH

  zi wait:'1' pack atload=+'zicompinit_fast; zicdreplay' for system-completions
  zi ${ZI_LIGHT:+light-mode} for z-shell/z-a-meta-plugins @annexes
  # XXX: z-shell/zsh-fancy-completions (included by @zsh-users+fast) tries
  #   to run `ypcat` (nonexistent command) when populating hosts lists
  #   for e.g. `ssh` completion, which triggers `find-the-command` and breaks
  #   the completion.  Not sure how to fix this properly.  For now, create
  #   this symlink as a workaround.
  (( $+commands[ypcat] )) || ln --symbolic =false $BIN_HOME/ypcat
  zi ${ZI_LIGHT:+light-mode} for @zsh-users+fast
  zi ${ZI_LIGHT:+light-mode} for @romkatv
  zi ${ZI_LIGHT:+light-mode} for z-shell/H-S-MW
  zi ${ZI_LIGHT:+light-mode} for zsh-vi-more/evil-registers
  zi ${ZI_LIGHT:+light-mode} for zsh-vi-more/vi-motions
  zi ${ZI_LIGHT:+light-mode} for zsh-vi-more/vi-quote
  zstyle :zle:evil-registers:'[A-Za-z%#]' editor nvim
  zi wait lucid ${ZI_LIGHT:+light-mode} for Tarrasch/zsh-functional
  zi wait lucid ${ZI_LIGHT:+light-mode} for sei40kr/zsh-run-help-collections

  ## ZI | THEMES & COLORS

  zi ${ZI_LIGHT:+light-mode} \
    if:'(( $+functions[fast-theme] ))' \
    as:'null' \
    atclone:'() { readonly destdir=${XDG_CONFIG_HOME:-~/.config}/f-sy-h; mkdir --parents $destdir && cp --force themes/catppuccin-mocha.ini $destdir/; }' \
    atpull:'%atclone' \
    atload:'fast-theme --quiet CONFIG:catppuccin-mocha' \
    for catppuccin/zsh-fsh
  function {
    readonly -a args=(
      id-as:'vivid-lscolors'
      atpull:'rm --force lscolors.zsh'
      run-atpull
      atload:'[[ -e lscolors.zsh ]] || print export LS_COLORS="${(qq)$(vivid generate catppuccin-mocha)}" >lscolors.zsh'
      pick:'lscolors.zsh'
    )
    if (( $+commands[vivid] )); then :
    elif (( $+commands[cargo] )); then args[1,0]=( cargo:'vivid' )
    else zi wait lucid ${ZI_LIGHT:+light-mode} as:'program' from:'gh-r' bpick:'*x86_64-unknown-linux-gnu*' extract:'!' pick:'vivid' for sharkdp/vivid
    fi
    zi wait lucid ${ZI_LIGHT:+light-mode} "${(@)args}" for z-shell/0
  }

  ## ZI | SYSTEM

  function {
    readonly script=/usr/share/doc/find-the-command/ftc.zsh
    zi wait lucid ${ZI_LIGHT:+light-mode} \
      id-as:'find-the-command' \
      if:"[[ -r $script ]]" \
      as:'null' \
      atload:"source '$script' askfirst noupdate" \
      for z-shell/0
  }
  function {
    readonly script=/opt/asdf-vm/asdf.sh
    zi wait lucid ${ZI_LIGHT:+light-mode} id-as:'asdf' if:"[[ -r $script ]]" pick:"$script" for z-shell/0
  }
  zi wait lucid is-snippet for \
    has:'systemctl' OMZP::systemd
  zi wait lucid ${ZI_LIGHT:+light-mode} \
    id-as:'manpath' \
    has:'manpath' \
    as:'null' \
    atpull:'rm --force init.zsh' \
    run-atpull \
    atload:'[[ -e init.zsh ]] || print -n -- export -aUT MANPATH manpath=\( ${(s<:>q-)"$(manpath)"} \) >init.zsh' \
    pick:'init.zsh' \
    for z-shell/0

  ## ZI | LANGUAGES & TOOLKITS

  # Elm
  zi wait lucid ${ZI_LIGHT:+light-mode} atload:'elm-completion-update 2>/dev/null' for kraklin/elm.plugin.zsh

  # KDE
  function {
    readonly compdir=$KDE_SRC/kdesrc-build/completions/zsh
    if [[ -d $compdir ]]; then
      zi wait lucid ${ZI_LIGHT:+light-mode} \
        id-as:'kde-buildtools-completions' \
        atclone:"
          rm --recursive --force completions
          cp --archive ${(q-)compdir} completions
          cp 0.plugin.zsh init.zsh
          print 'fpath[1,0]=( \${0:h}/completions )' >>init.zsh" \
        atpull:'%atclone' run-atpull \
        src:'init.zsh' \
        for z-shell/0
    fi
  }

  # nvim-qt
  zi wait lucid ${ZI_LIGHT:+light-mode} \
    id-as:'nvim-qt-runtime-path' \
    has:'nvim-qt' \
    as:'null' \
    atpull:'rm --force init.zsh' \
    run-atpull \
    atload:'[[ -e init.zsh ]] || print -n -- export NVIM_QT_RUNTIME_PATH=${(q-)${${(M)${(f)"$(nvim-qt --version)"}:#[[:blank:]]#runtime:[[:blank:]]##*}#[[:blank:]]#runtime:[[:blank:]]##}:P} >init.zsh' \
    pick:'init.zsh' \
    for z-shell/0

  # Perl
  function {
    readonly prefix=${XDG_DATA_HOME:-~/.local/share}/perl5
    zi wait lucid ${ZI_LIGHT:+light-mode} \
      id-as:'perlpath' \
      has:'cpanm' \
      as:'null' \
      atclone:"
        PERL5LIB=$prefix/lib/perl5 perldoc -l local::lib &>/dev/null || cpanm --local-lib=$prefix local::lib
        local assn lhs rhs
        print -r -- \${(F)\${(f)\"\$(perl -I$prefix/lib/perl5 -Mlocal::lib=$prefix 2>/dev/null)\"}%%;*} >|\${XDG_CONFIG_HOME:-\~/.config}/environment.d/20-perl.conf" \
      atpull:'%atclone' run-atpull \
      for z-shell/0
  }

  # Python
  function {
    readonly script=${XDG_CONFIG_HOME:-~/.config}/python/startup.py
    zi wait lucid ${ZI_LIGHT:+light-mode} \
      id-as:'python-startup' \
      as:'null' \
      atclone:"
        mkdir --parents $script:h
        rm --force $script
        python -m fancycompleter install --force &>/dev/null && mv ~/python_startup.py $script" \
      atpull:'%atclone' run-atpull \
      atload:"export PYTHONSTARTUP=${(q-)script}" \
      for z-shell/0
  }

  ## ZI | MISCELLANEA

  # Locally generated completions
  function {
    readonly -A shtab_cmds_modules=(
      pipdeptree pipdeptree._cli.build_parser
    )
    readonly tabtab=${XDG_CONFIG_HOME:-~/.config}/tabtab/zsh/__tabtab.zsh
    (( $+commands[shtab] )) \
      || zi wait lucid ${ZI_LIGHT:+light-mode} id-as:'shtab' pip:'shtab' nocompile for sharkdp/shtab
    zi wait lucid ${ZI_LIGHT:+light-mode} \
      id-as:'localgen-completions' \
      atclone:'
        rm --recursive --force completions && mkdir completions
        (( $+commands[cog] )) && cog generate-completions zsh >completions/_cog.zsh
        (( $+commands[pip] )) && pip completion --zsh >completions/_pip.zsh
        (( $+commands[pipx] )) && register-python-argcomplete pipx >completions/_pipx.zsh
        (( $+commands[pipenv] )) && _PIPENV_COMPLETE=zsh_source pipenv >completions/_pipenv.zsh
        if (( $+commands[pnpm] )); then
          [[ -e ~/.zshrc ]] && cp --archive --force ~/.zshrc{,.zi-bak}
          pnpm install-completion zsh >/dev/null
          if [[ -e ~/.zshrc.zi-bak ]]; then mv --force ~/.zshrc{.zi-bak,}; else rm --force ~/.zshrc; fi
        fi
        (( $+commands[rye] )) && rye self completion --shell=zsh >completions/_rye.zsh
        if (( $+commands[shtab] )); then
          shtab --print-own-completion=zsh >completions/_shtab.zsh
          local cmd parser
          for cmd parser in ${(kv)shtab_cmds_modules}; do
            shtab --shell=zsh $parser >completions/_$cmd.zsh
          done
        fi
        cp 0.plugin.zsh init.zsh'"
        print 'fpath[1,0]=( \${0:h}/completions )' >>init.zsh
        [[ -f $tabtab ]] || { mkdir --parents $tabtab:h && touch $tabtab }" \
      atpull:'%atclone' run-atpull \
      multisrc:"init.zsh $tabtab" \
      for z-shell/0
  }

  # Locally generated startup scripts
  zi wait lucid ${ZI_LIGHT:+light-mode} \
    id-as:'localgen-zshrc' \
    atclone:'
      rm --recursive --force scripts && mkdir scripts
      (( $+commands[gh] )) && gh copilot --version >/dev/null \
        && gh copilot alias -- zsh >scripts/gh-copilot-aliases.zsh
      cp 0.plugin.zsh init.zsh'"
      print 'integer ret; for script in \${0:h}/scripts/*; do source \$script; ret=\$\(( ret + ? )); done; \(( ! ret ))' >>init.zsh" \
    atpull:'%atclone' run-atpull \
    src:'init.zsh' \
    for z-shell/0
else
  autoload -Uz compinit
  compinit
fi


## BUILT-IN SETTINGS


## BUILT-IN SETTINGS | SHELL OPTIONS


# Changing Directories
setopt auto_cd auto_pushd cdable_vars cd_silent pushd_ignore_dups pushd_silent
# Completion
setopt always_to_end complete_in_word glob_complete no_list_beep
# Expansion and Globbing
setopt bad_pattern brace_ccl case_paths extended_glob glob_star_short hist_subst_pattern magic_equal_subst numeric_glob_sort rematch_pcre
# History
setopt extended_history hist_fcntl_lock hist_find_no_dups hist_ignore_space hist_lex_words hist_no_store hist_reduce_blanks inc_append_history_time
# Initialization
setopt no_global_export
# Input/Output
setopt no_clobber correct dvorak no_flow_control no_hash_cmds no_hash_dirs rc_quotes
# Job Control
setopt long_list_jobs
# Scripts and Functions
setopt c_bases c_precedences local_loops no_multi_func_def pipe_fail
# Zle
setopt combining_chars


## BUILT-IN SETTINGS | PARAMETERS


CORRECT_IGNORE_FILE='.*'
HISTORY_IGNORE='(? *|bg(| *)|bye|dirs(| *)|disown *|exit|fg(| *)|hash(| *)|history|job *|jobs(| *)|kill *|logout|popd(| *)|pushd(| *)|pwd|r|rehash|unhash *|wait(| *)|whence *|which *)'
HISTFILE=${XDG_STATE_HOME:-~/.local/state}/zsh/history
HISTSIZE=101000000
KEYTIMEOUT=1 # centiseconds
SAVEHIST=100000000

ZSH_AUTOSUGGEST_BUFFER_MAX_SIZE=100
ZSH_AUTOSUGGEST_STRATEGY=( match_prev_cmd history )
[[ -n /dev/pts/*(#qN) ]] && ZSH_AUTOSUGGEST_STRATEGY+=( completion )


## BUILT-IN SETTINGS | MODULES & FUNCTIONS


zmodload zsh/attr
zmodload zsh/datetime
zmodload zsh/mathfunc
zmodload zsh/param/private
zmodload zsh/pcre
zmodload zsh/regex
zmodload -F zsh/stat b:zstat

autoload -Uz add-zsh-hook
autoload -Uz bracketed-paste-magic
autoload -Uz catch
autoload -Uz regexp-replace
unalias run-help
autoload -Uz run-help
autoload -Uz ${^fpath}/run-help-*(N:t)
autoload -Uz throw
autoload -Uz zargs
autoload -Uz zcp
autoload -Uz zln
autoload -Uz zmv
autoload -Uz zsh-mime-setup
autoload -Uz zstyle+


## BUILT-IN SETTINGS | HOOKS & WIDGETS

function xterm_title_precmd {
  print -Pn -- '\e]2;%n@%m %~\a'
  [[ "$TERM" == 'screen'* ]] \
    && print -Pn -- '\e_\005{g}%n\005{-}@\005{m}%m\005{-} \005{B}%~\005{-}\e\\'
}
function xterm_title_preexec {
  print -Pn -- '\e]2;%n@%m %~ %# '
  print -n -- "${(q)1}\a"
  if [[ "$TERM" == 'screen'* ]]; then
    print -Pn -- '\e_\005{g}%n\005{-}@\005{m}%m\005{-} \005{B}%~\005{-} %# '
    print -n -- "${(q)1}\e\\"
  fi
}
if [[ "$TERM" == (Eterm*|alacritty*|aterm*|foot*|gnome*|konsole*|kterm*|putty*|rxvt*|screen*|wezterm*|tmux*|xterm*) ]]; then
  add-zsh-hook -Uz precmd xterm_title_precmd
  add-zsh-hook -Uz preexec xterm_title_preexec
fi

function workspace-update-path {
  local newpaths=( ${(A):-(../)#package.json(N-.:h)} )
  newpaths=( ${^newpaths}/node_modules/.bin(N-/) )
  path=( $newpaths ${path:#*/node_modules/.bin} )
}
add-zsh-hook chpwd workspace-update-path
workspace-update-path

zle -N bracketed-paste bracketed-paste-magic


## BUILT-IN SETTINGS | KEY BINDINGS


typeset -A key=(
  Tab "${terminfo[ht]}"
  Shift-Tab "${terminfo[kcbt]}"
  Backspace "${terminfo[kbs]}"
  Control-Backspace "${terminfo[cub1]}"
  Home "${terminfo[khome]}"
  End "${terminfo[kend]}"
  Insert "${terminfo[kich1]}"
  Delete "${terminfo[kdch1]}"
  Up "${terminfo[kcuu1]}"
  Down "${terminfo[kcud1]}"
  Left "${terminfo[kcub1]}"
  Right "${terminfo[kcuf1]}"
  PageUp "${terminfo[kpp]}"
  PageDown "${terminfo[knp]}"
  F1 "${terminfo[kf1]}"
  F2 "${terminfo[kf2]}"
  F3 "${terminfo[kf3]}"
  F4 "${terminfo[kf4]}"
  F5 "${terminfo[kf5]}"
  F6 "${terminfo[kf6]}"
  F7 "${terminfo[kf7]}"
  F8 "${terminfo[kf8]}"
  F9 "${terminfo[kf9]}"
  F10 "${terminfo[kf10]}"
  F11 "${terminfo[kf11]}"
  F12 "${terminfo[kf12]}"
  F13 "${terminfo[kf13]}"
  F14 "${terminfo[kf14]}"
  F15 "${terminfo[kf15]}"
  F16 "${terminfo[kf16]}"
  F17 "${terminfo[kf17]}"
  F18 "${terminfo[kf18]}"
  F19 "${terminfo[kf19]}"
  F20 "${terminfo[kf20]}"
  F21 "${terminfo[kf21]}"
  F22 "${terminfo[kf22]}"
  F23 "${terminfo[kf23]}"
  F24 "${terminfo[kf24]}"
)
function {
  readonly -A extkeys=(
    Home kHOM
    End kEND
    Delete kDC
    Up kUP
    Down kDN
    Left kLFT
    Right kRIT
    PageUp kPRV
    PageDown kNXT
  )
  readonly -A modifiers=(
    Shift 2
    Alt 3
    Alt-Shift 4
    Control 5
    Control-Shift 6
    Control-Alt 7
    Control-Alt-Shift 8
    Meta 9
    Meta-Shift 10
    Meta-Alt 11
    Meta-Alt-Shift 12
    Meta-Control 13
    Meta-Control-Shift 14
    Meta-Control-Alt 15
    Meta-Control-Alt-Shift 16
  )
  local extkey extkey_tiname mod mod_suffix keycode
  for extkey extkey_tiname in ${(kv)extkeys}; do
    for mod mod_suffix in ${(kv)modifiers}; do
      keycode=$terminfo[$extkey_tiname$mod_suffix]
      [[ -n $keycode ]] && key[$mod-$extkey]=$keycode
    done
  done
}

bindkey $key[Backspace] backward-delete-char
bindkey $key[Delete] delete-char
bindkey $key[Home] beginning-of-line
bindkey $key[End] end-of-line
bindkey '^A' beginning-of-line
bindkey '^E' end-of-line
bindkey '^H' run-help
bindkey '^K' kill-line
bindkey '^L' autosuggest-accept


## BUILT-IN SETTINGS | STYLES


zstyle '*' pager bat


## BUILT-IN SETTINGS | COMPLETIONS


function compdefas { (( $+_comps[$1] )) && compdef $_comps[$1] ${^@[2,-1]}=$1 }


## FUNCTIONS

if (( $+commands[kwallet-query] )); then
  function export-secret-from-kwallet {
    readonly var=$1 folder=$2 entry=$3
    export $var=$(kwallet-query kdewallet -f $folder -r $entry 2>/dev/null)
  }

  function wrap-with-secret-from-kwallet {
    readonly cmd=$1 var=$2 folder=$3 entry=$4
    eval "
    function $cmd {
      local -i use_kwallet=0
      [[ -v $var ]] || use_kwallet=1
      (( use_kwallet )) && export-secret-from-kwallet $var $folder $entry
      command $cmd \"\$@\"
      (( use_kwallet )) && unset $var
    }"
  }

  wrap-with-secret-from-kwallet parcel FIREBASE_API_KEY firebase-api api_key
  wrap-with-secret-from-kwallet pnpm FIREBASE_API_KEY firebase-api api_key
  (( $+commands[sgpt] )) && wrap-with-secret-from-kwallet sgpt OPENAI_API_KEY openai-api api_key
fi

if (( $+commands[bw] )); then
  function bw {
    if [[ -z $BW_CLIENTID ]] && (( $+commands[kwallet-query] )); then
      export BW_CLIENTID=$(kwallet-query kdewallet -f bitwarden-api -r client_id 2>/dev/null)
      export BW_CLIENTSECRET=$(kwallet-query kdewallet -f bitwarden-api -r client_secret 2>/dev/null)
    fi
    if [[ -n $BW_CLIENTID && -z $BW_SESSION ]] && (( $+commands[kwallet-query] )); then
      export BW_SESSION=$(command bw unlock $(kwallet-query kdewallet -f bitwarden-api -r password 2>/dev/null) --raw)
    fi
    command bw "$@"
  }
fi

function caller-name {
  print -r -- ${${funcstack[3,-1]}[(r)^\(*\)]}
}

function env-system {
  readonly -a cmds=(
    'exec </dev/tty &>/dev/tty'
    'source /etc/zsh/zprofile'
    "${(j< >)${(q)@}}"
  )
  env --ignore-environment TERM=$TERM \
    zsh --no-rcs -c "${(j<;>)cmds}"
}

typeset -A ext_mimetype
function {
  readonly -a files=( /etc/mime.types ~/.mime.types )
  readonly token_pat='[^][:cntrl:][:space:]()<>@,;:\\"/?=[]##'
  # XXX: This is extracted to a constant and weirdly quoted/escaped merely to appease Neovim's deficient parsing of Zsh extended globs
  readonly pat="(#b)(${~token_pat}/${~token_pat}"')(([[:space:]]##'"${~token_pat}"')##)'
  local line mimetype ext
  local -a exts
  <${^files}(N-.) while read -r line; do
    if [[ $line == $~pat ]]; then
      mimetype=$match[1]
      exts=( ${(z)match[2]} )
      for ext in $exts; do
        ext_mimetype[$ext]=$mimetype
      done
    fi
  done
}

function file-mimetype {
  readonly ext=$1:e
  local mimetype
  [[ -n $ext ]] && mimetype=$ext_mimetype[$ext]
  [[ -n $mimetype ]] || mimetype=$(file --brief --mime-type -- $1)
  print -rn -- $mimetype
}

function help {
  {
    readonly cmdname=$(realcmdname "$@")
    [[ -n $cmdname ]] || throw NoHelp
    if [[ $cmdname == (${(~j.|.)${(z)${(f)"$(run-help)"}[3,-1]}}) ]]; then
      PAGER=cat run-help $cmdname | bat --plain --language=help
    elif man --whatis --sections=1 $cmdname &>/dev/null; then
      man $cmdname
    else throw NoHelp
    fi
  } always {
    if catch NoHelp; then
      print -r -- "No help for ${(q-)cmdname:-$@}" >&2
      return 1
    fi
  }
}

function history {
  local -a opts=( "${${args:#(-|)[[:digit:]]##}[@]}" )
  local -a args=( "${${(M)args:#(-|)[[:digit:]]##}[@]}" )
  (( #opts )) || opts=( -Ddi )
  (( #args )) || args=( 1 )
  builtin history $opts $args | BAT_STYLE=plain LESS+=' +G' "${${(z)PAGER}[@]}"
}

function in-dir {
  cd $1 || return
  shift
  { "$@" } always { cd - }
}

function journalctl {
  if [[ -n ${argv:#(--follow|-([^-]*|)f*)|--no-pager} ]]; then
    local less=$LESS
    [[ -n ${(M)argv:#(--pager-end|-([^-]*|)f*)} ]] && less+=' +G'
    grc --colour=on $commands[$0] "$@" | $PAGER
  else
    grc --colour=on $commands[$0] "$@"
  fi
}

function mkcd {
  mkdir --parents $args[2,-1] -- $1 && cd $1
}

function mktemp {
  local -a opts_tmpdir opts_rest args
  while (( $# )); do
    case $1 in
      (--tmpdir|-p) opts_tmpdir+=( $1 "$2" ); shift ;;
      (--tmpdir=*|-p*) opts_tmpdir+=( $1 ) ;;
      (--suffix) opts_rest+=( $1 "$2" ); shift ;;
      (--suffix=*) opts_rest+=( $1 ) ;;
      (--) opts_rest+=( $1 ); args+=( "$@" ); break ;;
      (*) args+=( "$1" )
    esac
    shift
  done
  (( #opts_tmpdir )) || opts_tmpdir=( --tmpdir=${XDG_RUNTIME_DIR:-${TMPDIR:-/tmp}} )
  if ! (( #args )); then
    [[ "${opts_rest[-1]}" == -- ]] || opts_rest+=( -- )
    args=( ${$(caller-name):-zsh}.XXXX )
  fi

  command mktemp "${opts_tmpdir[@]}" "${opts_rest[@]}" "${args[@]}"
}

function mktempd {
  mktemp --directory "$@"
}

function netscan {
  local -a opts args
  while (( $# )); do
    case $1 in
      (-*) opts+=( $1 ) ;;
      (--) shift; args+=( "$@" ); break ;;
      (*) args+=( $1 )
    esac
    shift
  done

  sudo rustscan -a $args -- --privileged $opts
}
compdefas nmap netscan

function netscan-all {
  netscan -A "$@"
}
compdefas nmap netscan-all

function netscan-hosts {
  netscan -PE -PS443 -PA80 -PP "$@"
}
compdefas nmap netscan-hosts

function netscan-os {
  netscan-ports -O --osscan-guess "$@"
}
compdefas nmap netscan-os

function netscan-ports {
  netscan "$@" $( (( $+argv[(re)--] )) || print -- --) --top
}
compdefas nmap netscan-ports

function netscan-ports-all {
  netscan "$@"
}
compdefas nmap netscan-ports-all

function pprint-file {
  local -a opts files
  while (( $# )); do
    case $1 in
      (-*) opts+=( $1 ) ;;
      (*) files+=( $1 )
    esac
    shift
  done

  local -a out_files
  local file mimetype tmpdir tmpfile
  for file in $files; do
    mimetype=$(file-mimetype $file)
    case $mimetype in
      (text/markdown)
        [[ -d $tmpdir ]] || { tmpdir=$(mktempd) || return; trap 'rm --recursive --force -- $tmpdir' EXIT }
        tmpfile=$tmpdir/${file#/}
        mkdir --parents -- $tmpfile:h
        command glow --style=$GLAMOUR_STYLE $file >$tmpfile
        out_files+=( $tmpfile )
        ;;
      (*) out_files+=( $file )
    esac
  done

  $PAGER $opts -- ${(q-)out_files}
}

function pprint-zfunc { functions -x2 -- "$@" | bat --language=zsh }

function py {
  if (( $# )); then
    python "$@"
  else
    python -ic '
try: import fancycompleter
except ModuleNotFoundError: pass
else: fancycompleter.interact(persist_history=True)'
  fi
}

function realcmdname {
  print -r -- ${${(zA)"$(strip-precmds ${(z)"$(resolve-aliases ${(z)"$(strip-redirects ${(z)"$(strip-vardefs "$@")"})"})"})"}[1]}
}

function resolve-aliases {
  emulate -L zsh
  local -a cmdargv=( $argv )
  local -a val
  while alias +r $cmdargv[1] &>/dev/null; do
    val=( ${(Qz)"$(alias -r $cmdargv[1])"#*=} ) || break
    cmdargv[1]=( $val )
  done
  print -r -- ${(q-)cmdargv}
}

function sgpt4s {
  sgpt --model=gpt-4-turbo-preview --shell "$*"
}

function sgpts {
  sgpt --shell "$*"
}

function strip-precmds {
  emulate -L zsh -o extended_glob
  while (( $# )); do
    case $1 in
      (-|builtin|command|nocorrect|noglob|sudo) shift ;;
      (exec)
        shift
        while [[ $1 == -[acl]## ]]; do
          [[ $1 == *a ]] && shift
          shift
        done
        ;;
      (*) break
    esac
  done
  print -r -- ${(q-)argv}
}

function strip-redirects {
  emulate -L zsh -o extended_glob
  readonly -a word_redirs=( ${(z):-'< <> > >| >! >> >>| >>! <<< >& &> >&| >&! &>| &>! >>& &>> >>&| >>&! &>>| &>>!'} )
  readonly -a fd_redirs=( ${(z):-'<& >&'} )
  readonly word_redir_pat=\(${(j.|.)${(b)word_redirs}}\) fd_redir_pat=\(${(j.|.)${(b)fd_redirs}}\)
  readonly ident_pat='[[:IDENT:]]##'
  readonly lhs_pat="(|[0-9]|{${ident_pat}})" fd_rhs_pat="(|-|p|[0-9]|\$${ident_pat})"
  integer i
  for (( i = 1; i <= $#argv; i++ )); do
    case $argv[i] in
      (${~lhs_pat}${~word_redir_pat}(*))
        argv[i]=()
        (( $#match[3] )) || argv[i]=()
        i=i-1
        ;;
      (${~fd_redir_pat}${~fd_rhs_pat})
        argv[i]=()
        (( $#match[2] )) || argv[i]=()
        i--
        ;;
    esac
  done
  print -r -- ${(q-)argv}
}

function strip-vardefs {
  emulate -L zsh -o extended_glob
  print -r -- ${(q-)argv:#[[:IDENT:]]##=*}
}

function zi-update {
  zi self-update && zi update --all
}

function zsh-config-update {
  [[ -d $ZDOTDIR_ORIGIN ]] || return
  [[ -d $ZDOTDIR:h ]] || mkdir --parents -- $ZDOTDIR:h || return
  [[ -e $ZDOTDIR && ! -w $ZDOTDIR ]] && { print -r "error: not writable:" ${(q-)ZDOTDIR}; return }

  readonly tmp=$ZDOTDIR.$RANDOM || return
  trap 'rm --recursive --force -- $tmp' EXIT
  cp --archive -- $ZDOTDIR_ORIGIN $tmp || return
  if [[ -d $ZDOTDIR/zshrc.d ]]; then
    mkdir --parents -- $tmp/zshrc.d || return
    cp --archive --update -- $ZDOTDIR/zshrc.d/* $tmp/zshrc.d/ || return
  fi
  rm --recursive --force -- $ZDOTDIR || return
  mv -- $tmp $ZDOTDIR || return
}

function zsh-update {
  if [[ -r $ZDOTDIR_ORIGIN ]]; then
    zsh-config-update || return
  fi
  zi-update
}


## ALIASES


alias ...='cd ../..'
alias ....='cd ../../..'
alias .....='cd ../../../..'
alias -- -='cd -'
alias '?'=help
alias '??'='gh copilot suggest --target=shell'
alias '??gh'='gh copilot suggest --target=gh'
alias '??git'='gh copilot suggest --target=git'
alias '???'=sgpts
alias '????'=sgpt4s
alias bat-help='bat --plain --language=help'
alias cat='bat --paging=never'
alias cdnvim="cd ${XDG_CONFIG_HOME:-~/.config}/nvim"
alias cdzsh="cd $ZDOTDIR"
alias clamdscan='clamdscan --multiscan --fdpass'
alias firewall-cmd='sudo firewall-cmd'
alias g=git
alias gg=lazygit
alias gitui='gitui --theme=catppuccin-mocha.ron --watcher'
alias ind=in-dir
alias informant='sudo informant'
alias jc='journalctl --catalog'
alias jc@='jc --unit'
alias jcb='jc --boot'
alias jcf='jc --follow'
alias jcf@='jcf --unit'
alias jcfu='jcf --user'
alias jcfu@='jcf --user-unit'
alias jck='jc --dmesg'
alias jckf='jck --follow'
alias jcu='jc --user'
alias jcu@='jc --user-unit'
alias l=lsd
alias la='l --almost-all'
alias lal='la --long'
alias lal/s='lal --sizesort'
alias lal/t='lal --timesort'
alias lal+='lal --total-size'
alias lal+/s='lal+ --sizesort'
alias lal+/t='lal+ --timesort'
alias ll='l --long'
alias ll/s='ll --sizesort'
alias ll/t='ll --timesort'
alias ll+='ll --total-size'
alias ll+/s='ll+ --sizesort'
alias ll+/t='ll+ --timesort'
alias lr='l --recursive'
alias lra='lr --almost-all'
alias lral='lra --long'
alias lral/s='lral --sizesort'
alias lral/t='lral --timesort'
alias lral+='lral --total-size'
alias lral+/s='lral+ --sizesort'
alias lral+/t='lral+ --timesort'
alias lrl='lr --long'
alias lrl/s='lrl --sizesort'
alias lrl/t='lrl --timesort'
alias lrl+='lrl --total-size'
alias lrl+/s='lrl+ --sizesort'
alias lrl+/t='lrl+ --timesort'
alias lsblk+='lsblk --output=NAME,VENDOR,MODEL,LABEL,FSSIZE,FSAVAIL,FSUSE%,MOUNTPOINTS'
alias lsblk++='lsblk --output=NAME,VENDOR,MODEL,PARTTYPENAME,PARTLABEL,FSTYPE,FSVER,LABEL,SIZE,FSSIZE,FSAVAIL,FSUSE%,MOUNTPOINTS'
alias lsblk+++='lsblk --output=NAME,VENDOR,MODEL,PARTTYPE,PARTTYPENAME,PARTUUID,PARTLABEL,FSTYPE,FSVER,UUID,LABEL,SIZE,FSSIZE,FSAVAIL,FSUSE%,MOUNTPOINTS'
[[ $TERM == linux ]] && alias lsd='lsd --icon=never'
alias lt='l --tree'
alias lta='lt --almost-all'
alias ltal='lta --long'
alias ltal+='ltal --total-size'
alias ltl='lt --long'
alias ltl+='ltl --total-size'
alias mkd='mkdir --parents'
alias p='print -r'
alias p0='print -rN'
alias paru='env-system paru'
alias paru-orphans='paru --query --unrequired --deps'
alias paru-orphans-remove='paru --remove --nosave --recursive $(paru-orphans)'
alias pc='whence -v'
alias pf=pprint-file
alias pf+='pf --show-all'
alias pfn=pprint-zfunc
alias pl='print -rl'
alias pp='typeset -p'
alias rehist='fc -RI'
alias rezsh='exec zsh --interactive --login'
alias rgman='rga /usr{,/local}/share/man --regexp'
alias rmd=rmdir
alias sgpt4='sgpt --model=gpt-4-turbo-preview'
alias sudo='sudo '
alias suv='sudo nvim'
alias suvup="sudo nvim -c 'AstroUpdate' && sudo nvim -c 'TSUpdate' -c 'lua require(\"astronvim.utils.updater\").update_packages()'"
alias ts=typeset
alias tsa='typeset -a'
alias tsaa='typeset -A'
alias v=nvim
alias visudo='sudo visudo'
alias vnvim="in-dir ${XDG_CONFIG_HOME:-~/.config}/nvim nvim -c 'lua require(\"resession\").load(vim.fn.getcwd(), { dir = \"dirsession\" })'"
alias vup="in-dir ~ nvim -c 'AstroUpdate' -c 'TSUpdate' -c 'Lazy'"
alias vzsh="in-dir $ZDOTDIR nvim -c 'lua require(\"resession\").load(vim.fn.getcwd(), { dir = \"dirsession\" })'"
alias zup='zsh-update'

alias -g -- --help='--help 2>&1 | bat --plain --language=help'
alias -g -- --help_='--help 2>&1 | bat --plain --language=help --paging=never'


## MISCELLANEA


[[ -d /run/media/$USER ]] && hash -d media=/run/media/$USER

if [[ -d $ZDOTDIR/zshrc.d ]]; then
  function {
    local zshrc
    for zshrc in $ZDOTDIR/zshrc.d/*; do
      [[ -r $zshrc ]] && source $zshrc
    done
  }
fi

# Load full prompt
function {
  local prompt_src
  case $TERM in
    (linux) prompt_src=$ZDOTDIR/p10k-plain.zsh ;;
    (*) prompt_src=$ZDOTDIR/p10k-fancy.zsh ;;
  esac
  [[ -r $prompt_src ]] && source $prompt_src
}

#(( $+commands[fastfetch] )) && fastfetch

dirs -c
