@echo off
REM setlocal EnableDelayedExpansion

set "inputFile=main.c"

for /F "delims=" %%a in ("!inputFile!") do (
    echo Line: %%a
)

endlocal
pause