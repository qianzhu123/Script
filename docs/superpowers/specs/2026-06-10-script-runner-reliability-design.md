# Script Runner Reliability Design

## Scope

Repair the local script collection, make ScriptToExe a general-purpose converter, and allow the web terminal to run several scripts at the same time.

## ScriptToExe

- Accept a `.bat`, `.cmd`, `.ps1`, or `.py` source path.
- Accept an optional `.ico` path. An empty icon path uses PyInstaller's default application icon.
- Create `<source-name>.exe` and `<source-name>.lnk` beside the source script.
- Embed the source script in the executable.
- At runtime, extract the embedded script into the executable directory, run it with that directory as the working directory, then remove the temporary script.
- Preserve normal project-relative behavior such as `%~dp0`, `$PSScriptRoot`, `__file__`, and `python app.py`.
- Locate Python through `PATH` and invoke PyInstaller as `python -m PyInstaller`.

## Cleanup Scripts

- All PowerShell files under `ps1` must parse without errors.
- Markdown backticks must not escape PowerShell string terminators.
- `scan-clean-all.bat`, `scan-clean-c.bat`, and `scan-clean-d.bat` must resolve project paths relative to their own location and propagate exit codes.

## Web Terminal

- Each run creates an independent terminal tab and WebSocket.
- Starting another script must not stop existing runs.
- A tab stores its own output, input connection, status, and script name.
- Users can select a tab, stop its process, and close it.
- Closing a running tab asks for confirmation; closing a finished tab removes it immediately.
- Script processes receive web-mode environment variables so compatible scripts skip local-only pauses.

## Verification

- Parse every PowerShell script.
- Build and run a fixture BAT as an EXE from a path containing spaces.
- Verify the generated shortcut target and working directory.
- Build `D:\code\myweb\qiandao\run_web.bat` and confirm its generated EXE resolves `app.py` from the qiandao directory.
- Test independent terminal session state and verify the UI in the local browser.
