function {
  local total_kb total_mb
  case "$OSTYPE" in
    linux*)
      while IFS=" " read -r key value _; do
        [[ $key == "MemTotal:" ]] && { total_kb=$value; break; }
      done < /proc/meminfo
      total_mb=$(( total_kb / 1024 ))
      ;;
    darwin*)
      total_mb=$(( $(sysctl -n hw.memsize) / 1024 / 1024 ))
      ;;
  esac

  if (( total_mb <= 4096 )); then
    export NODE_OPTIONS="${NODE_OPTIONS:+$NODE_OPTIONS }--max-old-space-size=1536"
  elif (( total_mb <= 6144 )); then
    export NODE_OPTIONS="${NODE_OPTIONS:+$NODE_OPTIONS }--max-old-space-size=2048"
  fi
}
