# Script Studio

Script Studio is a local web dashboard for organizing, launching, and monitoring Windows batch and PowerShell scripts from a browser-based interface.

It is designed for personal automation workflows where you want a clean launcher, script grouping, quick terminal output, drag-and-drop script import, and private local configuration that is not published to GitHub.

## GitHub Repository Details

Use this text in the GitHub repository settings.

Description:

```text
A local web dashboard for organizing, launching, and monitoring BAT and PowerShell scripts.
```

Website:

```text
https://github.com/qianzhu123/Script
```

Topics:

```text
script-runner windows batch powershell nodejs express websocket dashboard terminal automation developer-tools
```

## Features

- Manage scripts with groups.
- Add, edit, delete, and reorder groups.
- Add, edit, delete, and reorder scripts.
- Add scripts by dragging `.bat`, `.cmd`, or `.ps1` files into the page when the browser exposes a file path.
- Select a script by clicking its card.
- Run BAT, CMD, and PowerShell scripts from a browser terminal.
- Run scripts with administrator privileges on Windows.
- Stop running scripts from the UI.
- Optionally release configured ports before running a script.
- Store private script data in a local Git-ignored config file.

## Requirements

- Windows 10 or later
- Node.js 18 or later
- npm

## Quick Start

Install dependencies:

```bash
npm install
```

Start the server:

```bash
npm start
```

Open the app:

```text
http://127.0.0.1:3100
```

You can also start it with:

```bat
start.bat
```

## Configuration

The repository includes only an example configuration:

```text
config/scripts.example.json
```

On first start, the app creates a local private config file:

```text
config/scripts.json
```

This local file is ignored by Git and should contain your private script list.

## Script Paths

Example repository paths are relative:

```text
bat/demo.bat
ps1/demo.ps1
```

Your local `config/scripts.json` can use either project-relative paths or absolute Windows paths:

```text
bat/demo.bat
D:\tools\my-script.bat
C:\Users\You\Scripts\task.ps1
```

Absolute paths are allowed for your local runtime configuration because `config/scripts.json` is ignored by Git. Do not add your private local config file to GitHub.

## Script To EXE

Run:

```bat
bat\ScriptToExe.bat
```

The converter asks for:

1. A `.bat`, `.cmd`, `.ps1`, or `.py` source script.
2. An optional `.ico` file. Press Enter to use PyInstaller's default icon.

It creates a same-name `.exe` and `.lnk` beside the source script. The generated executable runs with its own directory as the working directory, so project-relative references such as `%~dp0`, `$PSScriptRoot`, `__file__`, and `python app.py` continue to resolve from the source project directory.

Python and PyInstaller are required:

```bat
python -m pip install pyinstaller
```

The generated EXE embeds the selected script, but it does not embed sibling project files. Keep files such as `app.py`, `templates`, `static`, and `data` beside the generated EXE when the source script depends on them.

## Concurrent Runs

Each launch creates a terminal tab above the output area. Tabs keep separate output and input streams, and can be selected, stopped, or closed independently. Closing a running tab also stops that script after confirmation.

## Drag And Drop

You can drag `.bat`, `.cmd`, or `.ps1` files into the page to add them.

Browser security rules may hide the full local path for dropped files. When the full path is available, Script Studio adds the script automatically. When the browser hides it, the add-script dialog opens and asks you to paste the absolute path manually.

## Private Data Policy

The following local files and folders are ignored by Git:

```text
config/scripts.json
config/groups.json
config/categories.json
logs/
temp/
*.lnk
```

Only demo scripts are included in this repository. Keep your private scripts and local configuration out of Git.

## Troubleshooting

If the script list is empty after startup:

1. Open `config/scripts.json`.
2. Make sure it contains a `scripts` array.
3. If you want to reset to the demo config, delete `config/scripts.json` and restart the server.
4. Refresh the browser with `Ctrl+F5` to bypass cached assets.

If dragging a file does not fill the path automatically, paste the full Windows path into the script path field. This is a browser security limitation, not an app limitation.

If the page loads but old text or broken labels remain visible, restart the server and force-refresh the browser.

## License

MIT
