#!/usr/bin/env -S zsh -f

emulate -L zsh
setopt errexit nounset pipefail

readonly repo_root=${0:A:h:h}
tmpdir=$(mktemp -d)
readonly tmpdir
trap 'rm -rf -- $tmpdir' EXIT

function fail {
  print -ru2 -- "profile-phases test failed: $1"
  return 1
}

ZDOTDIR=$tmpdir/zsh
mkdir -p -- $ZDOTDIR/profile.d

print -rl -- \
  'typeset -gx PROFILE_ENV_LOADED=1' \
  >$ZDOTDIR/profile.d/example.zshenv
print -rl -- \
  'typeset -g PROFILE_INTERACTIVE_LOADED=1' \
  'typeset -g PROFILE_MIGRATION_ORDER="${PROFILE_MIGRATION_ORDER:-}upstream,"' \
  'alias profile-example=true' \
  >$ZDOTDIR/profile.d/example.zshrc
print -r -- 'typeset -g LOCAL_NAMED_ENV_PROFILE_LOADED=1' \
  >$ZDOTDIR/profile.d/example.local.zshenv
print -r -- '# Disabled by default.' >$ZDOTDIR/profile.d/example.disabled

source $repo_root/profiles.zsh zshenv
(( ! ${+PROFILE_ENV_LOADED} )) ||
  fail 'a disabled profile loaded its all-process fragment'
[[ ${LOCAL_NAMED_ENV_PROFILE_LOADED:-0} == 1 ]] ||
  fail 'a normally named .local.zshenv profile was suppressed'

mkdir -p -- $ZDOTDIR/zshrc.d
print -rl -- \
  'typeset -g PROFILE_LEGACY_INTERACTIVE_LOADED=1' \
  'typeset -g PROFILE_MIGRATION_ORDER="${PROFILE_MIGRATION_ORDER:-}legacy,"' \
  >$ZDOTDIR/zshrc.d/example.local.zsh
print -r -- \
  'typeset -g PROFILE_MIGRATION_ORDER="${PROFILE_MIGRATION_ORDER:-}local"' \
  >$ZDOTDIR/profile.d/example.local.zshrc
source $repo_root/profiles.zsh zshenv
[[ ${PROFILE_ENV_LOADED:-0} == 1 ]] ||
  fail 'a matching legacy local profile did not enable the all-process fragment'
source $repo_root/profiles.zsh zshrc
[[ ${PROFILE_INTERACTIVE_LOADED:-0} == 1 ]] ||
  fail 'a matching legacy local profile did not enable the interactive split fragment'
[[ ${PROFILE_LEGACY_INTERACTIVE_LOADED:-0} == 1 ]] ||
  fail 'a matching split profile suppressed distinct pre-migration legacy commands'
[[ $PROFILE_MIGRATION_ORDER == upstream,legacy,local ]] ||
  fail 'pre-migration legacy commands did not precede an independent local supplement'
unset PROFILE_ENV_LOADED
unset \
  PROFILE_INTERACTIVE_LOADED \
  PROFILE_LEGACY_INTERACTIVE_LOADED \
  PROFILE_MIGRATION_ORDER
unalias profile-example
rm -- \
  $ZDOTDIR/profile.d/example.local.zshrc \
  $ZDOTDIR/zshrc.d/example.local.zsh

print -r -- \
  'typeset -g CANONICAL_MIGRATION_ORDER="${CANONICAL_MIGRATION_ORDER:-}zeta,"' \
  >$ZDOTDIR/profile.d/zeta.zshrc
print -r -- \
  'typeset -g CANONICAL_MIGRATION_ORDER="${CANONICAL_MIGRATION_ORDER:-}alpha-legacy"' \
  >$ZDOTDIR/zshrc.d/alpha.local.zsh
source $repo_root/profiles.zsh zshrc
[[ $CANONICAL_MIGRATION_ORDER == zeta,alpha-legacy ]] ||
  fail 'unmatched legacy commands did not follow regular interactive profiles'
