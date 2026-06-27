const fs = require('node:fs');
const path = require('node:path');
const { createConfigBackup } = require('../config-backup.js');

const root = path.resolve(__dirname, '..');
const sourcePath = path.join(root, 'config', 'scripts.json');
const backupDir = path.join(root, 'backup');

if (!fs.existsSync(sourcePath)) {
  console.error('Cannot back up missing file: config/scripts.json');
  process.exit(1);
}

try {
  const backupPath = createConfigBackup({ sourcePath, backupDir });
  console.log(`Created config backup: ${path.relative(root, backupPath)}`);
} catch (error) {
  console.error(`Config backup failed: ${error.message}`);
  process.exit(1);
}
