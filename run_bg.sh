#!/bin/zsh
nohup "$(dirname "$0")/.build/debug/QuickDict" >/tmp/quickdict.log 2>&1 &
echo $!
disown
