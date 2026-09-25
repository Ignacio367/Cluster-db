@echo off
REM Apagado ORDENADO: Compose detiene en orden inverso a las dependencias,
REM asi galera1 sale ultimo y queda con safe_to_bootstrap: 1 (apto para levantar.bat).
REM No usa -v: los datos se conservan.
cd /d "%~dp0.."
docker compose -f docker-compose.monitoring.yml down
docker compose down
echo Cluster apagado. Para volver: scripts\levantar.bat
