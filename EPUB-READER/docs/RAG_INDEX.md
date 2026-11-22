# RAG 知识库项目文档索引

## 📁 文档位置说明

所有 RAG（检索增强生成）相关的文档已移至 `RAG/` 文件夹。

## 📚 RAG 项目文档列表

| 文档 | 路径 | 大小 | 用途 |
|------|------|------|------|
| 智能体最佳实践 | [RAG/AGENT_BEST_PRACTICES.md](../RAG/AGENT_BEST_PRACTICES.md) | 8.14 KB | 智能体构建方法论 |
| RAG 实施方案 | [RAG/RAG_IMAGE_KNOWLEDGE_BASE.md](../RAG/RAG_IMAGE_KNOWLEDGE_BASE.md) | 19.28 KB | 完整技术实施方案 |
| 快速启动指南 | [RAG/RAG_QUICK_START.md](../RAG/RAG_QUICK_START.md) | 5.39 KB | 快速入门教程 |
| 简化示例代码 | [RAG/simple_rag_example.py](../RAG/simple_rag_example.py) | 8.93 KB | 可运行示例 |
| 项目总览 | [RAG/RAG_PROJECT_README.md](../RAG/RAG_PROJECT_README.md) | 8 KB | 项目导航和概述 |
| 项目总结 | [RAG/RAG_PROJECT_SUMMARY.md](../RAG/RAG_PROJECT_SUMMARY.md) | 8.12 KB | 完成总结和计划 |
| 快速参考 | [RAG/RAG_QUICK_REFERENCE.md](../RAG/RAG_QUICK_REFERENCE.md) | 9.55 KB | 命令速查和技巧 |

**总计**: 7 个文件，约 67.41 KB

## 🚀 快速开始

### 1. 阅读文档

建议按以下顺序阅读：

1. **初学者**: 
   - [RAG_QUICK_START.md](../RAG/RAG_QUICK_START.md) - 快速入门
   - [simple_rag_example.py](../RAG/simple_rag_example.py) - 运行示例

2. **开发者**:
   - [RAG_IMAGE_KNOWLEDGE_BASE.md](../RAG/RAG_IMAGE_KNOWLEDGE_BASE.md) - 技术实现
   - [AGENT_BEST_PRACTICES.md](../RAG/AGENT_BEST_PRACTICES.md) - 最佳实践

3. **快速查阅**:
   - [RAG_QUICK_REFERENCE.md](../RAG/RAG_QUICK_REFERENCE.md) - 速查手册

### 2. 准备环境

```powershell
# 创建 pest 图片文件夹
New-Item -ItemType Directory -Path "pest"

# 复制图片到 pest 文件夹
# Copy-Item "your_images\*" -Destination "pest\"

# 安装依赖
pip install pillow pytesseract chromadb sentence-transformers

# 运行示例
python RAG/simple_rag_example.py
```

## 📊 项目结构

```
EPUB-READER/
├── RAG/                      # RAG 知识库项目
│   ├── AGENT_BEST_PRACTICES.md           # 智能体最佳实践
│   ├── RAG_IMAGE_KNOWLEDGE_BASE.md       # 技术实施方案
│   ├── RAG_QUICK_START.md                # 快速启动指南
│   ├── simple_rag_example.py             # 简化示例代码
│   ├── RAG_PROJECT_README.md             # 项目总览
│   ├── RAG_PROJECT_SUMMARY.md            # 项目总结
│   └── RAG_QUICK_REFERENCE.md            # 快速参考
├── docs/                     # 其他项目文档
│   └── RAG_INDEX.md          # 本文件（索引）
└── pest/                     # 害虫图片文件夹（需手动创建）
    └── *.jpg, *.png, ...     # 图片文件
```

## 🎯 核心功能

- ✅ OCR 文字识别（支持中英文）
- ✅ 图像描述生成（可选）
- ✅ 向量检索（语义搜索）
- ✅ 智能问答（LLM 生成回答）
- ✅ 本地部署（完全离线）

## 🔧 技术栈

- **OCR**: PaddleOCR / Tesseract
- **向量数据库**: ChromaDB
- **嵌入模型**: all-MiniLM-L6-v2
- **LLM**: Llama 3 (Ollama)
- **框架**: LangChain

## 📖 相关文档

### EPUB Reader 项目文档

- [云端存储本地进度](./CLOUD_STORAGE_LOCAL_PROGRESS.md)
- [数据存储说明](./DATA_STORAGE.md)
- [文档合并记录](./DOCUMENT_MERGE_RECORD.md)
- [EPUB 文件协议修复](./EPUB_FILE_PROTOCOL_FIX.md)
- [图标修复指南](./ICON_FIX_GUIDE.md)
- [路径兼容性](./PATH_COMPATIBILITY.md)

## 💡 提示

- 所有 RAG 相关的新文档都应放在 `RAG/` 文件夹
- `docs/` 文件夹保留 EPUB Reader 项目的其他文档
- 遵循项目规范，文档更新需同步到对应文件

---

**最后更新**: 2026-06-29  
**维护者**: EPUB-READER Team
