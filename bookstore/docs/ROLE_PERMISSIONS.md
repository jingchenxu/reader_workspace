# EPUB阅读器服务端 - 角色权限说明

## 用户角色

系统支持两种用户角色：

### 1. USER（普通用户）
- 只能查看和管理自己的书籍
- 可以同步、删除自己的书籍
- 可以管理自己的阅读进度、书签和批注

### 2. ADMIN（管理员）
- 可以查看所有用户的书籍
- 可以管理所有用户
- 拥有普通用户的所有权限

## API接口权限

### 公开接口（无需登录）
- `POST /api/auth/register` - 用户注册
- `POST /api/auth/login` - 用户登录

### 认证接口（需要登录）

#### 书籍接口
- `POST /api/books/sync` - 同步书籍（所有用户）
- `GET /api/books` - 获取书籍列表
  - 普通用户：只返回自己的书籍
  - 管理员：返回所有书籍
- `DELETE /api/books/{id}` - 删除书籍（只能删除自己的）

#### 同步接口
- `POST /api/sync/progress` - 保存阅读进度
- `GET /api/sync/progress/{bookId}` - 获取阅读进度
- `POST /api/sync/bookmark` - 添加书签
- `GET /api/sync/bookmarks/{bookId}` - 获取书签列表
- `DELETE /api/sync/bookmark/{id}` - 删除书签
- `POST /api/sync/annotation` - 添加批注
- `GET /api/sync/annotations/{bookId}` - 获取批注列表
- `PUT /api/sync/annotation/{id}` - 更新批注
- `DELETE /api/sync/annotation/{id}` - 删除批注

### 管理员接口（仅ADMIN角色）

#### 用户管理
- `GET /api/admin/users` - 获取所有用户列表
- `PUT /api/admin/users/{id}/role` - 更新用户角色

## 使用示例

### 1. 注册管理员账号

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

### 2. 注册普通用户

```bash
POST http://localhost:8080/api/auth/register
Content-Type: application/json

{
  "username": "user1",
  "password": "user123",
  "email": "user1@example.com",
  "role": "USER"
}
```

### 3. 登录获取Token

```bash
POST http://localhost:8080/api/auth/login
Content-Type: application/json

{
  "username": "admin",
  "password": "admin123"
}

响应：
{
  "success": true,
  "message": "登录成功",
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

### 4. 管理员查看所有书籍

```bash
GET http://localhost:8080/api/books
Authorization: Bearer {admin_token}
```

### 5. 普通用户查看自己的书籍

```bash
GET http://localhost:8080/api/books
Authorization: Bearer {user_token}
```

### 6. 管理员查看所有用户

```bash
GET http://localhost:8080/api/admin/users
Authorization: Bearer {admin_token}
```

### 7. 管理员修改用户角色

```bash
PUT http://localhost:8080/api/admin/users/2/role
Authorization: Bearer {admin_token}
Content-Type: application/json

{
  "role": "ADMIN"
}
```

## 数据库表结构

### users表新增字段
- `role` VARCHAR(20) - 用户角色（USER或ADMIN），默认为USER

## 注意事项

1. 首次使用时，需要手动创建一个ADMIN角色的账号
2. 可以通过直接修改数据库或将第一个注册用户设置为ADMIN
3. 建议至少保留一个ADMIN账号用于系统管理
4. 普通用户尝试访问管理员接口会返回403 Forbidden错误
