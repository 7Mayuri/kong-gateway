// Minimal Express backend sitting behind the Kong gateway.
const express = require('express');
const app = express();
const PORT = process.env.PORT || 5000;

app.use(express.json());

// Used by Docker/Kong health checks, no auth required.
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

app.use((err, req, res, next) => {
  console.error(err.stack);
  res.status(500).json({
    error: 'Internal Server Error',
    status: 'error'
  });
});

app.listen(PORT, '0.0.0.0', () => {
  console.log(`Backend service listening on port ${PORT}`);
});

