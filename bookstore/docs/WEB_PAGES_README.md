# EPUB阅读器网站首页说明

## 📖 概述

已成功创建基于Thymeleaf的EPUB阅读器网站首页，提供以下功能：
- 精美的首页展示
- 用户注册入口
- 用户登录入口
- 阅读器下载入口

## 🌐 访问地址

- **首页**: http://localhost:8080/
- **注册页面**: http://localhost:8080/register
- **登录页面**: http://localhost:8080/login

## ✨ 功能特性

### 1. 首页 (index.html)
- **导航栏**：包含Logo、功能特性链接、下载链接、登录和注册按钮
- **Hero区域**：展示应用名称和简介，提供快速操作按钮
- **功能特性区**：6个核心功能卡片展示
  - 多端同步
  - 云端存储
  - 智能管理
  - 阅读批注
  - 用户系统
  - 高性能
- **下载区域**：提供Windows、macOS、Linux三个平台的下载入口
- **页脚**：版权信息

### 2. 注册页面 (register.html)
- 用户名输入（3-50个字符）
- 邮箱输入（必填）
- 手机号输入（可选）
- 密码输入（至少6个字符）
- 确认密码
- 表单验证
- 注册成功后自动跳转到登录页面
- 返回首页链接

### 3. 登录页面 (login.html)
- 用户名输入
- 密码输入
- 登录成功后保存Token到localStorage
- 显示用户角色信息
- 注册入口链接
- 返回首页链接

## 🎨 设计特点

- **渐变色背景**：紫色渐变 (#667eea → #764ba2)
- **响应式设计**：适配桌面和移动设备
- **动画效果**：淡入动画、悬停效果
- **现代化UI**：圆角、阴影、毛玻璃效果
- **用户友好**：清晰的提示信息和错误处理

## 🔧 技术实现

### 后端
- Spring Boot 2.7.18
- Thymeleaf模板引擎
- Spring Security（配置了公开访问路径）

### 前端
- 纯HTML5 + CSS3
- 原生JavaScript（无框架依赖）
- Fetch API进行异步请求

### 安全配置
已在SecurityConfig中配置以下路径为公开访问：
```java
.antMatchers("/").permitAll()
.antMatchers("/register").permitAll()
.antMatchers("/login").permitAll()
.antMatchers("/*.html").permitAll()
```

## 📝 使用示例

### 1. 访问首页
打开浏览器访问 http://localhost:8080/

### 2. 注册用户
- 点击"注册"按钮或访问 http://localhost:8080/register
- 填写注册表单
- 点击注册按钮
- 注册成功后自动跳转到登录页面

### 3. 用户登录
- 点击"登录"按钮或访问 http://localhost:8080/login
- 输入用户名和密码
- 点击登录按钮
- 登录成功后会显示Token和角色信息

### 4. 注册管理员账号
在注册时，可以通过API直接指定角色：
```bash
POST http://localhost:8080/api/auth/register
Content-Type: application/json

{
  "username": "admin",
  "password": "admin123",
  "email": "admin@example.com",
  "role": "ADMIN"
}
```

注意：网页版注册表单默认创建USER角色，如需创建ADMIN角色，需要使用API工具（如Postman）直接调用API。

## 🚀 后续扩展建议

1. **添加书籍列表页面**：登录后展示用户的书籍
2. **在线阅读器**：集成EPUB.js实现在线阅读
3. **个人中心**：用户信息管理、头像上传等
4. **下载功能完善**：提供实际的阅读器安装包下载
5. **多语言支持**：国际化配置
6. **SEO优化**：添加meta标签、sitemap等

## 📂 文件结构

```
src/main/resources/templates/
├── index.html      # 首页
├── register.html   # 注册页面
└── login.html      # 登录页面

src/main/java/com/bookstore/controller/
└── HomeController.java  # 首页控制器
```

## ⚠️ 注意事项

1. 所有页面都已配置为公开访问，无需登录即可查看
2. 注册和登录功能通过JavaScript调用REST API实现
3. 登录成功后Token保存在localStorage中，可在后续API调用中使用
4. 下载链接目前为占位符（#），需要后续添加实际的下载文件

---

**服务状态**: ✅ 运行中  
**访问地址**: http://localhost:8080
