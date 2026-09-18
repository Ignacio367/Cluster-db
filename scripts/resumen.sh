#!/bin/bash
# Convierte los .txt de sysbench en un CSV listo para tablas/graficos del informe.
# Uso (desde el host):  ./scripts/resumen.sh > results/resumen.csv
echo "archivo,threads,tps,qps,lat_avg_ms,lat_p95_ms,errores"
for f in results/*.txt; do
  [ -e "$f" ] || continue
  th=$(grep -m1 'Number of threads:' "$f" | awk '{print $NF}')
  tps=$(grep -m1 'transactions:' "$f" | sed 's/.*(\(.*\) per sec.*/\1/')
  qps=$(grep -m1 'queries:' "$f" | sed 's/.*(\(.*\) per sec.*/\1/')
  avg=$(grep -m1 'avg:' "$f" | awk '{print $2}')
  p95=$(grep -m1 '95th percentile:' "$f" | awk '{print $3}')
  err=$(grep -m1 'ignored errors:' "$f" | awk '{print $3}')
  echo "$(basename "$f"),$th,$tps,$qps,$avg,$p95,$err"
done
