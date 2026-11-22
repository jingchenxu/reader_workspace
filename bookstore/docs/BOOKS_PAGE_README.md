# 书籍列表页面功能说明

## 📖 功能概述

用户登录成功后，自动跳转到书籍列表页面，展示该账户下的所有书籍。

## 🌐 访问地址

- **书籍列表页**: http://localhost:8080/books
- **需要登录**: 是（未登录会自动跳转到登录页）

## ✨ 页面功能

### 1. 页面头部
- **Logo**: EPUB阅读器标识
- **用户信息**: 显示用户名和角色（USER/ADMIN）
- **退出登录**: 点击退出并清除本地Token

### 2. 书籍统计
- 显示当前用户的书籍总数
- 实时更新书籍数量

### 3. 操作栏
- **同步新书籍**: 点击上传EPUB文件到服务端

### 4. 书籍网格展示
每本书籍卡片包含：
- 📚 **封面图片**: 如果有封面则显示，否则显示默认图标
- 📝 **书名**: 书籍标题
- 👤 **作者**: 书籍作者（未知作者显示"未知作者"）
- 📅 **添加日期**: 格式为 yyyy-MM-dd
- 🔖 **阅读按钮**: 点击打开书籍阅读器（待实现）

### 5. 空状态
当用户没有书籍时显示：
- 📚 空状态图标
- "暂无书籍"提示
- "同步书籍"按钮

## 🎨 设计特点

- **响应式布局**: 适配桌面和移动设备
- **卡片式设计**: 美观的书籍展示
- **悬停效果**: 鼠标悬停时卡片上浮
- **渐变色主题**: 紫色渐变 (#667eea → #764ba2)
- **现代化UI**: 圆角、阴影、平滑过渡

## 🔧 技术实现

### 后端
- **Controller**: HomeController.books()
- **Service**: BookService.getUserBooks()
- **认证**: Spring Security + JWT
- **模板引擎**: Thymeleaf

### 前端
- **HTML5 + CSS3**: 纯静态页面
- **JavaScript**: 原生JS处理交互
- **Fetch API**: 异步上传书籍
- **LocalStorage**: 存储用户Token

## 📝 使用流程

### 1. 登录
```
访问 http://localhost:8080/login
输入用户名和密码
点击登录
```

### 2. 自动跳转
登录成功后，系统会：
1. 保存Token到localStorage
2. 保存用户信息（userId, username, role）
3. 1秒后自动跳转到 /books 页面

### 3. 查看书籍
- 页面加载时自动获取当前用户的书籍列表
- 以网格形式展示所有书籍
- 显示书籍总数

### 4. 同步新书籍
```
点击"同步新书籍"按钮
选择EPUB文件
自动上传到服务端
上传成功后刷新页面
```

### 5. 阅读书籍
```
点击书籍卡片或"阅读"按钮
（阅读器功能待实现）
```

### 6. 退出登录
```
点击右上角"退出登录"按钮
清除localStorage中的Token和用户信息
跳转到首页
```

## 🔐 安全机制

1. **登录验证**: 未登录用户访问/books会自动跳转到/login
2. **Token认证**: 所有API请求需要携带Bearer Token
3. **用户隔离**: 每个用户只能看到自己的书籍
4. **管理员特权**: 管理员可以看到所有用户的书籍（后续实现）

## 📊 数据流

```
用户登录 → 获取Token → 保存到localStorage → 跳转到/books
                                              ↓
                                    HomeController.books()
                                              ↓
                                    验证用户身份
                                              ↓
                                    BookService.getUserBooks(userId)
                                              ↓
                                    返回书籍列表
                                              ↓
                                    Thymeleaf渲染页面
```

## 🚀 API接口

### 获取用户书籍
```
GET /api/books
Headers: Authorization: Bearer {token}
Response: {
  "success": true,
  "message": "获取书籍列表成功",
  "data": [
    {
      "id": 1,
      "title": "书名",
      "author": "作者",
      "coverPath": "封面路径",
      "addedAt": "2026-05-27T14:00:00"
    }
  ]
}
```

### 同步书籍
```
POST /api/books/sync
Headers: Authorization: Bearer {token}
Body: FormData (file + bookData)
Response: {
  "success": true,
  "message": "同步成功",
  "data": {...}
}
```

## 📂 相关文件

### Controller
- `HomeController.java` - 页面路由控制

### Template
- `books.html` - 书籍列表页面模板

### Service
- `BookService.java` - 书籍业务逻辑

### Security
- `SecurityConfig.java` - 安全配置（/books需要认证）

## 🎯 后续优化建议

1. **分页功能**: 当书籍较多时支持分页加载
2. **搜索功能**: 支持按书名、作者搜索
3. **排序功能**: 按添加时间、书名等排序
4. **分类标签**: 支持书籍分类管理
5. **在线阅读器**: 集成EPUB.js实现在线阅读
6. **批量操作**: 支持批量删除、批量下载
7. **阅读进度**: 在卡片上显示阅读进度
8. **最近阅读**: 突出显示最近阅读的书籍

## ⚠️ 注意事项

1. **首次使用**: 新用户登录后书籍列表为空，需要同步书籍
2. **文件格式**: 目前仅支持.epub格式文件
3. **文件大小**: 单个文件最大50MB
4. **网络要求**: 需要保持网络连接以加载封面图片
5. **浏览器兼容**: 建议使用Chrome、Firefox、Edge等现代浏览器

---

**功能状态**: ✅ 已完成  
**服务地址**: http://localhost:8080/books  
**最后更新**: 2026-05-27 14:14
