const assert = require('node:assert/strict');
const test = require('node:test');

const { RunSessionStore } = require('../public/run-session-store.js');

test('keeps output and status independent for simultaneous runs', () => {
  const store = new RunSessionStore();
  const first = store.create({ scriptId: 'a', name: 'First' });
  const second = store.create({ scriptId: 'b', name: 'Second' });

  store.append(first.id, 'first-output');
  store.append(second.id, 'second-output');
  store.setStatus(first.id, 'finished');

  assert.equal(store.get(first.id).output, 'first-output');
  assert.equal(store.get(first.id).status, 'finished');
  assert.equal(store.get(second.id).output, 'second-output');
  assert.equal(store.get(second.id).status, 'running');
  assert.equal(store.list().length, 2);
});

test('selects and removes one run without changing the other', () => {
  const store = new RunSessionStore();
  const first = store.create({ scriptId: 'a', name: 'First' });
  const second = store.create({ scriptId: 'b', name: 'Second' });

  store.select(first.id);
  store.remove(first.id);

  assert.equal(store.get(first.id), null);
  assert.equal(store.selected().id, second.id);
});
