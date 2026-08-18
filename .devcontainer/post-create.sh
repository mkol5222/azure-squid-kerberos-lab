#!/usr/bin/env bash
set -euo pipefail

curl -sfS https://dotenvx.sh | sudo sh

sudo apt-get update
sudo apt-get install -y \
    sshpass \
    age \
    zoxide \
    fzf \
    bat \
    ripgrep \
    fd-find

{
    echo
    echo 'eval "$(zoxide init bash)"'
    echo 'alias bat="batcat"'
    #echo 'alias ls="exa --group-directories-first"'
    echo 'alias fd="fdfind"'
} >> ~/.bashrc
