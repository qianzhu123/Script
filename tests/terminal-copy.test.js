const assert = require('node:assert/strict');
const test = require('node:test');

const { copyButtonPresentation, copyText } = require('../public/terminal-copy.js');

test('copies text with the Clipboard API when available', async () => {
  const writes = [];
  const environment = {
    navigator: {
      clipboard: {
        writeText: async (text) => writes.push(text)
      }
    }
  };

  await copyText('script output', environment);

  assert.deepEqual(writes, ['script output']);
});

test('falls back to a temporary textarea when the Clipboard API is unavailable', async () => {
  const events = [];
  const textarea = {
    value: '',
    style: {},
    setAttribute(name, value) { events.push(['attribute', name, value]); },
    select() { events.push(['select']); }
  };
  const environment = {
    navigator: {},
    document: {
      body: {
        appendChild(node) { events.push(['append', node.value]); },
        removeChild() { events.push(['remove']); }
      },
      createElement(tag) {
        assert.equal(tag, 'textarea');
        return textarea;
      },
      execCommand(command) {
        events.push(['command', command]);
        return true;
      }
    }
  };

  await copyText('fallback output', environment);

  assert.deepEqual(events, [
    ['attribute', 'readonly', ''],
    ['append', 'fallback output'],
    ['select'],
    ['command', 'copy'],
    ['remove']
  ]);
});

test('uses the fallback when Clipboard API copying fails', async () => {
  const commands = [];
  const textarea = { style: {}, setAttribute() {}, select() {} };
  const environment = {
    navigator: {
      clipboard: {
        writeText: async () => { throw new Error('denied'); }
      }
    },
    document: {
      body: { appendChild() {}, removeChild() {} },
      createElement: () => textarea,
      execCommand(command) {
        commands.push(command);
        return true;
      }
    }
  };

  await copyText('retry output', environment);

  assert.deepEqual(commands, ['copy']);
});

test('rejects empty output instead of copying placeholder text', async () => {
  await assert.rejects(() => copyText('', {}), /没有可复制的运行结果/);
});

test('disables the copy symbol when the active run has no output', () => {
  assert.deepEqual(copyButtonPresentation('', 'idle'), {
    symbol: '⧉',
    label: '复制运行结果',
    disabled: true,
    status: 'idle'
  });
});

test('shows distinct success and failure feedback for copy attempts', () => {
  assert.deepEqual(copyButtonPresentation('output', 'success'), {
    symbol: '✓',
    label: '运行结果已复制',
    disabled: false,
    status: 'success'
  });
  assert.deepEqual(copyButtonPresentation('output', 'failure'), {
    symbol: '!',
    label: '复制失败',
    disabled: false,
    status: 'failure'
  });
});
