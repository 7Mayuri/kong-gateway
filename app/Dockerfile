# Small Node image keeps the backend container lightweight.
FROM node:18-alpine

WORKDIR /app

COPY package*.json ./
RUN npm install --omit=dev

COPY server.js .

# Drop root; the app only ever reads these files.
USER node

EXPOSE 5000

HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD node -e "require('http').get('http://localhost:5000/health', (r) => {if (r.statusCode !== 200) throw new Error(r.statusCode)})" || exit 1

# Exec node directly so it is PID 1 and receives SIGTERM for graceful shutdown.
CMD ["node", "server.js"]


