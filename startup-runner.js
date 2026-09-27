const fs = require('node:fs');
const path = require('node:path');

const { logFileNameForScriptId, normalizeScriptId } = require('./autostart-manager.js');
const { buildRunnerLaunch } = require('./runner-launch.js');

function stripOuterQuotes(value) {
  let text = String(value || '').trim();
  let changed = true;
  while (changed && text.length >= 2) {
    changed = false;
    for (const [left, right] of [['\\"', '\\"'], ["\\'", "\\'"], ['"', '"'], ["'", "'"]]) {
      if (text.startsWith(left) && text.endsWith(right)) {
        text = text.slice(left.length, -right.length).trim();
        changed = true;
      }
    }
  }
  return text;
}

function resolveConfiguredScriptPath(root, configuredPath) {
  const clean = stripOuterQuotes(configuredPath);
  if (!clean) throw new Error('The configured script path is empty.');
  return path.normalize(path.isAbsolute(clean) ? clean : path.resolve(root, clean));
}

function writeLogLine(stream, message) {
  stream.write(`[${new Date().toISOString()}] ${message}\r\n`);
}

function closeStream(stream) {
  return new Promise((resolve, reject) => {
    stream.once('error', reject);
    stream.end(resolve);
  });
}

async function runConfiguredScript(scriptId, options = {}) {
  const id = normalizeScriptId(scriptId);
  const root = path.resolve(options.root || __dirname);
  const scriptsPath = path.resolve(options.scriptsPath || path.join(root, 'config', 'scripts.json'));
  const logsDirectory = path.resolve(options.logsDirectory || path.join(root, 'logs', 'autostart'));
  const logPath = path.join(logsDirectory, logFileNameForScriptId(id));
  const spawn = options.spawn || require('node:child_process').spawn;

  fs.mkdirSync(logsDirectory, { recursive: true });
  const log = fs.createWriteStream(logPath, { flags: 'a' });
  writeLogLine(log, `Autostart runner started for scriptId=${JSON.stringify(id)}.`);

  let child = null;
  try {
    const config = JSON.parse(fs.readFileSync(scriptsPath, 'utf8'));
    if (!config || !Array.isArray(config.scripts)) {
      throw new Error('config/scripts.json has an invalid schema.');
    }
    const script = config.scripts.find((candidate) => candidate && candidate.id === id);
    if (!script) {
      throw Object.assign(new Error(`Script not found: ${id}`), { exitCode: 2 });
    }

    const absolutePath = resolveConfiguredScriptPath(root, script.path);
    if (!fs.existsSync(absolutePath)) {
      throw Object.assign(new Error(`Script file not found: ${absolutePath}`), { exitCode: 3 });
    }

    const launch = buildRunnerLaunch({
      absolutePath,
      shellName: script.shell,
      root,
      baseEnv: process.env
    });
    child = spawn(launch.command, launch.args, launch.options);
    if (child.stdout) child.stdout.pipe(log, { end: false });
    if (child.stderr) child.stderr.pipe(log, { end: false });
    if (child.stdin) child.stdin.end();

    let spawnError = null;
    const forwardSignal = () => {
      if (child && !child.killed) child.kill();
    };
    process.once('SIGINT', forwardSignal);
    process.once('SIGTERM', forwardSignal);

    const outcome = await new Promise((resolve) => {
      child.once('error', (error) => { spawnError = error; });
      child.once('close', (code, signal) => resolve({ code, signal }));
    });
    process.removeListener('SIGINT', forwardSignal);
    process.removeListener('SIGTERM', forwardSignal);

    if (spawnError) {
      throw Object.assign(new Error(`Unable to start script: ${spawnError.message}`), { exitCode: 4 });
    }
    const exitCode = Number.isInteger(outcome.code) ? outcome.code : 1;
    writeLogLine(log, `Script exited with code=${exitCode} signal=${outcome.signal || 'none'}.`);
    await closeStream(log);
    return { exitCode, logPath };
  } catch (error) {
    writeLogLine(log, `Runner error: ${error && error.stack ? error.stack : String(error)}`);
    try { await closeStream(log); } catch {}
    return { exitCode: Number.isInteger(error && error.exitCode) ? error.exitCode : 1, logPath };
  }
}

if (require.main === module) {
  const scriptId = process.argv[2];
  if (!scriptId) {
    process.stderr.write('Usage: node startup-runner.js <script-id>\n');
    process.exitCode = 64;
  } else {
    runConfiguredScript(scriptId)
      .then(({ exitCode }) => { process.exitCode = exitCode; })
      .catch((error) => {
        process.stderr.write(`${error && error.stack ? error.stack : error}\n`);
        process.exitCode = 1;
      });
  }
}

module.exports = { stripOuterQuotes, resolveConfiguredScriptPath, runConfiguredScript };
