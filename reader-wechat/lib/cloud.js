const defaultServer = 'http://localhost:8080'
function request(options) {
  return new Promise((resolve,reject)=>wx.request({...options,success(res){
    if(res.statusCode>=200 && res.statusCode<300 && res.data.success!==false) resolve(res)
    else reject(Error(res.data.message || '请求失败 '+res.statusCode))
  },fail:reject}))
}
module.exports = Behavior({
  data:{cloudOpen:false,remote:[],username:'',message:''},
  methods:{
    toggleCloud(){
      const session = wx.getStorageSync('cloud-session') || {}
      this.session = session
      this.setData({cloudOpen:!this.data.cloudOpen,username:session.username || '',server:session.server || wx.getStorageSync('cloud-server') || defaultServer})
      if(this.data.cloudOpen && session.token) this.refresh()
    },
    serverChanged(e){
      const server = e.detail.value.trim().replace(/\/+$/,'')
      if(server!==this.data.server){this.cookie='';this.setData({server,picture:''})}
    },
    async captcha(){
      const server=this.data.server
      try {
        const res=await request({url:server+'/api/auth/captcha?t='+Date.now(),responseType:'arraybuffer'})
        if(server!==this.data.server)return
        const cookies=res.cookies || [res.header['Set-Cookie'] || res.header['set-cookie'] || '']
        this.cookie=cookies.map(c=>c.split(';')[0]).join('; ')
        this.setData({picture:'data:image/png;base64,'+wx.arrayBufferToBase64(res.data),message:''})
      } catch(e){this.error(e)}
    },
    async login(e){
      const {username,password,captcha,server:input}=e.detail.value
      const server=input.trim().replace(/\/+$/,'')
      if(!this.data.picture || server!==this.data.server){this.error(Error('请先获取验证码'));return}
      try {
        const res=await request({url:server+'/api/auth/login',method:'POST',header:{Cookie:this.cookie || ''},data:{username,password,captcha}})
        const data=res.data.data
        if(!data || !data.token)throw Error('登录响应缺少凭证')
        this.session={server,username:data.username || username,token:data.token}
        wx.setStorageSync('cloud-session',this.session)
        wx.setStorageSync('cloud-server',server)
        this.setData({username:this.session.username,picture:''})
        this.refresh()
      } catch(err){this.error(err)}
    },
    error(e){this.setData({message:e.message || e.errMsg || '请求失败'})},
    async refresh(){
      const session=this.session
      try {
        const res=await request({url:session.server+'/api/books',header:{Authorization:'Bearer '+session.token}})
        if(session!==this.session)return
        const remote=res.data.data
        if(!Array.isArray(remote))throw Error('书架响应格式错误')
        this.setData({remote,message:remote.length?'':'云端书架为空'})
      } catch(e){this.error(e)}
    },
    download(e){
      if(this.data.busy)return
      const id=e.currentTarget.dataset.id
      const {server,username,token}=this.session
      const key=JSON.stringify([server,username,id])
      const local=this.data.books.find(b=>b.cloudKey===key)
      if(local){wx.navigateTo({url:'read?id='+local.id});return}
      this.setData({busy:true,message:''})
      wx.downloadFile({url:server+'/api/books/'+encodeURIComponent(id)+'/download',header:{Authorization:'Bearer '+token},success:res=>{
        if(res.statusCode===200)this.importFile({path:res.tempFilePath,name:this.data.remote.find(b=>String(b.id)===String(id))?.title || '云端图书'},key)
        else {this.error(Error('下载失败 '+res.statusCode));this.setData({busy:false})}
      },fail:e=>{this.error(e);this.setData({busy:false})}})
    },
    logout(){
      wx.removeStorageSync('cloud-session')
      this.session={};this.cookie=''
      this.setData({username:'',remote:[],message:'',picture:''})
    }
  }
})
