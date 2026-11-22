export function buildFileUrl(path, root) {
  if (!path) return ''
  const normalized = path.replace(/\\/g, '/')
  const absolute = /^(?:[a-z]:\/|\/)/i.test(normalized) ? normalized : root + '/' + normalized
  return window.__TAURI__.core.convertFileSrc(absolute)
}
export function isValidFileUrl(url) { return !!url }
