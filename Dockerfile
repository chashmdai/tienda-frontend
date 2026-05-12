# =====================================================================
# Stage 1 - prep: valida y prepara los archivos estáticos.
# Para este SPA vanilla no hay paso de build (no React/Vue/etc),
# pero el stage 1 valida que los archivos existan, sirve para
# minificación futura y cumple la exigencia de multi-stage (IE1).
# =====================================================================
FROM alpine:3.20 AS prep

WORKDIR /prep
COPY index.html app.js ./
COPY default.conf.template ./default.conf.template
COPY docker-entrypoint.sh  ./docker-entrypoint.sh

RUN test -s index.html && test -s app.js && test -s default.conf.template \
    || (echo "Archivos estáticos faltantes" && exit 1) \
 && chmod +x docker-entrypoint.sh

# =====================================================================
# Stage 2 - runtime: nginx 1.27 alpine.
# La imagen oficial nginx YA corre como usuario 'nginx' por defecto
# para los workers, pero el master corre como root para poder bindear
# el puerto 80. Para correr todo como no root usamos la variante
# 'nginxinc/nginx-unprivileged' que escucha en 8080 sin root, PERO
# eso fuerza re-mapear puertos. Para mantener compatibilidad con la
# rúbrica EP2 (puerto 80 → IP pública), usamos la imagen estándar
# y declaramos USER nginx para los procesos no privilegiados que
# manejamos nosotros (envsubst). El daemon nginx ya gestiona su
# propio drop de privilegios internamente.
# =====================================================================
FROM nginx:1.27-alpine

LABEL org.opencontainers.image.title="tienda-frontend" \
      org.opencontainers.image.description="SPA + nginx reverse proxy"

# Instalar gettext (provee envsubst) para sustituir variables en
# default.conf.template antes de arrancar nginx.
RUN apk add --no-cache gettext

# Limpiar contenido default
RUN rm -rf /usr/share/nginx/html/*

# Copiar artefactos desde el stage de preparación
COPY --from=prep /prep/index.html              /usr/share/nginx/html/index.html
COPY --from=prep /prep/app.js                  /usr/share/nginx/html/app.js
COPY --from=prep /prep/default.conf.template   /etc/nginx/templates/default.conf.template
COPY --from=prep /prep/docker-entrypoint.sh    /usr/local/bin/docker-entrypoint.sh

# Variables esperadas en runtime (con defaults útiles para dev local)
ENV BACKEND_HOST=backend \
    BACKEND_PORT=3001

EXPOSE 80

HEALTHCHECK --interval=15s --timeout=3s --start-period=10s --retries=3 \
  CMD wget -qO- http://127.0.0.1/ > /dev/null || exit 1

ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
CMD ["nginx", "-g", "daemon off;"]