cp -- \
  $ZDOTDIR/zshrc.d/alpha.local.zsh \
  $ZDOTDIR/profile.d/alpha.zshrc
CANONICAL_MIGRATION_ORDER=
source $repo_root/profiles.zsh zshrc
[[ $CANONICAL_MIGRATION_ORDER == zeta,alpha-legacy ]] ||
  fail 'a canonical migration changed legacy command ordering'
unset CANONICAL_MIGRATION_ORDER
rm -- \
  $ZDOTDIR/profile.d/alpha.zshrc \
  $ZDOTDIR/profile.d/zeta.zshrc \
  $ZDOTDIR/zshrc.d/alpha.local.zsh

print -r -- '# Enabled on this host.' >$ZDOTDIR/profile.d/example.enabled
source $repo_root/profiles.zsh zshenv
[[ ${PROFILE_ENV_LOADED:-0} == 1 ]] ||
  fail 'an enabled profile did not load its all-process fragment'
(( ! ${+PROFILE_INTERACTIVE_LOADED} )) ||
  fail 'the all-process phase loaded an interactive fragment'

source $repo_root/profiles.zsh zshrc
[[ ${PROFILE_INTERACTIVE_LOADED:-0} == 1 ]] ||
  fail 'an enabled profile did not load its interactive fragment'
(( ${+aliases[profile-example]} )) ||
  fail 'the interactive fragment did not define its alias'

print -rl -- 'return 17' >$ZDOTDIR/profile.d/a-failing.zshenv
print -rl -- 'typeset -g PROFILE_AFTER_FAILURE=1' \
  >$ZDOTDIR/profile.d/b-after-failure.zshenv
failure_log=$tmpdir/failure.stderr
source $repo_root/profiles.zsh zshenv 2>$failure_log ||
  fail 'a failing profile fragment made the shell unusable'
[[ ${PROFILE_AFTER_FAILURE:-0} == 1 ]] ||
  fail 'a failing profile fragment prevented later profiles from loading'
grep -Fq 'zsh startup: optional zshenv profile failed:' $failure_log ||
  fail 'a failing optional profile did not surface degradation'
rm -- \
  $ZDOTDIR/profile.d/a-failing.zshenv \
  $ZDOTDIR/profile.d/b-after-failure.zshenv

print -rl -- \
  'typeset -g LEGACY_INTERACTIVE_LOADED=1' \
  'alias legacy-example=true' \
  >$ZDOTDIR/zshrc.d/legacy.local.zsh
source $repo_root/profiles.zsh zshenv
(( ! ${+LEGACY_INTERACTIVE_LOADED} )) ||
  fail 'an unmatched legacy local profile loaded during the all-process phase'
source $repo_root/profiles.zsh zshrc
[[ ${LEGACY_INTERACTIVE_LOADED:-0} == 1 ]] ||
  fail 'an unmatched legacy local profile was not preserved interactively'
(( ${+aliases[legacy-example]} )) ||
  fail 'an unmatched legacy local profile lost its interactive aliases'

print -r -- 'typeset -g ENV_ONLY_PROFILE_LOADED=1' \
  >$ZDOTDIR/profile.d/env-only.zshenv
print -rl -- \
  'typeset -g ENV_ONLY_LEGACY_INTERACTIVE_LOADED=1' \
  '(( ++ENV_ONLY_INTERACTIVE_LOAD_COUNT ))' \
  >$ZDOTDIR/zshrc.d/env-only.local.zsh
typeset -gi ENV_ONLY_INTERACTIVE_LOAD_COUNT=0
source $repo_root/profiles.zsh zshrc
[[ ${ENV_ONLY_LEGACY_INTERACTIVE_LOADED:-0} == 1 ]] ||
  fail 'a zshenv-only profile suppressed its legacy interactive supplement'
