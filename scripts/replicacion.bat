@echo off
REM Demuestra la replicacion sincrona: escribe en un nodo y lee al instante en otro.
REM Uso: scripts\replicacion.bat [nodo_escritura] [nodo_lectura]   (por defecto galera1 y galera3)
set W=%1
set R=%2
if "%W%"=="" set W=galera1
if "%R%"=="" set R=galera3
echo === Escribiendo una fila en %W% ===
echo CREATE TABLE IF NOT EXISTS sbtest.demo (id INT AUTO_INCREMENT PRIMARY KEY, escrito_en VARCHAR(20), momento DATETIME(3) DEFAULT NOW(3)); INSERT INTO sbtest.demo (escrito_en) VALUES (@@wsrep_node_name); | docker exec -i %W% sh -c "mariadb -uroot -p$MARIADB_ROOT_PASSWORD"
echo === Leyendo desde %R% (ahi nunca se escribio directamente) ===
echo SELECT @@wsrep_node_name AS leido_en, d.* FROM sbtest.demo d ORDER BY id DESC LIMIT 5; | docker exec -i %R% sh -c "mariadb -uroot -p$MARIADB_ROOT_PASSWORD -t"
