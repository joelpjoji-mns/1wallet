import http from 'node:http';
import { createReadStream } from 'node:fs';
import { stat } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = fileURLToPath(new URL('../build/prototype/', import.meta.url));
const port = Number(process.argv[2] ?? 4173);
if (!Number.isInteger(port) || port < 1 || port > 65535) {
  throw new Error('Provide a port between 1 and 65535.');
}
await stat(path.join(root, 'index.html'));
const mime = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.mjs': 'text/javascript; charset=utf-8',
  '.json': 'application/json',
  '.css': 'text/css; charset=utf-8',
  '.wasm': 'application/wasm',
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
  '.svg': 'image/svg+xml',
  '.ttf': 'font/ttf',
  '.woff2': 'font/woff2',
};

const server = http.createServer(async (request, response) => {
  if (!['GET', 'HEAD'].includes(request.method)) {
    response.writeHead(405, { Allow: 'GET, HEAD' }).end('Method not allowed');
    return;
  }
  let pathname;
  try {
    pathname = decodeURIComponent(new URL(request.url, 'http://localhost').pathname);
  } catch (error) {
    console.error('Invalid request URL:', error.message);
    response.writeHead(400).end('Invalid URL');
    return;
  }
  const file = path.resolve(root, `.${pathname}`, pathname.endsWith('/') ? 'index.html' : '');
  const relative = path.relative(root, file);
  if (relative.startsWith('..') || path.isAbsolute(relative) || pathname.includes('\0')) {
    response.writeHead(403).end('Forbidden');
    return;
  }
  try {
    const info = await stat(file);
    if (!info.isFile()) {
      response.writeHead(404).end('File not found');
      return;
    }
    response.writeHead(200, {
      'Content-Type': mime[path.extname(file)] ?? 'application/octet-stream',
      'Content-Length': info.size,
      'Cache-Control': 'no-store',
    });
    if (request.method === 'HEAD') {
      response.end();
      return;
    }
    const stream = createReadStream(file);
    stream.on('error', (error) => {
      console.error('Failed to serve file:', error);
      response.destroy(error);
    });
    stream.pipe(response);
  } catch (error) {
    if (['ENOENT', 'ENOTDIR'].includes(error.code)) {
      response.writeHead(404).end('File not found');
      return;
    }
    console.error('Prototype server error:', error);
    response.writeHead(500).end('Could not read file');
  }
});
server.on('error', (error) => {
  console.error('Prototype server failed:', error);
  process.exitCode = 1;
});
server.listen(port, '127.0.0.1', () => {
  console.log(`1Wallet Screen Studio: http://127.0.0.1:${port}`);
});
