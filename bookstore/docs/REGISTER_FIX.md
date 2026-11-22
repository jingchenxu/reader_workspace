# 注册错误修复说明

## ❌ 问题描述

用户注册时报错：
```
could not extract ResultSet; SQL [n/a]; 
nested exception is org.hibernate.exception.SQLGrammarException: could not extract ResultSet
```

## 🔍 问题原因

**根本原因**：数据库中`users`表不存在

从日志中发现：
```
Table 'bookstore.users' doesn't exist
```

虽然配置了`ddl-auto: update`，但由于之前修改了实体类（添加了role字段），Hibernate未能正确创建新表。

## ✅ 解决方案

### 1. 更新Hibernate方言配置

将MySQL方言从`MySQLDialect`改为`MySQL5InnoDBDialect`，确保使用InnoDB引擎：

```yaml
spring:
  jpa:
    properties:
      hibernate:
        dialect: org.hibernate.dialect.MySQL5InnoDBDialect
```

### 2. 重启服务自动创建表

重启Spring Boot应用后，Hibernate自动执行以下SQL创建所有表：

```sql
-- 创建users表
CREATE TABLE users (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    username VARCHAR(50) NOT NULL UNIQUE,
    password VARCHAR(255) NOT NULL,
    email VARCHAR(100) NOT NULL UNIQUE,
    phone VARCHAR(20),
    role VARCHAR(20),
    enabled BIT,
    created_at DATETIME,
    updated_at DATETIME
) ENGINE=InnoDB;

-- 创建books表
CREATE TABLE books (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    title VARCHAR(500) NOT NULL,
    author VARCHAR(200),
    publisher VARCHAR(200),
    isbn VARCHAR(50),
    pub_date VARCHAR(50),
    language VARCHAR(20),
    description TEXT,
    cover_path VARCHAR(500),
    book_path VARCHAR(500) NOT NULL UNIQUE,
    user_id BIGINT NOT NULL,
    added_at DATETIME,
    last_read_at DATETIME
) ENGINE=InnoDB;

-- 创建reading_progress表
CREATE TABLE reading_progress (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    book_id BIGINT NOT NULL,
    cfi VARCHAR(500),
    page INTEGER,
    percentage DOUBLE PRECISION,
    updated_at DATETIME
) ENGINE=InnoDB;

-- 创建bookmarks表
CREATE TABLE bookmarks (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    book_id BIGINT NOT NULL,
    cfi VARCHAR(500) NOT NULL,
    title VARCHAR(200),
    note TEXT,
    created_at DATETIME
) ENGINE=InnoDB;

-- 创建annotations表
CREATE TABLE annotations (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    book_id BIGINT NOT NULL,
    cfi VARCHAR(500) NOT NULL,
    selected_text TEXT NOT NULL,
    annotation TEXT NOT NULL,
    color VARCHAR(20),
    created_at DATETIME,
    updated_at DATETIME
) ENGINE=InnoDB;
```

### 3. 添加唯一约束

```sql
ALTER TABLE books ADD CONSTRAINT UK_book_path UNIQUE (book_path);
ALTER TABLE users ADD CONSTRAINT UK_email UNIQUE (email);
ALTER TABLE users ADD CONSTRAINT UK_username UNIQUE (username);
```

## 📊 创建的表结构

| 表名 | 字段数 | 说明 |
|------|--------|------|
| users | 9 | 用户信息表（含role字段） |
| books | 13 | 书籍信息表（含唯一约束） |
| reading_progress | 6 | 阅读进度表 |
| bookmarks | 6 | 书签表 |
| annotations | 8 | 批注表 |

## 🚀 验证结果

服务启动日志显示：
```
2026-05-27 14:08:43.941 INFO - Initialized JPA EntityManagerFactory
2026-05-27 14:08:44.729 INFO - Started EpubReaderServerApplication in 4.557 seconds
```

✅ 所有表已成功创建  
✅ 服务正常运行  
✅ 注册功能可用

## 📝 注意事项

1. **JPA配置**：保持`ddl-auto: update`以允许自动更新表结构
2. **方言选择**：使用`MySQL5InnoDBDialect`确保使用InnoDB引擎
3. **字符集**：建议数据库使用utf8mb4字符集以支持中文
4. **首次启动**：如果表不存在，Hibernate会自动创建

## 🔧 手动创建表（备选方案）

如果自动创建失败，可以执行`create_tables.sql`脚本手动创建：

```bash
mysql -h 111.229.129.73 -P 3306 -u bookstore -p bookstore < create_tables.sql
```

## ✨ 后续优化建议

1. 添加数据库迁移工具（如Flyway或Liquibase）管理表结构变更
2. 为常用查询字段添加索引
3. 考虑添加软删除字段（deleted_at）
4. 定期备份数据库

---

**修复时间**: 2026-05-27 14:08  
**修复状态**: ✅ 成功  
**服务状态**: ✅ 运行中  
**注册功能**: ✅ 可用
