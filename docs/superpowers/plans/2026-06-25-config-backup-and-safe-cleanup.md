# Config Backup and Safe Cleanup Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Back up `config/scripts.json` before every application write, prune only automatic backups older than seven days on startup, document manual backup rules, and remove only verified temporary residue.

**Architecture:** Add a focused CommonJS backup module used by both `server.js` and a manual CLI. Route every application configuration replacement through a tested helper that creates a backup first. Keep cleanup restricted by exact filename and resolved-path allowlists.

**Tech Stack:** Node.js CommonJS, `node:test`, PowerShell verification, existing Express application.

---

## File Structure

- Create `config-backup.js`: timestamp parsing/formatting, backup creation, pre-write replacement, and retention pruning.
- Create `scripts/backup-config.js`: manual CLI used by people and AI assistants before direct JSON edits.
- Create `tests/config-backup.test.js`: unit and integration tests using temporary directories.
- Modify `server.js`: use the backup module in `saveConfig` and prune expired automatic backups during startup.
- Modify `package.json`: expose `npm run backup-config`.
- Modify `README.md`: require pre-edit backup and document automatic retention.
- Create `.gitignore`: ignore generated runtime content and only automatic backup files.
- Remove only approved residue under `temp`, `temp/_runners`, and `logs/_runners`.

### Task 1: Capture Protected Inventory

- [ ] **Step 1: Record protected files before cleanup**

Run:

```powershell
$root = 'D:\code\myweb\daily'
Get-ChildItem "$root\bat","$root\ps1" -Recurse -Force -File |
  ForEach-Object { $_.FullName.Substring($root.Length + 1) } |
  Sort-Object |
  Set-Content "$env:TEMP\daily-protected-scripts-before.txt"
Get-ChildItem $root -Recurse -Force -File -Filter *.lnk |
  ForEach-Object { $_.FullName.Substring($root.Length + 1) } |
  Sort-Object |
  Set-Content "$env:TEMP\daily-shortcuts-before.txt"
```

Expected: two inventory files are created outside the repository.

### Task 2: Test Backup and Retention Behavior

**Files:**

- Create: `tests/config-backup.test.js`
- Create later: `config-backup.js`

- [ ] **Step 1: Write failing tests**

Create tests that import:

```js
const {
  formatBackupTimestamp,
  isAutomaticBackupName,
  createConfigBackup,
  writeJsonWithBackup,
  pruneExpiredBackups
} = require('../config-backup.js');
```

Cover fixed local timestamp formatting, exact automatic-name matching, distinct millisecond names, byte-identical backup content, backup-before-write failure behavior, deletion older than seven days, retention at exactly seven days, and preservation of manual/malformed files and directories.

- [ ] **Step 2: Verify RED**

Run:

```powershell
node --test tests/config-backup.test.js
```

Expected: FAIL because `config-backup.js` does not exist.

### Task 3: Implement the Backup Module

**Files:**

- Create: `config-backup.js`
- Test: `tests/config-backup.test.js`

- [ ] **Step 1: Implement timestamp and matching helpers**

Use local date fields and zero-padding to produce:

```text
scripts-YYYY-MM-DD_HH-mm-ss-SSS.json
```

Parse only valid calendar timestamps matched by the exact filename regular expression.

- [ ] **Step 2: Implement backup creation**

`createConfigBackup({ sourcePath, backupDir, now })` must return `null` when the source does not exist, otherwise create the directory and copy the source bytes to a timestamped path. If that exact filename already exists, increment the effective timestamp by one millisecond until an unused name is found.

- [ ] **Step 3: Implement protected writes**

`writeJsonWithBackup({ sourcePath, backupDir, data, now })` must call `createConfigBackup` before writing formatted JSON. A backup error must propagate before any source write occurs.

- [ ] **Step 4: Implement retention pruning**

