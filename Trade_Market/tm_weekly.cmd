@echo off
rem Task Scheduler entry point (task "Prospect Actuary trade market weekly", Tuesday 5:00 AM). Runs tm_weekly.sh with Git Bash.
cd /d "%~dp0"
if not exist "%~dp0logs" mkdir "%~dp0logs"
"C:\Program Files\Git\bin\bash.exe" -lc "cd \"$(cygpath '%~dp0')\" && bash tm_weekly.sh" >> "%~dp0logs\tm_scheduler.txt" 2>&1
