#!/usr/bin/env bash
# Helper used by Claude to run a phase script and log output: ./run.sh script.R logfile.txt
cd "$(dirname "$0")"
R_ENVIRON_USER="C:/Users/kylem/Documents/.Renviron" "/c/Program Files/R/R-4.6.1/bin/Rscript.exe" "$1" "${@:3}" > "$2" 2>&1
echo "exit: $?"