`pruneExpiredBackups({ backupDir, now, retentionDays, onDelete, onError })` must inspect only files matching the exact automatic pattern and delete those whose encoded timestamp is strictly earlier than `now - retentionDays`.

- [ ] **Step 5: Verify GREEN**

Run:

```powershell
node --test tests/config-backup.test.js
```

Expected: all backup tests pass.

### Task 4: Integrate Application Writes and Startup Cleanup

**Files:**

- Modify: `server.js`
- Test: `tests/config-backup.test.js`

- [ ] **Step 1: Configure backup paths**

Import `writeJsonWithBackup` and `pruneExpiredBackups`, then define:

```js
const BACKUP_DIR = path.join(ROOT, 'backup');
```

- [ ] **Step 2: Protect the central save path**

Replace the body of `saveConfig` so all existing group/script CRUD routes use:

```js
writeJsonWithBackup({
  sourcePath: SCRIPT_CONFIG,
  backupDir: BACKUP_DIR,
  data: normalizeConfig(config)
});
```

- [ ] **Step 3: Prune once during startup**

Before `server.listen`, call retention pruning with seven days. Log each deleted relative path and log cleanup errors without stopping startup.

- [ ] **Step 4: Verify focused and existing tests**

Run:

```powershell
npm test
npm run check
```

Expected: both commands exit `0`.

### Task 5: Add Manual Backup Command and Documentation

**Files:**

- Create: `scripts/backup-config.js`
- Modify: `package.json`
- Modify: `README.md`
- Create: `.gitignore`

- [ ] **Step 1: Add CLI**

The CLI must resolve the repository root, call `createConfigBackup`, fail if `config/scripts.json` is missing, and print the created repository-relative path.

- [ ] **Step 2: Add package command**

Add:

```json
"backup-config": "node scripts/backup-config.js"
```

- [ ] **Step 3: Document direct-edit workflow**

Update each README workflow that changes `config/scripts.json` to run:

```powershell
npm run backup-config
```

immediately before direct modification. Explain automatic website backups, exact naming, seven-day startup retention, and preservation of manual backup files.

- [ ] **Step 4: Ignore only generated content**

Create `.gitignore` with:

```gitignore
node_modules/
temp/
logs/
backup/scripts-????-??-??_??-??-??-???.json
```

- [ ] **Step 5: Verify manual backup**

Run the CLI, compare the newest generated backup bytes to `config/scripts.json`, then remove only that verification backup.

Expected: identical bytes and no change to `config/scripts.json`.

### Task 6: Perform Conservative One-Time Cleanup

**Files:**

- Delete only approved generated residue.

- [ ] **Step 1: Build and verify exact target list**

Targets:

```text
temp/script-to-exe-build-*
temp/_runners
logs/_runners
temp/*.stdout.log
temp/*.stderr.log
temp/cv_debug.log
temp/_final_patch.js
temp/_continue_patch.js
temp/temp_patch.py
```

Resolve every target and reject any path outside `D:\code\myweb\daily\temp` or `D:\code\myweb\daily\logs\_runners`.

- [ ] **Step 2: Delete only verified targets**

Use native PowerShell `Remove-Item -LiteralPath`; do not delete `temp` or `logs` wholesale.

- [ ] **Step 3: Verify protected inventory**

Recreate the script and shortcut inventories and compare them with Task 1 using `Compare-Object`.

Expected: no differences.

### Task 7: Final Verification

- [ ] **Step 1: Run full checks**

```powershell
npm test
npm run check
node --check config-backup.js
node --check scripts/backup-config.js
```

Expected: all commands exit `0`.

- [ ] **Step 2: Verify protected backup**

```powershell
Test-Path -LiteralPath 'D:\code\myweb\daily\backup\scripts.json'
```

Expected: `True`.

- [ ] **Step 3: Review scope**

```powershell
git status --short
git diff --check
```

Expected: only intended new/modified implementation and documentation files plus pre-existing user changes; no script deletion introduced by this task.

