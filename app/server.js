const http = require('http');

const PORT = process.env.PORT || 8080;

const server = http.createServer((req, res) => {
  // Health check endpoint para o ALB
  if (req.url === '/health' || req.url === '/') {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({
      status: 'UP',
      app: 'OSPCT Cloud App',
      version: '1.0.0',
      message: 'Deploy automatizado via GitHub Actions e AWS ECR com sucesso!',
      environment: process.env.ENVIRONMENT || 'production',
      database: process.env.DB_NAME ? 'Conectado ao catálogo de segredos' : 'N/A',
      timestamp: new Date().toISOString()
    }, null, 2));
    return;
  }

  res.writeHead(404, { 'Content-Type': 'text/plain' });
  res.end('Not Found');
});

server.listen(PORT, '0.0.0.0', () => {
  console.log(`🚀 Servidor OSPCT rodando na porta ${PORT}`);
});
