#!/usr/bin/env bash
# run_r.sh <folder> <script.R> <logfile> [args...]: runs Rscript in <folder> with Kyle's .Renviron (CFBD key)
dir="$1"; script="$2"; log="$3"; shift 3
cd "$dir" && R_ENVIRON_USER="C:/Users/kylem/Documents/.Renviron" "/c/Program Files/R/R-4.6.1/bin/Rscript.exe" "$script" "$@" > "$log" 2>&1
