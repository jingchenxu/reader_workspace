const {inspect} = require('../lib/book')
const fs = wx.getFileSystemManager()
Page({
  behaviors:[require("../lib/cloud")],
  data:{books:[], busy:false},
  onLoad(){this.setData({books:wx.getStorageSync('books') || []})},
  pick(){
    if(this.data.busy) return
    this.setData({busy:true})
    wx.chooseMessageFile({count:1,type:'file',extension:['epub'],success:res=>{
      this.importFile(res.tempFiles[0])
    },fail:()=>this.setData({busy:false})})
  },
  importFile(file,cloudKey=''){
      const id = 'book-' + Date.now()
      const dir = wx.env.USER_DATA_PATH + '/' + id
      const fail = () => {
        try { fs.rmdirSync(dir,true) } catch (_) {}
        wx.showToast({title:'导入失败，请检查文件和剩余空间',icon:'none'})
      }
      try { fs.mkdirSync(dir) } catch (_) {fail();this.setData({busy:false});return}
      fs.unzip({zipFilePath:file.path,targetPath:dir,success:()=>{
        try {
          const book = inspect(path=>fs.readFileSync(dir+'/'+path,'utf8'))
          book.title = book.title || file.name
          const books = [{...book,id,cloudKey},...this.data.books]
          wx.setStorageSync('books',books)
          this.setData({books})
        } catch (_) {fail()}
      },fail,complete:()=>this.setData({busy:false})})
  },
  read(e){wx.navigateTo({url:'read?id='+e.currentTarget.dataset.id})},
  remove(e){
    const id = e.currentTarget.dataset.id
    wx.showModal({title:'从书架移除这本书？',success:res=>{
      if(!res.confirm) return
      const books = this.data.books.filter(b=>b.id!==id)
      wx.setStorageSync('books',books)
      this.setData({books})
      wx.removeStorageSync(id)
      wx.removeStorageSync(id+"-marks")
      wx.getFileSystemManager().rmdir({dirPath:wx.env.USER_DATA_PATH+'/'+id,recursive:true})
    }})
  }
})
