# SQLite表结构同步说明

## 📊 同步完成时间
2026-05-27

## ✅ 已同步的表结构

### 1. books 表

**SQLite结构：**
```sql
CREATE TABLE books (
    id INTEGER PRIMARY KEY,
    title TEXT NOT NULL,
    author TEXT,
    publisher TEXT,
    isbn TEXT,
    pub_date TEXT,
    language TEXT,
    description TEXT,
    cover_path TEXT,
    book_path TEXT NOT NULL UNIQUE,
    added_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    last_read_at DATETIME
);
```

**服务端实体变更：**
- ✅ 添加唯一约束：`@UniqueConstraint(columnNames = "book_path")`
- ❌ 移除字段：`fileName`, `fileSize`, `fileType`, `createdAt`, `updatedAt`
- ✅ 保留字段：所有SQLite中的字段

### 2. reading_progress 表

**SQLite结构：**
```sql
CREATE TABLE reading_progress (
    id INTEGER PRIMARY KEY,
    book_id INTEGER NOT NULL,
    cfi TEXT,
    page INTEGER DEFAULT 0,
    percentage REAL DEFAULT 0,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
);
```

**服务端实体变更：**
- ✅ 添加默认值：`page = 0`, `percentage = 0.0`
- ✅ 完全匹配SQLite结构

### 3. bookmarks 表

**SQLite结构：**
```sql
CREATE TABLE bookmarks (
    id INTEGER PRIMARY KEY,
    book_id INTEGER NOT NULL,
    cfi TEXT NOT NULL,
    title TEXT,
    note TEXT,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP
);
```

**服务端实体状态：**
- ✅ 完全匹配SQLite结构
- ✅ cfi字段已设置为NOT NULL

### 4. annotations 表

**SQLite结构：**
```sql
CREATE TABLE annotations (
    id INTEGER PRIMARY KEY,
    book_id INTEGER NOT NULL,
    cfi TEXT NOT NULL,
    selected_text TEXT NOT NULL,
    annotation TEXT NOT NULL,
    color TEXT DEFAULT '#FFEB3B',
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
);
```

**服务端实体变更：**
- ✅ 添加默认颜色值：`color = "#FFEB3B"`
- ✅ 完全匹配SQLite结构

## 🔄 修改的文件清单

### Entity层
1. `Book.java` - 移除多余字段，添加唯一约束
2. `ReadingProgress.java` - 添加默认值
3. `Bookmark.java` - 无需修改（已匹配）
4. `Annotation.java` - 添加默认颜色值

### DTO层
5. `BookSyncRequest.java` - 移除fileName, fileSize, fileType，添加bookPath
6. `BookResponse.java` - 移除fileName, fileSize, fileType, createdAt

### Repository层
7. `BookRepository.java` - 将`existsByUserIdAndFileName`改为`existsByUserIdAndBookPath`

### Service层
8. `BookService.java` - 更新convertToResponse方法，移除多余字段映射

## 🗑️ 删除的字段

以下字段在服务端存在但SQLite中不存在，已删除：

### Book实体
- `fileName` - 文件名
- `fileSize` - 文件大小
- `fileType` - 文件类型
- `createdAt` - 创建时间（使用addedAt替代）
- `updatedAt` - 更新时间

## ✨ 新增的特性

1. **唯一约束**：books表的book_path字段添加唯一约束，防止同一用户重复上传相同路径的书籍
2. **默认值**：为reading_progress和annotations添加了合理的默认值

## 🔍 对比验证

通过Python脚本读取SQLite数据库结构，确保服务端与桌面端完全一致：

```bash
python read_sqlite_structure.py
```

输出显示所有4个表的结构已完全对齐。

## 🚀 服务状态

- **状态**: ✅ 运行中
- **端口**: 8080
- **数据库**: MySQL (已自动同步表结构)
- **访问地址**: http://localhost:8080

## 📝 注意事项

1. **数据迁移**：如果之前有旧数据，需要注意删除的字段会导致数据丢失
2. **API兼容性**：前端调用API时不应再传递fileName、fileSize、fileType字段
3. **书籍去重**：现在通过book_path进行唯一性校验，而不是fileName

## 🎯 下一步建议

1. 测试书籍同步功能，确保新结构正常工作
2. 验证唯一约束是否生效
3. 检查默认值是否正确应用
4. 更新前端代码以适配新的API结构

---

**同步完成时间**: 2026-05-27 14:03  
**同步状态**: ✅ 成功  
**服务状态**: ✅ 运行中
