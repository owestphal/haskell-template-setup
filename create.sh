#!/usr/bin/env zsh
source env
docker build -t haskell-template-setup .
docker create --name haskell-template-setup haskell-template-setup
docker cp haskell-template-setup:$ROOT $PWD/root
docker rm -f haskell-template-setup
echo copied $ROOT to $PWD/root
