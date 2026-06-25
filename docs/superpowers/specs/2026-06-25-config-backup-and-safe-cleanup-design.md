# Config Backup and Safe Cleanup Design

## Goal

Protect `D:\code\myweb\daily\config\scripts.json` before every configuration write, remove only expired automatic backups on application startup, and clean the repository without deleting existing project scripts or the user's backup files.

## Protected Content

The following content must not be deleted or overwritten during this work:

- The entire `D:\code\myweb\daily\backup` directory, except expired files that match the new automatic-backup naming convention.
- Existing files under `bat\` and `ps1\`.
- Existing shortcut files, including `.lnk`.
- Existing script entries in `config\scripts.json`, except through normal user-requested application operations.
- Existing files under `output\` and `reports\`.
- Existing uncommitted user changes.
- Backup files that do not match the new automatic-backup naming convention, including `backup\scripts.json`.

## Automatic Backup Behavior

Create a focused CommonJS module responsible for backing up and pruning `scripts.json`. `server.js` will call this module instead of implementing filesystem policy inline.

Before every application operation that writes `config\scripts.json`, the application must:

1. Confirm that the current `config\scripts.json` exists.
2. Ensure the `backup` directory exists.
3. Copy the current file to a new backup.
4. Only write the new configuration after the backup succeeds.

This applies to:

- Creating, renaming, deleting, or reordering groups.
- Creating, editing, deleting, or reordering scripts.
- Any future application write routed through `saveConfig`.

Initial configuration creation is excluded because no existing `scripts.json` is available to protect. If a configuration file exists but is invalid, it must still be copied before replacement.

If backup creation fails, the configuration write must fail and the previous `scripts.json` must remain unchanged.

## Backup Naming

Automatic backups use this Windows-compatible format:

```text
backup/scripts-YYYY-MM-DD_HH-mm-ss-SSS.json
```

Example:

```text
backup/scripts-2026-06-25_21-54-00-123.json
```

The timestamp uses local system time. Milliseconds prevent collisions when multiple changes happen within one second.

The automatic-backup matcher must accept only the exact pattern:

```text
scripts-\d{4}-\d{2}-\d{2}_\d{2}-\d{2}-\d{2}-\d{3}.json
```

## Startup Retention

On every application startup:

1. Ensure the `backup` directory exists.
2. Inspect only files matching the exact automatic-backup pattern.
3. Derive backup age from the timestamp encoded in the filename.
4. Delete a matching backup only when its encoded timestamp is strictly older than seven days relative to startup time.
5. Leave files exactly seven days old until they become older than the retention boundary.
6. Ignore malformed names, directories, manual backups, and unrelated files.
7. Log deleted backups and non-fatal cleanup errors without preventing application startup.

Using the encoded timestamp makes retention deterministic and prevents a later file copy from extending retention through a changed filesystem modification time.

## Manual and AI Configuration Changes

Add a small command-line script that creates one automatic-format backup without changing `scripts.json`. Expose it through:

```text
npm run backup-config
```

Update `README.md` so any person or AI assistant must run this command immediately before directly editing `config\scripts.json`.

The documentation must also state:

- Automatic website operations already back up before writing.
- Backups older than seven days are pruned when the website starts.
- Only automatic-format backups are pruned.
- `backup\scripts.json` and other manual backup files are retained.

## Repository Cleanup

The one-time cleanup is intentionally conservative because the repository contains many untracked scripts and user changes.

Delete only items confirmed to be disposable runtime or test residue:

- The stale `temp\script-to-exe-build-*` test build directory.
- Files under `temp\_runners`.
- Files under `logs\_runners`.
- Known `.stdout.log`, `.stderr.log`, and debug `.log` files under `temp`.
- Temporary patch helpers under `temp` whose names clearly identify them as patch artifacts.

Preserve:

- Potentially reusable `.ps1`, `.py`, `.js`, and `.md` files unless their names clearly mark them as temporary patch artifacts.
- Historical application logs under `logs` unless separately requested.
- `node_modules`, because it is required for immediate application startup and is small in this checkout.
- All script directories and files.

Before deletion, resolve every target path and verify it remains inside one of the approved `temp` or runner directories. After deletion, verify protected paths and script-file inventories remain unchanged.

## Git Ignore Rules

Add `.gitignore` entries for generated local content:

```text
node_modules/
temp/
logs/
backup/scripts-????-??-??_??-??-??-???.json
```

Do not ignore the whole `backup` directory because manual backups are protected user content.

## Module Boundary

The backup module will expose independently testable functions for:

- Formatting a local timestamp.
- Recognizing automatic backup names.
- Creating a backup before a write.
- Pruning automatic backups older than seven days.

Filesystem paths and the current time will be accepted as function inputs where useful so tests can use temporary directories and fixed dates.

`server.js` will:

- Configure the source and backup paths.
- Run pruning once during startup.
- Call backup creation from the central `saveConfig` path.
- Keep startup cleanup errors non-fatal.
- Allow backup failures during configuration writes to propagate to existing route error handling.

## Testing

Automated Node tests must verify:

- Timestamp formatting produces a Windows-compatible deterministic name.
- Two backups created in different milliseconds receive distinct names.
- Backup content exactly matches the pre-write `scripts.json`.
- A failed backup prevents the subsequent configuration write.
- Startup pruning deletes an automatic backup older than seven days.
- Startup pruning retains a backup newer than or exactly seven days old.
- Startup pruning retains `backup\scripts.json`, malformed names, unrelated files, and directories.
- Existing test suites and `npm run check` continue to pass.

One integration-style test will exercise the central save path or an exported write helper so the test proves backup happens before replacement, rather than only testing isolated filename utilities.

## Verification

Completion requires fresh evidence for all of the following:

- `npm test`
- `npm run check`
- A manual backup command creates a correctly named file with identical content.
- A controlled startup-cleanup test removes only an expired automatic backup.
- `backup\scripts.json` still exists.
- The inventories of `bat`, `ps1`, and `.lnk` files match the pre-cleanup inventory.
- `git status --short` shows no unintended deletion or modification.

