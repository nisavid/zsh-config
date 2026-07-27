if [[ -r $ZDOTDIR/startup.zsh ]]; then
  source $ZDOTDIR/startup.zsh zprofile "$OSTYPE" ||
    print -ru2 -- "zsh startup: portable environment policy failed in .zprofile"
else
  print -ru2 -- "zsh startup: required policy is missing: $ZDOTDIR/startup.zsh"
fi
