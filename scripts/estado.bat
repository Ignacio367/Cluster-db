@echo off
REM Estado del cluster visto desde un nodo (por defecto galera2).
REM Uso: scripts\estado.bat [galera1^|galera2^|galera3]
REM La password de root NO esta en este archivo: la lee el propio contenedor
REM desde su variable MARIADB_ROOT_PASSWORD (que viene del .env).
set NODO=%1
if "%NODO%"=="" set NODO=galera2
echo === Cluster visto desde %NODO% ===
echo SHOW STATUS WHERE Variable_name IN ('wsrep_cluster_size','wsrep_cluster_status','wsrep_local_state_comment','wsrep_ready'); | docker exec -i %NODO% sh -c "mariadb -uroot -p$MARIADB_ROOT_PASSWORD -t"
