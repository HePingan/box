const http = require('http');
const WebSocket = require('ws');

function getJson(url) {
  return new Promise((resolve, reject) => {
    http.get(url, (res) => {
      let data = '';
      res.on('data', (chunk) => data += chunk);
      res.on('end', () => resolve(JSON.parse(data)));
    }).on('error', reject);
  });
}

(async () => {
  const tabs = await getJson('http://127.0.0.1:9223/json');
  const tab = tabs.find(t => (t.url || '').includes('127.0.0.1:8080')) || tabs[0];
  console.log('TAB', tab.id, tab.url);
  const ws = new WebSocket(tab.webSocketDebuggerUrl);
  let id = 0;
  const pending = new Map();
  function send(method, params = {}) {
    return new Promise((resolve, reject) => {
      const msg = {id: ++id, method, params};
      pending.set(id, {resolve, reject, method});
      ws.send(JSON.stringify(msg));
    });
  }
  ws.on('message', (raw) => {
    const msg = JSON.parse(raw);
    if (msg.id && pending.has(msg.id)) {
      const p = pending.get(msg.id); pending.delete(msg.id);
      if (msg.error) p.reject(new Error(JSON.stringify(msg.error)));
      else p.resolve(msg.result);
      return;
    }
    if (msg.method === 'Runtime.consoleAPICalled') {
      const args = (msg.params.args || []).map(a => a.value || a.description || a.unserializableValue || '').join(' ');
      console.log('CONSOLE', msg.params.type, args);
      if (msg.params.stackTrace) console.log('STACK', JSON.stringify(msg.params.stackTrace, null, 2));
    }
    if (msg.method === 'Runtime.exceptionThrown') {
      console.log('EXCEPTION', JSON.stringify(msg.params.exceptionDetails, null, 2));
    }
    if (msg.method === 'Log.entryAdded') {
      console.log('LOG', JSON.stringify(msg.params.entry, null, 2));
    }
  });
  await new Promise(resolve => ws.on('open', resolve));
  await send('Runtime.enable');
  await send('Log.enable');
  await send('Page.enable');
  await send('Runtime.evaluate', {expression: 'localStorage.clear(); sessionStorage.clear(); true'}).catch(()=>{});
  await send('Page.navigate', {url: 'http://127.0.0.1:8080/#/account'});
  await new Promise(resolve => setTimeout(resolve, 8000));
  const evalResult = await send('Runtime.evaluate', {expression: 'document.body.innerText', returnByValue: true});
  console.log('BODY_TEXT_START');
  console.log((evalResult.result.value || '').slice(0, 4000));
  console.log('BODY_TEXT_END');
  ws.close();
})().catch(e => { console.error(e); process.exit(1); });
