const assert = require('node:assert/strict');
const test = require('node:test');

const {
  normalizeSearchQuery,
  findMatchingScripts,
  highlightSearchText,
  nextSearchIndex
} = require('../public/script-search.js');

const groups = [
  { id: 'video-tools', name: '视频工具' },
  { id: 'automation', name: '自动化' }
];

const scripts = [
  { id: 'name-match', name: 'VideoSpeedExport', path: 'bat/export.bat', description: '导出文件', groupId: 'automation' },
  { id: 'description-match', name: 'ConvertMedia', path: 'bat/convert.bat', description: '处理 video 文件', groupId: 'automation' },
  { id: 'path-match', name: 'InspectFile', path: 'tools/video_probe.ps1', description: '检查文件', groupId: 'automation' },
  { id: 'group-match', name: 'RenderClip', path: 'bat/render.bat', description: '渲染片段', groupId: 'video-tools' },
  { id: 'no-match', name: 'KillPort', path: 'bat/kill-port.bat', description: '关闭端口', groupId: 'automation' }
];

test('normalizes surrounding whitespace and case', () => {
  assert.equal(normalizeSearchQuery('  VIDEO  '), 'video');
  assert.equal(normalizeSearchQuery('   '), '');
});

test('searches name, description, path, and group name across all scripts', () => {
  assert.deepEqual(
    findMatchingScripts(scripts, groups, 'video').map((script) => script.id),
    ['name-match', 'description-match', 'path-match']
  );
  assert.deepEqual(
    findMatchingScripts(scripts, groups, '视频').map((script) => script.id),
    ['group-match']
  );
});

test('returns all scripts unchanged for an empty query', () => {
  assert.deepEqual(findMatchingScripts(scripts, groups, ''), scripts);
});

test('escapes HTML before highlighting matched text', () => {
  assert.equal(
    highlightSearchText('<Video & tools>', 'video'),
    '&lt;<mark>Video</mark> &amp; tools&gt;'
  );
  assert.equal(highlightSearchText('<safe>', ''), '&lt;safe&gt;');
});

test('wraps search navigation in both directions', () => {
  assert.equal(nextSearchIndex(2, 3, 1), 0);
  assert.equal(nextSearchIndex(0, 3, -1), 2);
  assert.equal(nextSearchIndex(-1, 3, 1), 0);
  assert.equal(nextSearchIndex(0, 0, 1), -1);
});
