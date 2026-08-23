# Small Node image keeps the backend container lightweight.
FROM node:18-alpine

WORKDIR /app

COPY package*.json ./
RUN npm install --omit=dev

COPY server.js .

# Drop root; the app only ever reads these files.
USER node

EXPOSE 5000

# No curl in this image, so probe with node. Use 127.0.0.1 because "localhost"
# resolves to ::1 here while the server binds IPv4; resume() frees the socket so it exits.
HEALTHCHECK --interval=10s --timeout=3s --start-period=5s --retries=3 \
    CMD node -e "require('http').get('http://127.0.0.1:5000/health',r=>{r.resume();process.exit(r.statusCode===200?0:1)}).on('error',()=>process.exit(1))"

# Exec node directly so it is PID 1 and receives SIGTERM for graceful shutdown.
CMD ["node", "server.js"]


