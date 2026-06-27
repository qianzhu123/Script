# Script Runner Reliability Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the script converter, cleanup scripts, and web terminal reliable for moved scripts and concurrent runs.

**Architecture:** ScriptToExe embeds source bytes but extracts them beside the generated EXE so project-relative path semantics remain intact. The web UI replaces its single socket with a small session store containing one socket and output buffer per run tab; the existing backend already supports independent WebSocket connections.

**Tech Stack:** PowerShell 5.1+, Windows batch, Python 3/PyInstaller, Node.js, Express, WebSocket, browser JavaScript.

---

### Task 1: Regression Tests

**Files:**
- Create: `tests/Test-PowerShellSyntax.ps1`
- Create: `tests/Test-ScriptToExe.ps1`
- Create: `tests/run-session-store.test.js`

- [ ] Add a parser test that fails while any `ps1/*.ps1` file has parser errors.
- [ ] Add an integration test that converts a fixture BAT, checks the EXE and shortcut, and verifies `%~dp0` resolves beside the EXE.
- [ ] Add a Node test for multiple independent run sessions.
- [ ] Run each test and confirm it fails for the current defect.

### Task 2: Repair PowerShell And Batch Launchers

**Files:**
- Modify: `ps1/Scan-CleanReport.ps1`
- Modify: `ps1/scan_clean_report.ps1`
- Modify: `bat/scan-clean-all.bat`
- Modify: `bat/scan-clean-c.bat`
- Modify: `bat/scan-clean-d.bat`

- [ ] Replace malformed Markdown string construction with format expressions or single-quoted literals.
- [ ] Normalize cleanup wrapper path discovery and exit-code handling.
- [ ] Run the PowerShell parser test until all scripts pass.

### Task 3: General ScriptToExe Converter

**Files:**
- Modify: `ps1/ScriptToExe.ps1`
- Modify: `bat/ScriptToExe.bat`

- [ ] Add source and optional icon input handling.
- [ ] Generate a runner that extracts beside the EXE and selects the correct interpreter.
- [ ] Build through `python -m PyInstaller`.
- [ ] Create a same-directory Windows shortcut with the EXE directory as its working directory.
- [ ] Run the integration test until it passes.
- [ ] Build and smoke-test the qiandao launcher.

### Task 4: Concurrent Web Terminal Tabs

**Files:**
- Create: `public/run-session-store.js`
- Modify: `public/index.html`
- Modify: `public/app.js`
- Modify: `public/style.css`
- Modify: `server.js`
- Modify: `package.json`

- [ ] Implement and test a pure run-session store.
- [ ] Render terminal tabs with status and close controls.
- [ ] Route output, input, stop, and close actions to the selected session.
- [ ] Add web-mode environment variables to spawned scripts.
- [ ] Run Node syntax and unit tests.
- [ ] Verify two simultaneous runs and tab switching in the local browser.

### Task 5: Final Audit

**Files:**
- Modify only scripts with confirmed portability or syntax defects.

- [ ] Parse all PowerShell files.
- [ ] Audit BAT files for obsolete desktop paths and broken project-relative references.
- [ ] Run the complete test command.
- [ ] Review the diff without reverting pre-existing user changes.
