# Daily Script Management Rules

This repository is used to manage daily utility scripts. When I ask an AI assistant to create, modify, or delete scripts in this project, follow this document strictly.

## 1. Files That May Be Modified

For script creation tasks, only the following paths may be created or modified by default:

```text
D:\code\myweb\daily\bat\*.bat
D:\code\myweb\daily\ps1\*.ps1
D:\code\myweb\daily\config\scripts.json
D:\code\myweb\daily\README.md
```

Do not modify any other project files unless I explicitly ask for it.

## 2. Script Storage Locations

### BAT Scripts

Windows Batch scripts must be created under:

```text
D:\code\myweb\daily\bat
```

The script path in `config/scripts.json` should use a project-relative path:

```text
bat/script_name.bat
```

### PowerShell Scripts

PowerShell scripts must be created under:

```text
D:\code\myweb\daily\ps1
```

The script path in `config/scripts.json` should use a project-relative path:

```text
ps1/script_name.ps1
```

Every PowerShell script must also have a same-name BAT launcher under `bat/`.
For PS1-backed scripts, register the BAT launcher in `config/scripts.json` by default so it can be launched by double-click.

Example:

```text
ps1/browser_auto.ps1
bat/browser_auto.bat
```

## 3. File Naming Rules

- Use English letters, numbers, underscores, or hyphens.
- Do not use spaces.
- Do not use Chinese characters in new script file names.
- The file name should clearly describe the script purpose.
- Keep script names concise. Prefer one to three short English words.
- `.bat` files must be placed in the `bat` folder.
- `.ps1` files must be placed in the `ps1` folder.
- If a `.ps1` file is created, a `.bat` file with the same base name must also be created.

Recommended format:

```text
action_target.bat
action_target.ps1
```

Examples:

```text
bat/backup_project.bat
ps1/clean_temp_files.ps1
```

## 4. scripts.json Location

After creating a new script, update the following file:

```text
D:\code\myweb\daily\config\scripts.json
```

The new script must be added to the `scripts` array. Its group must be selected according to the existing `groups` array.

### scripts.json Backup Rules

Before a person or AI assistant directly modifies `config/scripts.json`, run this command immediately before the edit:

```powershell
npm run backup-config
```

The backup is written under `backup/` with a Windows-compatible local timestamp:

```text
backup/scripts-2026-06-25_21-54-00-123.json
```

Website operations that create, edit, delete, or reorder scripts and groups automatically create the same backup before writing. If the backup fails, the configuration write is cancelled.

Every website startup removes only automatic backups whose filename timestamp is more than seven days old. Manual files such as `backup/scripts.json`, malformed names, directories, and unrelated backup content are never removed automatically.

## 5. Group Selection Rules

Before adding a script, read the `groups` array in `config/scripts.json` and choose the correct `groupId` based on the script purpose.

Current common groups include:

| Purpose | groupId | Display Name |
| --- | --- | --- |
| Common scripts | `常用` | 常用 |
| Local services | `group-mq8b1r2n-6set70` | 本地服务 |
| Developer tools | `开发工具` | 开发工具 |
| Reverse engineering / Android reverse engineering | `安卓逆向` | 逆向 |
| File processing | `文件处理` | 文件处理 |
| Ports and services | `端口与服务` | 端口与服务 |
| Disk cleanup | `磁盘清理` | 磁盘清理 |
| System maintenance | `系统维护` | 系统维护 |
| Network checks | `网络检查` | 网络检查 |
| Proxy tools | `group-mq8bcb2k-ih45b6` | 代理 |
| Automation | `group-mq9a888i` | 自动化 |
| Data-related tools | `group-mq9j08xp` | 一些数据 |
| Skill tools | `skill` | skill |

If the correct group is unclear, ask me first. Do not create a new group without confirmation.

## 6. scripts.json Entry Format

Each new script must add one object to the `scripts` array.

BAT example:

```json
{
  "id": "bat-example_script-bat",
  "name": "example_script",
  "groupId": "常用",
  "path": "bat/example_script.bat",
  "description": "Briefly describe what this script does",
  "priority": "normal",
  "shell": "",
  "ports": [],
  "order": 100
}
```

PowerShell example:

```json
{
  "id": "ps1-example_script-ps1",
  "name": "example_script",
  "groupId": "group-mq9a888i",
  "path": "ps1/example_script.ps1",
  "description": "Briefly describe what this script does",
  "priority": "normal",
  "shell": "",
  "ports": [],
  "order": 101
}
```

## 7. Field Rules

### id

