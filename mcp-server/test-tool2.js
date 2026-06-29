import { spawn } from 'child_process';

const server = spawn('node', ['dist/index.js'], {
  stdio: ['pipe', 'pipe', 'pipe']
});

server.stderr.on('data', data => console.error(`[Server stderr] ${data}`));

let resultStr = '';
server.stdout.on('data', data => {
  resultStr += data.toString();
});

const req = {
  jsonrpc: '2.0',
  id: 1,
  method: 'tools/call',
  params: {
    name: 'verify_all_domain_routes',
    arguments: { envDir: 'ha-dev' }
  }
};

server.stdin.write(JSON.stringify(req) + '\n');
setTimeout(() => {
    try {
      const resp = JSON.parse(resultStr.trim().split('\n').pop());
      console.log(resp.result.content[0].text);
    } catch (e) {
      console.log("Raw output:", resultStr);
    }
    server.kill();
}, 8000);