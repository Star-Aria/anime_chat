@echo off
setlocal
set "GPT_SOVITS_ROOT=C:\GPT-SoVITS-v2pro-20250604-nvidia50"

if not exist "%GPT_SOVITS_ROOT%\runtime\python.exe" (
  echo 未找到 GPT-SoVITS：%GPT_SOVITS_ROOT%
  pause
  exit /b 1
)

cd /d "%GPT_SOVITS_ROOT%"
echo 正在启动 GPT-SoVITS API（端口 9880）...
"%GPT_SOVITS_ROOT%\runtime\python.exe" api_v2.py -c GPT_SoVITS/configs/tts_infer.yaml

endlocal
