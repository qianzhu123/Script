const fs = require('fs');
const path = require('path');

const root = path.resolve(__dirname, '..');
const vendorDir = path.join(root, 'public', 'vendor');
fs.mkdirSync(vendorDir, { recursive: true });

const files = [
  ['@xterm/xterm/css/xterm.css', 'xterm.css'],
  ['@xterm/xterm/lib/xterm.js', 'xterm.js'],
  ['@xterm/addon-fit/lib/addon-fit.js', 'xterm-addon-fit.js']
];

for (const [sourcePackagePath, targetName] of files) {
  const source = require.resolve(sourcePackagePath);
  fs.copyFileSync(source, path.join(vendorDir, targetName));
}
