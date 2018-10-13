#!/bin/bash

if [ -z "$NOBUILD" ]; then
  swift build
fi

./.build/debug/cub_shortcuts "$@"
