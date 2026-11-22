# EPUB阅读器服务端

基于Spring Boot开发的EPUB阅读器后端服务，提供用户认证和书籍同步功能。

## 功能特性

- ✅ 用户注册与登录（JWT认证）
- ✅ EPUB书籍文件上传与同步
- ✅ 书籍元数据管理
- ✅ RESTful API接口
- ✅ 文件存储管理

## 技术栈

- Java 17
- Spring Boot 3.2.0
- Spring Security + JWT
- Spring Data JPA
- MySQL 8.0+
- Maven

## 快速开始

### 1. 环境要求

- JDK 17+
- Maven 3.6+
- MySQL 8.0+

### 2. 数据库配置

创建数据库：
```sql
CREATE DATABASE epub_reader CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
```

修改 `src/main/resources/application.yml` 中的数据库配置：
```yaml
spring:
  datasource:
    url: jdbc:mysql://localhost:3306/epub_reader
    username: your_username
    password: your_password
```

### 3. 编译运行

```bash
mvn clean package
java -jar target/epub-reader-server-1.0.0.jar
```

或使用Maven直接运行：
```bash
mvn spring-boot:run
```

## API接口文档

### 认证接口

#### 注册用户
- **URL**: `POST /api/auth/register`
- **请求体**:
```json
{
  "username": "testuser",
  "password": "123456",
  "email": "test@example.com",
  "phone": "13800138000"
}
```

#### 用户登录
- **URL**: `POST /api/auth/login`
- **请求体**:
```json
{
  "username": "testuser",
  "password": "123456"
}
```
- **响应**:
```json
{
  "success": true,
  "message": "登录成功",
  "data": {
    "token": "eyJhbGciOiJIUzI1NiJ9...",
    "type": "Bearer",
    "userId": 1,
    "username": "testuser",
    "email": "test@example.com"
  }
}
```

### 书籍接口

所有书籍接口需要在Header中携带JWT Token：
```
Authorization: Bearer {your_token}
```

#### 同步书籍
- **URL**: `POST /api/books/sync`
- **Content-Type**: `multipart/form-data`
- **参数**:
  - `file`: EPUB文件
  - `title`: 书名
  - `author`: 作者
  - `isbn`: ISBN号
  - `description`: 描述
  - `coverUrl`: 封面URL
  - `fileName`: 文件名
  - `fileSize`: 文件大小

#### 获取书籍列表
- **URL**: `GET /api/books`
- **响应**:
```json
{
  "success": true,
  "message": "获取书籍列表成功",
  "data": [
    {
      "id": 1,
      "title": "示例书籍",
      "author": "作者名",
      "isbn": "978-7-111-11111-1",
      "description": "书籍描述",
      "coverUrl": "http://example.com/cover.jpg",
      "filePath": "./uploads/books/xxx.epub",
      "fileName": "book.epub",
      "fileSize": 1024000,
      "fileType": "epub",
      "syncTime": "2024-01-01T12:00:00",
      "createdAt": "2024-01-01T12:00:00"
    }
  ]
}
```

#### 删除书籍
- **URL**: `DELETE /api/books/{id}`

## 项目结构

```
src/main/java/com/bookstore/
├── controller/          # 控制器层
│   ├── AuthController.java
│   └── BookController.java
├── dto/                 # 数据传输对象
│   ├── ApiResponse.java
│   ├── BookResponse.java
│   ├── BookSyncRequest.java
│   ├── JwtResponse.java
│   ├── LoginRequest.java
│   └── RegisterRequest.java
├── entity/              # 实体类
│   ├── Book.java
│   └── User.java
├── exception/           # 异常处理
│   └── GlobalExceptionHandler.java
├── repository/          # 数据访问层
│   ├── BookRepository.java
│   └── UserRepository.java
├── security/            # 安全配置
│   ├── JwtAuthenticationFilter.java
│   ├── JwtUtils.java
│   └── SecurityConfig.java
└── service/             # 业务逻辑层
    ├── AuthService.java
    ├── BookService.java
    └── UserDetailsServiceImpl.java
```

## 配置说明

### JWT配置
在 `application.yml` 中配置：
```yaml
app:
  jwt:
    secret: YourSecretKeyForJWTTokenGenerationMustBeLongEnoughAndSecure2024
    expiration: 86400000  # 24小时（毫秒）
```

### 文件上传配置
```yaml
app:
  file:
    upload-dir: ./uploads/books  # 文件存储路径
    max-size: 52428800           # 最大文件大小50MB
```

## 注意事项

1. 首次运行前请确保MySQL数据库已创建并正确配置
2. JWT密钥请修改为安全的随机字符串
3. 生产环境建议启用HTTPS
4. 文件上传目录需要有读写权限
5. 建议定期备份数据库和上传的文件

## License

MIT
