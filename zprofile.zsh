function {
  local shim_dir=~/.local/lib/secret-exec/bin
  [[ -d $shim_dir ]] || return
  path=( $shim_dir ${path:#$shim_dir} )
  rehash
}
