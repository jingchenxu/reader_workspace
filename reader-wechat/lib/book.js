const sax = require('./sax')
function parse(xml, open, close, text) {
  const parser = sax.parser(false, { lowercase: true })
  parser.onopentag = node => open(node.name.split(':').pop(), node.attributes)
  parser.onclosetag = name => close(name.split(':').pop())
  parser.ontext = parser.oncdata = text
  parser.write(xml).close()
}
function resolve(base, href) {
  const parts = base.split('/').slice(0,-1).filter(Boolean)
  const path = decodeURIComponent(href.split('#')[0])
  if (/^[a-z]+:|^\/|\\\\/i.test(path)) throw Error('无效的书籍路径')
  for (const part of path.split('/')) {
    if (part === '..') {
      if (!parts.length) throw Error('无效的书籍路径')
      parts.pop()
    } else if (part && part !== '.') parts.push(part)
  }
  return parts.join('/')
}
function inspect(read) {
  let opf, title = '', inTitle = false
  const items = Object.create(null), order = []
  parse(read('META-INF/container.xml'), (tag,a) => {
    if(tag === 'rootfile' && !opf) opf = resolve('',a['full-path'])
  },()=>{},()=>{})
  parse(read(opf), (tag,a) => {
    if(tag === 'title' && !title) inTitle = true
    if(tag === 'item' && /html/.test(a['media-type'])) items[a.id] = resolve(opf,a.href)
    if(tag === 'itemref') order.push(a.idref)
  },tag => { if(tag === 'title') inTitle = false },s => { if(inTitle) title += s })
  const chapters = order.map(id => items[id]).filter(Boolean)
  if (!chapters.length) throw Error('没有可读章节')
  return {title:title.trim(),chapters}
}
function chapter(xml) {
  let content = '', body = false, hidden = 0
  parse(xml, tag => {
    if(tag === 'body') body = true
    if(['script','style'].includes(tag)) hidden++
    if(body && tag === 'br') content += '\n'
  },tag => {
    if(tag === 'body') body = false
    if(['script','style'].includes(tag)) hidden--
    if(body && /^(p|div|li|h[1-6])$/.test(tag)) content += '\n\n'
  },s => { if(body && !hidden) content += s })
  return content.trim()
}
module.exports = {inspect,chapter}
