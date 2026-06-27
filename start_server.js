const { spawn } = require('child_process');
const path = require('path');

const serverPath = path.join(__dirname, 'server.js');
const proc = spawn('node', [serverPath], {
  cwd: __dirname,
  stdio: 'inherit',
  detached: true,
  env: { ...process.env, SCRIPT_STUDIO_OUTPUT_ENCODING: 'gbk' }
});
proc.unref();
console.log('Server started, PID:', proc.pid);
process.exit(0);
