@echo off
setlocal ENABLEDELAYEDEXPANSION

set INPUT=%1
set OUTPUT=out.asm

set /a COUNT=0

:: Clean temp files
del msg_*.txt >nul 2>&1
del printf_calls.txt >nul 2>&1

:: Step 1: Parse all printf() lines and extract strings
for /f "usebackq tokens=* delims=" %%L in ("%INPUT%") do (
    set "LINE=%%L"
    set "LINE=!LINE: =!"

    echo !LINE! | findstr /C:"printf(" >nul
    if !errorlevel! neq 1 (
        for /f "tokens=2 delims=(" %%A in ("!LINE!") do (
            for /f "tokens=1 delims=)" %%B in ("%%A") do (
                set STR=%%B
                set STR=!STR:"=!
                set STR=!STR:,=,!
                echo !STR! > msg_!COUNT!.txt
                echo     lea rcx, [rel msg!COUNT!] >> printf_calls.txt
                echo     call printf >> printf_calls.txt
                set /a COUNT+=1
            )
        )
    )
)

:: Step 2: Write assembly file
(
    echo extern printf
    echo global main
    echo.
    echo section .data
    for /l %%i in (0,1,%COUNT%) do (
        if exist msg_%%i.txt (
            set /p TXT=<msg_%%i.txt
            echo     msg%%i db "!TXT!", 10, 0
        )
    )
    echo.
    echo section .text
    echo main:
    echo     sub rsp, 40
    type printf_calls.txt
    echo     add rsp, 40
    echo     xor eax, eax
    echo     ret
) > %OUTPUT%

:: Cleanup
del msg_*.txt >nul 2>&1
del printf_calls.txt >nul 2>&1

echo.
echo [OK] Generated: %OUTPUT%
