#!/bin/bash

swift build && ./.build/debug/cub_shortcuts "$@"
