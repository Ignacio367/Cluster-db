#!/bin/bash
# Benchmark sysbench contra el cluster. Se ejecuta DENTRO del contenedor sysbench:
#   docker exec -it sysbench /scripts/bench.sh prepare
#   docker exec -it sysbench /scripts/bench.sh run 50 A_todos_ok
#   docker exec -it sysbench /scripts/bench.sh cleanup
set -e

ACCION=${1:-run}
THREADS=${2:-50}
ETIQUETA=${3:-sin_etiqueta}

HOST=${BENCH_HOST:-haproxy}
PORT=${BENCH_PORT:-3306}
TABLES=${BENCH_TABLES:-10}
SIZE=${BENCH_TABLE_SIZE:-100000}
TIME=${BENCH_TIME:-60}

COMUN="--db-driver=mysql --mysql-host=$HOST --mysql-port=$PORT \
--mysql-user=bench --mysql-password=$BENCH_PASSWORD --mysql-db=sbtest \
--tables=$TABLES --table-size=$SIZE"

case "$ACCION" in
  prepare) sysbench oltp_common $COMUN --threads=8 prepare ;;
  cleanup) sysbench oltp_common $COMUN cleanup ;;
  run)
    OUT="/results/${ETIQUETA}_t${THREADS}_$(date +%H%M%S).txt"
    echo ">> $ETIQUETA | threads=$THREADS | host=$HOST:$PORT -> $OUT"
    sysbench oltp_read_write $COMUN \
      --threads="$THREADS" --time="$TIME" --report-interval=5 \
      --mysql-ignore-errors=1213,1205,1180,2013,2006 \
      run | tee "$OUT"
    ;;
  read_only)
    OUT="/results/${ETIQUETA}_RO_t${THREADS}_$(date +%H%M%S).txt"
    sysbench oltp_read_only $COMUN --threads="$THREADS" --time="$TIME" \
      --report-interval=5 run | tee "$OUT"
    ;;
  write_only)
    OUT="/results/${ETIQUETA}_WO_t${THREADS}_$(date +%H%M%S).txt"
    sysbench oltp_write_only $COMUN --threads="$THREADS" --time="$TIME" \
      --report-interval=5 --mysql-ignore-errors=1213,1205,1180 run | tee "$OUT"
    ;;
  *) echo "acciones: prepare | run | read_only | write_only | cleanup"; exit 1 ;;
esac
