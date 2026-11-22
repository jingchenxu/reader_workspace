import JSZip from 'jszip'

function base64(blob) {
  return new Promise((resolve, reject) => {
    const reader = new FileReader()
    reader.onload = () => resolve(reader.result.split(',')[1])
    reader.onerror = () => reject(reader.error)
    reader.readAsDataURL(blob)
  })
}

function xml(text) {
  const doc = new DOMParser().parseFromString(text, 'application/xml')
  if (doc.querySelector('parsererror')) throw Error('EPUB 元数据格式错误')
  return doc
}

async function readMetadata(file) {
  const zip = await JSZip.loadAsync(file)
  const container = xml(await zip.file('META-INF/container.xml').async('string'))
  const path = container.querySelector('rootfile').getAttribute('full-path')
  const opf = xml(await zip.file(path).async('string'))
  const meta = opf.getElementsByTagNameNS('*', 'metadata')[0]
  const values = name => Array.from(meta.getElementsByTagNameNS('*', name), el => el.textContent.trim())
  const metadata = {
    title: values('title')[0], author: values('creator')[0], publisher: values('publisher')[0],
    isbn: values('identifier').find(value => /^(978\d{10}|\d{9}[\dX])$/i.test(value)),
    pubDate: values('date')[0], language: values('language')[0], description: values('description')[0]
  }
  const id = meta.querySelector('meta[name="cover"]')?.getAttribute('content')
  const items = Array.from(opf.getElementsByTagNameNS('*','item'))
  const item = items.find(i=>i.id===id) || items.find(i=>i.getAttribute('properties')?.split(/\s+/).includes('cover-image')) ||
    items.find(i=>['cover','cover-image'].includes(i.id))
  const types = {'image/jpeg':'jpg','image/png':'png','image/gif':'gif','image/webp':'webp','image/svg+xml':'svg'}
  const extension = item && types[item.getAttribute('media-type')]
  let cover = null
  if (extension) {
    const href = new URL(item.getAttribute('href'), new URL(path, 'https://epub.invalid/'))
    const entry = zip.file(decodeURIComponent(href.pathname.slice(1)))
    if (entry) cover = await entry.async('base64')
  }
  return {metadata, cover, extension}
}

export async function importEpub(file, overrides = {}) {
  let parsed = {}
  try { parsed = await readMetadata(file) }
  catch (error) { console.warn('未能读取 EPUB 元数据，使用文件名', error) }
  const metadata = { ...parsed.metadata }
  metadata.title ||= file.name.replace(/\.epub$/i, '')
  metadata.author ||= '未知作者'
  for (const [key, value] of Object.entries(overrides)) {
    if (value && value !== '未知作者') metadata[key] = value
  }
  return window.__TAURI__.core.invoke('import_book', {
    metadata, content:await base64(file), cover:parsed.cover || null, extension:parsed.extension || null
  })
}

export async function selectEpubFiles() {
  const input = document.createElement('input')
  input.type = 'file'
  input.accept = '.epub'
  input.multiple = true
  return new Promise(resolve => {
    input.onchange = () => resolve(Array.from(input.files))
    input.oncancel = () => resolve([])
    input.click()
  })
}
