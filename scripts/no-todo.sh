#!/bin/sh

if git grep -n --cached -i -- 'TODO' -- '*.py' '*.js' > /dev/null 2>&1; then
  echo "❌ ERROR: Found TODOs in staged files:"
  git grep -n --cached -i -- 'TODO' -- '*.py' '*.js'
  echo "⚠️  Please remove TODOs (or unstage them) before commit."
  exit 1
fi

exit 0
