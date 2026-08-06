FROM node:20-slim

WORKDIR /app

COPY package.json package-lock.json ./
RUN npm ci

COPY . .

# BACKEND_INTERNAL_URL (server-to-server proxy target for next.config.ts's
# rewrites()) MUST be a build arg, not a docker-compose runtime env var:
# `next build` resolves rewrites() once and freezes the result into
# routes-manifest.json / required-server-files.json -- `next start` never
# re-evaluates it, so setting this only at `docker run` time silently has
# no effect (confirmed the hard way: the frontend container proxied to a
# baked-in "localhost:8000" default no matter what docker-compose.yml's
# `environment:` said).
ARG BACKEND_INTERNAL_URL=http://backend:8000
ENV BACKEND_INTERNAL_URL=${BACKEND_INTERNAL_URL}
RUN npm run build

EXPOSE 3000
CMD ["npm", "start"]
