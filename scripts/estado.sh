#!/bin/bash
# Muestra el estado del cluster. Uso: ./scripts/estado.sh
# ejecutar desde la raiz del repo
set -a; . ./.env; set +a

for n in galera1 galera2 galera3; do
  echo "--------------------------------------------- $n"
  docker exec "$n" mariadb -uroot -p"$ROOT_PASSWORD" -N -B -e "
    SHOW STATUS WHERE Variable_name IN
    ('wsrep_cluster_size','wsrep_cluster_status','wsrep_local_state_comment',
     'wsrep_ready','wsrep_connected','wsrep_flow_control_paused',
     'wsrep_local_send_queue_avg','wsrep_local_recv_queue_avg');" 2>/dev/null \
    || echo "  (nodo caido / no responde)"
done
echo
echo "Panel HAProxy: http://localhost:8404   |  Adminer: http://localhost:8080"
