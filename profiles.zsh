# Load optional host/profile fragments in a phase-safe order.
function {
  emulate -L zsh
  setopt extended_glob

  local phase=${1:-}
  [[ $phase == (zshenv|zshrc) ]] || {
    print -ru2 -- "zsh startup: invalid optional-profile phase: $phase"
    return 0
  }

  local profile_dir=$ZDOTDIR/profile.d
  local legacy_dir=$ZDOTDIR/zshrc.d
  local profile profile_stem profile_name

  if [[ $phase == zshenv ]]; then
    for profile in $profile_dir/*.zshenv(N-.r); do
      profile_stem=${profile%.zshenv}
      profile_name=${profile_stem:t}
      [[ ! -e $profile_stem.disabled ||
        -e $profile_stem.enabled ||
        -e $legacy_dir/$profile_name.local.zsh ]] || continue
      if ! source $profile; then
        print -ru2 -- \
          "zsh startup: optional zshenv profile failed: $profile"
      fi
    done
    return 0
  fi

  local -a regular_profiles local_profiles migration_profiles modern_profiles
  local -a legacy_profiles legacy_sources migrated_profiles
  for profile in $profile_dir/*.zshrc(N-.r); do
    [[ $profile == *.local.zshrc ]] && continue
    profile_stem=${profile%.zshrc}
    profile_name=${profile_stem:t}
    [[ ! -e $profile_stem.disabled ||
      -e $profile_stem.enabled ||
      -e $legacy_dir/$profile_name.local.zsh ]] || continue
    regular_profiles+=( $profile )
  done
  for profile in $profile_dir/*.local.zshrc(N-.r); do
    [[ -h $profile ]] && continue
    if [[ ${profile:t} == *.legacy(|-<->).local.zshrc ]]; then
      migration_profiles+=( $profile )
    else
      local_profiles+=( $profile )
    fi
  done
  modern_profiles=( $regular_profiles $migration_profiles $local_profiles )
  legacy_profiles=( $legacy_dir/*.local.zsh(N-.r) )

  local legacy_profile legacy_name legacy_source legacy_numbered_prefix
  local -a legacy_stat profile_stat
  integer legacy_source_slot profile_slot profiles_equal
  for legacy_profile in $legacy_profiles; do
    legacy_name=${${legacy_profile:t}%.local.zsh}
    legacy_source=$legacy_profile
    legacy_source_slot=0
    legacy_numbered_prefix=$profile_dir/$legacy_name.legacy-
    for profile in $modern_profiles; do
      if [[ $profile == "$profile_dir/$legacy_name.legacy.local.zshrc" ||
        $profile == "$legacy_numbered_prefix"<->.local.zshrc ]]; then
        if [[ $profile == "$profile_dir/$legacy_name.legacy.local.zshrc" ]]; then
          profile_slot=1
        else
          profile_slot=${${${profile:t}#$legacy_name.legacy-}%.local.zshrc}
        fi
        if (( ! legacy_source_slot || profile_slot < legacy_source_slot )); then
          [[ $legacy_source == $legacy_profile || legacy_source_slot ]] &&
          legacy_source=$profile
          legacy_source_slot=$profile_slot
        fi
        migrated_profiles+=( $profile )
      elif [[ $profile == "$profile_dir/$legacy_name.zshrc" ||
        $profile == "$profile_dir/$legacy_name.local.zshrc" ]]; then
        profiles_equal=0
        if (( $+commands[cmp] )); then
          command cmp -s -- $legacy_profile $profile &&
            profiles_equal=1
        elif zmodload -F zsh/stat b:zstat 2>/dev/null; then
          legacy_stat=()
          profile_stat=()
          if zstat -A legacy_stat +size -- $legacy_profile &&
            zstat -A profile_stat +size -- $profile &&
            [[ $legacy_stat[1] == $profile_stat[1] &&
              "$(<$legacy_profile)" == "$(<$profile)" ]]; then
            profiles_equal=1
          fi
        fi
        if (( profiles_equal )); then
          [[ $legacy_source != $legacy_profile ]] ||
            legacy_source=$profile
          migrated_profiles+=( $profile )
        fi
      fi
    done
    legacy_sources+=( $legacy_source )
  done

  local migrated_profile
  integer is_migrated
  for profile in $migration_profiles; do
    is_migrated=0
    for migrated_profile in $migrated_profiles; do
      [[ $profile == "$migrated_profile" ]] &&
        { is_migrated=1; break; }
    done
    (( is_migrated )) || legacy_sources+=( $profile )
  done

  for profile in $regular_profiles; do
    is_migrated=0
    for migrated_profile in $migrated_profiles; do
      [[ $profile == "$migrated_profile" ]] &&
        { is_migrated=1; break; }
    done
    (( is_migrated )) && continue
    if ! source $profile; then
      print -ru2 -- "zsh startup: optional zshrc profile failed: $profile"
    fi
  done

  for legacy_source in $legacy_sources; do
    if ! source $legacy_source; then
      print -ru2 -- \
        "zsh startup: optional legacy-compatible interactive profile failed: $legacy_source"
    fi
  done

  for profile in $local_profiles; do
    is_migrated=0
    for migrated_profile in $migrated_profiles; do
      [[ $profile == "$migrated_profile" ]] &&
        { is_migrated=1; break; }
    done
    (( is_migrated )) && continue
    if ! source $profile; then
      print -ru2 -- \
        "zsh startup: optional local zshrc profile failed: $profile"
    fi
  done
  return 0
} "$@"
