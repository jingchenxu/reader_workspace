package com.bookstore.util;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.web.multipart.MultipartFile;
import org.w3c.dom.*;
import org.xml.sax.InputSource;

import javax.xml.parsers.DocumentBuilder;
import javax.xml.parsers.DocumentBuilderFactory;
import java.io.*;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.HashMap;
import java.util.Map;
import java.util.zip.ZipEntry;
import java.util.zip.ZipInputStream;

/**
 * EPUB文件解析工具类
 * 用于从EPUB文件中提取元数据（书名、作者等）和封面图片
 * EPUB本质上是ZIP压缩包，包含OPF元数据文件和资源文件
 */
public class EpubParser {

    private static final Logger logger = LoggerFactory.getLogger(EpubParser.class);

    /**
     * 从EPUB文件中提取元数据和封面
     *
     * @param file EPUB文件
     * @return 包含元数据和封面数据的Map
     */
    public static Map<String, Object> parseEpub(MultipartFile file) {
        return parseEpub(file::getInputStream);
    }

    public static Map<String, Object> parseEpub(Path path) {
        return parseEpub(() -> Files.newInputStream(path));
    }

    private static Map<String, Object> parseEpub(InputStreamProvider inputStreamProvider) {
        Map<String, Object> result = new HashMap<>();
        
        try (InputStream inputStream = inputStreamProvider.open();
             ZipInputStream zipInputStream = new ZipInputStream(inputStream)) {
            
            // 第一步：读取 container.xml 找到 OPF 文件路径
            String opfPath = findOpfPath(zipInputStream);
            if (opfPath == null) {
                logger.warn("未找到OPF文件");
                return result;
            }
            
            // 第二步：重置流并解析 OPF 文件
            inputStream.close();
            try (InputStream inputStream2 = inputStreamProvider.open();
                 ZipInputStream zipInputStream2 = new ZipInputStream(inputStream2)) {
                
                parseOpfFile(zipInputStream2, opfPath, result);
            }
            
            // 第三步：如果找到了封面路径，提取封面数据
            if (result.containsKey("coverPathInEpub")) {
                String coverPath = (String) result.get("coverPathInEpub");
                try (InputStream inputStream3 = inputStreamProvider.open();
                     ZipInputStream zipInputStream3 = new ZipInputStream(inputStream3)) {
                    extractCoverImage(zipInputStream3, coverPath, result);
                }
            }
            
        } catch (Exception e) {
            logger.error("解析EPUB文件失败", e);
        }

        return result;
    }

    @FunctionalInterface
    private interface InputStreamProvider {
        InputStream open() throws IOException;
    }
    
    /**
     * 查找OPF文件路径（从META-INF/container.xml）
     */
    private static String findOpfPath(ZipInputStream zis) throws Exception {
        ZipEntry entry;
        while ((entry = zis.getNextEntry()) != null) {
            if ("META-INF/container.xml".equals(entry.getName())) {
                Document doc = parseXml(zis);
                NodeList rootFiles = doc.getElementsByTagName("rootfile");
                if (rootFiles.getLength() > 0) {
                    Element rootFile = (Element) rootFiles.item(0);
                    return rootFile.getAttribute("full-path");
                }
            }
            zis.closeEntry();
        }
        return null;
    }
    
    /**
     * 解析OPF文件，提取元数据和封面信息
     */
    private static void parseOpfFile(ZipInputStream zis, String opfPath, Map<String, Object> result) throws Exception {
        ZipEntry entry;
        String opfDir = opfPath.contains("/") ? opfPath.substring(0, opfPath.lastIndexOf('/') + 1) : "";
        
        while ((entry = zis.getNextEntry()) != null) {
            if (entry.getName().equals(opfPath)) {
                Document doc = parseXml(zis);
                
                // 提取元数据
                NodeList metadataNodes = doc.getElementsByTagName("metadata");
                if (metadataNodes.getLength() > 0) {
                    Element metadata = (Element) metadataNodes.item(0);
                    extractMetadata(metadata, result);
                }
                
                // 查找封面引用
                NodeList manifestNodes = doc.getElementsByTagName("item");
                String coverId = null;
                for (int i = 0; i < manifestNodes.getLength(); i++) {
                    Element item = (Element) manifestNodes.item(i);
                    String properties = item.getAttribute("properties");
                    if (properties != null && properties.contains("cover-image")) {
                        coverId = item.getAttribute("id");
                        break;
                    }
                }
                
                // 如果没找到cover-image属性，尝试找meta中的cover引用
                if (coverId == null) {
                    NodeList metaNodes = metadataNodes.item(0).getChildNodes();
                    for (int i = 0; i < metaNodes.getLength(); i++) {
                        if (metaNodes.item(i) instanceof Element) {
                            Element meta = (Element) metaNodes.item(i);
                            if ("cover".equals(meta.getAttribute("name"))) {
                                coverId = meta.getAttribute("content");
                                break;
                            }
                        }
                    }
                }
                
                // 根据coverId找到封面文件路径
                if (coverId != null) {
                    String coverPath = findCoverPath(manifestNodes, coverId);
                    if (coverPath != null) {
                        result.put("coverPathInEpub", opfDir + coverPath);
                        logger.info("找到封面文件: {}", opfDir + coverPath);
                    }
                }
                
                break;
            }
            zis.closeEntry();
        }
    }
    
