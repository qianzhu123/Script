const fs = require('fs');
const path = require('path');
const vm = require('vm');

const ROOT = __dirname;
const mustExist = [
  'server.js',
  'runner-launch.js',
  'public/index.html',
  'public/app.js',
  'public/script-search.js',
  'public/run-session-store.js',
  'public/style.css',
  'config/scripts.json'
];

let ok = true;
for (const rel of mustExist) {
  const abs = path.join(ROOT, rel);
  if (!fs.existsSync(abs)) {
    console.error(`[FAIL] Missing: ${rel}`);
    ok = false;
  } else {
    console.log(`[ OK ] ${rel}`);
  }
}

for (const rel of ['server.js', 'runner-launch.js', 'public/app.js', 'public/script-search.js', 'public/run-session-store.js']) {
  try {
    new vm.Script(fs.readFileSync(path.join(ROOT, rel), 'utf8'), { filename: rel });
    console.log(`[ OK ] Syntax: ${rel}`);
  } catch (error) {
    console.error(`[FAIL] Syntax: ${rel}\n${error.stack || error.message}`);
    ok = false;
  }
}

try {
  const config = JSON.parse(fs.readFileSync(path.join(ROOT, 'config/scripts.json'), 'utf8'));
  if (!config || !Array.isArray(config.groups) || !Array.isArray(config.scripts)) {
    throw new Error('expected an object containing groups[] and scripts[]');
  }
  console.log(`[ OK ] Config: ${config.groups.length} groups, ${config.scripts.length} scripts`);
} catch (error) {
  console.error(`[FAIL] config/scripts.json: ${error.message}`);
  ok = false;
}

process.exit(ok ? 0 : 1);
