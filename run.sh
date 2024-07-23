#!/usr/bin/env bash

# The first bundle in my path comes from the Fedora dnf package.
# For some reason this wants to install gems in /usr/share/gems/gems,
# where I don't have permissions.
# The Ruby installed with rbenv doesn't have this problem, so use
# that instead.
# (I can't just uninstall the dnf package since TexLive depends on
# it, and I'm not sure if it would work with the rbenv version
# if I put that first in my normal PATH)

#export PATH=$(rbenv which bundle | xargs dirname):$PATH
bundle exec jekyll serve
