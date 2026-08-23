// Start the Express backend behind Kong.
const express = require('express');
const app = express();
const PORT = process.env.PORT || 5000;

// Limit request body size.
app.use(express.json({ limit: '10kb' }));

// Serve health checks without authentication.
app.get('/health', (req, res) => {
  res.json({
    status: 'ok',
    message: 'Service is running'
  });
});

app.get('/api/ping', (req, res) => {
  res.json({
    message: 'hello from app',
    status: 'ok'
  });
});

app.get('/api/hello', (req, res) => {
  const name = req.query.name || 'World';
  res.json({
    message: `Hello, ${name}!`,
    status: 'ok'
  });
});

app.get('/api/data', (req, res) => {
  res.json({
    status: 'ok',
    data: [
      { id: 1, name: 'Item A' },
      { id: 2, name: 'Item B' },
      { id: 3, name: 'Item C' }
    ]
  });
});

app.use((req, res) => {
  res.status(404).json({
    error: 'Not Found',
    status: 'error'
  });
});

// Return JSON for application errors.
app.use((err, req, res, next) => {
  if (err.type === 'entity.parse.failed') {
    return res.status(400).json({ error: 'Malformed JSON body', status: 'error' });
  }
  if (err.type === 'entity.too.large') {
    return res.status(413).json({ error: 'Payload too large', status: 'error' });
  }
  console.error(err.stack);
  res.status(500).json({
    error: 'Internal Server Error',
    status: 'error'
  });
});

const server = app.listen(PORT, '0.0.0.0', () => {
  console.log(`Backend service listening on port ${PORT}`);
});

// Shut down gracefully.
function shutdown(signal) {
  console.log(`${signal} received, closing server`);
  server.close(() => process.exit(0));
  setTimeout(() => {
    console.error('Forced shutdown after timeout');
    process.exit(1);
  }, 10000).unref();
}

process.on('SIGTERM', () => shutdown('SIGTERM'));
process.on('SIGINT', () => shutdown('SIGINT'));

process.on('unhandledRejection', (reason) => {
  console.error('Unhandled rejection:', reason);
});

process.on('uncaughtException', (err) => {
  console.error('Uncaught exception:', err);
  shutdown('uncaughtException');
});

