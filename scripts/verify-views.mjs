import { spawn } from 'child_process';
import fs from 'fs';
import path from 'path';

const outDir = '/Users/ianmora/.gemini/antigravity/brain/3fd275b4-baf8-48a3-a48b-20e70f8620d4';
const chromePath = '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
const port = 9333;

const chrome = spawn(chromePath, [
  `--remote-debugging-port=${port}`,
  '--headless=new',
  '--disable-gpu',
  '--disable-extensions',
  '--window-size=1280,900',
  '--no-first-run',
  '--no-default-browser-check',
  'about:blank'
]);

chrome.stderr.on('data', () => {});

async function wait(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

async function run() {
  await wait(1500);

  let wsUrl = null;
  for (let i = 0; i < 15; i++) {
    try {
      const res = await fetch(`http://127.0.0.1:${port}/json`);
      const tabs = await res.json();
      const pageTab = tabs.find((t) => t.type === 'page');
      if (pageTab && pageTab.webSocketDebuggerUrl) {
        wsUrl = pageTab.webSocketDebuggerUrl;
        break;
      }
    } catch (e) {
      await wait(500);
    }
  }

  if (!wsUrl) {
    console.error('Failed to get WebSocket debugger URL for page');
    chrome.kill();
    process.exit(1);
  }

  const ws = new WebSocket(wsUrl);
  let id = 1;
  const callbacks = new Map();

  ws.onmessage = (event) => {
    const msg = JSON.parse(event.data);
    if (msg.id && callbacks.has(msg.id)) {
      callbacks.get(msg.id)(msg.result, msg.error);
      callbacks.delete(msg.id);
    }
  };

  function send(method, params = {}) {
    return new Promise((resolve, reject) => {
      const msgId = id++;
      callbacks.set(msgId, (result, error) => {
        if (error) reject(error);
        else resolve(result);
      });
      ws.send(JSON.stringify({ id: msgId, method, params }));
    });
  }

  await new Promise((resolve) => ws.onopen = resolve);

  await send('Page.enable');
  await send('Runtime.enable');

  console.log('Navigating to http://localhost:8080 ...');
  await send('Page.navigate', { url: 'http://localhost:8080' });
  await wait(2500);

  // Force all reveal elements visible for clear screenshots
  await send('Runtime.evaluate', {
    expression: `
      document.querySelectorAll('.reveal').forEach(el => el.classList.add('visible'));
      if (window.ScrollTrigger) ScrollTrigger.refresh();
    `
  });

  const targets = [
    { id: '#architecture', name: 'dark_arch_view.png' },
    { id: '#roadmap', name: 'dark_roadmap_view.png' },
    { id: '#privacy-pool', name: 'dark_pool_view.png' },
    { id: '#tokenomics', name: 'dark_tokenomics_view.png' },
    { id: '#governance', name: 'dark_gov_view.png' }
  ];

  for (const t of targets) {
    console.log(`Scrolling to ${t.id} ...`);
    await send('Runtime.evaluate', {
      expression: `
        (() => {
          const el = document.querySelector('${t.id}');
          if (el) {
            const y = el.getBoundingClientRect().top + window.pageYOffset - 50;
            window.scrollTo({ top: y, behavior: 'instant' });
          }
        })()
      `
    });
    await wait(1000);

    const shot = await send('Page.captureScreenshot', { format: 'png' });
    const buf = Buffer.from(shot.data, 'base64');
    const dest = path.join(outDir, t.name);
    fs.writeFileSync(dest, buf);
    console.log(`Saved ${t.name} (${buf.length} bytes)`);
  }

  ws.close();
  chrome.kill();
  console.log('Done!');
  process.exit(0);
}

run().catch((err) => {
  console.error(err);
  chrome.kill();
  process.exit(1);
});
