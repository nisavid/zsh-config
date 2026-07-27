# Zsh runtime configuration


## COMMAND PATHS

zmodload zsh/parameter

if [[ -r $ZDOTDIR/startup.zsh ]]; then
  source $ZDOTDIR/startup.zsh zshrc-pre "$OSTYPE" ||
    print -ru2 -- "zsh startup: portable environment policy failed before interactive setup"
else
  print -ru2 -- "zsh startup: required policy is missing: $ZDOTDIR/startup.zsh"
fi

[[ -z ${BIN_HOME:-} || -d $BIN_HOME ]] || mkdir -p -- "$BIN_HOME"
[[ -z ${APPIMAGE_HOME:-} || -d $APPIMAGE_HOME ]] || mkdir -p -- "$APPIMAGE_HOME"

# TODO: move to lazy init
if (( $+commands[rgrc] )); then eval "$(rgrc --aliases)"
elif [[ -r /etc/grc.zsh ]]; then source /etc/grc.zsh
fi

if (( $+commands[kubecolor] )); then
  alias kubectl=kubecolor
fi

[[ -r ~/.config/broot/launcher/bash/br ]] && source ~/.config/broot/launcher/bash/br

: ${WARP_COMPAT:-0}
[[ $TERM_PROGRAM == Warp* || ($TERM_PROGRAM == tmux && $TMUX == *warp*) ]] && WARP_COMPAT=1
export WARP_COMPAT

# Load Instant Prompt
POWERLEVEL9K_INSTANT_PROMPT=verbose
function {
  (( WARP_COMPAT )) && return

  readonly instant_prompt_src=${XDG_CACHE_HOME:-~/.cache}/p10k-instant-prompt-nisavid.zsh
  [[ -r $instant_prompt_src ]] && source $instant_prompt_src
}

# NOTE: From this point until “Load full prompt” near the end of this file,
# nothing should print any output.

# Fully rebuild the command hash table so that `$commands`
# is accurate and complete
hash -rf


## ENVIRONMENT VARIABLES


print -v PPNAME /proc/$PPID/exe(N:P:t)
TMPPREFIX=${XDG_RUNTIME_DIR:-/tmp}/zsh

(( $+commands[bat] )) && export PAGER=bat

(( $+commands[lesspipe.sh] )) && export LESSOPEN='| lesspipe.sh %s'
(( $+commands[src-hilite-lesspipe.sh] )) && export LESSOPEN='| src-hilite-lesspipe.sh %s'

