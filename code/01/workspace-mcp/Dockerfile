FROM node:22-alpine AS build

ARG NPM_CONFIG_REGISTRY=https://packagefeedproxy.microsoft.io/npm/
ENV NPM_CONFIG_REGISTRY=${NPM_CONFIG_REGISTRY}
ENV NPM_CONFIG_REPLACE_REGISTRY_HOST=registry.npmjs.org
ENV NPM_CONFIG_OMIT_LOCKFILE_REGISTRY_RESOLVED=true
ENV NPM_CONFIG_ALLOW_REMOTE=all

WORKDIR /app
COPY package.json package-lock.json .npmrc ./
RUN npm ci
COPY tsconfig.json ./
COPY src ./src
COPY test ./test
COPY fixture ./fixture
RUN npm run build && npm prune --omit=dev

FROM node:22-alpine

RUN apk add --no-cache git
WORKDIR /app
COPY --from=build --chown=node:node /app/package.json /app/package-lock.json ./
COPY --from=build --chown=node:node /app/node_modules ./node_modules
COPY --from=build --chown=node:node /app/dist ./dist
COPY --from=build --chown=node:node /app/fixture ./fixture

RUN mkdir -p /workspace/repo && chown -R node:node /workspace
USER node

ENV NODE_ENV=production
ENV PORT=8931
EXPOSE 8931

HEALTHCHECK --interval=10s --timeout=3s --retries=6 \
  CMD wget -qO- http://127.0.0.1:8931/healthz >/dev/null || exit 1

CMD ["node", "dist/src/server.js"]
