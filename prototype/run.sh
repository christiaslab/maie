#!/bin/sh
set -eu
cd "$(dirname "$0")"
if [ ! -x '.build/Maie Prototype.app/Contents/MacOS/MaiePrototype' ]; then
    sh build.sh
fi
open '.build/Maie Prototype.app'
