const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const test = require('node:test');

const {
  formatBackupTimestamp,
  isAutomaticBackupName,
  createConfigBackup,
  writeJsonWithBackup,
  pruneExpiredBackups
} = require('../config-backup.js');

function makeTempDir(t) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'daily-config-backup-'));
  t.after(() => fs.rmSync(dir, { recursive: true, force: true }));
  return dir;
}

test('formats local timestamps as Windows-compatible backup names', () => {
  const date = new Date(2026, 5, 25, 21, 54, 0, 123);

  assert.equal(formatBackupTimestamp(date), '2026-06-25_21-54-00-123');
  assert.equal(isAutomaticBackupName('scripts-2026-06-25_21-54-00-123.json'), true);
  assert.equal(isAutomaticBackupName('scripts-2026-06-25:21:54:00.json'), false);
  assert.equal(isAutomaticBackupName('scripts.json'), false);
  assert.equal(isAutomaticBackupName('scripts-2026-02-31_21-54-00-123.json'), false);
});

test('creates byte-identical backups and avoids same-millisecond collisions', (t) => {
  const root = makeTempDir(t);
  const sourcePath = path.join(root, 'config', 'scripts.json');
  const backupDir = path.join(root, 'backup');
  const now = new Date(2026, 5, 25, 21, 54, 0, 123);
  const original = Buffer.from('{"groups":[],"scripts":[{"name":"原始"}]}\r\n', 'utf8');
  fs.mkdirSync(path.dirname(sourcePath), { recursive: true });
  fs.writeFileSync(sourcePath, original);

  const first = createConfigBackup({ sourcePath, backupDir, now });
  const second = createConfigBackup({ sourcePath, backupDir, now });

  assert.equal(path.basename(first), 'scripts-2026-06-25_21-54-00-123.json');
  assert.equal(path.basename(second), 'scripts-2026-06-25_21-54-00-124.json');
  assert.deepEqual(fs.readFileSync(first), original);
  assert.deepEqual(fs.readFileSync(second), original);
});

test('writes new JSON only after successfully backing up the old file', (t) => {
  const root = makeTempDir(t);
  const sourcePath = path.join(root, 'config', 'scripts.json');
  const backupDir = path.join(root, 'backup');
  const oldContent = '{"groups":[],"scripts":[{"id":"old"}]}\n';
  fs.mkdirSync(path.dirname(sourcePath), { recursive: true });
  fs.writeFileSync(sourcePath, oldContent, 'utf8');

  const backupPath = writeJsonWithBackup({
    sourcePath,
    backupDir,
    data: { groups: [], scripts: [{ id: 'new' }] },
    now: new Date(2026, 5, 25, 22, 0, 0, 0)
  });

  assert.equal(fs.readFileSync(backupPath, 'utf8'), oldContent);
  assert.deepEqual(JSON.parse(fs.readFileSync(sourcePath, 'utf8')), {
    groups: [],
    scripts: [{ id: 'new' }]
  });
});

test('leaves scripts.json unchanged when backup creation fails', (t) => {
  const root = makeTempDir(t);
  const sourcePath = path.join(root, 'config', 'scripts.json');
  const backupDir = path.join(root, 'not-a-directory');
  const oldContent = '{"groups":[],"scripts":[{"id":"old"}]}\n';
  fs.mkdirSync(path.dirname(sourcePath), { recursive: true });
  fs.writeFileSync(sourcePath, oldContent, 'utf8');
  fs.writeFileSync(backupDir, 'blocking file', 'utf8');

  assert.throws(() => writeJsonWithBackup({
    sourcePath,
    backupDir,
    data: { groups: [], scripts: [{ id: 'new' }] },
    now: new Date(2026, 5, 25, 22, 0, 0, 0)
  }));
  assert.equal(fs.readFileSync(sourcePath, 'utf8'), oldContent);
});

test('does not create a backup when scripts.json does not exist', (t) => {
  const root = makeTempDir(t);
  const sourcePath = path.join(root, 'config', 'scripts.json');
  const backupDir = path.join(root, 'backup');

  assert.equal(createConfigBackup({ sourcePath, backupDir }), null);
  assert.equal(fs.existsSync(backupDir), false);
});

test('prunes only automatic backups strictly older than seven days', (t) => {
  const root = makeTempDir(t);
  const backupDir = path.join(root, 'backup');
  fs.mkdirSync(backupDir);
  const files = [
    'scripts-2026-06-17_11-59-59-999.json',
    'scripts-2026-06-18_12-00-00-000.json',
    'scripts-2026-06-20_08-00-00-000.json',
    'scripts.json',
    'scripts-2026-02-31_08-00-00-000.json',
    'notes.txt'
  ];
  for (const name of files) fs.writeFileSync(path.join(backupDir, name), name, 'utf8');
  fs.mkdirSync(path.join(backupDir, 'scripts-2026-06-10_00-00-00-000.json'));

  const deleted = pruneExpiredBackups({
    backupDir,
    now: new Date(2026, 5, 25, 12, 0, 0, 0),
    retentionDays: 7
  });

  assert.deepEqual(deleted.map((file) => path.basename(file)), [
    'scripts-2026-06-17_11-59-59-999.json'
  ]);
  assert.equal(fs.existsSync(path.join(backupDir, files[0])), false);
  for (const name of files.slice(1)) {
    assert.equal(fs.existsSync(path.join(backupDir, name)), true, name);
  }
  assert.equal(fs.statSync(path.join(backupDir, 'scripts-2026-06-10_00-00-00-000.json')).isDirectory(), true);
});

test('reports cleanup errors without deleting unrelated files', (t) => {
  const root = makeTempDir(t);
  const backupDir = path.join(root, 'backup');
  fs.writeFileSync(backupDir, 'not a directory', 'utf8');
  const errors = [];

  const deleted = pruneExpiredBackups({
    backupDir,
    now: new Date(2026, 5, 25, 12, 0, 0, 0),
    retentionDays: 7,
    onError: (error) => errors.push(error)
  });

  assert.deepEqual(deleted, []);
  assert.equal(errors.length, 1);
  assert.equal(fs.readFileSync(backupDir, 'utf8'), 'not a directory');
});
