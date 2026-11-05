export const STORAGE_KEY = 'theme';

const normalize = (theme) => (theme === 'light' ? 'light' : 'dark');

export function getTheme(storage = globalThis.localStorage) {
  let value = null;
  try {
    value = storage.getItem(STORAGE_KEY);
  } catch {
    value = null;
  }
  return normalize(value);
}

export function setTheme(theme, storage = globalThis.localStorage) {
  const normalized = normalize(theme);
  try {
    storage.setItem(STORAGE_KEY, normalized);
  } catch {
    // storage unavailable; theme still applies for this session
  }
  return normalized;
}

export function applyTheme(theme, root = document.documentElement) {
  root.setAttribute('data-theme', normalize(theme));
}
