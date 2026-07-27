# Portable environment and ordered path policy for every Zsh startup phase.
#
# Source with a phase name and an optional OSTYPE-compatible platform string:
#
#   source "$ZDOTDIR/startup.zsh" zshenv "$OSTYPE"
#
# The launcher phase emits the same core path policy without the developer
# toolchain. Deployment adapters can source it in an isolated Zsh process and
# print PATH for a platform-specific launcher.
function {
  emulate -L zsh
  setopt extended_glob

  local phase=${1:-unknown}
  local platform=${2:-$OSTYPE}
  integer is_interactive=0
  [[ -o interactive ]] && is_interactive=1

  typeset -g BIN_HOME=${BIN_HOME:-$HOME/.local/bin}
  typeset -g APPIMAGE_HOME=${APPIMAGE_HOME:-$BIN_HOME/appimage}
  typeset -gx KREW_ROOT=${KREW_ROOT:-${XDG_DATA_HOME:-$HOME/.local/share}/krew}
  typeset -gx KDE_SRC=${KDE_SRC:-$HOME/src/kde}
  typeset -gx VP_HOME=${VP_HOME:-$HOME/.vite-plus}
  if [[ -z ${PNPM_HOME:-} ]]; then
    case $platform in
      (darwin*) typeset -gx PNPM_HOME=$HOME/Library/pnpm ;;
      (*) typeset -gx PNPM_HOME=${XDG_DATA_HOME:-$HOME/.local/share}/pnpm ;;
    esac
  else
    typeset -gx PNPM_HOME
  fi

  local homebrew_prefix=${HOMEBREW_PREFIX:-}
  if [[ -z $homebrew_prefix ]]; then
    case $platform in
      (darwin*)
        if [[ -d /opt/homebrew ]]; then
          homebrew_prefix=/opt/homebrew
        elif [[ -d /usr/local/Homebrew ]]; then
          homebrew_prefix=/usr/local
        fi
        ;;
      (linux*)
        [[ ! -d /home/linuxbrew/.linuxbrew ]] ||
          homebrew_prefix=/home/linuxbrew/.linuxbrew
        ;;
    esac
  fi
  [[ -z $homebrew_prefix ]] || typeset -gx HOMEBREW_PREFIX=$homebrew_prefix

  local -a candidate_specs managed_paths new_path original_path
  candidate_specs=(
    core optional $HOME/.local/lib/secret-exec/bin
    developer optional $HOME/.lmstudio/bin
    developer optional $KDE_SRC/kdesrc-build
    developer optional $KREW_ROOT/bin
    core optional $HOME/.orbstack/bin
    developer optional $VP_HOME/bin
    developer optional $HOME/.bun/bin
    developer optional $PNPM_HOME/bin
    developer optional $HOME/.cargo/bin
    developer optional ${GOBIN:-$HOME/go/bin}
    developer reserved "$APPIMAGE_HOME"
    developer optional ${XDG_DATA_HOME:-$HOME/.local/share}/zi/polaris/sbin
    developer optional ${XDG_DATA_HOME:-$HOME/.local/share}/zi/polaris/bin
    developer optional ${PYENV_ROOT:-${XDG_DATA_HOME:-$HOME/.local/share}/pyenv}/bin
    core reserved "$BIN_HOME"
    core optional /opt/podman/bin
    developer optional "${homebrew_prefix:+$homebrew_prefix/opt/rustup/bin}"
    core optional "${homebrew_prefix:+$homebrew_prefix/bin}"
    core optional "${homebrew_prefix:+$homebrew_prefix/sbin}"
  )

  local -A managed_seen
  local candidate presence scope
  integer candidate_index
  for (( candidate_index = 1; candidate_index <= $#candidate_specs; candidate_index += 3 )); do
    scope=$candidate_specs[$candidate_index]
    presence=$candidate_specs[$(( candidate_index + 1 ))]
    candidate=$candidate_specs[$(( candidate_index + 2 ))]
    [[ -n $candidate ]] || continue
    [[ $presence == reserved || -d $candidate ]] || continue
    [[ $phase != launcher || $scope == core ]] || continue
    if [[ -n ${managed_seen[$candidate]-} ]]; then
      (( is_interactive )) &&
        print -ru2 -- "zsh startup: duplicate managed PATH entry: $candidate"
      continue
    fi
    managed_seen[$candidate]=1
    managed_paths+=( $candidate )
  done

  local -A output_seen managed_input_count
  for candidate in $managed_paths; do
    output_seen[$candidate]=1
    new_path+=( $candidate )
  done

  local inherited_entry
  integer managed_path_count
  for inherited_entry in "${path[@]}"; do
    if [[ -z $inherited_entry ]]; then
      (( is_interactive )) &&
        print -ru2 -- 'zsh startup: removed unsafe empty PATH entry'
      continue
    fi
    if [[ -n ${managed_seen[$inherited_entry]-} ]]; then
      managed_path_count=${managed_input_count[$inherited_entry]:-0}
      (( ++managed_path_count ))
      managed_input_count[$inherited_entry]=$managed_path_count
      if (( is_interactive && managed_path_count > 1 )); then
        print -ru2 -- "zsh startup: removed exact duplicate PATH entry: $inherited_entry"
      fi
      continue
    fi
    if [[ -n ${output_seen[$inherited_entry]-} ]]; then
      (( is_interactive )) &&
        print -ru2 -- "zsh startup: removed exact duplicate PATH entry: $inherited_entry"
      continue
    fi
    output_seen[$inherited_entry]=1
    new_path+=( $inherited_entry )
  done

  if (( is_interactive )); then
    local -A canonical_entries
    local canonical_entry prior_entry
    for inherited_entry in "${new_path[@]}"; do
      [[ -d $inherited_entry ]] || continue
      canonical_entry=${inherited_entry:A}
      prior_entry=${canonical_entries[$canonical_entry]-}
      if [[ -n $prior_entry && $prior_entry != $inherited_entry ]]; then
        print -ru2 -- \
          "zsh startup: canonically equivalent PATH entries: $prior_entry and $inherited_entry"
      else
        canonical_entries[$canonical_entry]=$inherited_entry
      fi
    done
  fi

  original_path=( "${path[@]}" )
  integer path_changed=$(( $#original_path != $#new_path ))
  if (( ! path_changed )); then
    for (( candidate_index = 1; candidate_index <= $#new_path; candidate_index++ )); do
      [[ $original_path[$candidate_index] == $new_path[$candidate_index] ]] ||
        { path_changed=1; break; }
    done
  fi
  path=( $new_path )
  (( ! path_changed )) || rehash

  local list_name list_value list_entry list_key canonical_list_entry prior_list_entry
  local -a list_entries unique_list_entries
  local -A list_seen canonical_list_entries
  for list_name in MANPATH INFOPATH TERMINFO_DIRS PERL5LIB XDG_DATA_DIRS; do
    (( ${+parameters[$list_name]} )) || continue
    [[ ${parameters[$list_name]} == *scalar* ]] || continue
    list_value=${(P)list_name}
    list_entries=( "${(@s.:.)list_value}" )
    unique_list_entries=()
    list_seen=()
    canonical_list_entries=()
    for list_entry in "${list_entries[@]}"; do
      list_key=v:$list_entry
      if [[ -n ${list_seen[$list_key]-} ]]; then
        (( is_interactive )) &&
          print -ru2 -- \
            "zsh startup: removed exact duplicate $list_name entry: ${list_entry:-<default>}"
        continue
      fi
      list_seen[$list_key]=1
      unique_list_entries+=( "$list_entry" )
      (( is_interactive )) || continue
      [[ -n $list_entry && -d $list_entry ]] || continue
      canonical_list_entry=${list_entry:A}
      prior_list_entry=${canonical_list_entries[$canonical_list_entry]-}
      if [[ -n $prior_list_entry && $prior_list_entry != $list_entry ]]; then
        print -ru2 -- \
          "zsh startup: canonically equivalent $list_name entries: $prior_list_entry and $list_entry"
      else
        canonical_list_entries[$canonical_list_entry]=$list_entry
      fi
    done
    typeset -gx "$list_name=${(j.:.)unique_list_entries}"
  done

  [[ $phase == zshrc-* ]] || return 0

  local orb_completions=$HOME/.orbstack/shell/completions/zsh
  local -a managed_fpath new_fpath
  [[ -d $orb_completions ]] && managed_fpath+=( $orb_completions )

  local -A fpath_seen managed_fpath_seen managed_fpath_input_count
  integer managed_fpath_count
  for candidate in $managed_fpath; do
    fpath_seen[$candidate]=1
    managed_fpath_seen[$candidate]=1
    new_fpath+=( $candidate )
  done
  for inherited_entry in "${fpath[@]}"; do
    if [[ -z $inherited_entry ]]; then
      (( is_interactive )) &&
        print -ru2 -- 'zsh startup: removed unsafe empty fpath entry'
      continue
    fi
    if [[ -n ${fpath_seen[$inherited_entry]-} ]]; then
      if [[ -n ${managed_fpath_seen[$inherited_entry]-} ]]; then
        managed_fpath_count=${managed_fpath_input_count[$inherited_entry]:-0}
        (( ++managed_fpath_count ))
        managed_fpath_input_count[$inherited_entry]=$managed_fpath_count
      fi
      if (( is_interactive )) &&
        { [[ -z ${managed_fpath_seen[$inherited_entry]-} ]] ||
          (( managed_fpath_count > 1 )); }; then
        print -ru2 -- "zsh startup: removed exact duplicate fpath entry: $inherited_entry"
      fi
      continue
    fi
    fpath_seen[$inherited_entry]=1
    new_fpath+=( $inherited_entry )
  done

  if (( is_interactive )); then
    canonical_list_entries=()
    for inherited_entry in "${new_fpath[@]}"; do
      [[ -d $inherited_entry ]] || continue
      canonical_list_entry=${inherited_entry:A}
      prior_list_entry=${canonical_list_entries[$canonical_list_entry]-}
      if [[ -n $prior_list_entry && $prior_list_entry != $inherited_entry ]]; then
        print -ru2 -- \
          "zsh startup: canonically equivalent fpath entries: $prior_list_entry and $inherited_entry"
      else
        canonical_list_entries[$canonical_list_entry]=$inherited_entry
      fi
    done
  fi
  fpath=( $new_fpath )
} "$@"
