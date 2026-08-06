FROM node:20-slim

WORKDIR /app

COPY package.json package-lock.json ./
RUN npm ci

COPY . .

# BACKEND_INTERNAL_URL (server-to-server proxy target for next.config.ts's
# rewrites(), read at server start, not baked into the client bundle) is
# passed as a runtime env var by docker-compose.yml, not set here.
RUN npm run build

EXPOSE 3000
CMD ["npm", "start"]
