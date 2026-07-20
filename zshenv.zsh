# secret-exec-environment-loader-v1
# Apply declarative environment.d assignments in file order so later entries
# can build on values established by earlier ones. Supported values contain
# literals, shell quoting and escaping, and $NAME, ${NAME}, ${NAME-word}, or
# ${NAME:-word} parameter expansion. Other shell syntax is rejected.
() {
  emulate -L zsh
  unsetopt xtrace verbose
  setopt extendedglob
  local __zshenv_fast_value_pattern='[-A-Za-z0-9_./,:+=%@${}]#'
  local __zshenv_saved_reject_definition=${functions[__zshenv_reject_definition]-}
  local __zshenv_saved_expand_value=${functions[__zshenv_expand_value]-}
  integer __zshenv_had_reject_definition=${+functions[__zshenv_reject_definition]}
  integer __zshenv_had_expand_value=${+functions[__zshenv_expand_value]}

  function __zshenv_reject_definition {
    print -ru2 -- "zshenv: ignored ${1}:${2}: ${3}"
  }

  function __zshenv_expand_value {
    local __zshenv_input=$1 __zshenv_output= __zshenv_char __zshenv_quote=none
    local __zshenv_next= __zshenv_body __zshenv_name __zshenv_operator
    local __zshenv_fallback __zshenv_current __zshenv_parameter_type
    local __zshenv_scan_quote __zshenv_suffix
    local __zshenv_remaining __zshenv_prefix
    integer __zshenv_i=1 __zshenv_j __zshenv_length=${#__zshenv_input}
    integer __zshenv_depth __zshenv_parameter_set

    # The managed public files overwhelmingly use unquoted path-like values.
    # Handle that strict subset without scanning every character, while the
    # full parser below owns quoted and escaped values.
    if [[ $__zshenv_input == ${~__zshenv_fast_value_pattern} ]]; then
      __zshenv_remaining=$__zshenv_input
      while [[ $__zshenv_remaining == *'$'* ]]; do
        __zshenv_prefix=${__zshenv_remaining%%\$*}
        [[ $__zshenv_prefix != *'{'* && $__zshenv_prefix != *'}'* ]] || return 1
        __zshenv_output+=$__zshenv_prefix
        __zshenv_remaining=$__zshenv_remaining[$(( ${#__zshenv_prefix} + 2 )),-1]
        [[ -n $__zshenv_remaining ]] || return 1
        __zshenv_body= __zshenv_name= __zshenv_operator= __zshenv_fallback=

        if [[ $__zshenv_remaining[1] == '{' ]]; then
          __zshenv_length=${#__zshenv_remaining}
          __zshenv_j=2
          __zshenv_depth=1
          while (( __zshenv_j <= __zshenv_length )); do
            __zshenv_char=$__zshenv_remaining[$__zshenv_j]
            if [[ $__zshenv_char == '$' && $__zshenv_remaining[$(( __zshenv_j + 1 ))] == '{' ]]; then
              (( __zshenv_depth++ ))
              (( __zshenv_j++ ))
            elif [[ $__zshenv_char == '}' ]]; then
              (( __zshenv_depth-- ))
              (( __zshenv_depth == 0 )) && break
            fi
            (( __zshenv_j++ ))
          done
          (( __zshenv_depth == 0 )) || return 1
          __zshenv_body=$__zshenv_remaining[2,$(( __zshenv_j - 1 ))]
          __zshenv_remaining=$__zshenv_remaining[$(( __zshenv_j + 1 )),-1]

          __zshenv_name=${__zshenv_body%%[^A-Za-z0-9_]*}
          [[ $__zshenv_name == [A-Za-z_][A-Za-z0-9_]# ]] || return 1
          __zshenv_suffix=$__zshenv_body[$(( ${#__zshenv_name} + 1 )),-1]
          if [[ $__zshenv_suffix == ':-'* ]]; then
            __zshenv_operator=:-
            __zshenv_fallback=$__zshenv_suffix[3,-1]
            __zshenv_expand_value $__zshenv_fallback || return 1
            __zshenv_fallback=$__zshenv_REPLY
          elif [[ $__zshenv_suffix == '-'* ]]; then
            __zshenv_operator=-
            __zshenv_fallback=$__zshenv_suffix[2,-1]
            __zshenv_expand_value $__zshenv_fallback || return 1
            __zshenv_fallback=$__zshenv_REPLY
          elif [[ -n $__zshenv_suffix ]]; then
            return 1
          fi
        else
          [[ $__zshenv_remaining[1] == [A-Za-z_] ]] || return 1
          __zshenv_name=${__zshenv_remaining%%[^A-Za-z0-9_]*}
          __zshenv_remaining=$__zshenv_remaining[$(( ${#__zshenv_name} + 1 )),-1]
        fi

        __zshenv_parameter_set=${+parameters[$__zshenv_name]}
        __zshenv_current=
        if (( __zshenv_parameter_set )); then
          __zshenv_parameter_type=${parameters[$__zshenv_name]}
          [[ $__zshenv_parameter_type != *array* && $__zshenv_parameter_type != *association* ]] || return 1
          __zshenv_current=${(P)__zshenv_name}
        fi

        if [[ $__zshenv_operator == ':-' ]] && (( ! __zshenv_parameter_set || ! ${#__zshenv_current} )); then
          __zshenv_output+=$__zshenv_fallback
        elif [[ $__zshenv_operator == '-' ]] && (( ! __zshenv_parameter_set )); then
          __zshenv_output+=$__zshenv_fallback
        else
          __zshenv_output+=$__zshenv_current
        fi
      done
      [[ $__zshenv_remaining != *'{'* && $__zshenv_remaining != *'}'* ]] || return 1
      __zshenv_REPLY=$__zshenv_output$__zshenv_remaining
      return 0
    fi

    while (( __zshenv_i <= __zshenv_length )); do
      __zshenv_char=$__zshenv_input[$__zshenv_i]

      if [[ $__zshenv_quote == single ]]; then
        if [[ $__zshenv_char == "'" ]]; then
          __zshenv_quote=none
        else
          __zshenv_output+=$__zshenv_char
        fi
        (( __zshenv_i++ ))
        continue
      fi

      if [[ $__zshenv_quote == double ]]; then
        if [[ $__zshenv_char == '"' ]]; then
          __zshenv_quote=none
          (( __zshenv_i++ ))
          continue
        fi
        if [[ $__zshenv_char == \\ ]]; then
          (( __zshenv_i < __zshenv_length )) || return 1
          __zshenv_next=$__zshenv_input[$(( __zshenv_i + 1 ))]
          if [[ $__zshenv_next == '$' || $__zshenv_next == '`' || $__zshenv_next == '"' || $__zshenv_next == \\ ]]; then
            __zshenv_output+=$__zshenv_next
            (( __zshenv_i += 2 ))
          else
            __zshenv_output+=$'\\'
            (( __zshenv_i++ ))
          fi
          continue
        fi
        [[ $__zshenv_char != '`' ]] || return 1
      else
        case $__zshenv_char in
          "'") __zshenv_quote=single; (( __zshenv_i++ )); continue ;;
          '"') __zshenv_quote=double; (( __zshenv_i++ )); continue ;;
          \\)
            (( __zshenv_i < __zshenv_length )) || return 1
            __zshenv_output+=$__zshenv_input[$(( __zshenv_i + 1 ))]
            (( __zshenv_i += 2 ))
            continue
            ;;
          [[:space:]]|'`'|';'|'|'|'&'|'<'|'>'|'('|')'|'{'|'}'|'['|']'|'*'|'?'|'~')
            return 1
            ;;
        esac
      fi

      if [[ $__zshenv_char != '$' ]]; then
        __zshenv_output+=$__zshenv_char
        (( __zshenv_i++ ))
        continue
      fi

      (( __zshenv_i < __zshenv_length )) || return 1
      __zshenv_next=$__zshenv_input[$(( __zshenv_i + 1 ))]
      __zshenv_body= __zshenv_name= __zshenv_operator= __zshenv_fallback=

      if [[ $__zshenv_next == '{' ]]; then
        __zshenv_j=$(( __zshenv_i + 2 ))
        __zshenv_depth=1
        __zshenv_scan_quote=none
        while (( __zshenv_j <= __zshenv_length )); do
          __zshenv_char=$__zshenv_input[$__zshenv_j]
          if [[ $__zshenv_scan_quote == single ]]; then
            [[ $__zshenv_char == "'" ]] && __zshenv_scan_quote=none
          elif [[ $__zshenv_scan_quote == double ]]; then
            if [[ $__zshenv_char == \\ ]]; then
              (( __zshenv_j++ ))
            elif [[ $__zshenv_char == '"' ]]; then
              __zshenv_scan_quote=none
            elif [[ $__zshenv_char == '$' && $__zshenv_input[$(( __zshenv_j + 1 ))] == '{' ]]; then
              (( __zshenv_depth++ ))
              (( __zshenv_j++ ))
            elif [[ $__zshenv_char == '}' && __zshenv_depth -gt 1 ]]; then
              (( __zshenv_depth-- ))
            fi
          else
            if [[ $__zshenv_char == "'" ]]; then
              __zshenv_scan_quote=single
            elif [[ $__zshenv_char == '"' ]]; then
              __zshenv_scan_quote=double
            elif [[ $__zshenv_char == \\ ]]; then
              (( __zshenv_j++ ))
            elif [[ $__zshenv_char == '$' && $__zshenv_input[$(( __zshenv_j + 1 ))] == '{' ]]; then
              (( __zshenv_depth++ ))
              (( __zshenv_j++ ))
            elif [[ $__zshenv_char == '}' ]]; then
              (( __zshenv_depth-- ))
              (( __zshenv_depth == 0 )) && break
            fi
          fi
          (( __zshenv_j++ ))
        done
        (( __zshenv_depth == 0 )) || return 1
        __zshenv_body=$__zshenv_input[$(( __zshenv_i + 2 )),$(( __zshenv_j - 1 ))]

        __zshenv_name=${__zshenv_body%%[^A-Za-z0-9_]*}
        [[ $__zshenv_name == [A-Za-z_][A-Za-z0-9_]# ]] || return 1
        __zshenv_suffix=$__zshenv_body[$(( ${#__zshenv_name} + 1 )),-1]
        if [[ $__zshenv_suffix == ':-'* ]]; then
          __zshenv_operator=:-
          __zshenv_fallback=$__zshenv_suffix[3,-1]
          __zshenv_expand_value $__zshenv_fallback || return 1
          __zshenv_fallback=$__zshenv_REPLY
        elif [[ $__zshenv_suffix == '-'* ]]; then
          __zshenv_operator=-
          __zshenv_fallback=$__zshenv_suffix[2,-1]
          __zshenv_expand_value $__zshenv_fallback || return 1
          __zshenv_fallback=$__zshenv_REPLY
        elif [[ -n $__zshenv_suffix ]]; then
          return 1
        fi
        __zshenv_i=$(( __zshenv_j + 1 ))
      elif [[ $__zshenv_next == [A-Za-z_] ]]; then
        __zshenv_j=$(( __zshenv_i + 1 ))
        while (( __zshenv_j <= __zshenv_length )) && [[ $__zshenv_input[$__zshenv_j] == [A-Za-z0-9_] ]]; do
          (( __zshenv_j++ ))
        done
        __zshenv_name=$__zshenv_input[$(( __zshenv_i + 1 )),$(( __zshenv_j - 1 ))]
        __zshenv_i=$__zshenv_j
      else
        return 1
      fi

      __zshenv_parameter_set=${+parameters[$__zshenv_name]}
      __zshenv_current=
      if (( __zshenv_parameter_set )); then
        __zshenv_parameter_type=${parameters[$__zshenv_name]}
        [[ $__zshenv_parameter_type != *array* && $__zshenv_parameter_type != *association* ]] || return 1
        __zshenv_current=${(P)__zshenv_name}
      fi

      if [[ $__zshenv_operator == ':-' ]] && (( ! __zshenv_parameter_set || ! ${#__zshenv_current} )); then
        __zshenv_output+=$__zshenv_fallback
      elif [[ $__zshenv_operator == '-' ]] && (( ! __zshenv_parameter_set )); then
        __zshenv_output+=$__zshenv_fallback
      else
        __zshenv_output+=$__zshenv_current
      fi
    done

    [[ $__zshenv_quote == none ]] || return 1
    __zshenv_REPLY=$__zshenv_output
  }

  local __zshenv_file __zshenv_definition __zshenv_name __zshenv_raw_value
  local __zshenv_parameter_type __zshenv_REPLY
  integer __zshenv_line_number
  for __zshenv_file in ${XDG_CONFIG_HOME:-~/.config}/environment.d/*(N-.r); do
    __zshenv_line_number=0
    while IFS= read -r __zshenv_definition || [[ -n $__zshenv_definition ]]; do
      (( __zshenv_line_number++ ))
      [[ $__zshenv_definition == *$'\r' ]] && __zshenv_definition=${__zshenv_definition%$'\r'}
      [[ -z $__zshenv_definition || $__zshenv_definition == '#'* ]] && continue

      if [[ $__zshenv_definition != [A-Za-z_][A-Za-z0-9_]#=* ]]; then
        __zshenv_reject_definition $__zshenv_file $__zshenv_line_number 'expected NAME=VALUE assignment'
        continue
      fi
      __zshenv_name=${__zshenv_definition%%=*}
      __zshenv_raw_value=${__zshenv_definition#*=}
      if ! __zshenv_expand_value $__zshenv_raw_value; then
        __zshenv_reject_definition $__zshenv_file $__zshenv_line_number 'unsupported or malformed value syntax'
        continue
      fi
      __zshenv_parameter_type=${parameters[$__zshenv_name]-}
      if [[ $__zshenv_parameter_type == *readonly* ]]; then
        __zshenv_reject_definition $__zshenv_file $__zshenv_line_number 'cannot replace a read-only parameter'
        continue
      fi
      if [[ -n $__zshenv_parameter_type && $__zshenv_parameter_type != scalar* ]]; then
        __zshenv_reject_definition $__zshenv_file $__zshenv_line_number 'cannot replace a non-scalar parameter'
        continue
      fi
      if ! export "$__zshenv_name=$__zshenv_REPLY"; then
        __zshenv_reject_definition $__zshenv_file $__zshenv_line_number 'could not export assignment'
      fi
    done <$__zshenv_file
  done

  if (( __zshenv_had_reject_definition )); then
    functions[__zshenv_reject_definition]=$__zshenv_saved_reject_definition
  else
    unfunction __zshenv_reject_definition
  fi
  if (( __zshenv_had_expand_value )); then
    functions[__zshenv_expand_value]=$__zshenv_saved_expand_value
  else
    unfunction __zshenv_expand_value
  fi
  return 0
}

ZDOTDIR=${XDG_CONFIG_HOME:-~/.config}/zsh

[[ -r ~/.local/bin/env ]] && source ~/.local/bin/env
[[ -r ~/.vite-plus/env ]] && source ~/.vite-plus/env
