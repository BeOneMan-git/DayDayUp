@echo off
rem DayDayUp: save every change in this folder and send it to GitHub.
rem Double-click after Claude has updated files here. GitHub then builds a new DayDayUp.ipa.
cd /d "%~dp0"
git add -A
git commit -m "update"
git pull --rebase
git push
echo.
echo Done. Check the build on your repository Actions page.
pause
