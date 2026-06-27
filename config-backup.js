const fs = require('node:fs');
const path = require('node:path');

const AUTOMATIC_BACKUP_PATTERN = /^scripts-(\d{4})-(\d{2})-(\d{2})_(\d{2})-(\d{2})-(\d{2})-(\d{3})\.json$/;
const DAY_MS = 24 * 60 * 60 * 1000;

function pad(value, width = 2) {
  return String(value).padStart(width, '0');
}

function formatBackupTimestamp(date = new Date()) {
  return [
    `${pad(date.getFullYear(), 4)}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}`,
    `${pad(date.getHours())}-${pad(date.getMinutes())}-${pad(date.getSeconds())}-${pad(date.getMilliseconds(), 3)}`
  ].join('_');
}

function parseAutomaticBackupTimestamp(name) {
  const match = AUTOMATIC_BACKUP_PATTERN.exec(String(name || ''));
  if (!match) return null;
  const [, year, month, day, hour, minute, second, millisecond] = match.map(Number);
  const parsed = new Date(year, month - 1, day, hour, minute, second, millisecond);
  if (
    parsed.getFullYear() !== year ||
    parsed.getMonth() !== month - 1 ||
    parsed.getDate() !== day ||
    parsed.getHours() !== hour ||
    parsed.getMinutes() !== minute ||
    parsed.getSeconds() !== second ||
    parsed.getMilliseconds() !== millisecond
  ) {
    return null;
  }
  return parsed;
}

function isAutomaticBackupName(name) {
  return parseAutomaticBackupTimestamp(name) !== null;
}

function createConfigBackup({ sourcePath, backupDir, now = new Date() }) {
  if (!fs.existsSync(sourcePath)) return null;
  fs.mkdirSync(backupDir, { recursive: true });

  let candidateTime = new Date(now.getTime());
  let backupPath;
  do {
    const name = `scripts-${formatBackupTimestamp(candidateTime)}.json`;
    backupPath = path.join(backupDir, name);
    candidateTime = new Date(candidateTime.getTime() + 1);
  } while (fs.existsSync(backupPath));

  fs.copyFileSync(sourcePath, backupPath, fs.constants.COPYFILE_EXCL);
  return backupPath;
}

function writeJsonWithBackup({ sourcePath, backupDir, data, now = new Date() }) {
  const backupPath = createConfigBackup({ sourcePath, backupDir, now });
  fs.mkdirSync(path.dirname(sourcePath), { recursive: true });
  fs.writeFileSync(sourcePath, `${JSON.stringify(data, null, 2)}\n`, 'utf8');
  return backupPath;
}

function pruneExpiredBackups({
  backupDir,
  now = new Date(),
  retentionDays = 7,
  onDelete = () => {},
  onError = () => {}
}) {
  const deleted = [];
  try {
    fs.mkdirSync(backupDir, { recursive: true });
    const cutoff = now.getTime() - retentionDays * DAY_MS;
    for (const entry of fs.readdirSync(backupDir, { withFileTypes: true })) {
      if (!entry.isFile()) continue;
      const timestamp = parseAutomaticBackupTimestamp(entry.name);
      if (!timestamp || timestamp.getTime() >= cutoff) continue;
      const target = path.join(backupDir, entry.name);
      try {
        fs.rmSync(target);
        deleted.push(target);
        onDelete(target);
      } catch (error) {
        onError(error, target);
      }
    }
  } catch (error) {
    onError(error, backupDir);
  }
  return deleted;
}

module.exports = {
  formatBackupTimestamp,
  isAutomaticBackupName,
  createConfigBackup,
  writeJsonWithBackup,
  pruneExpiredBackups
};