(( ENV_ONLY_INTERACTIVE_LOAD_COUNT == 1 )) ||
  fail 'a zshenv-only legacy supplement did not execute exactly once'

print -r -- '(( ++ENV_ONLY_MODERN_LOCAL_LOAD_COUNT ))' \
  >$ZDOTDIR/profile.d/env-only.local.zshrc
typeset -gi ENV_ONLY_MODERN_LOCAL_LOAD_COUNT=0
ENV_ONLY_INTERACTIVE_LOAD_COUNT=0
source $repo_root/profiles.zsh zshrc
(( ENV_ONLY_MODERN_LOCAL_LOAD_COUNT == 1 &&
  ENV_ONLY_INTERACTIVE_LOAD_COUNT == 1 )) ||
  fail 'an independent local supplement suppressed distinct legacy commands'

cp -- \
  $ZDOTDIR/zshrc.d/env-only.local.zsh \
  $ZDOTDIR/profile.d/env-only.local.zshrc
ENV_ONLY_INTERACTIVE_LOAD_COUNT=0
source $repo_root/profiles.zsh zshrc
(( ENV_ONLY_INTERACTIVE_LOAD_COUNT == 1 )) ||
  fail 'a migrated zshenv-only legacy supplement executed more than once'

print -r -- '(( ++EDGE_LOCAL_MIGRATION_LOAD_COUNT ))' \
  >$ZDOTDIR/zshrc.d/edge.local.local.zsh
cp -- \
  $ZDOTDIR/zshrc.d/edge.local.local.zsh \
  $ZDOTDIR/profile.d/edge.local.zshrc
typeset -gi EDGE_LOCAL_MIGRATION_LOAD_COUNT=0
source $repo_root/profiles.zsh zshrc
(( EDGE_LOCAL_MIGRATION_LOAD_COUNT == 1 )) ||
  fail 'a migrated profile name ending in .local executed more than once'

git -C $repo_root check-ignore -q profile.d/example.enabled ||
  fail 'host-local profile enable markers are not ignored'
git -C $repo_root check-ignore -q profile.d/example.local.zshrc ||
  fail 'migrated host-local profile fragments are not ignored'

openclaw_homebrew_output=$(
  env -i \
    HOMEBREW_PREFIX=/opt/custom-homebrew \
    /bin/zsh -f -c \
    'setopt extendedglob; source "$1"; print -r -- "$HOMEBREW_PREFIX:$HOMEBREW_CELLAR:$HOMEBREW_REPOSITORY"' \
    -- $repo_root/profile.d/openclaw.zshenv
) || fail 'the OpenClaw profile rejected an explicit Homebrew prefix'
[[ $openclaw_homebrew_output == \
  /opt/custom-homebrew:/opt/custom-homebrew/Cellar:/opt/custom-homebrew/Homebrew ]] ||
  fail 'the OpenClaw profile did not preserve and derive an explicit Homebrew prefix'

if [[ $OSTYPE == darwin* ]]; then
  node_fixture_bin=$tmpdir/node-fixture-bin
  mkdir -p -- $node_fixture_bin
  print -rl -- '#!/bin/zsh -f' 'print -r -- 4294967296' \
    >$node_fixture_bin/sysctl
  chmod +x $node_fixture_bin/sysctl
  node_options_output=$(
    env -i \
      HOME=$tmpdir/node-home \
      PATH=$node_fixture_bin:/usr/bin:/bin \
      NODE_OPTIONS='--require "/tmp/a b.js" --max-old-space-size=999' \
      /bin/zsh -f -c \
      'source "$1"; print -r -- "$NODE_OPTIONS"' \
      -- $repo_root/profile.d/node-lowmem.zshenv
  ) || fail 'the low-memory Node profile failed with a quoted option value'
  [[ $node_options_output == '--require "/tmp/a b.js" --max-old-space-size=1536' ]] ||
    fail 'the low-memory Node profile did not preserve quoted option values'
fi

print -r -- 'profile phase checks passed'
