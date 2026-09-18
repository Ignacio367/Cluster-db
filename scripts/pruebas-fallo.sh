#!/bin/bash
# Escenarios B, C y D. Ejecutar desde la raiz del repo, con carga corriendo en paralelo.
#
#   Terminal 1:  docker exec -it sysbench /scripts/bench.sh run 50 B_caida_nodo3
#   Terminal 2:  ./scripts/pruebas-fallo.sh B
#
set -a; . ./.env; set +a

estado_nodo () {
  docker exec "$1" mariadb -uroot -p"$ROOT_PASSWORD" -N -B -e \
    "SHOW STATUS WHERE Variable_name IN ('wsrep_cluster_size','wsrep_local_state_comment');" 2>/dev/null \
    || echo "$1 no responde"
}

case "${1:-}" in

  B) # --- un secundario fuera de servicio (parada ordenada)
     echo "[$(date +%T)] deteniendo galera3..."
     docker stop galera3
     sleep 5
     estado_nodo galera1
     echo ">> Mirar el reporte por intervalo de sysbench: ahi se ve el bache de TPS."
     ;;

  C) # --- recuperacion y resincronizacion (medir tiempo hasta SYNCED)
     echo "[$(date +%T)] iniciando galera3..."
     T0=$(date +%s)
     docker start galera3
     while true; do
       EST=$(docker exec galera3 mariadb -uroot -p"$ROOT_PASSWORD" -N -B -e \
             "SHOW STATUS LIKE 'wsrep_local_state_comment';" 2>/dev/null | awk '{print $2}')
       echo "[$(date +%T)] estado galera3: ${EST:-arrancando}"
       [ "$EST" = "Synced" ] && break
       sleep 2
     done
     echo ">> Tiempo de resincronizacion: $(( $(date +%s) - T0 )) segundos"
     ;;

  D) # --- caida abrupta del nodo que recibe el trafico (failover de HAProxy)
     echo "[$(date +%T)] matando galera1 (kill, no stop: simula corte real)..."
     docker kill galera1
     sleep 3
     estado_nodo galera2
     echo ">> En Galera no hay primario: el failover lo hace HAProxy al retirar el nodo"
     echo ">> de la rotacion (inter 2s / fall 2 => ~4 s). Ver panel http://localhost:8404"
     ;;

  E) # --- perdida de quorum (2 de 3 nodos caidos)
     echo "[$(date +%T)] deteniendo galera2 y galera3: se pierde el quorum..."
     docker stop galera2 galera3
     sleep 5
     echo ">> galera1 deberia quedar NO operativo (Non-Primary) para evitar split-brain:"
     estado_nodo galera1
     ;;

  restore)
     docker start galera1 galera2 galera3 2>/dev/null
     sleep 20; ./scripts/estado.sh
     ;;

  *) echo "uso: $0 {B|C|D|E|restore}"; exit 1 ;;
esac
