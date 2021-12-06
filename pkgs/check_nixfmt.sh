#!/usr/bin/env bash

test_fmt() {
  hash nixfmt 2>&- || {
    echo >&2 "nixfmt not in PATH."
    exit 1
  }
  IFS='
'

  exitcode=0

  for file in $(git diff --cached --name-only --diff-filter=ACM | grep '\.nix$'); do
    output=$(git cat-file -p :"$file" | nixfmt -c 2>&1)
    if test $? -ne 0; then
      echo "${output//<stdin>/$file}"
      exitcode="$?"
    fi
  done

  exit "$exitcode"
}

case "$1" in
--about)
  echo "Check Nix code formatting"
  ;;
*)
  test_fmt
  ;;
esac
