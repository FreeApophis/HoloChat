@echo off
rem Usage: bin\admin grant^|revoke USERNAME
if "%~1"=="grant" (set "HOLO_FUN=grant_admin") else if "%~1"=="revoke" (set "HOLO_FUN=revoke_admin") else goto usage
if "%~2"=="" goto usage
set "HOLO_USERNAME=%~2"
call "%~dp0\holo_chat" eval "HoloChat.Release.%HOLO_FUN%(System.get_env(~s(HOLO_USERNAME)))"
exit /b

:usage
echo Usage: admin grant^|revoke USERNAME
exit /b 1
