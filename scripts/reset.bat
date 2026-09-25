@echo off
REM Despliegue DESDE CERO: borra los volumenes, levanta el cluster y carga los datos.
REM Usar si levantar.bat falla o para arrancar limpio. Tarda unos 7 minutos.
cd /d "%~dp0.."
echo ATENCION: esto BORRA todos los datos del cluster. Ctrl+C para cancelar.
pause
docker compose -f docker-compose.monitoring.yml down
docker compose down -v
call "%~dp0levantar.bat" || exit /b 1
echo Cargando datos de prueba...
call "%~dp0preparar.bat"
call "%~dp0estado.bat" galera1
