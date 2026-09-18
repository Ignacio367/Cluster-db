# Cluster-db — Clúster de Alta Disponibilidad con MariaDB Galera

Trabajo Práctico N° 4 — Clúster / HIA
Analista Programador Universitario — Herramientas Informáticas Avanzadas

---

## 1. Resumen de la solución

| Dimensión | Elección |
|---|---|
| Motor | MariaDB 10.11 (`mariadb:10.11`) |
| Distribución de recursos | **Shared-Nothing** (cada nodo con su propio volumen) |
| Topología | **Multi-Master / Activo-Activo** (Galera Cluster) |
| Replicación | **Virtualmente síncrona** por certificación (write-sets, RPO = 0) |
| Punto de acceso | **HAProxy 2.8** en `mode tcp` (round-robin + escritor único) |
| Cliente | Adminer (web) + contenedor sysbench (pruebas) |
| Monitorización | mysqld-exporter × 3 + node-exporter + cAdvisor + Prometheus + Grafana |
| Nodos | 3 (mínimo para mantener quórum y evitar split-brain) |

**Por qué Galera y no replicación primario/secundario clásica:** el failover es
implícito. No hay nodo primario que deba ser promovido, no hace falta un
orquestador externo (Patroni, etcd, Orchestrator) y la consistencia es fuerte
por diseño. El costo es latencia de escritura, que es exactamente lo que las
pruebas de este TP miden.

---

## 2. Topología

```
        CLIENTES (Adminer :8080 / sysbench / cliente SQL :3307)
                            |
                    +---------------+
                    |   HAProxy     |  :3306 round-robin  -> host :3307
                    |   mode tcp    |  :3307 single-writer -> host :3308
                    +---------------+  :8404 stats + /metrics
                      /      |      \
              galera1     galera2    galera3      red: galera-net (bridge)
              :3306       :3306      :3306        replicación: 4567/4568/4444
                 |           |          |
             volume1     volume2    volume3       /var/lib/mysql
```

### Puertos

| Puerto host | Servicio | Justificación |
|---|---|---|
| 3307 | HAProxy → cluster (round-robin) | único punto de entrada SQL para clientes |
| 3308 | HAProxy → escritor único | comparativa round-robin vs single-writer |
| 8080 | Adminer | cliente de administración web |
| 8404 | HAProxy stats + `/metrics` | evidencia de failover en vivo |
| 9090 / 3000 | Prometheus / Grafana | dashboards |

**No expuestos** (solo dentro de `galera-net`): `3306` de cada nodo, `4567`
(replicación y membresía), `4568` (IST incremental), `4444` (SST completo),
`9104` (exporters). El acceso administrativo directo a un nodo se hace por
`docker exec`, no por un puerto publicado.

---

## 3. Estructura del repositorio

```
Cluster-db/
├── docker-compose.yml               # cluster + proxy + clientes
├── docker-compose.monitoring.yml    # stack de observabilidad (separado)
├── .env.example                     # plantilla de credenciales (.env es ignorado)
├── .gitignore
├── config/
│   ├── galera-common.cnf            # config wsrep compartida por los 3 nodos
│   └── haproxy.cfg                  # balanceo, health checks, stats
├── node1/node.cnf                   # identidad del nodo 1
├── node2/node.cnf
├── node3/node.cnf
├── scripts/
│   ├── initdb/01-usuarios.sh        # usuarios y privilegios mínimos
│   ├── initdb/02-datos.sh           # carga ~170k filas (base "biblioteca")
│   ├── estado.sh                    # estado wsrep de los 3 nodos
│   ├── bench.sh                     # sysbench parametrizado
│   ├── barrido.sh                   # escenario A: 10→200 clientes × 3
│   ├── pruebas-fallo.sh             # escenarios B, C, D, E
│   ├── resumen.sh                   # .txt de sysbench → CSV
│   └── backup.sh
├── monitoring/
│   ├── prometheus.yml
│   ├── alertas.yml
│   └── grafana/provisioning/datasources/prometheus.yml
├── backups/
├── results/                         # salidas de sysbench (evidencia)
└── tests/Dockerfile                 # imagen sysbench + mariadb-client
```

> Nota: los datos de cada nodo viven en **volúmenes Docker nombrados**
> (`galera1-data`, etc.) y no en bind-mounts, para evitar problemas de permisos
> y de rendimiento de I/O que falsearían las mediciones. Los directorios
> `node1/ node2/ node3/` alojan la configuración propia de cada nodo.

---

## 4. Despliegue

### 4.1 Requisitos
Docker Engine 24+ y Docker Compose v2. Una sola máquina física alcanza.
Recomendado: 8 GB de RAM (3 nodos × 512 MB de buffer pool + stack de monitoreo).

### 4.2 Primer arranque

```bash
git clone <repo> && cd Cluster-db
cp .env.example .env
nano .env                  # cambiar TODAS las contraseñas
                           # dejar BOOTSTRAP_ARGS=--wsrep-new-cluster

docker compose up -d --build
docker compose logs -f galera1     # esperar "ready for connections"
```

