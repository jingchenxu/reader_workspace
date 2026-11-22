# Swagger API文档使用说明

## 📖 概述

已成功集成Swagger (SpringDoc OpenAPI 3.0) 用于EPUB阅读器服务端的接口管理与调试。

## 🌐 访问地址

### Swagger UI（推荐）
```
http://localhost:8080/swagger-ui.html
```
或
```
http://localhost:8080/swagger-ui/index.html
```

### OpenAPI JSON文档
```
http://localhost:8080/v3/api-docs
```

### OpenAPI YAML文档
```
http://localhost:8080/v3/api-docs.yaml
```

## ✨ 功能特性

### 1. 接口分类展示
所有API按功能模块分组：
- **用户认证** - 注册、登录等
- **书籍管理** - 同步、查询、删除书籍
- **阅读同步** - 阅读进度、书签、批注

### 2. JWT认证支持
- 页面顶部有"Authorize"按钮
- 点击后输入JWT Token（格式：Bearer {token}）
- 所有需要认证的接口会自动携带Token

### 3. 在线调试
- 每个接口都有"Try it out"按钮
- 可以填写参数并直接发送请求
- 实时查看响应结果

### 4. 详细文档
- 接口说明
- 参数描述
- 请求示例
- 响应示例
- 数据模型

## 📝 使用步骤

### 1. 访问Swagger UI
打开浏览器访问：http://localhost:8080/swagger-ui.html

### 2. 认证（如需测试需要登录的接口）

#### 步骤1：获取Token
先通过`/api/auth/login`接口登录获取Token：
```json
POST /api/auth/login
{
  "username": "your_username",
  "password": "your_password"
}
```

响应：
```json
{
  "success": true,
  "data": {
    "token": "eyJhbGciOiJIUzI1NiJ9...",
    "type": "Bearer",
    "userId": 1,
    "username": "admin",
    "email": "admin@example.com",
    "role": "ADMIN"
  }
}
```

#### 步骤2：配置Authorization
1. 点击页面右上角的 **"Authorize"** 按钮
2. 在Value框中输入：`Bearer eyJhbGciOiJIUzI1NiJ9...`（完整Token）
3. 点击 **"Authorize"**
4. 点击 **"Close"**

### 3. 测试接口

#### 示例1：注册用户
1. 展开 **"用户认证"** 分组
2. 点击 `POST /api/auth/register`
3. 点击 **"Try it out"**
4. 填写请求体：
```json
{
  "username": "testuser",
  "password": "test123",
  "email": "test@example.com",
  "phone": "13800138000"
}
```
5. 点击 **"Execute"**
6. 查看响应结果

#### 示例2：获取书籍列表
1. 展开 **"书籍管理"** 分组
2. 点击 `GET /api/books`
3. 点击 **"Try it out"**
4. 点击 **"Execute"**（需要先完成认证）
5. 查看返回的书籍列表

#### 示例3：同步书籍
1. 展开 **"书籍管理"** 分组
2. 点击 `POST /api/books/sync`
3. 点击 **"Try it out"**
4. 上传EPUB文件并填写书籍信息
5. 点击 **"Execute"**

## 📊 API分组说明

### 用户认证 (Auth Controller)
- `POST /api/auth/register` - 用户注册
- `POST /api/auth/login` - 用户登录

### 书籍管理 (Book Controller)
- `POST /api/books/sync` - 同步书籍
- `GET /api/books` - 获取书籍列表
- `DELETE /api/books/{id}` - 删除书籍

### 阅读同步 (Sync Controller)
- `POST /api/sync/progress` - 保存阅读进度
- `GET /api/sync/progress/{bookId}` - 获取阅读进度
- `POST /api/sync/bookmark` - 添加书签
- `GET /api/sync/bookmarks/{bookId}` - 获取书签列表
- `DELETE /api/sync/bookmark/{id}` - 删除书签
- `POST /api/sync/annotation` - 添加批注
- `GET /api/sync/annotations/{bookId}` - 获取批注列表
- `PUT /api/sync/annotation/{id}` - 更新批注
- `DELETE /api/sync/annotation/{id}` - 删除批注

### 管理员接口 (Admin Controller)
- `GET /api/admin/users` - 获取所有用户
- `PUT /api/admin/users/{id}/role` - 更新用户角色

## 🔧 技术实现

### 依赖
```xml
<dependency>
    <groupId>org.springdoc</groupId>
    <artifactId>springdoc-openapi-ui</artifactId>
    <version>1.7.0</version>
</dependency>
```

### 配置类
- `SwaggerConfig.java` - Swagger配置
  - API标题、描述、版本
  - 联系信息
  - JWT认证配置

### Controller注解
- `@Tag` - 接口分组
- `@Operation` - 接口说明
- `@Parameter` - 参数说明

### 安全配置
已在SecurityConfig中配置Swagger路径为公开访问：
```java
.antMatchers("/swagger-ui/**").permitAll()
.antMatchers("/v3/api-docs/**").permitAll()
.antMatchers("/swagger-resources/**").permitAll()
.antMatchers("/webjars/**").permitAll()
```

## 💡 使用技巧

### 1. 快速复制Curl命令
点击"Execute"后，可以在响应区域看到完整的curl命令，方便在终端中测试。

### 2. 查看数据模型
在页面底部可以看到所有DTO和Entity的数据模型定义。

### 3. 导出API文档
- 访问 `/v3/api-docs` 获取JSON格式
- 访问 `/v3/api-docs.yaml` 获取YAML格式
- 可以导入到Postman或其他API工具

### 4. 搜索接口
使用页面顶部的搜索框快速查找特定接口。

## ⚠️ 注意事项

1. **认证要求**：大部分接口需要JWT Token才能访问
2. **Token格式**：必须包含"Bearer "前缀
3. **文件上传**：同步书籍接口需要使用multipart/form-data
4. **参数验证**：注意必填参数和参数格式
5. **错误处理**：查看响应中的error字段了解错误原因

## 🎯 优势

1. **可视化**：清晰的接口展示和分组
2. **交互式**：可以直接测试API
3. **自动化**：自动生成文档，无需手动维护
4. **标准化**：遵循OpenAPI 3.0规范
5. **易用性**：友好的用户界面

## 📂 相关文件

### 配置
- `pom.xml` - Swagger依赖
- `SwaggerConfig.java` - Swagger配置
- `SecurityConfig.java` - 安全配置

### Controller注解
- `AuthController.java` - 用户认证接口
- `BookController.java` - 书籍管理接口
- `SyncController.java` - 阅读同步接口
- `AdminController.java` - 管理员接口

---

**Swagger版本**: SpringDoc OpenAPI 1.7.0  
**OpenAPI版本**: 3.0  
**访问地址**: http://localhost:8080/swagger-ui.html  
**集成时间**: 2026-05-27 14:20
