# tienda-frontend

SPA estática + nginx reverse proxy. Es el **único** componente expuesto
a internet en la arquitectura EP2; oculta el backend en la subred
privada haciendo de bridge para las llamadas `/api/*`.

## Stack

- HTML + CSS + JS vanilla (sin build step de framework)
- nginx 1.27 alpine
- envsubst (sustitución de variables en runtime)

## Estructura

```
.
├── Dockerfile                 # multi-stage (prep + nginx)
├── default.conf.template      # config nginx parametrizada
├── docker-entrypoint.sh       # envsubst → nginx -t → nginx -g
├── index.html                 # markup
├── app.js                     # fetch a /api/productos (ruta relativa)
├── docker-compose.yml         # stack e2e local (front + back + db)
├── .dockerignore
├── .env.example
└── .github/workflows/cicd.yml
```

## Cómo funciona el reverse proxy (IE9)

1. El navegador del usuario solo conoce la **IP pública** de la EC2
   frontend.
2. `app.js` hace `fetch('/api/productos')` — ruta **relativa**, mismo
   origen.
3. nginx en el contenedor recibe `/api/*` y lo proxea a
   `http://${BACKEND_HOST}:${BACKEND_PORT}`, donde `BACKEND_HOST` es la
   IP privada de la EC2-backend (inyectada por env var).
4. El backend recibe la petición desde la subred privada. La conexión
   directa navegador → backend es **imposible** (SG cerrado y sin IP
   pública).

Beneficios:
- **Cero IPs hardcoded** en el bundle JS.
- **Cero CORS**: el navegador habla con un solo origen.
- Rotar la IP del backend solo requiere actualizar el secret
  `BACKEND_HOST` y re-correr el deploy del frontend.

## Variables de entorno

| Variable        | Default   | Descripción                          |
|-----------------|-----------|--------------------------------------|
| `BACKEND_HOST`  | `backend` | IP privada o nombre DNS del backend  |
| `BACKEND_PORT`  | `3001`    | Puerto del backend                   |

## Desarrollo local

```bash
cp .env.example .env
# Editar las credenciales DB para el stack local

docker compose up --build -d
open http://localhost
```

El compose levanta los 3 contenedores y enlaza nginx → backend → db.

## Pipeline CI/CD

- Trigger: `push` en rama `deploy`.
- Pasos: checkout → AWS creds → ECR login → build + push → SSM deploy.

### GitHub Secrets

| Secret                       | Valor                                  |
|------------------------------|----------------------------------------|
| `AWS_ACCESS_KEY_ID`          | Credencial temporal Learner Lab        |
| `AWS_SECRET_ACCESS_KEY`      | Credencial temporal Learner Lab        |
| `AWS_SESSION_TOKEN`          | Token Learner Lab (vence 4h)           |
| `EC2_FRONTEND_INSTANCE_ID`   | ID EC2 frontend                        |
| `BACKEND_HOST`               | IP privada EC2-backend                 |
| `BACKEND_PORT`               | `3001`                                 |

## Decisiones técnicas

### Multi-stage Dockerfile (IE1)

- **Stage 1 (prep)**: alpine ligero. Valida que los archivos existan
  y marca el entrypoint como ejecutable.
- **Stage 2 (runtime)**: nginx 1.27 alpine. Solo recibe los artefactos
  validados del stage anterior.

### `default.conf.template` + envsubst

El archivo de configuración nginx vive como **plantilla** y se renderiza
al arrancar el contenedor. Esto desacopla la imagen (mismo bit-a-bit
en dev y prod) de la configuración de runtime.

El entrypoint:
1. Verifica que `BACKEND_HOST` esté definido.
2. Ejecuta `envsubst` sobre la plantilla.
3. Valida sintaxis con `nginx -t`.
4. Pasa control a `nginx -g 'daemon off;'`.

## Seguridad

- Instancia EC2 en subred pública con IP elástica.
- Security Group: ingress 80/tcp 0.0.0.0/0 (público) + 22/tcp solo
  desde IP de admin (o eliminado si se usa SSM Session Manager).
- Egress hacia subred privada solo en puerto 3001/tcp del SG-backend.
- Nginx workers ya corren como usuario `nginx` no root.
