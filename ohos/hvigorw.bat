@echo off
REM [移植适配] 直跑 hvigor 核心 CLI，绕开 DevEco hvigorw.js 对 env.ohpmBin 的无条件覆盖
REM （hvigorw.js 会把 ohpmBin 指回 DevEco 原版 ohpm.bat，其逐字符 call 设计在 pm-cli 重入时触发 BATCH RECURSION）
echo === hvigorw called %date% %time% === >> D:\HarmonyDev\hvigorw_debug.log
echo CWD=%CD% >> D:\HarmonyDev\hvigorw_debug.log
"D:\DevEco Studio\tools\node\node.exe" "D:\DevEco Studio\tools\hvigor\hvigor\bin\hvigor.js" %*
echo EXITCODE=%ERRORLEVEL% >> D:\HarmonyDev\hvigorw_debug.log
exit /b %ERRORLEVEL%