`galera1` arranca con `--wsrep-new-cluster` (crea el quórum inicial) y ejecuta
los scripts de `scripts/initdb/`. `galera2` y `galera3` esperan a que
`galera1` esté *healthy* y se incorporan por **SST con mariabackup**, que copia
la base completa (incluidos los usuarios).

### 4.3 Verificación

```bash
./scripts/estado.sh
```

Debe mostrar en los tres nodos:

```
wsrep_cluster_size          3
wsrep_cluster_status        Primary
wsrep_local_state_comment   Synced
wsrep_ready                 ON
```

**Si `wsrep_cluster_size` no es 3, no avanzar**: revisar `docker logs galera2`.

### 4.4 Arranques posteriores (importante)

Una vez formado el clúster, editar `.env` y **dejar `BOOTSTRAP_ARGS=` vacío**.
Volver a arrancar con `--wsrep-new-cluster` crearía un clúster nuevo y partiría
la membresía (split-brain).

```bash
docker compose down          # ordenado: galera1 se detiene último
# .env -> BOOTSTRAP_ARGS=
docker compose up -d
```

Si el clúster se apagó de forma abrupta y ningún nodo levanta, hay que
rearrancar desde el nodo con el `seqno` más alto (ver
`/var/lib/mysql/grastate.dat`) usando `BOOTSTRAP_ARGS=--wsrep-new-cluster`
solo en esa ocasión.

### 4.5 Monitorización

```bash
docker compose -f docker-compose.monitoring.yml up -d
```

- Prometheus: <http://localhost:9090> → *Status → Targets*, todo `UP`
- Grafana: <http://localhost:3000> (admin / `MONITOR_PASSWORD`), datasource ya provisionada
- Dashboards a importar por ID: **7362** (MySQL Overview), **1860** (Node Exporter), **193** (Docker/cAdvisor), **12693** (HAProxy 2)
- Panel obligatorio del clúster: crear uno propio con
  `mysql_global_status_wsrep_cluster_size`,
  `mysql_global_status_wsrep_local_state`,
  `mysql_global_status_wsrep_flow_control_paused_ns`,
  `mysql_global_status_threads_connected`,
  `rate(mysql_global_status_queries[1m])`

---

## 5. Seguridad

### 5.1 Credenciales
Ninguna contraseña está escrita en `docker-compose.yml` ni en los `.cnf`. Todas
se inyectan desde `.env`, que está en `.gitignore`; se versiona solo
`.env.example`. `root` no se usa para ninguna operación de servicio y no está
accesible desde fuera de la red Docker.

### 5.2 Usuarios y privilegios mínimos

| Usuario | Privilegios | Usado por |
|---|---|---|
| `administrador` | `ALL ON *.*` | DDL, mantenimiento, backups |
| `replicacion` | `RELOAD, PROCESS, LOCK TABLES, BINLOG MONITOR, REPLICA MONITOR, REPLICATION SLAVE ADMIN` | SST/IST entre nodos |
| `aplicacion` | `SELECT, INSERT, UPDATE, DELETE` solo en `biblioteca.*` | Adminer / app cliente |
| `monitorizacion` | `PROCESS, REPLICATION CLIENT, SLAVE MONITOR, SELECT` | mysqld-exporter |
| `bench` | `ALL` solo en `sbtest.*` | sysbench (necesita DDL, aislado de la base real) |
| `haproxy_check` | sin privilegios, sin contraseña | health check de HAProxy |

> `aplicacion` no puede hacer `DROP` ni `ALTER`. `bench` no puede tocar
> `biblioteca`. Ese aislamiento es deliberado: un benchmark no debe poder
> destruir los datos del TP.

---

## 6. Base de datos de prueba

`scripts/initdb/02-datos.sh` crea la base `biblioteca` con el motor `SEQUENCE`
de MariaDB (carga en segundos, sin dependencias):

| Tabla | Filas |
|---|---|
| `autores` | 2.000 |
| `libros` | 50.000 |
| `socios` | 20.000 |
| `prestamos` | 100.000 |

Para el benchmark se usa una base separada, `sbtest`, generada por sysbench
(10 tablas × 100.000 filas ≈ 1.000.000 de filas).

---

## 7. Cliente de acceso (Adminer)

<http://localhost:8080>

| Campo | Valor |
|---|---|
| Sistema | MySQL |
| Servidor | `haproxy` (ya viene precargado) |
| Usuario | `aplicacion` |
| Contraseña | la de `APP_PASSWORD` |
| Base de datos | `biblioteca` |

El cliente **no conoce ningún nodo**: habla solo con el balanceador. Para
demostrarlo en la defensa, ejecutar en Adminer:

```sql
SELECT @@wsrep_node_name;
```

Cerrando y reabriendo la sesión, el nodo que responde cambia (round-robin).
Y para ver la replicación síncrona en vivo:

```sql
-- en Adminer (vía proxy)
INSERT INTO socios (nombre, email, alta) VALUES ('Prueba HA', 'ha@uni.edu.ar', CURDATE());
```