`id` must be unique.

Recommended format:

```text
bat-file_name_without_extension-bat
ps1-file_name_without_extension-ps1
```

Keep underscores in file names. Spaces are not allowed.

Examples:

```text
bat-clean_temp-bat
ps1-clean_temp-ps1
```

### name

`name` should be the script file name without the extension.

Example:

```text
clean_temp
```

### groupId

`groupId` must use an existing `id` from the `groups` array.

Do not confuse the display name with the `groupId`. Some groups have different display names and IDs.

Example:

```text
Display name: 自动化
groupId: group-mq9a888i
```

### path

Use a project-relative path:

```text
bat/xxx.bat
ps1/xxx.ps1
```

Do not use an absolute path for newly created scripts unless I explicitly request it.

### description

`description` is required.

Rules:

- Use one short sentence to describe the script purpose.
- Use a brief Chinese description for user-facing script entries.
- Do not leave it empty.
- Keep it concise.

Example:

```text
Clean temporary files from the selected directory
```

### priority

Use the default value:

```text
normal
```

### shell

Use an empty string by default:

```json
""
```

### ports

Use an empty array by default:

```json
[]
```

If the script starts or occupies specific ports, and I have explicitly provided those ports, fill them in.

Example:

```json
[3000, 8080]
```

### order

`order` must be the current maximum `order` value in the `scripts` array plus 1.

If the current maximum value is `58`, the new script should use:

```json
"order": 59
```

## 8. BAT Script Writing Rules

A BAT script should preferably include this basic structure:

```bat
@echo off
chcp 65001 >nul
setlocal

REM Write script logic here

endlocal
pause
```

Requirements:

- Use UTF-8 friendly console output.
- Show clear prompts before important operations.
- Dangerous operations must ask for confirmation.
- Wrap paths in quotes whenever possible.
- If the project root is needed, derive it from `%~dp0` when appropriate.

## 9. PowerShell Script Writing Rules

A PS1 script should preferably include this basic structure:

```powershell
$ErrorActionPreference = "Stop"

# Write script logic here
```

Requirements:

- Use `Join-Path` for paths.
- Use `$PSScriptRoot` when the script directory is needed.
- Print clear logs for important operations.
- Dangerous operations must ask for confirmation.
- Do not change critical system settings by default unless I explicitly ask for it.

## 10. New Script Workflow

When creating a new script, the AI assistant must follow this order:

1. Confirm the script type: BAT or PS1.
2. Create the script in the correct folder:
   - BAT: `bat/`
   - PS1: `ps1/`
3. Read `config/scripts.json`.
4. Select the correct `groupId` from the existing `groups` array.
5. Calculate the new `order` value.
6. If the script type is PS1, create a same-name BAT launcher in `bat/`.
7. Run `npm run backup-config` immediately before directly editing `config/scripts.json`.
8. Append the new script entry to the `scripts` array. For PS1-backed scripts, register the BAT launcher path by default.
9. Use a brief Chinese description in the `description` field.
10. Ensure the JSON format remains valid.
11. Do not modify unrelated files.
12. Tell me which files were added and which group was used.

## 11. Existing Script Modification Rules

If I ask to modify an existing script:

- Only modify the target script file.
- Run `npm run backup-config` immediately before directly modifying `config/scripts.json`.
- Modify `config/scripts.json` only if the script description, path, group, ports, or other metadata needs to change.
- Do not reformat or reorder the entire JSON file unnecessarily.
- Do not delete other script entries.

## 12. Script Deletion Rules

If I ask to delete a script:

1. Delete the corresponding `.bat` or `.ps1` file.
2. Run `npm run backup-config` immediately before directly editing `config/scripts.json`.
3. Remove the matching entry from the `scripts` array in `config/scripts.json`.
4. Do not delete any other scripts.
5. Do not delete groups unless I explicitly request it.

## 13. Prohibited Actions

- Do not place BAT scripts in the `ps1` folder.
- Do not place PS1 scripts in the `bat` folder.
- Do not create new groups without confirmation.
- Do not use absolute paths in the `path` field for newly created local scripts.
- Do not leave `description` empty.
- Do not modify unrelated project files.
- Do not delete existing configuration entries unless requested.
- Do not break the JSON format of `scripts.json`.

## 14. AI Completion Summary Template

After creating a new script, reply using this format:

```text
Completed:
- Added script: bat/xxx.bat or ps1/xxx.ps1
- Updated config: config/scripts.json
- Group: display name / groupId
- Description: one-sentence script description
- No other files were modified
```
