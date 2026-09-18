#!/bin/bash
# Escenario A completo: 10/25/50/100/200 clientes x 3 repeticiones.
# Uso (desde el host):  docker exec -it sysbench /scripts/barrido.sh A_todos_ok
set -e
ETIQUETA=${1:-A_todos_ok}
for t in 10 25 50 100 200; do
  for r in 1 2 3; do
    /scripts/bench.sh run "$t" "${ETIQUETA}_r${r}"
    sleep 10   # deja que el cluster se estabilice entre corridas
  done
done
echo ">> Barrido terminado. Resultados en ./results/"
