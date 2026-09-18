#!/bin/bash
# Volcado logico del cluster a ./backups/ (ejecutar desde la raiz del repo).
set -e
set -a; . ./.env; set +a
F="backups/${APP_DB}_$(date +%Y%m%d_%H%M%S).sql"
docker exec galera1 mariadb-dump -uadministrador -p"$ADMIN_PASSWORD" \
  --single-transaction --routines --triggers "$APP_DB" > "$F"
echo ">> backup: $F ($(du -h "$F" | cut -f1))"
