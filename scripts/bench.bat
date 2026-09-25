@echo off
REM Benchmark sysbench oltp_read_write contra HAProxy (nunca contra un nodo).
REM Uso: scripts\bench.bat [clientes] [rr^|escritor] [segundos]
REM   scripts\bench.bat              -> 50 clientes, round-robin, 60 s
REM   scripts\bench.bat 100          -> 100 clientes
REM   scripts\bench.bat 50 escritor  -> backend de escritor unico
REM La salida queda guardada en results\ como evidencia.
set T=%1
if "%T%"=="" set T=50
set MODO=%2
if "%MODO%"=="" set MODO=rr
set PUERTO=3306
if /i "%MODO%"=="escritor" set PUERTO=3307
set SEG=%3
if "%SEG%"=="" set SEG=60
echo === sysbench: %T% clientes, backend %MODO% (HAProxy:%PUERTO%), %SEG% s ===
docker exec -it sysbench sh -c "sysbench oltp_read_write --db-driver=mysql --mysql-host=haproxy --mysql-port=%PUERTO% --mysql-user=bench --mysql-password=$BENCH_PASSWORD --mysql-db=sbtest --tables=10 --table-size=100000 --threads=%T% --time=%SEG% --report-interval=5 run 2>&1 | tee /results/bench_%MODO%_%T%.txt"
