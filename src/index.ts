import { Hono } from 'hono';

const app = new Hono();

app.get('/', (c) => c.text('Hello World!'));

// Cloudflare Workers के लिए, serve() की जरूरत नहीं - export default करें
export default app;