readonly LESS_VERSION=${${"$(less --version 2>/dev/null)"#less }%% *}
readonly -A LESS_OPTS_BY_VERSION=(
  8   '--quiet'
  26  '--LONG-PROMPT'
  37  '--tabs=4'
  76  '--ignore-case'
  103 '--LINE-NUMBERS'
  136 '--RAW-CONTROL-CHARS'
  179 '--window=-4'
  214 '--quit-if-one-screen'
  356 '--status-column'
  436 '--tilde'
  531 '--nohistdups'
  540 '--mouse'
  542 '--wheel-lines=3'
  574 '--incsearch'
  576 '--use-color'
  601 '--exit-follow-on-close'
  620 '--modelines=5'
  621 '--wordwrap'
  622 '--show-preproc-errors'
)

# Filter the given `less` options down to the options that are compatible
# with the current `less` version.
function _less_opts_compat {
  emulate -L zsh

  local -a desired_opts filtered_opts
  desired_opts=( "${(@)argv}" )

  local version
  for version in ${(on)${(k)less_opts_by_version}}; do
    (( version > LESS_VERSION )) && break
    for opt in ${(z)less_opts_by_version[$v]}; do
      (( ${wanted[(I)$opt]} )) || continue
      filtered_opts+=( "$opt" )
    done
  done

  print -r -- "${(j< >)filtered_opts}"
}

function {
  local -a less_opts=(
    --exit-follow-on-close
    --incsearch
    --ignore-case
    --LINE-NUMBERS
    --LONG-PROMPT
    --modelines=5
    --mouse
    --nohistdups
    --quiet
    --quit-if-one-screen
    --RAW-CONTROL-CHARS
    --show-preproc-errors
    --status-column
    --tabs=4
    --tilde
    --use-color
    --wheel-lines=3
    --window=-4
    --wordwrap
  )
  export LESS=$(_less_opts_compat "${less_opts[@]}")
}

function {
  local -a bat_less_opts=(
    --quit-if-one-screen
    --ignore-case
    --LONG-PROMPT
    --LINE-NUMBERS
    --quiet
    --RAW-CONTROL-CHARS
    --tilde
    --window=-4
    --incsearch
    --mouse
    --nohistdups
    --show-preproc-errors
    --status-column
    --use-color
    --wheel-lines=3
    --wordwrap
  )
  export BAT_PAGER="less $(_less_opts_compat "${bat_less_opts[@]}")"
}

export GROFF_NO_SGR=1

#(( $+commands[bat] )) && export MANPAGER="sh -c 'col --no-backspaces --spaces | bat --language man --plain'"
(( $+commands[nvim] )) && export MANPAGER='nvim +Man!'
export MANROFFOPT='-c'
export MANWIDTH=$COLUMNS

#export BROWSER=firefox

(( $+commands[nvim] )) && export EDITOR=nvim
export SYSTEMD_EDITOR=$EDITOR

export FZF_BASE=/usr/share/fzf
[[ $COLORTERM == *(24bit|truecolor)* ]] \
  && export FZF_DEFAULT_OPTS=" \
    --color=bg+:#313244,bg:#1e1e2e,spinner:#f5e0dc,hl:#f38ba8 \
    --color=fg:#cdd6f4,header:#f38ba8,info:#cba6f7,pointer:#f5e0dc \
    --color=marker:#f5e0dc,fg+:#cdd6f4,prompt:#cba6f7,hl+:#f38ba8"

function {
  readonly glamour_style=${XDG_CONFIG_HOME:-~/.config}/glamour/catppuccin-mocha.json
  [[ -r $glamour_style ]] && export GLAMOUR_STYLE=$glamour_style
}


if [[ ! -v SSH_CONNECTION ]] && (( $+commands[ssh-tpm-agent] )); then
  export SSH_AUTH_SOCK=$(ssh-tpm-agent --print-socket)
fi
if [[ -d ~/.gnupg ]] && (( $+commands[gpg-connect-agent] )); then
  export GPG_TTY=/dev/${(%):-%l}
  gpg-connect-agent UPDATESTARTUPTTY /bye >/dev/null
  if [[ ! -v SSH_CONNECTION && -z $SSH_AUTH_SOCK ]]; then
    export SSH_AUTH_SOCK=${XDG_RUNTIME_DIR:-/tmp}/gnupg/S.gpg-agent.ssh
  fi
fi
if [[ ! -v SSH_CONNECTION && -z $SSH_AUTH_SOCK ]] && (( $+commands[ssh-agent] )); then
  readonly ssh_agent_env=${XDG_RUNTIME_DIR:-/tmp}/ssh-agent.$UID.env
  if [[ -e $ssh_agent_env ]]; then
    source $ssh_agent_env &>/dev/null
    if ! kill -0 $SSH_AGENT_PID; then
      unset SSH_AGENT_PID SSH_AUTH_SOCK
    fi
  fi
  if [[ -z $SSH_AUTH_SOCK ]]; then
    ssh-agent -s >! $ssh_agent_env
    source $ssh_agent_env &>/dev/null
  fi
fi

function {
  readonly lazygit_config_dir=${XDG_CONFIG_HOME:-~/.config}/lazygit
  readonly lazygit_config=$lg_config_dir/config.yml
  readonly lazygit_theme_config=$lg_config_dir/catppuccin-mocha-sapphire.yml
  [[ -r $lazygit_config && -r $lazygit_theme_config ]] \
    && export LG_CONFIG_FILE=$lazygit_theme_config,$lg_config_dir/config.yml
}

[[ $COLORTERM == *(24bit|truecolor)* ]] \
  && export MICRO_TRUECOLOR=1


## TERMINAL


zmodload zsh/terminfo

function {
  local -a inherited_terminfo_dirs terminfo_dirs
  local -A terminfo_seen
  local terminfo_dir
  if [[ -n ${TERMINFO_DIRS:-} ]]; then
    inherited_terminfo_dirs=( "${(@s.:.)TERMINFO_DIRS}" )
    for terminfo_dir in "${inherited_terminfo_dirs[@]}"; do
      if [[ -z ${terminfo_seen[x$terminfo_dir]-} ]]; then
        terminfo_dirs+=( "$terminfo_dir" )
        terminfo_seen[x$terminfo_dir]=1
      fi
    done
  fi
  for terminfo_dir in /etc/terminfo /lib/terminfo /usr/share/terminfo; do
    if [[ -d $terminfo_dir && -z ${terminfo_seen[x$terminfo_dir]-} ]]; then
      terminfo_dirs+=( $terminfo_dir )
      terminfo_seen[x$terminfo_dir]=1
    fi
  done
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
if [[ ! -r $ZI[BIN_DIR]/zi.zsh ]]; then
  function {
    emulate -L zsh

    if (( ! $+commands[git] )); then
      print -ru2 -- "Unable to install Zi: git is not available in PATH."
      return 1
    fi

    if ! command mkdir -p -- "$ZI[HOME_DIR]"; then
      print -ru2 -- "Unable to install Zi: cannot create ${(q-)ZI[HOME_DIR]}."
      return 1
    fi

    local install_dir
    install_dir=$(command mktemp -d "$ZI[HOME_DIR]/install.XXXXXX") || {
      print -ru2 -- "Unable to install Zi: cannot create a temporary directory in ${(q-)ZI[HOME_DIR]}."
      return 1
    }

    {
      print -ru2 -- "Zi is missing; installing it in ${(q-)ZI[BIN_DIR]}."
      command git clone --depth=1 --branch=main https://github.com/z-shell/zi.git "$install_dir/bin" || {
        print -ru2 -- "Unable to install Zi: git clone failed."
        return 1
      }
      if [[ ! -r $install_dir/bin/zi.zsh ]]; then
        print -ru2 -- "Unable to install Zi: the downloaded repository does not contain zi.zsh."
        return 1
      fi

      if [[ -e $ZI[BIN_DIR] || -h $ZI[BIN_DIR] ]] \
        && ! command mv -- "$ZI[BIN_DIR]" "$install_dir/incomplete-bin"; then
        print -ru2 -- "Unable to install Zi: cannot replace the incomplete installation at ${(q-)ZI[BIN_DIR]}."
        return 1
      fi
      if ! command mv -- "$install_dir/bin" "$ZI[BIN_DIR]"; then
        [[ -e $install_dir/incomplete-bin || -h $install_dir/incomplete-bin ]] \
          && command mv -- "$install_dir/incomplete-bin" "$ZI[BIN_DIR]"
        print -ru2 -- "Unable to install Zi: cannot activate the downloaded repository."
        return 1
      fi
    } always {
      command rm -rf -- "$install_dir"
    }
  }
fi

integer ZI_READY=0
if [[ -r $ZI[BIN_DIR]/zi.zsh ]]; then
  if source $ZI[BIN_DIR]/zi.zsh && (( $+functions[zi] )); then
    ZI_READY=1
  else
    (( ! $+functions[zi] )) || unfunction zi
    print -ru2 -- \
      "Zi is installed but failed to load from ${(q-)ZI[BIN_DIR]}/zi.zsh."
  fi
else
  print -ru2 -- "Zi is unavailable; shell plugins and the configured prompt will not be loaded."
fi

ZI_LIGHT=1
if (( ZI_READY )); then
  ## ZI | ZSH
  function {
    local -a system_completions=( /usr/share/zsh/functions/Completion/*/_*(N.) )
    if (( #system_completions )); then
      zi wait:'1' pack atload=+'zicompinit_fast; zicdreplay' for system-completions
    else
      zi wait:'1' lucid \
        id-as:'completion-init' \
        as:'null' \
        atload:'zicompinit_fast; zicdreplay' \
        for z-shell/0
    fi
  }
  zi wait:'2' lucid ${ZI_LIGHT:+light-mode} \
    id-as:'adguard-completion' \
    if:'[[ -s /opt/adguard-cli/bash-completion.sh ]]' \
    as:'null' \
    atload:'autoload -Uz bashcompinit; bashcompinit; source /opt/adguard-cli/bash-completion.sh' \
    for z-shell/0
  if (( WARP_COMPAT )); then
    # With the syntax highlighting (original or fast) or autosuggestion plugins, Warp renders the prompt decorations af
    zi ${ZI_LIGHT:+light-mode} for zsh-users/zsh-completions
    zi ${ZI_LIGHT:+light-mode} for z-shell/z-a-bin-gem-node
  else
    zi ${ZI_LIGHT:+light-mode} for z-shell/z-a-meta-plugins @annexes
    # XXX: z-shell/zsh-fancy-completions (included by @zsh-users+fast) tries
    #   to run `ypcat` (nonexistent command) when populating hosts lists
    #   for e.g. `ssh` completion, which triggers `find-the-command` and breaks
    #   the completion.  Not sure how to fix this properly.  For now, create
    #   this symlink as a workaround.
    (( $+commands[ypcat] )) || ln -s =false $BIN_HOME/ypcat
    zi ${ZI_LIGHT:+light-mode} for @zsh-users+fast
    zi ${ZI_LIGHT:+light-mode} for @romkatv
  fi
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
    atclone:'() { readonly destdir=${XDG_CONFIG_HOME:-~/.config}/f-sy-h; mkdir -p "$destdir" && cp -f themes/catppuccin-mocha.ini "$destdir/"; }' \
    atpull:'%atclone' \
    atload:'fast-theme --quiet CONFIG:catppuccin-mocha' \
    for catppuccin/zsh-fsh
  function {
    local -a args=(
      id-as:'vivid-lscolors'
      atclone:'print export LS_COLORS="${(qq)$(vivid generate catppuccin-mocha)}" >lscolors.zsh'
      atpull:'%atclone'
      run-atpull
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
    atpull:'rm -f init.zsh' \
    run-atpull \
    atinit:'local cache=${ZI[PLUGINS_DIR]}/manpath/init.zsh; [[ -r $cache && "$(<$cache)" == "export -aT MANPATH "* ]] || print -n -- export -aT MANPATH manpath=\( ${(s<:>q-)"$(manpath)"} \) >|$cache' \
    pick:'init.zsh' \
    for z-shell/0

  ## ZI | LANGUAGES & TOOLKITS

  # Elm
  zi wait lucid ${ZI_LIGHT:+light-mode} atload:'elm-completion-update 2>/dev/null' for kraklin/elm.plugin.zsh

  function {
    local repair_path='} always {
      if [[ -r $ZDOTDIR/startup.zsh ]]; then
        source $ZDOTDIR/startup.zsh zshrc-final "$OSTYPE"
        __zshrc_repair_status=$?
        (( __zshrc_repair_status == 0 )) ||
          print -ru2 -- "zsh startup: portable environment policy failed after deferred $__zshrc_feature setup"
      else
        __zshrc_repair_status=1
        print -ru2 -- "zsh startup: required policy is missing after deferred $__zshrc_feature setup: $ZDOTDIR/startup.zsh"
      fi'
    local fnm_init='function { emulate -L zsh; {
      local __zshrc_environment __zshrc_feature=fnm __zshrc_line
      local __zshrc_assignment __zshrc_name __zshrc_raw_value __zshrc_value
      local __zshrc_chpwd_type __zshrc_expected_hook __zshrc_hook_body
      local __zshrc_hook_declaration
      local __zshrc_parameter_type
      local __zshrc_path_prefix __zshrc_path_type __zshrc_PATH_type
      local -a __zshrc_lines __zshrc_old_chpwd __zshrc_old_path
      local -a __zshrc_required_names __zshrc_warn_functions __zshrc_words
      local -A __zshrc_exports __zshrc_old_types __zshrc_old_values
      integer __zshrc_apply_status __zshrc_chpwd_existed
      integer __zshrc_conflict __zshrc_feature_status __zshrc_repair_status
      integer __zshrc_hook_existed __zshrc_invalid
      integer __zshrc_saw_path
      __zshrc_required_names=(
        FNM_MULTISHELL_PATH
        FNM_VERSION_FILE_STRATEGY
        FNM_DIR
        FNM_LOGLEVEL
        FNM_NODE_DIST_MIRROR
        FNM_COREPACK_ENABLED
        FNM_RESOLVE_ENGINES
        FNM_ARCH
      )
      __zshrc_expected_hook=$(
        function __zshrc_expected_fnm_autoload_hook {
          if [[ -f .node-version || -f .nvmrc || -f package.json ]]; then
            fnm use --silent-if-unchanged
          fi
        }
        print -rn -- $functions[__zshrc_expected_fnm_autoload_hook]
      )
      __zshrc_environment=$(fnm env --shell zsh)
      __zshrc_feature_status=$?
      if (( __zshrc_feature_status )); then
        print -ru2 -- "fnm is available but failed to generate shell environment output (status $__zshrc_feature_status)."
      elif [[ -z $__zshrc_environment ]]; then
        __zshrc_feature_status=1
        print -ru2 -- "fnm produced no shell environment output."
      else
        __zshrc_lines=( ${(f)__zshrc_environment} )
        for __zshrc_line in $__zshrc_lines; do
          [[ $__zshrc_line == rehash ]] && continue
          __zshrc_words=( ${(z)__zshrc_line} )
          if (( $#__zshrc_words != 2 )) || [[ $__zshrc_words[1] != export ]]; then
            __zshrc_invalid=1
            break
          fi
          __zshrc_assignment=$__zshrc_words[2]
          __zshrc_name=${__zshrc_assignment%%=*}
          __zshrc_raw_value=${__zshrc_assignment#*=}
          [[ $__zshrc_assignment == *=* ]] || {
            __zshrc_invalid=1
            break
          }
          __zshrc_value=${(Q)__zshrc_raw_value}
          if [[ $__zshrc_name == PATH ]]; then
            if (( __zshrc_saw_path )) || [[ $__zshrc_value != *":\$PATH" ]]; then
              __zshrc_invalid=1
              break
            fi
            __zshrc_saw_path=1
            __zshrc_path_prefix=${__zshrc_value%:\$PATH}
            continue
          fi
          case $__zshrc_name in
            (FNM_MULTISHELL_PATH|FNM_VERSION_FILE_STRATEGY|FNM_DIR|FNM_LOGLEVEL|FNM_NODE_DIST_MIRROR|FNM_COREPACK_ENABLED|FNM_RESOLVE_ENGINES|FNM_ARCH) ;;
            (*)
              __zshrc_invalid=1
              break
              ;;
          esac
          (( ! ${+__zshrc_exports[$__zshrc_name]} )) || {
            __zshrc_invalid=1
            break
          }
          __zshrc_exports[$__zshrc_name]=$__zshrc_value
        done
        for __zshrc_name in $__zshrc_required_names; do
          [[ -n ${__zshrc_exports[$__zshrc_name]-} ]] || {
            __zshrc_invalid=1
            break
          }
        done
        if (( ! __zshrc_invalid )); then
          [[ ${__zshrc_exports[FNM_MULTISHELL_PATH]} == /* &&
            $__zshrc_path_prefix == ${__zshrc_exports[FNM_MULTISHELL_PATH]}/bin ]] ||
            __zshrc_invalid=1
        fi
        if (( ! __zshrc_invalid )); then
          for __zshrc_name in $__zshrc_required_names; do
            __zshrc_parameter_type=${parameters[$__zshrc_name]-}
            [[ -z $__zshrc_parameter_type ||
              $__zshrc_parameter_type == scalar ||
              $__zshrc_parameter_type == scalar-export ]] || {
              __zshrc_conflict=1
              break
            }
            __zshrc_old_types[$__zshrc_name]=$__zshrc_parameter_type
            __zshrc_old_values[$__zshrc_name]=${(P)__zshrc_name}
          done
          __zshrc_path_type=${parameters[path]-}
          __zshrc_PATH_type=${parameters[PATH]-}
          __zshrc_chpwd_type=${parameters[chpwd_functions]-}
          [[ $__zshrc_path_type == *array* &&
            $__zshrc_path_type == *tied* &&
            $__zshrc_path_type != *readonly* &&
            $__zshrc_PATH_type == *scalar* &&
            $__zshrc_PATH_type == *tied* &&
            $__zshrc_PATH_type != *readonly* &&
            ( -z $__zshrc_chpwd_type || $__zshrc_chpwd_type == array ) ]] ||
            __zshrc_conflict=1
          if (( ${+dis_functions[_fnm_autoload_hook]} )); then
            __zshrc_conflict=1
          elif (( ${+functions[_fnm_autoload_hook]} )); then
            __zshrc_hook_body=$functions[_fnm_autoload_hook]
            __zshrc_hook_declaration=$(builtin typeset -fp _fnm_autoload_hook)
            __zshrc_warn_functions=( ${(f)"$(builtin functions +W)"} )
            [[ $__zshrc_hook_body == $__zshrc_expected_hook &&
              $__zshrc_hook_declaration != *"# traced"* ]] &&
              (( ! ${__zshrc_warn_functions[(I)_fnm_autoload_hook]} )) ||
              __zshrc_conflict=1
          fi
        fi
        if (( __zshrc_invalid || ! __zshrc_saw_path )); then
          __zshrc_feature_status=1
          print -ru2 -- "fnm generated unsupported shell environment output."
        elif (( __zshrc_conflict )); then
          __zshrc_feature_status=1
          print -ru2 -- "fnm generated shell environment output that conflicts with existing shell parameter state."
        else
          __zshrc_old_path=( $path )
          __zshrc_chpwd_existed=${+chpwd_functions}
          (( __zshrc_chpwd_existed )) &&
            __zshrc_old_chpwd=( $chpwd_functions )
          __zshrc_hook_existed=${+functions[_fnm_autoload_hook]}

          autoload -Uz add-zsh-hook
          add-zsh-hook -h >/dev/null 2>&1 ||
            __zshrc_apply_status=$?
          if (( ! __zshrc_apply_status && ! __zshrc_hook_existed )); then
            function _fnm_autoload_hook {
              if [[ -f .node-version || -f .nvmrc || -f package.json ]]; then
                fnm use --silent-if-unchanged
              fi
            }
          fi
          if (( ! __zshrc_apply_status )); then
            add-zsh-hook -D chpwd _fnm_autoload_hook ||
              __zshrc_apply_status=$?
          fi
          if (( ! __zshrc_apply_status )); then
            add-zsh-hook chpwd _fnm_autoload_hook ||
              __zshrc_apply_status=$?
          fi
          if (( ! __zshrc_apply_status &&
            ! ${chpwd_functions[(I)_fnm_autoload_hook]} )); then
            __zshrc_apply_status=1
          fi
          for __zshrc_name in $__zshrc_required_names; do
            (( __zshrc_apply_status )) && break
            export "$__zshrc_name=${__zshrc_exports[$__zshrc_name]}"
            __zshrc_apply_status=$?
          done
          if (( ! __zshrc_apply_status )); then
            if [[ -n ${__zshrc_old_types[FNM_MULTISHELL_PATH]} &&
              -n ${__zshrc_old_values[FNM_MULTISHELL_PATH]} ]]; then
              path=( ${path:#${__zshrc_old_values[FNM_MULTISHELL_PATH]}/bin} )
            fi
            path=( $__zshrc_path_prefix $path )
            __zshrc_apply_status=$?
          fi
          if (( __zshrc_apply_status )); then
            path=( $__zshrc_old_path )
            if (( __zshrc_chpwd_existed )); then
              chpwd_functions=( $__zshrc_old_chpwd )
            else
              unset chpwd_functions
            fi
            (( __zshrc_hook_existed )) ||
              unset "functions[_fnm_autoload_hook]"
            for __zshrc_name in $__zshrc_required_names; do
              if [[ -z ${__zshrc_old_types[$__zshrc_name]} ]]; then
                unset "$__zshrc_name"
              else
                typeset -g "$__zshrc_name=${__zshrc_old_values[$__zshrc_name]}"
                if [[ ${__zshrc_old_types[$__zshrc_name]} == scalar-export ]]; then
                  export "$__zshrc_name"
                else
                  typeset +gx "$__zshrc_name"
                fi
              fi
            done
            __zshrc_feature_status=1
            print -ru2 -- "fnm generated shell environment output that could not be applied safely."
          fi
          rehash
        fi
      fi'
    local vite_init='function { emulate -L zsh; {
      local __zshrc_feature="Vite+"
      integer __zshrc_feature_status __zshrc_repair_status
      source ~/.vite-plus/env
      __zshrc_feature_status=$?
      (( __zshrc_feature_status == 0 )) ||
        print -ru2 -- "Vite+ is installed but failed to load from ~/.vite-plus/env (status $__zshrc_feature_status)."'
    local finish_action='} }'

    # Node (fnm)
    # Zi's ordinary deferred atload does not publish task status; explicit
    # diagnostics and the final PATH repair are the observable failure contract.
    zi wait lucid ${ZI_LIGHT:+light-mode} \
      id-as:'fnm' \
      if:'[[ ! -r ~/.vite-plus/env ]]' \
      has:'fnm' \
      as:'null' \
      atload:"$fnm_init $repair_path $finish_action" \
      for z-shell/0

    # Vite+ — wait'2' so it loads after compinit (wait'1') and its vp/vpr
    # completions register; the snippet also defines the vp() wrapper.
    zi wait'2' lucid ${ZI_LIGHT:+light-mode} \
      id-as:'vite-plus' \
      if:'[[ -r ~/.vite-plus/env ]]' \
      as:'null' \
      atload:"$vite_init $repair_path $finish_action" \
      for z-shell/0
  }

  # KDE
  function {
    readonly compdir=$KDE_SRC/kdesrc-build/completions/zsh
    if [[ -d $compdir ]]; then
      zi wait lucid ${ZI_LIGHT:+light-mode} \
        id-as:'kde-buildtools-completions' \
        atclone:"
          rm -rf completions
          cp -a ${(q-)compdir} completions
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
    atpull:'rm -f init.zsh' \
    run-atpull \
    atinit:'local cache=${ZI[PLUGINS_DIR]}/nvim-qt-runtime-path/init.zsh; [[ -r $cache ]] || print -n -- export NVIM_QT_RUNTIME_PATH=${(q-)${${(M)${(f)"$(nvim-qt --version)"}:#[[:blank:]]#runtime:[[:blank:]]##*}#[[:blank:]]#runtime:[[:blank:]]##}:P} >|$cache' \
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
    if [[ ! -e $script ]]; then
      mkdir -p -- $script:h
      if python -c 'import fancycompleter' &>/dev/null \
        && python -m fancycompleter install --force &>/dev/null \
        && [[ -e ~/python_startup.py ]]; then
        mv ~/python_startup.py $script
      else
        print -r -- '# fancycompleter is not available; this PYTHONSTARTUP file is intentionally empty.' >$script
      fi
    fi
    export PYTHONSTARTUP=$script
  }

  ## ZI | MISCELLANEA

  # Locally generated completions
  function {
    readonly -A shtab_cmds_modules=(
      pipdeptree pipdeptree._cli.build_parser
    )
    readonly tabtab=${XDG_CONFIG_HOME:-~/.config}/tabtab/zsh/__tabtab.zsh
    (( $+commands[shtab] )) \
      || zi wait lucid ${ZI_LIGHT:+light-mode} id-as:'shtab' pip:'shtab' nocompile for iterative/shtab
    zi wait lucid ${ZI_LIGHT:+light-mode} \
      id-as:'localgen-completions' \
      atclone:'
        rm -rf completions && mkdir completions
        (( $+commands[bun] )) && [[ -r ~/.bun/_bun ]] && cp ~/.bun/_bun completions/_bun
        (( $+commands[cog] )) && cog generate-completions zsh >completions/_cog.zsh
        (( $+commands[openclaw] )) && openclaw completion --shell=zsh >completions/_openclaw.zsh
        (( $+commands[pip] )) && pip completion --zsh >completions/_pip.zsh
        (( $+commands[pipx] )) && register-python-argcomplete pipx >completions/_pipx.zsh
        (( $+commands[pipenv] )) && _PIPENV_COMPLETE=zsh_source pipenv >completions/_pipenv.zsh
        if (( $+commands[pnpm] )); then
          [[ -e ~/.zshrc ]] && cp --archive --force ~/.zshrc{,.zi-bak}
          pnpm install-completion zsh >/dev/null
          if [[ -e ~/.zshrc.zi-bak ]]; then mv --force ~/.zshrc{.zi-bak,}; else rm -f ~/.zshrc; fi
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
        [[ -f $tabtab ]] || { mkdir -p -- $tabtab:h && touch $tabtab }" \
      atpull:'%atclone' run-atpull \
      multisrc:"init.zsh $tabtab" \
      for z-shell/0
  }

  # Locally generated startup scripts
  zi wait lucid ${ZI_LIGHT:+light-mode} \
    id-as:'localgen-zshrc' \
    atclone:'
      rm -rf scripts && mkdir scripts
      if (( $+commands[gh] )) && gh copilot --version &>/dev/null; then
        {
          gh copilot -- alias -- zsh 2>/dev/null ||
            gh copilot alias -- zsh 2>/dev/null
        } >scripts/gh-copilot-aliases.zsh || rm -f scripts/gh-copilot-aliases.zsh
      fi
      cp 0.plugin.zsh init.zsh'"
      print 'integer ret; for script in \${0:h}/scripts/*\(N); do source \$script; ret=\$\(( ret + ? )); done; \(( ! ret ))' >>init.zsh" \
    atpull:'%atclone' run-atpull \
    src:'init.zsh' \
    for z-shell/0
else
  autoload -Uz compinit
  compinit
  if [[ -s /opt/adguard-cli/bash-completion.sh ]]; then
    autoload -Uz bashcompinit
    bashcompinit
    source /opt/adguard-cli/bash-completion.sh
  fi
  if [[ -r ~/.vite-plus/env ]]; then
    source ~/.vite-plus/env ||
      print -ru2 -- "Vite+ is installed but failed to load from ~/.vite-plus/env."
  fi
fi
unset ZI_READY


## BUILT-IN SETTINGS


## BUILT-IN SETTINGS | SHELL OPTIONS


# Changing Directories
setopt auto_cd auto_pushd cdable_vars cd_silent pushd_ignore_dups pushd_silent
# Completion
setopt always_to_end complete_in_word glob_complete no_list_beep
# Expansion and Globbing
setopt bad_pattern brace_ccl case_paths extended_glob glob_star_short hist_subst_pattern magic_equal_subst numeric_glob_sort
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
case $OSTYPE in
  darwin*) ZSH_STATE_HOME=~/Library/Application\ Support/zsh ;;
  *) ZSH_STATE_HOME=${XDG_STATE_HOME:-~/.local/state}/zsh ;;
esac
[[ -d $ZSH_STATE_HOME ]] || mkdir -p -- "$ZSH_STATE_HOME"
HISTFILE=$ZSH_STATE_HOME/history
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
zmodload zsh/regex
zmodload -F zsh/stat b:zstat

autoload -Uz add-zsh-hook
autoload -Uz bracketed-paste-magic
autoload -Uz catch
autoload -Uz regexp-replace
alias run-help >/dev/null && unalias run-help
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

#function workspace-update-path {
#  local newpaths=( ${(A):-(../)#package.json(N-.:h)} )
#  newpaths=( ${^newpaths}/node_modules/.bin(N-/) )
#  path=( $newpaths ${path:#*/node_modules/.bin} )
#}
#add-zsh-hook chpwd workspace-update-path
#workspace-update-path

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

#if (( $+commands[pass] )); then
#  function export-secret-from-pass {
#    readonly var=$1 name=$2
#    export $var=$(pass $name)
#  }
#
#  function wrap-with-secret-from-pass {
#    readonly cmd=$1 var=$2 name=$3
#    eval "
#    function $cmd {
#      local -i use_pass=0
#      [[ -v $var ]] || use_pass=1
#      (( use_pass )) && export-secret-from-pass $var $name
#      command $cmd \"\$@\"
#      (( use_pass )) && unset $var
#    }"
#  }
#
#  wrap-with-secret-from-pass nano-pdf GEMINI_API_KEY api/gemini/GEMINI_API_KEY
#  wrap-with-secret-from-pass openclaw JINA_API_KEY api/jina/JINA_API_KEY
#fi

#if (( $+commands[kwallet-query] )); then
#  function export-secret-from-kwallet {
#    readonly var=$1 folder=$2 entry=$3
#    export $var=$(kwallet-query kdewallet -f $folder -r $entry 2>/dev/null)
#  }
#
#  function wrap-with-secret-from-kwallet {
#    readonly cmd=$1 var=$2 folder=$3 entry=$4
#    eval "
#    function $cmd {
#      local -i use_kwallet=0
#      [[ -v $var ]] || use_kwallet=1
#      (( use_kwallet )) && export-secret-from-kwallet $var $folder $entry
#      command $cmd \"\$@\"
#      (( use_kwallet )) && unset $var
#    }"
#  }
#
#  wrap-with-secret-from-kwallet parcel FIREBASE_API_KEY firebase-api api_key
#  wrap-with-secret-from-kwallet pnpm FIREBASE_API_KEY firebase-api api_key
#  (( $+commands[sgpt] )) && wrap-with-secret-from-kwallet sgpt OPENAI_API_KEY openai-api api_key
#fi

#if (( $+commands[bw] )); then
#  function bw {
#    if [[ -z $BW_CLIENTID ]] && (( $+commands[kwallet-query] )); then
#      export BW_CLIENTID=$(kwallet-query kdewallet -f bitwarden-api -r client_id 2>/dev/null)
#      export BW_CLIENTSECRET=$(kwallet-query kdewallet -f bitwarden-api -r client_secret 2>/dev/null)
#    fi
#    if [[ -n $BW_CLIENTID && -z $BW_SESSION ]] && (( $+commands[kwallet-query] )); then
#      export BW_SESSION=$(command bw unlock $(kwallet-query kdewallet -f bitwarden-api -r password 2>/dev/null) --raw)
#    fi
#    command bw "$@"
#  }
#fi

function caller-name {
  print -r -- ${${funcstack[3,-1]}[(r)^\(*\)]}
}

function diff-fancy {
  diff --unified "$@" | diff-so-fancy
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

typeset -A ext_mimetype=(
  md text/markdown
  markdown text/markdown
  mdown text/markdown
  markdn text/markdown
  mkd text/markdown
)

function {
  readonly -a files=( /etc/mime.types ~/.mime.types )
  local -a readable_files=( ${^files}(N-.) )
  (( #readable_files )) || return
  readonly token_pat='[^][:cntrl:][:space:]()<>@,;:\\"/?=[]##'
  # XXX: This is extracted to a constant and weirdly quoted/escaped merely to appease Neovim's deficient parsing of Zsh extended globs
  readonly pat="(#b)(${~token_pat}/${~token_pat}"')(([[:space:]]##'"${~token_pat}"')##)'
  local line mimetype ext
  local -a exts
  <${^readable_files} while read -r line; do
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

function ghcs-gh {
  gh copilot suggest --target=gh -- "$@"
}

function ghcs-git {
  gh copilot suggest --target=git -- "$@"
}

function ghcs-shell {
  gh copilot suggest --target=shell -- "$@"
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
  mkdir -p -- $args[2,-1] "$1" && cd "$1"
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

function img2webp-drawing-lossless {
  local -a files_in files_out

  while (( $# )); do
    [[ -e $1 ]] || { print -Pr -- "%F{red}%Berror:%b file not found:%f ${(q-)1}" >&2; return 1 }

    files_in+=( $1 )
    files_out+=( ${1:r}.webp )

    shift
  done

  for (( i = 1; i <= $#files_in; i++ )); do
    cwebp -preset drawing -lossless -q 100 -progress $files_in[i] -o $files_out[i]
  done
}

function img2webp-drawing-nearlossless {
  local -a files_in files_out

  while (( $# )); do
    [[ -e $1 ]] || { print -Pr -- "%F{red}%Berror:%b file not found:%f ${(q-)1}" >&2; return 1 }

    files_in+=( $1 )
    files_out+=( ${1:r}.webp )

    shift
  done

  for (( i = 1; i <= $#files_in; i++ )); do
    cwebp -preset drawing -near_lossless 60 -progress $files_in[i] -o $files_out[i]
  done
}

function img2webp-drawing-q95 {
  local -a files_in files_out

  while (( $# )); do
    [[ -e $1 ]] || { print -Pr -- "%F{red}%Berror:%b file not found:%f ${(q-)1}" >&2; return 1 }

    files_in+=( $1 )
    files_out+=( ${1:r}.webp )

    shift
  done

  for (( i = 1; i <= $#files_in; i++ )); do
    cwebp -preset drawing -q 95 -sharp_yuv -af -sns 100 -mt -progress $files_in[i] -o $files_out[i]
  done
}
function pty-readall {
  emulate -L zsh

  zmodload zsh/zpty || return

  local name=pty-readall-$$-$RANDOM buf
  integer idle=0
  zpty -b $name "${(@q)argv}" || return
  {
    while (( idle < 40 )); do
      if zpty -r $name buf; then
        if [[ $buf == *$'\e]11;?\e\\'* ]]; then
          zpty -w -n $name $'\e]11;rgb:1e1e/1e1e/2e2e\e\\'
          buf=${buf//$'\e]11;?\e\\'/}
        fi
        if [[ $buf == *$'\e[6n'* ]]; then
          zpty -w -n $name $'\e[1;1R'
          buf=${buf//$'\e[6n'/}
        fi
        print -rn -- $buf
        idle=0
      elif zpty -t $name; then
        sleep 0.05
        (( idle++ ))
      else
        while zpty -r $name buf; do
          print -rn -- $buf
        done
        break
      fi
    done
  } always {
    zpty -d $name &>/dev/null
  }
}

function pprint-file {
  local -a opts files
  while (( $# )); do
    case $1 in
      (-*) opts+=( $1 ) ;;
      (*) files+=( $1 )
    esac
    shift
  done

  local -a out_files bat_opts=( --decorations=always --color=always )
  local file mimetype tmpdir tmpfile
  for file in $files; do
    mimetype=$(file-mimetype $file)
    case $mimetype in
      (text/markdown)
        [[ -d $tmpdir ]] || { tmpdir=$(mktempd) || return; trap 'rm -rf $tmpdir' EXIT }
        tmpfile=$tmpdir/${file#/}
        mkdir -p -- $tmpfile:h
        { pty-readall command glow --style=$GLAMOUR_STYLE $file || command glow --style=$GLAMOUR_STYLE $file } | tr -d '\r' >! $tmpfile
        out_files+=( $tmpfile )
        if (( $#files == 1 )); then
          bat_opts+=( --file-name=$file --language=txt )
        fi
        ;;
      (*) out_files+=( $file )
    esac
  done

  command bat $bat_opts $opts -- ${(q-)out_files}
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
  sgpt --model=gpt-4-turbo --shell "$*"
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
  emulate -L zsh
  setopt extended_glob

  [[ -d $ZDOTDIR_ORIGIN ]] || return
  [[ -d $ZDOTDIR:h ]] || mkdir -p -- $ZDOTDIR:h || return
  [[ -e $ZDOTDIR && ! -w $ZDOTDIR ]] && { print -r "error: not writable:" ${(q-)ZDOTDIR}; return }

  local -a local_profiles
  if [[ -d $ZDOTDIR/profile.d ]]; then
    if (( ! $+commands[git] )) ||
      ! command git -C "$ZDOTDIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
      print -ru2 -- \
        "Unable to update Zsh config: cannot classify local profiles in ${(q-)ZDOTDIR}."
      return 1
    fi
    local local_profile relative_profile
    for local_profile in $ZDOTDIR/profile.d/*(N); do
      relative_profile=profile.d/$local_profile:t
      if command git -C "$ZDOTDIR" ls-files --error-unmatch -- \
        "$relative_profile" >/dev/null 2>&1 &&
        command git -C "$ZDOTDIR" diff --quiet -- "$relative_profile" &&
        command git -C "$ZDOTDIR" diff --cached --quiet -- "$relative_profile"; then
        continue
      fi
      local_profiles+=( $local_profile )
    done
  fi

  readonly tmp=$(command mktemp -d "$ZDOTDIR.XXXXXX") || return
  trap 'rm -rf $tmp' EXIT
  cp -a -- $ZDOTDIR_ORIGIN/. $tmp || return
  if (( $#local_profiles )); then
    mkdir -p -- $tmp/profile.d || return
    cp -a -- $local_profiles $tmp/profile.d/ || return
  fi
  local legacy_profile legacy_name legacy_destination stale_destination
  local existing_migration
  local -a existing_migrations stale_migrations
  if [[ -d $ZDOTDIR/zshrc.d ]]; then
    integer legacy_suffix legacy_already_migrated
    mkdir -p -- $tmp/profile.d || return
    for legacy_profile in $ZDOTDIR/zshrc.d/*.local.zsh(N-.r); do
      legacy_name=${${legacy_profile:t}%.local.zsh}
      if [[ -e $tmp/profile.d/$legacy_name.zshenv ||
        -h $tmp/profile.d/$legacy_name.zshenv ||
        -e $tmp/profile.d/$legacy_name.zshrc ||
        -h $tmp/profile.d/$legacy_name.zshrc ]]; then
        touch -- $tmp/profile.d/$legacy_name.enabled || return
      fi
      legacy_destination=$tmp/profile.d/$legacy_name.legacy.local.zshrc
      legacy_suffix=1
      legacy_already_migrated=0
      while [[ -e $legacy_destination || -h $legacy_destination ]]; do
        if [[ ! -h $legacy_destination && -f $legacy_destination ]]; then
          if (( ! $+commands[cmp] )); then
            print -ru2 -- \
              "Unable to update Zsh config: cmp is required to classify ${(q-)legacy_destination}."
            return 1
          fi
          if command cmp -s -- $legacy_profile $legacy_destination; then
            legacy_already_migrated=1
          fi
          break
        fi
        (( legacy_suffix++ ))
        legacy_destination=$tmp/profile.d/$legacy_name.legacy-$legacy_suffix.local.zshrc
      done
      (( legacy_already_migrated )) ||
        cp -a -- $legacy_profile $legacy_destination || return
      stale_migrations=(
        $tmp/profile.d/$legacy_name.legacy.local.zshrc(N)
        $tmp/profile.d/$legacy_name.legacy-<->.local.zshrc(N)
      )
      for stale_destination in $stale_migrations; do
        [[ $stale_destination == "$legacy_destination" ||
          -h $stale_destination ]] && continue
        rm -f -- $stale_destination || return
      done
      rm -f -- $tmp/zshrc.d/$legacy_profile:t || return
    done
  fi
  if [[ -d $tmp/zshrc.d ]]; then
    for legacy_profile in $tmp/zshrc.d/*.local.zsh(N-.r); do
      legacy_name=${${legacy_profile:t}%.local.zsh}
      existing_migrations=()
      for existing_migration in \
        $tmp/profile.d/$legacy_name.legacy.local.zshrc(N-.r) \
        $tmp/profile.d/$legacy_name.legacy-<->.local.zshrc(N-.r); do
        [[ -h $existing_migration ]] ||
          existing_migrations+=( $existing_migration )
      done
      (( $#existing_migrations )) || continue
      rm -f -- $legacy_profile || return
    done
  fi
  rm -rf $ZDOTDIR || return
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
alias '??'=ghcs-shell
alias '??gh'=ghcs-gh
alias '??git'=ghcs-git
alias '???'=sgpts
alias '????'=sgpt4s
alias bat-help='bat --plain --language=help'
alias brewup='brew update && brew upgrade'
alias cat='bat --paging=never'
alias cdnvim="cd ${(q-)XDG_CONFIG_HOME:-~/.config}/nvim"
alias cdzsh="cd ${(q-)ZDOTDIR}"
alias clamdscan='clamdscan --multiscan --fdpass'
alias firewall-cmd='sudo firewall-cmd'
alias d=diff-fancy
alias g=git
alias gearlever='flatpak run it.mijorus.gearlever'
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
alias k=kubectl
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
alias mkd='mkdir -p --'
alias p='print -r'
alias p0='print -rN'
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
alias vdiff=vimdiff
alias visudo='sudo visudo'
alias vnvim="in-dir ${(q-)XDG_CONFIG_HOME:-~/.config}/nvim nvim -c 'lua require(\"resession\").load(vim.fn.getcwd(), { dir = \"dirsession\" })'"
alias vup="in-dir ~ nvim -c 'AstroUpdate' -c 'TSUpdate' -c 'Lazy'"
#alias vzsh="in-dir ${(q-)ZDOTDIR} nvim -c 'lua require(\"resession\").load(vim.fn.getcwd(), { dir = \"dirsession\" })'"
alias vzsh='v -p ~/.config/zsh/{zshrc.zsh,profile.d/*}'
alias zup='zsh-update'

#alias -g -- --help='--help 2>&1 | bat --plain --language=help'
#alias -g -- --help_='--help 2>&1 | bat --plain --language=help --style=plain --paging=never'


## MISCELLANEA


[[ -d /run/media/$USER ]] && hash -d media=/run/media/$USER

if [[ -r $ZDOTDIR/profiles.zsh ]]; then
  source $ZDOTDIR/profiles.zsh zshrc ||
    print -ru2 -- "zsh startup: optional interactive profiles failed in .zshrc"
else
  print -ru2 -- "zsh startup: required profile dispatcher is missing: $ZDOTDIR/profiles.zsh"
fi

if [[ -r $ZDOTDIR/startup.zsh ]]; then
  source $ZDOTDIR/startup.zsh zshrc-final "$OSTYPE" ||
    print -ru2 -- "zsh startup: portable environment policy failed after interactive setup"
else
  print -ru2 -- "zsh startup: required policy is missing: $ZDOTDIR/startup.zsh"
fi

# Load full prompt
function {
  (( WARP_COMPAT )) && return

  local prompt_src
  case $TERM in
    (linux) prompt_src=$ZDOTDIR/p10k-plain.zsh ;;
    (*) prompt_src=$ZDOTDIR/p10k-fancy.zsh ;;
  esac
  [[ -r $prompt_src ]] && source $prompt_src
}

#(( $+commands[fastfetch] )) && fastfetch

dirs -c
