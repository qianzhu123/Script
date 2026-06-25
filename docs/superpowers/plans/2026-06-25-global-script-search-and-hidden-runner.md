# Global Script Search and Hidden Runner Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a one-line global script search with highlighting and navigation, and keep web-launched script output exclusively in the browser terminal.

**Architecture:** Put pure search behavior in a browser-and-Node compatible helper, and put child-process launch specifications in a separate Node helper. `public/app.js` handles DOM state and scrolling while `server.js` delegates process launch decisions to the tested helper.

**Tech Stack:** Node.js CommonJS, browser JavaScript, HTML/CSS, `node:test`, Express/WebSocket, in-app browser verification.

---

## File Structure

- Create `public/script-search.js`: pure query, matching, highlighting, and navigation helpers.
- Create `runner-launch.js`: pure child-process launch specification builder.
- Create `tests/script-search.test.js`: search and safe highlight tests.
- Create `tests/runner-launch.test.js`: hidden-window launch tests.
- Modify `public/index.html`: single-line search control between title and add button.
- Modify `public/app.js`: search state, global rendering, result selection, keyboard navigation, and scrolling.
- Modify `public/style.css`: one-line header, search field, result count, and highlights.
- Modify `server.js`: consume `runner-launch.js` and use hidden launch options.
- Modify `docs/WEB_TERMINAL_USAGE.md`: global search and single terminal behavior.
- Modify `docs/WEB_TERMINAL_DEVELOPMENT.md`: runner-window policy.

### Task 1: Establish Baseline and Protected Script Checks

- [ ] **Step 1: Verify video scripts remain outside the change**

Run:

```powershell
git diff -- bat/VideoSpeedExport.bat ps1/VideoSpeedExport.ps1
```

Expected: no task-created diff.

- [ ] **Step 2: Run the current test baseline**

Run:

```powershell
npm test
npm run check
```

Expected: all current tests and checks pass.

### Task 2: Test and Implement Pure Search Behavior

**Files:**

- Create: `tests/script-search.test.js`
- Create: `public/script-search.js`

- [ ] **Step 1: Write failing search tests**

Import:

```js
const {
  normalizeSearchQuery,
  findMatchingScripts,
  highlightSearchText,
  nextSearchIndex
} = require('../public/script-search.js');
```

Tests must assert:

```js
assert.deepEqual(
  findMatchingScripts(scripts, groups, 'video').map((script) => script.id),
  ['name-match', 'description-match', 'path-match', 'group-match']
);
assert.equal(normalizeSearchQuery('  VIDEO  '), 'video');
assert.equal(highlightSearchText('<Video>', 'video'), '&lt;<mark>Video</mark>&gt;');
assert.equal(nextSearchIndex(2, 3, 1), 0);
assert.equal(nextSearchIndex(0, 3, -1), 2);
```

- [ ] **Step 2: Verify RED**

Run:

```powershell
node --test tests/script-search.test.js
```

Expected: FAIL because `public/script-search.js` does not exist.

- [ ] **Step 3: Implement the UMD helper**

Expose the helper through both:

```js
module.exports = api;
window.ScriptSearch = api;
```

`findMatchingScripts` must preserve input order, match name/description/path/group name case-insensitively, and return all scripts for an empty query.

`highlightSearchText` must HTML-escape text and query before wrapping matching segments in `<mark>`.

- [ ] **Step 4: Verify GREEN**

Run:

```powershell
node --test tests/script-search.test.js
```

Expected: all search tests pass.

### Task 3: Test and Implement Hidden Runner Specifications

**Files:**

- Create: `tests/runner-launch.test.js`
- Create: `runner-launch.js`
- Modify later: `server.js`

- [ ] **Step 1: Write failing runner tests**

Import:

```js
const { buildRunnerLaunch } = require('../runner-launch.js');
```

For `.ps1`, `.py`, and `.bat`, assert:

```js
assert.equal(spec.options.windowsHide, true);
assert.equal(spec.options.shell, false);
assert.equal(spec.options.cwd, expectedDirectory);
assert.equal(spec.options.env.SCRIPT_STUDIO_ROOT, root);
```

Also assert the expected executable and leading arguments for each type.

- [ ] **Step 2: Verify RED**

Run:

```powershell
node --test tests/runner-launch.test.js
```

Expected: FAIL because `runner-launch.js` does not exist.

- [ ] **Step 3: Implement launch builder**

Return:

```js
{
  command,
  args,
  options: {
    cwd: path.dirname(absolutePath),
    windowsHide: true,
    shell: false,
    env
  }
}
```

Preserve the existing PowerShell, Python, and CMD command lines exactly.

- [ ] **Step 4: Verify GREEN**

Run:

```powershell
node --test tests/runner-launch.test.js
```

Expected: all runner tests pass.

### Task 4: Integrate the Hidden Runner

