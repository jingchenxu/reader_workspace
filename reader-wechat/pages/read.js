const {chapter} = require('../lib/book')
Page({
  data:{labels:[],index:0,content:''},
  onLoad({id}){
    this.book = (wx.getStorageSync('books') || []).find(b=>b.id===id)
    if(!this.book) {wx.navigateBack();return}
    wx.setNavigationBarTitle({title:this.book.title})
    this.setData({labels:this.book.chapters.map((_,i)=>'第 '+(i+1)+' 章')})
    this.setData({marks:wx.getStorageSync(id+"-marks") || [],font:wx.getStorageSync("reader-font") || 18})
    this.show(Number(wx.getStorageSync(id)) || 0)
  },
  show(index){
    index = Math.max(0,Math.min(index,this.book.chapters.length-1))
    const path = wx.env.USER_DATA_PATH+'/'+this.book.id+'/'+this.book.chapters[index]
    let content
    try {
      content = chapter(wx.getFileSystemManager().readFileSync(path,'utf8')) || '本章没有可显示的文字'
      wx.setStorageSync(this.book.id,index)
    } catch (_) {content = '章节读取失败'}
    this.setData({index,content})
    wx.pageScrollTo({scrollTop:0,duration:0})
  },
  fontChange(e){
    const font = Number(e.detail.value)
    wx.setStorageSync('reader-font',font)
    this.setData({font})
  },
  saveMark(e){
    const index = this.data.index
    const note = (e.detail.value.note || '').trim()
    this.storeMarks([...this.data.marks,{id:Date.now(),index,note:note || this.data.labels[index]}])
  },
  storeMarks(marks){
    wx.setStorageSync(this.book.id+'-marks',marks)
    this.setData({marks})
  },
  deleteMark(e){this.storeMarks(this.data.marks.filter(m=>m.id!==Number(e.currentTarget.dataset.id)))},
  openMark(e){this.show(Number(e.currentTarget.dataset.index))},
  toggleTools(){this.setData({tools:!this.data.tools})},
  jump(e){this.show(Number(e.detail.value))},
  prev(){this.show(this.data.index-1)},
  next(){this.show(this.data.index+1)}
})
