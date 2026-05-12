# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.
# Frontend Dockerfile — Multi-stage build for sovereign-chat-experience-starter UI
# Builds the Vite/React app and serves via nginx

FROM mcr.microsoft.com/azurelinux/base/nodejs:20 AS builder

WORKDIR /app
COPY package*.json ./
RUN npm ci
COPY . .

ARG VITE_API_URL=/api
ARG VITE_BASE_PATH=/
ENV VITE_API_URL=${VITE_API_URL}
ENV VITE_BASE_PATH=${VITE_BASE_PATH}

RUN echo ">>> Building with VITE_API_URL=${VITE_API_URL}"

RUN npm run build

FROM mcr.microsoft.com/azurelinux/base/nginx:1 AS production

# Inline nginx config — SPA routing with health endpoint
# Azure Linux nginx doesn't have conf.d/ by default, so write full config
RUN printf '\
worker_processes auto;\n\
events { worker_connections 1024; }\n\
http {\n\
    include /etc/nginx/mime.types;\n\
    default_type application/octet-stream;\n\
    types_hash_max_size 2048;\n\
    access_log /dev/stdout;\n\
    error_log /dev/stderr;\n\
    sendfile on;\n\
    keepalive_timeout 65;\n\
\n\
    server {\n\
        listen 80;\n\
        root /usr/share/nginx/html;\n\
        index index.html;\n\
\n\
        location /health {\n\
            access_log off;\n\
            return 200 "ok";\n\
            add_header Content-Type text/plain;\n\
        }\n\
\n\
        location / {\n\
            try_files $uri $uri/ /index.html;\n\
        }\n\
\n\
        location ~* \\.(js|css|png|jpg|jpeg|gif|ico|svg|woff2?)$ {\n\
            expires 1y;\n\
            add_header Cache-Control "public, immutable";\n\
        }\n\
    }\n\
}\n' > /etc/nginx/nginx.conf

COPY --from=builder /app/dist /usr/share/nginx/html
COPY docker-entrypoint.sh /docker-entrypoint.sh
RUN chmod +x /docker-entrypoint.sh

EXPOSE 80

HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD curl -sf http://localhost:80/health || exit 1

ENTRYPOINT ["/docker-entrypoint.sh"]
