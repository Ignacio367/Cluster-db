@echo off
REM Carga el dataset de prueba: 10 tablas x 100.000 filas (1.000.000 de filas) via HAProxy.
REM Se ejecuta UNA vez tras un despliegue desde cero.
echo === Cargando sbtest (10 x 100.000 filas) ===
docker exec -it sysbench sh -c "sysbench oltp_common --db-driver=mysql --mysql-host=haproxy --mysql-port=3306 --mysql-user=bench --mysql-password=$BENCH_PASSWORD --mysql-db=sbtest --tables=10 --table-size=100000 --threads=8 prepare"
