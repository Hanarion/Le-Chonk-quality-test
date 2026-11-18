#!/bin/sh
# Build the Ada/SDL2 Tetris with GPRbuild.
set -e
cd "$(dirname "$0")"
gprbuild -P tetris.gpr -p "$@"
echo "Built ./tetris  — run it with: ./tetris"
