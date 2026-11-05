import test from 'node:test';
import assert from 'node:assert/strict';
import { STORAGE_KEY, getTheme, setTheme, applyTheme } from '../js/theme.js';

function fakeStorage(initial = {}) {
  const map = new Map(Object.entries(initial));
  return {
    getItem: (k) => (map.has(k) ? map.get(k) : null),
    setItem: (k, v) => map.set(k, String(v)),
  };
}

function stubRoot() {
  const attrs = new Map();
  return {
    setAttribute: (k, v) => attrs.set(k, v),
    getAttribute: (k) => (attrs.has(k) ? attrs.get(k) : null),
    attrs,
  };
}

test('defaults to dark when storage is empty', () => {
  assert.equal(getTheme(fakeStorage()), 'dark');
});

test('setTheme light then getTheme returns light', () => {
  const storage = fakeStorage();
  setTheme('light', storage);
  assert.equal(getTheme(storage), 'light');
  assert.equal(storage.getItem(STORAGE_KEY), 'light');
});

test('unknown values fall back to dark', () => {
  assert.equal(getTheme(fakeStorage({ theme: 'blue' })), 'dark');
  assert.equal(getTheme(fakeStorage({ theme: null })), 'dark');
  assert.equal(setTheme('banana', fakeStorage()), 'dark');
});

test('applyTheme sets data-theme on the root', () => {
  const root = stubRoot();
  applyTheme('light', root);
  assert.equal(root.getAttribute('data-theme'), 'light');
  applyTheme('dark', root);
  assert.equal(root.getAttribute('data-theme'), 'dark');
  applyTheme('garbage', root);
  assert.equal(root.getAttribute('data-theme'), 'dark');
});
