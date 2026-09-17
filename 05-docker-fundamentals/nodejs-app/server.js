// Minimal Hello World HTTP server using only Node's built-in http module.
const http = require('http');
const PORT = process.env.PORT || 3000;

const server = http.createServer((req, res) => {
  res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
  res.end(
    '<!DOCTYPE html><html>' +
    '<head><title>Hello World - Node.js</title></head>' +
    '<body><h1>Hello World from Node.js</h1>' +
    `<p>Node ${process.version} on port ${PORT}, path ${req.url}</p>` +
    '</body></html>'
  );
  console.log(`[nodejs-app] ${req.method} ${req.url}`);
});

server.listen(PORT, '0.0.0.0', () => {
  console.log(`[nodejs-app] listening on 0.0.0.0:${PORT}`);
});
