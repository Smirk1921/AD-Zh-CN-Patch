@echo off
setlocal
chcp 65001 >nul

if not exist "%~dp0Patch.ps1" goto incomplete
if not exist "%~dp0patch-manifest.json" goto incomplete
if not exist "%~dp0payload\zh-cn-catalog.js" goto incomplete
if not exist "%~dp0payload\zh-cn-runtime.js" goto incomplete
if not exist "%~dp0payload\zh-cn.css" goto incomplete
if not exist "%~dp0payload\fonts\LXGWWenKai-Medium.ttf" goto incomplete
if not exist "%~dp0payload\fonts\OFL.txt" goto incomplete
if not "%~2"=="" goto usage

if "%~1"=="" (
  powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Patch.ps1" -Action Install -Interactive
) else (
  powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Patch.ps1" -Action Install -GameRoot "%~1" -Interactive
)
set "exitCode=%errorlevel%"
echo.
if not "%exitCode%"=="0" echo 安装未完成，请查看上方提示。
pause
exit /b %exitCode%

:incomplete
echo 汉化包文件不完整。请先将整个 ZIP 解压到普通文件夹，再运行安装器。
echo.
pause
exit /b 2

:usage
echo 一次只能指定一个位置。请拖入游戏目录、游戏 EXE、app.asar 或 Steam 库根目录。
echo.
pause
exit /b 2
