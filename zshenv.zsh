# secret-exec-environment-loader-v1
# Apply declarative environment.d assignments in file order so later entries
# can build on values established by earlier ones. Supported values contain
# literals, shell quoting and escaping, and $NAME, ${NAME}, ${NAME-word}, or
# ${NAME:-word} parameter expansion. Other shell syntax is rejected.
() {
  emulate -L zsh
  unsetopt xtrace verbose
  setopt extendedglob
  local fast_value_pattern='[-A-Za-z0-9_./,:+=%@${}]#'
  local saved_reject_definition=${functions[__zshenv_reject_definition]-}
  local saved_expand_value=${functions[__zshenv_expand_value]-}
  integer had_reject_definition=${+functions[__zshenv_reject_definition]}
  integer had_expand_value=${+functions[__zshenv_expand_value]}

  function __zshenv_reject_definition {
    print -ru2 -- "zshenv: ignored ${1}:${2}: ${3}"
  }

  function __zshenv_expand_value {
    local input=$1 output= char quote=none next=
    local body name operator fallback current parameter_type scan_quote suffix
    local remaining prefix
    integer i=1 j length=${#input} depth parameter_set

    # The managed public files overwhelmingly use unquoted path-like values.
    # Handle that strict subset without scanning every character, while the
    # full parser below owns quoted and escaped values.
    if [[ $input == ${~fast_value_pattern} ]]; then
      remaining=$input
      while [[ $remaining == *'$'* ]]; do
        prefix=${remaining%%\$*}
        [[ $prefix != *'{'* && $prefix != *'}'* ]] || return 1
        output+=$prefix
        remaining=$remaining[$(( ${#prefix} + 2 )),-1]
        [[ -n $remaining ]] || return 1
        body= name= operator= fallback=

        if [[ $remaining[1] == '{' ]]; then
          length=${#remaining}
          j=2
          depth=1
          while (( j <= length )); do
            char=$remaining[$j]
            if [[ $char == '$' && $remaining[$(( j + 1 ))] == '{' ]]; then
              (( depth++ ))
              (( j++ ))
            elif [[ $char == '}' ]]; then
              (( depth-- ))
              (( depth == 0 )) && break
            fi
            (( j++ ))
          done
          (( depth == 0 )) || return 1
          body=$remaining[2,$(( j - 1 ))]
          remaining=$remaining[$(( j + 1 )),-1]

          name=${body%%[^A-Za-z0-9_]*}
          [[ $name == [A-Za-z_][A-Za-z0-9_]# ]] || return 1
          suffix=$body[$(( ${#name} + 1 )),-1]
          if [[ $suffix == ':-'* ]]; then
            operator=:-
            fallback=$suffix[3,-1]
            __zshenv_expand_value $fallback || return 1
            fallback=$REPLY
          elif [[ $suffix == '-'* ]]; then
            operator=-
            fallback=$suffix[2,-1]
            __zshenv_expand_value $fallback || return 1
            fallback=$REPLY
          elif [[ -n $suffix ]]; then
            return 1
          fi
        else
          [[ $remaining[1] == [A-Za-z_] ]] || return 1
          name=${remaining%%[^A-Za-z0-9_]*}
          remaining=$remaining[$(( ${#name} + 1 )),-1]
        fi

        parameter_set=${+parameters[$name]}
        current=
        if (( parameter_set )); then
          parameter_type=${parameters[$name]}
          [[ $parameter_type != *array* && $parameter_type != *association* ]] || return 1
          current=${(P)name}
        fi

        if [[ $operator == ':-' ]] && (( ! parameter_set || ! ${#current} )); then
          output+=$fallback
        elif [[ $operator == '-' ]] && (( ! parameter_set )); then
          output+=$fallback
        else
          output+=$current
        fi
      done
      [[ $remaining != *'{'* && $remaining != *'}'* ]] || return 1
      REPLY=$output$remaining
      return 0
    fi

    while (( i <= length )); do
      char=$input[$i]

      if [[ $quote == single ]]; then
        if [[ $char == "'" ]]; then
          quote=none
        else
          output+=$char
        fi
        (( i++ ))
        continue
      fi

      if [[ $quote == double ]]; then
        if [[ $char == '"' ]]; then
          quote=none
          (( i++ ))
          continue
        fi
        if [[ $char == \\ ]]; then
          (( i < length )) || return 1
          next=$input[$(( i + 1 ))]
          if [[ $next == '$' || $next == '`' || $next == '"' || $next == \\ ]]; then
            output+=$next
            (( i += 2 ))
          else
            output+=$'\\'
            (( i++ ))
          fi
          continue
        fi
        [[ $char != '`' ]] || return 1
      else
        case $char in
          "'") quote=single; (( i++ )); continue ;;
          '"') quote=double; (( i++ )); continue ;;
          \\)
            (( i < length )) || return 1
            output+=$input[$(( i + 1 ))]
            (( i += 2 ))
            continue
            ;;
          [[:space:]]|'`'|';'|'|'|'&'|'<'|'>'|'('|')'|'{'|'}'|'['|']'|'*'|'?'|'~')
            return 1
            ;;
        esac
      fi

      if [[ $char != '$' ]]; then
        output+=$char
        (( i++ ))
        continue
      fi

      (( i < length )) || return 1
      next=$input[$(( i + 1 ))]
      body= name= operator= fallback=

      if [[ $next == '{' ]]; then
        j=$(( i + 2 ))
        depth=1
        scan_quote=none
        while (( j <= length )); do
          char=$input[$j]
          if [[ $scan_quote == single ]]; then
            [[ $char == "'" ]] && scan_quote=none
          elif [[ $scan_quote == double ]]; then
            if [[ $char == \\ ]]; then
              (( j++ ))
            elif [[ $char == '"' ]]; then
              scan_quote=none
            elif [[ $char == '$' && $input[$(( j + 1 ))] == '{' ]]; then
              (( depth++ ))
              (( j++ ))
            elif [[ $char == '}' && depth -gt 1 ]]; then
              (( depth-- ))
            fi
          else
            if [[ $char == "'" ]]; then
              scan_quote=single
            elif [[ $char == '"' ]]; then
              scan_quote=double
            elif [[ $char == \\ ]]; then
              (( j++ ))
            elif [[ $char == '$' && $input[$(( j + 1 ))] == '{' ]]; then
              (( depth++ ))
              (( j++ ))
            elif [[ $char == '}' ]]; then
              (( depth-- ))
              (( depth == 0 )) && break
            fi
          fi
          (( j++ ))
        done
        (( depth == 0 )) || return 1
        body=$input[$(( i + 2 )),$(( j - 1 ))]

        name=${body%%[^A-Za-z0-9_]*}
        [[ $name == [A-Za-z_][A-Za-z0-9_]# ]] || return 1
        suffix=$body[$(( ${#name} + 1 )),-1]
        if [[ $suffix == ':-'* ]]; then
          operator=:-
          fallback=$suffix[3,-1]
          __zshenv_expand_value $fallback || return 1
          fallback=$REPLY
        elif [[ $suffix == '-'* ]]; then
          operator=-
          fallback=$suffix[2,-1]
          __zshenv_expand_value $fallback || return 1
          fallback=$REPLY
        elif [[ -n $suffix ]]; then
          return 1
        fi
        i=$(( j + 1 ))
      elif [[ $next == [A-Za-z_] ]]; then
        j=$(( i + 1 ))
        while (( j <= length )) && [[ $input[$j] == [A-Za-z0-9_] ]]; do
          (( j++ ))
        done
        name=$input[$(( i + 1 )),$(( j - 1 ))]
        i=$j
      else
        return 1
      fi

      parameter_set=${+parameters[$name]}
      current=
      if (( parameter_set )); then
        parameter_type=${parameters[$name]}
        [[ $parameter_type != *array* && $parameter_type != *association* ]] || return 1
        current=${(P)name}
      fi

      if [[ $operator == ':-' ]] && (( ! parameter_set || ! ${#current} )); then
        output+=$fallback
      elif [[ $operator == '-' ]] && (( ! parameter_set )); then
        output+=$fallback
      else
        output+=$current
      fi
    done

    [[ $quote == none ]] || return 1
    REPLY=$output
  }

  local file definition name raw_value parameter_type REPLY
  integer line_number
  for file in ${XDG_CONFIG_HOME:-~/.config}/environment.d/*(N-.r); do
    line_number=0
    while IFS= read -r definition || [[ -n $definition ]]; do
      (( line_number++ ))
      [[ $definition == *$'\r' ]] && definition=${definition%$'\r'}
      [[ -z $definition || $definition == '#'* ]] && continue

      if [[ $definition != [A-Za-z_][A-Za-z0-9_]#=* ]]; then
        __zshenv_reject_definition $file $line_number 'expected NAME=VALUE assignment'
        continue
      fi
      name=${definition%%=*}
      raw_value=${definition#*=}
      if ! __zshenv_expand_value $raw_value; then
        __zshenv_reject_definition $file $line_number 'unsupported or malformed value syntax'
        continue
      fi
      parameter_type=${parameters[$name]-}
      if [[ $parameter_type == *readonly* ]]; then
        __zshenv_reject_definition $file $line_number 'cannot replace a read-only parameter'
        continue
      fi
      if ! export "$name=$REPLY"; then
        __zshenv_reject_definition $file $line_number 'could not export assignment'
      fi
    done <$file
  done

  if (( had_reject_definition )); then
    functions[__zshenv_reject_definition]=$saved_reject_definition
  else
    unfunction __zshenv_reject_definition
  fi
  if (( had_expand_value )); then
    functions[__zshenv_expand_value]=$saved_expand_value
  else
    unfunction __zshenv_expand_value
  fi
  return 0
}

ZDOTDIR=${XDG_CONFIG_HOME:-~/.config}/zsh

[[ -r ~/.local/bin/env ]] && source ~/.local/bin/env
[[ -r ~/.vite-plus/env ]] && source ~/.vite-plus/env
