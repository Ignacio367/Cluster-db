@echo off
REM Arranque en frio del cluster CONSERVANDO los datos (despues de apagar.bat).
REM 1) funda el cluster desde galera1 con --wsrep-new-cluster
REM 2) recrea galera1 SIN ese parametro, para que un reinicio posterior
REM    (por ejemplo tras docker kill) se una al grupo y no funde otro (split-brain)
cd /d "%~dp0.."
set R=
for /f %%s in ('docker inspect -f "{{.State.Running}}" galera2 2^>nul') do set R=%%s
if "%R%"=="true" (
  echo El cluster ya esta corriendo: no se vuelve a bootstrapear.
  call "%~dp0estado.bat"
  exit /b 0
)
powershell -NoProfile -Command "(Get-Content .env) -replace '^BOOTSTRAP_ARGS=.*','BOOTSTRAP_ARGS=' | Set-Content .env"
echo [1/4] Bootstrap desde galera1 (tarda 3-5 min)...
set BOOTSTRAP_ARGS=--wsrep-new-cluster
docker compose up -d --build
if errorlevel 1 goto fallo
set BOOTSTRAP_ARGS=
call "%~dp0_esperar.bat" galera3 || goto fallo
echo [2/4] Recreando galera1 sin bootstrap...
docker compose up -d --no-deps --force-recreate galera1
call "%~dp0_esperar.bat" galera1 || goto fallo
echo [3/4] Monitorizacion...
docker compose -f docker-compose.monitoring.yml up -d
echo [4/4] Estado final:
call "%~dp0estado.bat" galera1
exit /b 0
:fallo
set BOOTSTRAP_ARGS=
echo.
echo *** El arranque fallo. Causa probable: galera1 no fue el ultimo en apagarse
echo *** (safe_to_bootstrap: 0). Solucion rapida: scripts\reset.bat (borra y recrea todo).
exit /b 1
