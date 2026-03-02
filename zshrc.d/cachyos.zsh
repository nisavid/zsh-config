
alias paru='env-system paru --skipreview'
alias paru-orphans='=paru --query --unrequired --deps --quiet'
alias paru-orphans-remove='paru --remove --nosave --recursive $(paru-orphans)'
alias paru-rebuild='paru --sync --rebuild $(checkrebuild | sd "^foreign\s+" "")'

