#!/bin/sh
set -eu

# =============================================================
# Sustituir variables de entorno en la plantilla de nginx
# y escribir la config final. Esto permite cambiar BACKEND_HOST
# sin reconstruir la imagen → mismo artefacto en dev y prod.
# =============================================================

: "${BACKEND_HOST:?BACKEND_HOST no definido}"
: "${BACKEND_PORT:=3001}"

echo "[entrypoint] Generando /etc/nginx/conf.d/default.conf con BACKEND_HOST=${BACKEND_HOST} BACKEND_PORT=${BACKEND_PORT}"

envsubst '${BACKEND_HOST} ${BACKEND_PORT}' \
  < /etc/nginx/templates/default.conf.template \
  > /etc/nginx/conf.d/default.conf

# Validar sintaxis antes de arrancar
nginx -t

# Ejecutar el CMD recibido (nginx -g 'daemon off;')
exec "$@"
