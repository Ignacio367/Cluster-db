# Cluster-db — Alta Disponibilidad con MariaDB Galera

TP N° 4 — Clúster / HIA · Herramientas Informáticas Avanzadas

## 1. Arquitectura

| Dimensión | Elección |
|---|---|
| Motor | MariaDB 10.11 |
| Recursos | **Shared-Nothing** (un volumen por nodo) |
| Topología | **Multi-Master / Activo-Activo** (Galera) |
| Replicación | **Síncrona por certificación** (write-sets, RPO = 0) |
| Acceso | **HAProxy 2.8** en `mode tcp` |
| Nodos | 3 (mínimo para quórum y evitar split-brain) |

```
CLIENTES (Adminer :8080 / sysbench / cliente SQL :3307)
                    |
            HAProxy  :3306 round-robin  -> host :3307
                     :3307 escritor único -> host :3308
                     :8404 stats + /metrics
              /      |      \
      galera1     galera2    galera3     red: galera-net
         |           |          |        repl: 4567/4568/4444
     volume1     volume2    volume3      /var/lib/mysql
```

### Puertos

| Host | Servicio | Justificación |
|---|---|---|
| 3307 | HAProxy round-robin | único punto de entrada SQL |
| 3308 | HAProxy escritor único | comparativa rr vs single-writer |
| 8080 | Adminer | cliente de administración |
| 8404 | HAProxy stats + métricas | evidencia de failover |
| 9090 / 3000 | Prometheus / Grafana | dashboards |

**No expuestos** (solo en `galera-net`): `3306` de cada nodo, `4567` (membresía),
`4568` (IST), `4444` (SST), `9104` (exporters). El acceso administrativo va por
`docker exec`, no por un puerto publicado.

## 2. Estructura

```
Cluster-db/
├── docker-compose.yml               # cluster + proxy + clientes + init
├── docker-compose.monitoring.yml    # observabilidad (aparte)
├── .env.example / .gitignore / .gitattributes
├── config/galera.cnf                # config wsrep de los 3 nodos
├── config/haproxy.cfg               # balanceo y health checks
├── node1/ node2/ node3/             # datos/config por nodo
├── monitoring/prometheus.yml, alertas.yml, grafana/provisioning/
├── backups/  results/               # dumps y evidencia de pruebas
└── tests/Dockerfile                 # imagen sysbench + mariadb-client
```

No hay scripts `.sh`: la creación de usuarios va en el propio compose
(servicio `init-usuarios`), lo que evita problemas de fin de línea CRLF/LF
entre Windows y Linux.

## 3. Despliegue

```bash
cp .env.example .env        # cambiar TODAS las contraseñas
docker compose up -d        # con BOOTSTRAP_ARGS=--wsrep-new-cluster
```

Orden en cadena: `galera1` bootstrapea → `init-usuarios` crea los usuarios y
termina → `galera2` entra por SST → `galera3` entra por SST. Total: 3–5 min.

Verificación:

```bash
docker exec galera1 mariadb -uroot -pTU_PASS -e "SHOW STATUS WHERE Variable_name IN ('wsrep_cluster_size','wsrep_cluster_status','wsrep_local_state_comment');"
```

Debe dar `3`, `Primary`, `Synced`. **Si no da 3, no avanzar.**

**Luego del primer arranque: dejar `BOOTSTRAP_ARGS=` vacío en `.env`.** Volver a
bootstrapear crearía un clúster nuevo y partiría la membresía (split-brain).

Apagar con `docker compose down` (sin `-v`, que borra los datos). El orden
importa: `galera1` debe salir último para quedar `safe_to_bootstrap: 1`.

### Monitorización

```bash
docker compose -f docker-compose.monitoring.yml up -d
```

- Prometheus <http://localhost:9090> → *Status → Targets*, todo `UP`
- Grafana <http://localhost:3000> (admin / `MONITOR_PASSWORD`), datasource ya provisionada
- Dashboards por ID: **7362** (MySQL), **1860** (Node Exporter), **193** (cAdvisor), **12693** (HAProxy)
- Panel obligatorio del clúster: `mysql_global_status_wsrep_cluster_size`,
  `..._wsrep_local_state`, `..._wsrep_flow_control_paused_ns`,
  `..._threads_connected`, `rate(mysql_global_status_queries[1m])`

## 4. Seguridad

Ninguna contraseña está en el compose ni en los `.cnf`: todas se interpolan
desde `.env`, que está en `.gitignore` (se versiona solo `.env.example`).
`root` no se usa para ninguna operación de servicio ni es accesible desde fuera
de la red Docker.

| Usuario | Privilegios | Usado por |
|---|---|---|
| `administrador` | `ALL ON *.*` | DDL, mantenimiento, backups |
| `replicacion` | `RELOAD, PROCESS, LOCK TABLES, BINLOG/REPLICA MONITOR, REPLICATION SLAVE ADMIN` (en `%` y `localhost`) | SST/IST entre nodos |
| `aplicacion` | `SELECT, INSERT, UPDATE, DELETE` en `sbtest.*` | Adminer / app cliente |
| `monitorizacion` | `PROCESS, REPLICATION CLIENT, SLAVE MONITOR, SELECT` | mysqld-exporter |
| `bench` | `ALL` en `sbtest.*` | sysbench (necesita DDL) |
| `haproxy_check` | ninguno, sin contraseña | health check de HAProxy |

