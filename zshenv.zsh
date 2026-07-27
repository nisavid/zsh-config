# Zsh reads this entrypoint for every invocation. Keep it silent on success and
# delegate each bounded responsibility to a namespace-clean implementation.
ZDOTDIR=${XDG_CONFIG_HOME:-$HOME/.config}/zsh

if [[ -o login && ! -r $ZDOTDIR/zprofile.zsh ]]; then
  print -ru2 -- "zsh startup: required login policy is missing: $ZDOTDIR/zprofile.zsh"
fi

if [[ -r $ZDOTDIR/environment.zsh ]]; then
  source $ZDOTDIR/environment.zsh ||
    print -ru2 -- "zsh startup: declarative environment loading failed in .zshenv"
else
  print -ru2 -- "zsh startup: required loader is missing: $ZDOTDIR/environment.zsh"
fi

if [[ -r $ZDOTDIR/profiles.zsh ]]; then
  source $ZDOTDIR/profiles.zsh zshenv ||
    print -ru2 -- "zsh startup: optional environment profiles failed in .zshenv"
else
  print -ru2 -- "zsh startup: required profile dispatcher is missing: $ZDOTDIR/profiles.zsh"
fi

if [[ -r $ZDOTDIR/startup.zsh ]]; then
  source $ZDOTDIR/startup.zsh zshenv "$OSTYPE" ||
    print -ru2 -- "zsh startup: portable environment policy failed in .zshenv"
else
  print -ru2 -- "zsh startup: required policy is missing: $ZDOTDIR/startup.zsh"
fi
