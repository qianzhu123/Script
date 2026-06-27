# Terminal Output Copy Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an accessible symbol button that copies the complete output of the active script run.

**Architecture:** Extract clipboard behavior into a small browser/CommonJS-compatible module so it can be tested with Node's built-in test runner. The page owns active-session selection and visual feedback; HTML and CSS place the action at the terminal's upper-right corner.

**Tech Stack:** Vanilla JavaScript, HTML, CSS, Node.js built-in test runner

---

### Task 1: Clipboard helper

**Files:**
- Create: `public/terminal-copy.js`
- Create: `tests/terminal-copy.test.js`
- Modify: `package.json`

- [x] Write tests that require `copyText(text, environment)` to prefer `navigator.clipboard.writeText`, use a hidden textarea plus `document.execCommand('copy')` as fallback, and reject empty text.
- [x] Run `node --test tests/terminal-copy.test.js`; expect failure because `public/terminal-copy.js` does not exist.
- [x] Implement `copyText` with Clipboard API and fallback behavior, exporting through CommonJS and `window.TerminalCopy`.
- [x] Update `npm test` to run every `tests/*.test.js` file.
- [x] Run `npm test`; expect all helper and existing session-store tests to pass.

### Task 2: Terminal copy control

**Files:**
- Modify: `public/index.html`
- Modify: `public/style.css`
- Modify: `public/app.js`

- [x] Add a `.terminal-wrap` around `#terminal`, add disabled `#copyOutputBtn` displaying `⧉`, and load `/terminal-copy.js` before `/app.js`.
- [x] Position the button at the terminal's upper-right corner, reserve output padding beneath it, and style hover, disabled, success, and failure states.
- [x] Add `activeSessionOutput()`, `syncCopyOutputButton()`, and `copyActiveOutput()` in `public/app.js`; copy only `state.sessions.get(state.activeTabId).output` and restore the symbol after feedback.
- [x] Call button synchronization after output changes, tab switching, tab closing, startup, success, and failure; bind the click handler during initialization.
- [x] Run `npm test` and `npm run check`; expect both commands to pass without warnings or errors from the changed files.

### Task 3: Browser verification

**Files:**
- Verify: `public/index.html`
- Verify: `public/style.css`
- Verify: `public/app.js`

- [x] Start the local server with `npm start`.
- [x] Verify the symbol is visible at the output's upper-right, disabled before output exists, enabled for an active run, and does not obscure terminal text.
- [x] Click the button and verify the clipboard contains the complete active run output and the symbol briefly changes to `✓`.
- [x] Switch run tabs and verify each tab copies only its own output; inspect a narrow viewport for layout regressions.
- [x] Run `git diff --check` and review the final scoped diff.