**Files:**

- Modify: `server.js`
- Test: `tests/runner-launch.test.js`

- [ ] **Step 1: Import the builder**

Add:

```js
const { buildRunnerLaunch } = require('./runner-launch.js');
```

- [ ] **Step 2: Replace duplicated spawn branches**

Use:

```js
const launch = buildRunnerLaunch({
  absolutePath: absolute,
  shellName: script.shell,
  root: ROOT,
  baseEnv: process.env
});
const child = spawn(launch.command, launch.args, launch.options);
```

Keep the existing stdout, stderr, close, error, input, and stop handlers unchanged.

- [ ] **Step 3: Verify server syntax and all tests**

Run:

```powershell
node --check server.js
npm test
npm run check
```

Expected: all commands exit `0`.

### Task 5: Add the One-Line Global Search UI

**Files:**

- Modify: `public/index.html`
- Modify: `public/style.css`
- Modify: `public/app.js`
- Load: `public/script-search.js`

- [ ] **Step 1: Add header markup**

Inside `.panel-header`, place this between `listTitle` and `addScriptBtn`:

```html
<label class="script-search">
  <span class="search-icon" aria-hidden="true">⌕</span>
  <input id="scriptSearchInput" type="search" placeholder="搜索名称、说明、路径或分组" autocomplete="off" />
  <span id="scriptSearchCount" class="search-count">0 / 0</span>
</label>
```

Load `/script-search.js` before `/app.js`.

- [ ] **Step 2: Add search state**

Extend state with:

```js
searchQuery: '',
searchResults: [],
searchIndex: -1
```

- [ ] **Step 3: Add global matching**

When the normalized query is non-empty:

- Set `state.currentGroup = 'all'`.
- Call `findMatchingScripts` with every script and group.
- Update group rendering and the title.
- Set result index to zero when results exist.
- Synchronize `state.selectedScript` and `selectedTitle`.

- [ ] **Step 4: Render safe highlights**

Use `highlightSearchText` for script name, path, description, and group display name.

Add the group display line only while search is active:

```html
<p class="search-group">分组：...</p>
```

Disable script dragging and drop sorting while searching.

- [ ] **Step 5: Add scrolling and keyboard navigation**

After rendering, scroll the active result card with:

```js
card.scrollIntoView({ behavior: 'smooth', block: 'center' });
```

Handle:

- `input`: refresh global results.
- `Enter`: advance result.
- `Shift+Enter`: previous result.
- `Escape`: clear search.

- [ ] **Step 6: Add one-line responsive styling**

Use:

```css
.panel-header {
  display: grid;
  grid-template-columns: max-content minmax(150px, 1fr) max-content;
  align-items: center;
}
```

Ensure title and button use `white-space: nowrap`; the search field uses `min-width: 0`.

Add yellow `<mark>` styling and `.search-active` card border/glow matching the approved preview.

### Task 6: Document Behavior

**Files:**

- Modify: `docs/WEB_TERMINAL_USAGE.md`
- Modify: `docs/WEB_TERMINAL_DEVELOPMENT.md`

- [ ] **Step 1: Document global search**

State that search checks all groups, switches to “全部脚本”, highlights matches, and supports Enter/Shift+Enter/Escape.

- [ ] **Step 2: Document single web terminal**

State that Script Studio hides the child Windows console and routes input/output through the browser. Directly launching scripts outside Script Studio may still open a console.

### Task 7: Browser and Runtime Verification

- [ ] **Step 1: Start the application on a controlled port**

Run:

```powershell
$env:PORT = '31998'
node server.js
```

- [ ] **Step 2: Verify search in browser**

Confirm:

- Header controls stay on one line at normal desktop width.
- Start inside a non-all group, search for a script in another group, and verify “全部脚本” becomes active.
- Result text and cards are highlighted.
- First result is selected and visible.
- Enter, Shift+Enter, and Escape behave as specified.
- No browser console errors occur.

- [ ] **Step 3: Verify hidden child process**

Run an interactive BAT or PowerShell script from the web UI and confirm:

- No new Windows terminal window appears.
- Output appears in the browser terminal.
- Browser input reaches the script.
- Stop still terminates the process.

### Task 8: Final Verification

- [ ] **Step 1: Run all automated checks**

```powershell
npm test
npm run check
node --check public/script-search.js
node --check runner-launch.js
node --check server.js
```

Expected: all commands exit `0`.

- [ ] **Step 2: Verify excluded scripts remain untouched**

```powershell
git diff -- bat/VideoSpeedExport.bat ps1/VideoSpeedExport.ps1
```

Expected: no task-created diff.

- [ ] **Step 3: Review change scope**

```powershell
git diff --check
git status --short
```

Expected: only intended web app, helper, test, and documentation changes from this task, alongside pre-existing user changes.

