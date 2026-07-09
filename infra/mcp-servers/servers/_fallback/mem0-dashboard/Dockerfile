# Mem0 Dashboard — Official Next.js web UI
#
# Builds from the mem0 monorepo's server/dashboard directory.
# One-time heavy build (~1GB docker layer), cached after first run.
#
# See: https://github.com/mem0ai/mem0/tree/main/server/dashboard

FROM node:20-alpine AS builder

WORKDIR /src

# Set NEXT_PUBLIC_* at build time so they are baked into the bundle.
# No runtime env replacement needed — avoids breaking minified JS.
ENV NEXT_PUBLIC_API_URL=http://localhost:8888
ENV NEXT_PUBLIC_INSTANCE_NAME=Mem0

# Shallow clone only the dashboard source (smaller than full repo)
RUN apk add --no-cache git && \
    git clone --depth 1 --filter=blob:none https://github.com/mem0ai/mem0.git . && \
    cd server/dashboard && \
    npm install --legacy-peer-deps && \
    npm run build

# ─── Runtime ─────────────────────────────────────────────────────────────────
FROM node:20-alpine

RUN addgroup --system --gid 1001 nodejs && \
    adduser --system --uid 1001 nextjs

WORKDIR /app

COPY --from=builder --chown=nextjs:nodejs /src/server/dashboard/public ./public
COPY --from=builder --chown=nextjs:nodejs /src/server/dashboard/.next/standalone ./
COPY --from=builder --chown=nextjs:nodejs /src/server/dashboard/.next/static ./.next/static

USER nextjs

EXPOSE 3000
ENV PORT=3000
ENV HOSTNAME="0.0.0.0"
ENV NEXT_TELEMETRY_DISABLED=1

CMD ["node", "server.js"]