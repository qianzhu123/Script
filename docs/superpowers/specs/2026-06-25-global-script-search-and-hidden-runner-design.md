# Global Script Search and Hidden Runner Design

## Goal

Add a one-line global script search control to the middle panel and prevent web-launched scripts from opening a duplicate Windows terminal while keeping all interaction inside the web terminal.

## Scope

This change modifies only the Script Studio web application and its tests.

The following files are explicitly outside scope and must remain unchanged:

- `bat/VideoSpeedExport.bat`
- `ps1/VideoSpeedExport.ps1`
- All other project script files under `bat/` and `ps1/`
- `config/scripts.json`

## Confirmed Root Cause

`server.js` launches PowerShell, Python, and CMD processes with `windowsHide: false`. Their standard output and error streams are also piped to the WebSocket and rendered in the browser.

This produces two output surfaces for one process:

1. The Windows console created by the child process.
2. The Script Studio web terminal receiving the child process pipes.

The runner must use `windowsHide: true` for web-launched processes. The existing piped `stdin`, `stdout`, and `stderr` remain unchanged, so interactive prompts continue through the browser.

## Runner Design

Extract process launch option construction into a small CommonJS helper that can be tested without starting the Express server.

The helper will return launch specifications for:

- PowerShell scripts.
- Python scripts.
- BAT, CMD, shortcut, and other command-shell scripts.

Every web launch specification must set:

```js
{
  windowsHide: true,
  shell: false
}
```

The current working-directory and environment behavior remains unchanged.

Tests will confirm that all supported launch types hide the Windows window while keeping the expected executable, arguments, working directory, and environment.

## Search Placement

The middle-panel header remains one row:

```text
全部脚本 | [ 搜索脚本信息                 1 / 3 ] | 新增脚本
```

The search control sits between the current group title and the existing add-script button.

The row uses three columns:

- Title: fixed to content width and never wraps.
- Search: flexible width, allowed to shrink.
- Add button: fixed to content width and never wraps.

The search field follows the existing white background, rounded corners, blue border, and focus-ring style.

## Search Scope and Matching

Entering any non-empty search query performs a global search:

1. Set the active group to `all`.
2. Render the “全部脚本” group as active.
3. Search every configured script regardless of its original group.

Matching is case-insensitive and checks:

- Script name.
- Script description.
- Script path.
- Group display name.

Whitespace surrounding the query is ignored. An empty query restores the normal current-group list without filtering.

## Search Rendering and Navigation

While a query is active:

- Render only matching scripts.
- Highlight matching text in name, description, path, and group display name.
- Add a yellow search-result border and subtle glow to matching cards.
- Show the current result position and total count inside the search field area.
- Select the first result and scroll it into view when the query changes.
- Keep the right-side selected script title synchronized.

Keyboard behavior:

- `Enter`: move to the next result and scroll it into view.
- `Shift+Enter`: move to the previous result.
- Navigation wraps at the beginning and end.
- `Escape`: clear the query and restore normal list rendering.

When no script matches, show a dedicated “没有找到匹配脚本” empty state and display `0 / 0`.

Editing, deleting, or running a selected result continues to use the existing controls.

Drag sorting is disabled while a search query is active because the visible list is filtered and cannot safely represent the complete ordering.

## Module Boundary

Create a browser-and-Node compatible search helper responsible for:

- Normalizing query text.
- Building searchable script text with group names.
- Filtering scripts globally.
- Splitting text into escaped highlighted segments.
- Calculating wrapped result navigation.

`public/app.js` remains responsible for DOM rendering, selection state, scrolling, and keyboard events.

Create a separate Node helper for process launch specifications so runner behavior is independently testable without importing `server.js`.

## Testing

Node tests must verify:

- Global search matches name, description, path, and group display name.
- Matching is case-insensitive.
- Empty queries do not filter.
- Highlight output escapes HTML before adding mark elements.
- Result navigation wraps forward and backward.
- PowerShell, Python, and CMD launch specifications all use `windowsHide: true`.
- Existing terminal input and output behavior remains unchanged.

Browser verification must confirm:

- The title, search field, counter, and add button remain on one line.
- Searching from a specific group switches to “全部脚本”.
- Matching cards and text are highlighted.
- The first result is selected and scrolled into view.
- Enter, Shift+Enter, and Escape work.
- Running an interactive script produces output only in the web terminal and does not open a separate Windows terminal.

## Documentation

Update the web terminal usage/development documentation to state:

- Search is global across all groups.
- The browser is the single terminal surface for web-launched scripts.
- Directly double-clicking a BAT or PS1 file outside Script Studio may still open its own console normally.

