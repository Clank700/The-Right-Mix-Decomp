#!/bin/sh
# Runs rightmix.py with python3.   usage: ./rightmix.sh doctor | setup | build --swf bartender.swf | gui
exec python3 "$(dirname "$0")/rightmix.py" "$@"