`replicacion` se crea también para `localhost` porque `mariabackup` se conecta
por socket Unix durante el SST.

## 5. Base de datos

Generada por sysbench: 10 tablas × 100.000 filas ≈ 1.000.000 de filas.

```bash
docker exec -it sysbench sysbench oltp_common \
  --db-driver=mysql --mysql-host=haproxy --mysql-port=3306 \
  --mysql-user=bench --mysql-password=TU_PASS --mysql-db=sbtest \
  --tables=10 --table-size=100000 --threads=8 prepare
```

Hasta ejecutar esto, Adminer no muestra tablas: es normal.

## 6. Cliente (Adminer)

<http://localhost:8080> · Sistema **MySQL** · Servidor **haproxy** ·
Usuario **aplicacion** · Base **sbtest**

El cliente no conoce ningún nodo: habla solo con el balanceador. Para
demostrarlo:

```sql
SELECT @@wsrep_node_name;              -- cambia al reabrir sesión (round-robin)
SHOW STATUS LIKE 'wsrep_cluster_size'; -- nodos vivos
SHOW STATUS LIKE 'wsrep_local_state_comment';
SHOW STATUS LIKE 'wsrep_flow_control_paused';
```

Replicación síncrona en vivo: insertar una fila por el proxy y verificarla en
otro nodo con `docker exec galera3 mariadb ... -e "SELECT ..."`, sin esperar.

## 7. Pruebas

Base del comando (cambia `--threads` y la etiqueta):

```bash
docker exec -it sysbench sysbench oltp_read_write \
  --db-driver=mysql --mysql-host=haproxy --mysql-port=3306 \
  --mysql-user=bench --mysql-password=TU_PASS --mysql-db=sbtest \
  --tables=10 --table-size=100000 \
  --threads=50 --time=60 --report-interval=5 run
```

| Escenario | Comando | Qué observar |
|---|---|---|
| A · todos activos | `--threads=` 10/25/50/100/200, ×3 | TPS, QPS, latencia p95 |
| B · cae un secundario | `docker stop galera3` con carga corriendo | bache de TPS en el reporte por intervalo |
| C · recuperación | `docker start galera3` + `wsrep_local_state_comment` hasta `Synced` | tiempo de resincronización, pico de I/O |
| D · cae el nodo con tráfico | `docker kill galera1` | failover de HAProxy (~4 s), errores 2013, panel :8404 |
| E · pérdida de quórum | `docker stop galera2 galera3` | `Non-Primary`: rechaza consultas para evitar split-brain |
| Escalabilidad | correr con 3, parar uno, correr con 2… | ¿mejora al sumar nodos? |
| Lectura vs escritura | `oltp_read_only` y `oltp_write_only` | dónde escala y dónde no |
| rr vs escritor único | `--mysql-port=3306` vs `3307` | abortos por certificación (1213) |

Sugerido: `--mysql-ignore-errors=1213,1205,1180,2013,2006` para que los abortos
por certificación se cuenten en vez de cortar la corrida. Guardar la salida en
`results/` (`> results/A_t50_r1.txt`) como evidencia.

Entre escenarios, verificar que los 3 nodos vuelvan a `Synced`: medir con el
clúster a medio sincronizar da números sin sentido.

## 8. Resultado esperado y limitaciones

- Las **lecturas escalan**: HAProxy reparte los `SELECT` y cada nodo tiene copia
  completa.
- Las **escrituras no escalan**, y pueden empeorar: cada commit espera la
  certificación del grupo, así que el clúster escribe a la velocidad del nodo
  más lento, y más nodos = más tráfico de certificación.
- Con alta concurrencia en round-robin aparecen **abortos por certificación**
  (error 1213): dos nodos reciben escrituras sobre la misma fila. El puerto de
  escritor único lo evita, y comparar ambos es la evidencia dura del costo real
  del multi-master.
- **`wsrep_flow_control_paused`** es el indicador de saturación del clúster:
  cuando sube, un nodo no alcanza a aplicar los write-sets y frena a todos.
- **En Galera no hay failover de base de datos**: no existe primario que
  promover, todos los nodos ya son escritores. Lo que conmuta es el destino del
  tráfico en el balanceador, en `inter 2s × fall 2 ≈ 4 s`. No hay pérdida de
  datos porque todo commit confirmado ya fue certificado (RPO = 0).

**Puntos únicos de falla:**

1. **HAProxy es único**: si cae, el servicio queda inaccesible aunque los tres
   nodos estén sanos.
2. **Una sola máquina física**: CPU, RAM, disco y kernel compartidos; los nodos
   no son independientes de verdad.
3. El health check `mysql-check` valida que el puerto responda, no que el nodo
   esté `Synced`: un nodo `Non-Primary` podría seguir en la rotación.
4. **Recuperación ante apagón total**: hay que comparar el `seqno` de
   `grastate.dat` de los tres nodos y bootstrapear desde el más avanzado.

**Para producción:** HAProxy redundante con keepalived + VIP (o ProxySQL /
MaxScale con detección de estado Galera), nodos en hosts distintos, health check
por script `clustercheck` que lea `wsrep_local_state`, TLS en conexiones y
replicación, backups automatizados con mariabackup, y
`innodb_flush_log_at_trx_commit=1` (aquí está en 2 para el laboratorio).