    /**
     * 从manifest中查找封面文件路径
     */
    private static String findCoverPath(NodeList manifestNodes, String coverId) {
        for (int i = 0; i < manifestNodes.getLength(); i++) {
            Element item = (Element) manifestNodes.item(i);
            if (coverId.equals(item.getAttribute("id"))) {
                return item.getAttribute("href");
            }
        }
        return null;
    }
    
    /**
     * 提取元数据
     */
    private static void extractMetadata(Element metadata, Map<String, Object> result) {
        // 标题
        NodeList titles = metadata.getElementsByTagName("dc:title");
        if (titles.getLength() > 0) {
            result.put("title", titles.item(0).getTextContent());
        }
        
        // 作者
        NodeList creators = metadata.getElementsByTagName("dc:creator");
        if (creators.getLength() > 0) {
            result.put("author", creators.item(0).getTextContent());
        }
        
        // 出版商
        NodeList publishers = metadata.getElementsByTagName("dc:publisher");
        if (publishers.getLength() > 0) {
            result.put("publisher", publishers.item(0).getTextContent());
        }
        
        // 语言
        NodeList languages = metadata.getElementsByTagName("dc:language");
        if (languages.getLength() > 0) {
            result.put("language", languages.item(0).getTextContent());
        }
        
        // 描述
        NodeList descriptions = metadata.getElementsByTagName("dc:description");
        if (descriptions.getLength() > 0) {
            result.put("description", descriptions.item(0).getTextContent());
        }
        
        // ISBN
        NodeList identifiers = metadata.getElementsByTagName("dc:identifier");
        for (int i = 0; i < identifiers.getLength(); i++) {
            Element identifier = (Element) identifiers.item(i);
            String raw = identifier.getTextContent();
            String scheme = identifier.getAttribute("opf:scheme");
            if (scheme == null || scheme.trim().isEmpty()) {
                scheme = identifier.getAttribute("scheme");
            }
            String isbn = normalizeIsbn(raw);
            if (isbn != null || "isbn".equalsIgnoreCase(scheme)) {
                if (isbn != null) result.put("isbn", isbn);
                break;
            }
        }
    }

    private static String normalizeIsbn(String value) {
        if (value == null) return null;
        String normalized = value.trim().replaceFirst("(?i)^urn:isbn:", "")
            .replaceFirst("(?i)^isbn[:\\s-]*", "")
            .replaceAll("[\\s-]", "");
        if (normalized.matches("\\d{13}") || normalized.matches("\\d{9}[\\dXx]")) {
            return normalized.toUpperCase();
        }
        return null;
    }
    
    /**
     * 解析XML
     */
    private static Document parseXml(InputStream is) throws Exception {
        DocumentBuilderFactory factory = DocumentBuilderFactory.newInstance();
        factory.setNamespaceAware(true);
        DocumentBuilder builder = factory.newDocumentBuilder();
        return builder.parse(new InputSource(new InputStreamReader(is, StandardCharsets.UTF_8)));
    }
    
    /**
     * 从EPUB ZIP中提取封面图片数据
     */
    private static void extractCoverImage(ZipInputStream zis, String coverPath, Map<String, Object> result) throws Exception {
        ZipEntry entry;
        while ((entry = zis.getNextEntry()) != null) {
            if (entry.getName().equals(coverPath)) {
                // 读取封面图片数据
                ByteArrayOutputStream baos = new ByteArrayOutputStream();
                byte[] buffer = new byte[4096];
                int len;
                while ((len = zis.read(buffer)) > 0) {
                    baos.write(buffer, 0, len);
                }
                
                byte[] coverData = baos.toByteArray();
                result.put("coverData", coverData);
                
                // 根据文件扩展名确定MIME类型
                String mimeType = "image/jpeg"; // 默认
                if (coverPath.toLowerCase().endsWith(".png")) {
                    mimeType = "image/png";
                } else if (coverPath.toLowerCase().endsWith(".gif")) {
                    mimeType = "image/gif";
                } else if (coverPath.toLowerCase().endsWith(".webp")) {
                    mimeType = "image/webp";
                }
                result.put("coverMimeType", mimeType);
                
                // 确定文件扩展名
                String extension = ".jpg";
                if (coverPath.toLowerCase().endsWith(".png")) {
                    extension = ".png";
                } else if (coverPath.toLowerCase().endsWith(".gif")) {
                    extension = ".gif";
                } else if (coverPath.toLowerCase().endsWith(".webp")) {
                    extension = ".webp";
                }
                result.put("coverExtension", extension);
                
                logger.info("成功提取封面图片，大小: {} bytes, 类型: {}", coverData.length, mimeType);
                break;
            }
            zis.closeEntry();
        }
    }
}
