function {
  integer total_mb=0
  case $OSTYPE in
    (linux*)
      local key value
      while IFS=" " read -r key value _; do
        if [[ $key == "MemTotal:" ]]; then
          total_mb=$(( value / 1024 ))
          break
        fi
      done </proc/meminfo
      ;;
    (darwin*)
      if (( $+commands[sysctl] )); then
        total_mb=$(( $(sysctl -n hw.memsize) / 1024 / 1024 ))
      fi
      ;;
  esac
  (( total_mb > 0 )) || return 0

  integer max_old_space_size=0
  if (( total_mb <= 4096 )); then
    max_old_space_size=1536
  elif (( total_mb <= 6144 )); then
    max_old_space_size=2048
  else
    return 0
  fi

  local -a node_options=( ${(z)${NODE_OPTIONS:-}} )
  node_options=( ${node_options:#--max-old-space-size=*} )
  node_options+=( --max-old-space-size=$max_old_space_size )
  export NODE_OPTIONS=${(j: :)node_options}
}
