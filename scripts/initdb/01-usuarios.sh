#!/bin/bash
# Se ejecuta UNA sola vez, en el primer arranque de galera1.
# Los nodos 2 y 3 reciben estos usuarios via SST (no ejecutan este script).
set -e

Q() { mariadb --protocol=socket -uroot -p"$MARIADB_ROOT_PASSWORD" -e "$1"; }

echo ">> Creando bases de datos..."
Q "CREATE DATABASE IF NOT EXISTS \`${APP_DB}\` CHARACTER SET utf8mb4;"
Q "CREATE DATABASE IF NOT EXISTS sbtest CHARACTER SET utf8mb4;"

echo ">> Creando usuarios con privilegios minimos..."

# 1) administrador  -> DDL y mantenimiento (reemplaza a root)
Q "CREATE USER IF NOT EXISTS 'administrador'@'%' IDENTIFIED BY '${ADMIN_PASSWORD}';
   GRANT ALL PRIVILEGES ON *.* TO 'administrador'@'%' WITH GRANT OPTION;"

# 2) replicacion -> SST con mariabackup + replicacion interna del cluster
Q "CREATE USER IF NOT EXISTS 'replicacion'@'%' IDENTIFIED BY '${REPL_PASSWORD}';
   GRANT RELOAD, PROCESS, LOCK TABLES, BINLOG MONITOR, REPLICA MONITOR,
         REPLICATION SLAVE ADMIN, REPLICATION SLAVE, REPLICATION CLIENT
     ON *.* TO 'replicacion'@'%';"

# 3) aplicacion -> solo DML sobre la base de trabajo (sin DROP/ALTER)
Q "CREATE USER IF NOT EXISTS 'aplicacion'@'%' IDENTIFIED BY '${APP_PASSWORD}';
   GRANT SELECT, INSERT, UPDATE, DELETE ON \`${APP_DB}\`.* TO 'aplicacion'@'%';"

# 4) monitorizacion -> solo lectura de estado (mysqld-exporter / Prometheus)
Q "CREATE USER IF NOT EXISTS 'monitorizacion'@'%' IDENTIFIED BY '${MONITOR_PASSWORD}';
   GRANT PROCESS, REPLICATION CLIENT, SLAVE MONITOR, SELECT ON *.* TO 'monitorizacion'@'%';"

# 5) bench -> aislado en sbtest, necesita DDL porque sysbench crea/borra tablas
Q "CREATE USER IF NOT EXISTS 'bench'@'%' IDENTIFIED BY '${BENCH_PASSWORD}';
   GRANT ALL PRIVILEGES ON sbtest.* TO 'bench'@'%';"

# 6) haproxy_check -> sin password y sin privilegios: solo para el health check TCP/MySQL
Q "CREATE USER IF NOT EXISTS 'haproxy_check'@'%';"

Q "FLUSH PRIVILEGES;"
echo ">> Usuarios creados."
