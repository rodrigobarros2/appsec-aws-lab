# Imagem fixada por versão e digest; build em dois estágios; roda sem root e
# sem npm/corepack na imagem final (menos superfície de ataque).
FROM node:22.23.5-alpine3.24@sha256:d6e6d1cae4ed0cda2dc336db1bbea6457c2b5d2a8bcd9ac1d80b909fe1c4f638 AS deps
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci --omit=dev --ignore-scripts

FROM node:22.23.5-alpine3.24@sha256:d6e6d1cae4ed0cda2dc336db1bbea6457c2b5d2a8bcd9ac1d80b909fe1c4f638
RUN rm -rf /usr/local/lib/node_modules/npm /usr/local/lib/node_modules/corepack \
      /usr/local/bin/npm /usr/local/bin/npx /usr/local/bin/corepack
ENV NODE_ENV=production HOST=0.0.0.0 PORT=8080
WORKDIR /app
COPY --from=deps --chown=1000:1000 /app/node_modules ./node_modules
COPY --chown=1000:1000 package.json ./
COPY --chown=1000:1000 src ./src
USER 1000:1000
EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=3s CMD ["node", "-e", "fetch('http://127.0.0.1:8080/saude').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"]
CMD ["node", "src/server.mjs"]
