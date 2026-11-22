import { importEpub, selectEpubFiles } from './importEpub'
const { invoke } = window.__TAURI__.core
const records = (kind, id = null) => invoke('records', { kind, id })
const action = (action, data = {}) => invoke('desktop_action', { action, data })
const findBook = async id => (await records('books')).find(book => book.id === id)
const failure = error => ({success:false,error:String(error)})

async function openEpub() {
  const files = await selectEpubFiles()
  const result = {success:files.length > 0, total:files.length, added:[], skipped:0, failed:[]}
  for (const file of files) {
    try {
      const {existing,id} = await importEpub(file)
      if (existing) result.skipped++
      else result.added.push(await findBook(id))
    } catch (error) { result.failed.push({path:file.name,reason:String(error)}) }
  }
  return result
}

async function exportNotes(id) {
  const book = await findBook(id)
  const [annotations,marks] = await Promise.all([records('annotations',id),records('bookmarks',id)])
  const lines = [`《${book.title}》 - 阅读笔记`,`作者：${book.author || '未知'}`,`导出时间：${new Date().toLocaleString()}`,'','='.repeat(50),'']
  if (annotations.length) {
    lines.push(`【批注】（共 ${annotations.length} 条）`,'')
    annotations.slice().reverse().forEach((a,i)=>lines.push(`${i+1}. ${a.selected_text}`,`   批注：${a.annotation}`,`   时间：${a.created_at}`,''))
    lines.push('-'.repeat(50),'')
  }
  if (marks.length) {
    lines.push(`【书签】（共 ${marks.length} 个）`,'')
    marks.slice().reverse().forEach((m,i)=>{
      lines.push(`${i+1}. ${m.title || '书签'}`)
      if (m.note) lines.push(`   备注：${m.note}`)
      lines.push(`   时间：${m.created_at}`,'')
    })
  }
  return invoke('export_file',{id,notes:lines.join('\n')}).catch(failure)
}
window.electronAPI = {
  getAppPath: () => invoke('app_path'),
  getUserDataPath: () => invoke('library_path'),
  getBooks: id => records('books', id),
  getCategories: () => records('categories'),
  getProgress: async id => (await records('progress', id))[0],
  getBookmarks: id => records('bookmarks', id),
  getAnnotations: id => records('annotations', id),
  addBookmark: async data => ({id:await invoke('add_bookmark', data)}),
  deleteBookmark: id => invoke('delete_bookmark', {id}),
  saveAnnotation: async data => ({success:true, id:await invoke('save_annotation', data)}),
  saveProgress: ({bookId, cfi, page, percentage}) => invoke('save_progress', {id:bookId, cfi, page, percentage}),
  openReaderWindow: book => invoke('open_reader',{id:book.id}),
  addCategory:(name,color)=>action('addCategory',{name,color}),
  updateCategory:(id,name,color)=>action('updateCategory',{id,name,color}).catch(failure),
  deleteCategory:id=>action('deleteCategory',{id}).catch(failure),
  updateBookCategory:(id,categoryId)=>action('updateBookCategory',{id,categoryId}),
  deleteBook:id=>action('deleteBook',{id}),
  deleteBookCompletely:id=>action('deleteBookCompletely',{id}).catch(failure),
  deleteAnnotation:id=>action('deleteAnnotation',{id}),
  getStorageInfo:()=>action('getStorageInfo'),
  clearCache:()=>action('clearCache').catch(failure),
  selectSavePath:()=>invoke('choose_directory'),
  readBookFile:bookPath=>action('readBookFile',{bookPath}).catch(failure),
  openEpub, exportNotes,
  exportBook:id=>invoke('export_file',{id,notes:null}).catch(failure),
  async downloadCloudBook(url,info,token) {
    try {
      const response = await fetch(url,{headers:token ? {Authorization:token.startsWith('Bearer ')?token:'Bearer '+token}: {}})
      if (!response.ok) throw Error('下载失败 '+response.status)
      const {id,existing}=await importEpub(new File([await response.blob()],info.title+'.epub'),info)
      return {success:!existing,book:await findBook(id)}
    } catch(error){return failure(error)}
  }
}
