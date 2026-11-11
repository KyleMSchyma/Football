@echo off
rem Windows Task Scheduler entry point for the weekly refresh (task "Prospect Actuary weekly refresh").
rem Runs refresh.sh with Git Bash; output goes to Weekly_Refresh\logs\<date>\refresh.txt
cd /d "%~dp0"
"C:\Program Files\Git\bin\bash.exe" -lc "cd \"$(cygpath '%~dp0')\" && bash refresh.sh" >> "%~dp0logs\scheduler.txt" 2>&1