```bash
# verificar que ya está en otro nodo, sin esperar
docker exec galera3 mariadb -uadministrador -p"$ADMIN_PASSWORD" biblioteca \
  -e "SELECT * FROM socios WHERE nombre='Prueba HA';"
```

---

## 8. Pruebas

### 8.1 Preparar el dataset de benchmark

```bash
docker exec -it sysbench /scripts/bench.sh prepare
```

### 8.2 Escenario A — todos los nodos activos

```bash
docker exec -it sysbench /scripts/barrido.sh A_todos_ok
# 10 / 25 / 50 / 100 / 200 clientes, 3 repeticiones cada uno, 60 s por corrida
```

M�tricas recogidas: TPS, QPS, latencia media y p95, errores. CPU/RAM/red/I-O
se leen de Grafana en la misma ventana temporal.

### 8.3 Escenario B — un secundario fuera de servicio

```bash
# terminal 1
docker exec -it sysbench /scripts/bench.sh run 50 B_caida_nodo3
# terminal 2, a los ~20 s
./scripts/pruebas-fallo.sh B
```

El `--report-interval=5` de sysbench muestra el segundo exacto de la caída:
ahí se ve el bache de TPS, el pico de latencia y si hubo errores.

### 8.4 Escenario C — recuperación y resincronización

```bash
./scripts/pruebas-fallo.sh C     # mide segundos hasta estado Synced
```

En Grafana se observa el pico de I/O y de red del SST/IST durante la
reincorporación.

### 8.5 Escenario D — caída del nodo que recibe el tráfico

```bash
./scripts/pruebas-fallo.sh D     # docker kill galera1
```

**Punto conceptual a defender:** en Galera no existe un nodo primario, así que
no hay "failover de base de datos" en el sentido clásico. El failover lo
ejecuta **HAProxy**, que retira el nodo de la rotación en
`inter 2s × fall 2 ≈ 4 s`. Las conexiones ya abiertas contra ese nodo **se
cortan** (el cliente recibe error 2013 y debe reconectar); las nuevas entran a
otro nodo. No hay pérdida de datos porque todo commit confirmado ya fue
certificado por el clúster (RPO = 0).

### 8.6 Escenario E — pérdida de quórum

```bash
./scripts/pruebas-fallo.sh E     # caen 2 de 3
```

El nodo sobreviviente pasa a `Non-Primary` y rechaza consultas: es el
comportamiento correcto para evitar split-brain, no una falla. Restaurar con
`./scripts/pruebas-fallo.sh restore`.

### 8.7 Escalabilidad

La tabla que pide la cátedra se construye **quitando** nodos, no agregándolos:

```bash
docker exec -it sysbench /scripts/bench.sh run 50 esc_3nodos
docker stop galera3
docker exec -it sysbench /scripts/bench.sh run 50 esc_2nodos
docker start galera3
```

Y para separar lectura de escritura (clave para la conclusión):

```bash
docker exec -it sysbench /scripts/bench.sh read_only  50 lecturas
docker exec -it sysbench /scripts/bench.sh write_only 50 escrituras
```

### 8.8 Resultados a CSV

```bash
./scripts/resumen.sh > results/resumen.csv
```

---

## 9. Resultado esperado y limitaciones

**Lo que se espera medir** (y hay que explicar, no solo mostrar):

- Las **lecturas escalan** al agregar nodos: HAProxy reparte los `SELECT` y
  cada nodo tiene copia completa de los datos.
- Las **escrituras no escalan**, y pueden incluso empeorar: cada commit espera
  la certificación de todos los nodos, así que el clúster escribe a la
  velocidad del nodo más lento. Más nodos = más tráfico de certificación.
- Con alta concurrencia aparecen **abortos por certificación** (error 1213,
  deadlock) en round-robin, porque dos nodos pueden recibir escrituras sobre la
  misma fila. Comparar con el puerto de escritor único (`:3308`) muestra esto
  con evidencia dura: menos errores, y a veces más TPS.
- El **flow control** (`wsrep_flow_control_paused`) es el indicador de
  saturación real del clúster: cuando sube, un nodo no alcanza a aplicar los
  write-sets y frena a todos.

**Puntos únicos de falla reconocidos:**

1. **HAProxy es único.** Si cae, el servicio queda inaccesible aunque los tres
   nodos estén sanos.
2. **Una sola máquina física.** CPU, RAM, disco y kernel son compartidos: los
   nodos no son independientes de verdad.
3. El health check `mysql-check` valida que el puerto responda, no que el nodo
   esté `Synced`: un nodo en `Non-Primary` podría seguir en la rotación.

**Para llevar a producción:** HAProxy redundante con keepalived + VIP (o
ProxySQL / MaxScale con detección de estado Galera), nodos en hosts físicos
distintos, health check por script `clustercheck` que lea `wsrep_local_state`,
TLS en las conexiones y en la replicación, backups automatizados con
mariabackup y retención, y `innodb_flush_log_at_trx_commit=1` (acá está en 2
para el laboratorio).
