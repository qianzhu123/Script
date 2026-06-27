const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');

const projectRoot = path.resolve(__dirname, '..');
const scriptExtensions = new Set(['.bat', '.cmd', '.ps1', '.vbs', '.sh']);
const skippedDirectories = new Set(['.git', 'backup', 'logs', 'node_modules', 'output', 'temp']);
const nonAsciiPattern = /[^\x09\x0A\x0D\x20-\x7E]/u;

function walkScripts(root) {
  if (!fs.existsSync(root)) return [];
  return fs.readdirSync(root, { withFileTypes: true }).flatMap((entry) => {
    const fullPath = path.join(root, entry.name);
    if (entry.isDirectory()) {
      if (skippedDirectories.has(entry.name)) return [];
      return walkScripts(fullPath);
    }
    if (!entry.isFile()) return [];
    return scriptExtensions.has(path.extname(entry.name).toLowerCase()) ? [fullPath] : [];
  });
}

test('executable scripts use English-only text', () => {
  const scripts = walkScripts(projectRoot).sort();
  const failures = [];

  for (const scriptPath of scripts) {
    const content = fs.readFileSync(scriptPath, 'utf8');
    const lines = content.split(/\r?\n/);
    lines.forEach((line, index) => {
      if (nonAsciiPattern.test(line)) {
        failures.push(`${path.relative(projectRoot, scriptPath)}:${index + 1}: ${line.trim()}`);
      }
    });
  }

  assert.deepEqual(failures, []);
});
