@echo off
REM Uso interno: espera hasta que el nodo %1 este "healthy" (wsrep_ready=ON).
REM Maximo ~7 minutos. Devuelve errorlevel 1 si no lo logra.
set /a INTENTOS=0
:loop
set H=
for /f %%s in ('docker inspect -f "{{.State.Health.Status}}" %1 2^>nul') do set H=%%s
if "%H%"=="healthy" (
  echo   %1 listo.
  exit /b 0
)
set /a INTENTOS+=1
if %INTENTOS% GEQ 42 (
  echo   %1 no llego a healthy. Revisar: docker logs %1
  exit /b 1
)
echo   esperando a %1 ... [%H%]
timeout /t 10 /nobreak >nul
goto loop
