# Scripts de operación (Windows, ejecutar desde la raíz del repo)

Envuelven los comandos largos de `docker exec` y `sysbench`. Ninguno contiene
contraseñas: las leen los contenedores desde sus variables de entorno (`.env`).

| Script | Qué hace |
|---|---|
| `scripts\reset.bat` | Borra todo, levanta el clúster desde cero y carga 1.000.000 de filas (~7 min) |
| `scripts\levantar.bat` | Arranque en frío conservando datos (bootstrap + recrea galera1 sin bootstrap) |
| `scripts\apagar.bat` | Apagado ordenado (galera1 sale último → `safe_to_bootstrap: 1`) |
| `scripts\estado.bat [nodo]` | `wsrep_cluster_size`, `status`, `local_state`, `ready` |
| `scripts\replicacion.bat [w] [r]` | Escribe en un nodo y lee en otro al instante |
| `scripts\bench.bat [clientes] [rr/escritor] [seg]` | sysbench vía HAProxy, guarda en `results\` |
| `scripts\preparar.bat` | Solo la carga de datos |

Las fallas se provocan con los comandos de Docker, que ya son cortos:
`docker stop galera3`, `docker start galera3`, `docker kill galera1`, `docker start galera1`.
