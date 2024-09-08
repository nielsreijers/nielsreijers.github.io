#!/bin/bash
# courtesy of https://github.com/BretFisher/jekyll-serve

set -e

echo "Running entrypoint script"

if [ ! -f Gemfile ]; then
  echo "NOTE: hmm, I don't see a Gemfile so I don't think there's a jekyll site here"
  echo "Either you didn't mount a volume, or you mounted it incorrectly."
  echo "Be sure you're in your jekyll site root and use something like this to launch"
  echo ""
  echo "docker run -p 4000:4000 -v \$(pwd):/site nielsreijers.com/jekyll-serve"
  exit 1
fi

bundle install --retry 5 --jobs 20

exec "$@"
