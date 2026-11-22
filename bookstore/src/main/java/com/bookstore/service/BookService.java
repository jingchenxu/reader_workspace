package com.bookstore.service;

import com.bookstore.dto.BookResponse;
import com.bookstore.dto.BookSyncRequest;
import com.bookstore.entity.Book;
import com.bookstore.entity.Category;
import com.bookstore.entity.User;
import com.bookstore.repository.BookRepository;
import com.bookstore.repository.CategoryRepository;
import com.bookstore.repository.UserRepository;
import com.bookstore.util.EpubParser;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.core.io.FileSystemResource;
import org.springframework.core.io.Resource;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.multipart.MultipartFile;

import java.io.IOException;
import java.io.InputStream;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.nio.file.StandardCopyOption;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.time.LocalDateTime;
import java.util.List;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.Optional;
import java.util.Comparator;
import java.util.UUID;
import java.util.stream.Collectors;

@Service
public class BookService {

    private static final Logger logger = LoggerFactory.getLogger(BookService.class);
    private static final long MAX_UPLOAD_SIZE = 50L * 1024 * 1024;

    private final BookRepository bookRepository;
    private final CategoryRepository categoryRepository;
    private final UserRepository userRepository;
    private final StorageQuotaService storageQuotaService;

    @Value("${app.file.upload-dir}")
    private String uploadDir;

    @Value("${app.file.cover-upload-dir}")
    private String coverUploadDir;

    public BookService(BookRepository bookRepository,
                       CategoryRepository categoryRepository,
                       UserRepository userRepository,
                       StorageQuotaService storageQuotaService) {
        this.bookRepository = bookRepository;
        this.categoryRepository = categoryRepository;
        this.userRepository = userRepository;
        this.storageQuotaService = storageQuotaService;
    }

    @Transactional
    public BookResponse syncBook(Long userId, BookSyncRequest syncRequest, MultipartFile file, MultipartFile coverFile) {
        try {
            validateUpload(file);
            User user = userRepository.findById(userId)
                .orElseThrow(() -> new RuntimeException("用户不存在"));

            String originalFilename = sanitizeOriginalFilename(file.getOriginalFilename());
            String requestedTitle = syncRequest.getTitle();
            String displayTitle = isBlank(requestedTitle)
                ? removeEpubExtension(originalFilename)
                : requestedTitle.trim();
            String fileHash = calculateSha256(file);

            Optional<Book> userOwnedBook = bookRepository.findByUserIdAndFileHash(userId, fileHash);
            long additionalBytes = userOwnedBook.isPresent() ? 0L : file.getSize();
            storageQuotaService.assertCanStore(user, additionalBytes);

            List<Book> sharedBooks = bookRepository.findByFileHash(fileHash);
            String bookPath = resolveSharedBookPath(fileHash, file, sharedBooks);
            String coverPath = resolveCoverPath(file, coverFile, sharedBooks);

            populateMissingMetadata(syncRequest, file);

            Book book = userOwnedBook.orElseGet(Book::new);
            book.setTitle(displayTitle);
            book.setOriginalFileName(originalFilename);
            book.setFileHash(fileHash);
            book.setAuthor(syncRequest.getAuthor());
            book.setPublisher(syncRequest.getPublisher());
            book.setIsbn(syncRequest.getIsbn());
            book.setPubDate(syncRequest.getPubDate());
            book.setLanguage(syncRequest.getLanguage());
            book.setDescription(syncRequest.getDescription());
            book.setCoverPath(coverPath);
            book.setBookPath(bookPath);
            book.setFileSize(file.getSize());
            book.setUserId(userId);
            if (hasCategoryInfo(syncRequest)) {
                book.setCategoryId(resolveCategoryId(userId, syncRequest));
            }
            if (book.getAddedAt() == null) {
                book.setAddedAt(LocalDateTime.now());
            }

            Book saved = bookRepository.saveAndFlush(book);
            logger.info("Book synchronized: userId={}, hash={}, title={}, sharedCopies={}",
                userId, fileHash, displayTitle, sharedBooks.size());
            return convertToResponse(saved);
        } catch (IOException e) {
            throw new RuntimeException("文件上传失败: " + e.getMessage(), e);
        }
    }

    private void validateUpload(MultipartFile file) {
        if (file == null || file.isEmpty()) {
            throw new RuntimeException("文件不能为空");
        }
        String filename = file.getOriginalFilename();
        if (filename == null || !filename.toLowerCase().endsWith(".epub")) {
            throw new RuntimeException("只支持EPUB格式文件");
        }
        if (file.getSize() > MAX_UPLOAD_SIZE) {
            throw new RuntimeException("文件大小不能超过50MB");
        }
    }

    private String sanitizeOriginalFilename(String filename) {
        String safeName = Paths.get(filename == null ? "book.epub" : filename).getFileName().toString();
        return safeName.trim().isEmpty() ? "book.epub" : safeName;
    }

    private String removeEpubExtension(String filename) {
        return filename.toLowerCase().endsWith(".epub")
            ? filename.substring(0, filename.length() - 5)
            : filename;
    }

    private String calculateSha256(MultipartFile file) throws IOException {
        try {
            MessageDigest digest = MessageDigest.getInstance("SHA-256");
            try (InputStream input = file.getInputStream()) {
                byte[] buffer = new byte[8192];
                int read;
                while ((read = input.read(buffer)) != -1) {
                    digest.update(buffer, 0, read);
                }
            }
            StringBuilder hex = new StringBuilder(64);
            for (byte value : digest.digest()) {
                hex.append(String.format("%02x", value & 0xff));
            }
            return hex.toString();
        } catch (NoSuchAlgorithmException e) {
            throw new IllegalStateException("SHA-256 is unavailable", e);
        }
    }

    private String resolveSharedBookPath(String fileHash, MultipartFile file, List<Book> sharedBooks) throws IOException {
        for (Book shared : sharedBooks) {
            if (shared.getBookPath() != null && Files.exists(Paths.get(shared.getBookPath()))) {
                return shared.getBookPath();
            }
        }

        Path directory = Paths.get(uploadDir);
        Files.createDirectories(directory);
        Path target = directory.resolve(fileHash + ".epub");
        if (!Files.exists(target)) {
            try (InputStream input = file.getInputStream()) {
                Files.copy(input, target, StandardCopyOption.REPLACE_EXISTING);
            }
        }
        return target.toString();
    }

    private String resolveCoverPath(MultipartFile file, MultipartFile coverFile, List<Book> sharedBooks) throws IOException {
        if (coverFile != null && !coverFile.isEmpty()) {
            String original = sanitizeCoverFilename(coverFile.getOriginalFilename());
            Path directory = Paths.get(coverUploadDir);
            Files.createDirectories(directory);
            Path target = directory.resolve(UUID.randomUUID() + "_" + original);
            try (InputStream input = coverFile.getInputStream()) {
                Files.copy(input, target, StandardCopyOption.REPLACE_EXISTING);
            }
            return "/uploads/covers/" + target.getFileName();
        }

        for (Book shared : sharedBooks) {
            if (shared.getCoverPath() != null && !shared.getCoverPath().trim().isEmpty()) {
                return shared.getCoverPath();
            }
        }

        try {
            Map<String, Object> metadata = EpubParser.parseEpub(file);
            byte[] coverData = (byte[]) metadata.get("coverData");
            if (coverData == null || coverData.length == 0) {
                return null;
            }
            String extension = (String) metadata.getOrDefault("coverExtension", ".jpg");
            Path directory = Paths.get(coverUploadDir);
            Files.createDirectories(directory);
            Path target = directory.resolve(UUID.randomUUID() + "_cover" + extension);
            Files.write(target, coverData);
            return "/uploads/covers/" + target.getFileName();
        } catch (Exception e) {
            logger.warn("Unable to extract EPUB cover", e);
            return null;
        }
    }

    private String sanitizeCoverFilename(String filename) {
        if (filename == null || filename.trim().isEmpty()) {
            return "cover.jpg";
        }
        return Paths.get(filename).getFileName().toString();
    }

    private void populateMissingMetadata(BookSyncRequest request, MultipartFile file) {
        try {
            Map<String, Object> metadata = EpubParser.parseEpub(file);
            if (isBlank(request.getAuthor())) request.setAuthor((String) metadata.get("author"));
            if (isBlank(request.getPublisher())) request.setPublisher((String) metadata.get("publisher"));
            if (isBlank(request.getLanguage())) request.setLanguage((String) metadata.get("language"));
            if (isBlank(request.getDescription())) request.setDescription((String) metadata.get("description"));
            if (isBlank(request.getIsbn())) request.setIsbn((String) metadata.get("isbn"));
        } catch (Exception e) {
            logger.warn("Unable to parse optional EPUB metadata", e);
        }
    }

    private boolean isBlank(String value) {
        return value == null || value.trim().isEmpty();
    }

    public List<BookResponse> getUserBooks(Long userId) {
        return bookRepository.findByUserIdOrderByAddedAtDesc(userId).stream()
            .map(this::convertToResponse)
            .collect(Collectors.toList());
    }

    public Page<BookResponse> getUserBooks(Long userId, Pageable pageable) {
        return bookRepository.findByUserIdOrderByAddedAtDesc(userId, pageable).map(this::convertToResponse);
    }

    public Page<BookResponse> getUserBooks(Long userId, Long categoryId, Pageable pageable) {
        if (categoryId == null) return getUserBooks(userId, pageable);
        categoryRepository.findByUserIdAndId(userId, categoryId)
            .orElseThrow(() -> new RuntimeException("分类不存在"));
        return bookRepository.findByUserIdAndCategoryIdOrderByAddedAtDesc(userId, categoryId, pageable)
            .map(this::convertToResponse);
    }

    public List<BookResponse> getAllBooks() {
        return bookRepository.findAllByOrderByAddedAtDesc().stream()
            .map(this::convertToResponse)
            .collect(Collectors.toList());
    }

    public List<Map<String, Object>> getAllBooksGroupedForAdmin() {
        Map<String, List<Book>> grouped = new LinkedHashMap<>();
        for (Book book : bookRepository.findAllByOrderByAddedAtDesc()) {
            String key = isBlank(book.getFileHash()) ? "book:" + book.getId() : "hash:" + book.getFileHash();
            grouped.computeIfAbsent(key, ignored -> new java.util.ArrayList<>()).add(book);
        }

        return grouped.values().stream().map(ownerships -> {
            Book representative = ownerships.stream()
                .min(Comparator.comparingInt(this::adminDisplayNameScore)
                    .thenComparingInt(book -> book.getTitle() == null ? Integer.MAX_VALUE : book.getTitle().length()))
                .orElse(ownerships.get(0));
            Map<String, Object> row = new LinkedHashMap<>();
            row.put("id", representative.getId());
            row.put("title", representative.getTitle());
            row.put("originalFileName", representative.getOriginalFileName());
            row.put("author", representative.getAuthor());
            row.put("publisher", representative.getPublisher());
            row.put("isbn", representative.getIsbn());
            row.put("language", representative.getLanguage());
            row.put("fileHash", representative.getFileHash());
            row.put("fileSize", representative.getFileSize());
            row.put("userId", representative.getUserId());
            row.put("ownerCount", ownerships.size());
            row.put("ownerIds", ownerships.stream().map(Book::getUserId).distinct().collect(Collectors.toList()));
            row.put("aliases", ownerships.stream().map(Book::getTitle).filter(title -> !isBlank(title)).distinct().collect(Collectors.toList()));
            return row;
        }).collect(Collectors.toList());
    }

    private int adminDisplayNameScore(Book book) {
        String title = book.getTitle();
        if (isBlank(title)) return 2;
        return title.matches("(?i)^book_\\d+_.*") ? 1 : 0;
    }

    public Map<String, Object> getAdminBookDetails(Long bookId) {
        Book book = bookRepository.findById(bookId)
            .orElseThrow(() -> new RuntimeException("书籍不存在"));
        List<Book> ownerships = book.getFileHash() == null
            ? java.util.Collections.singletonList(book)
            : bookRepository.findByFileHash(book.getFileHash());
        List<Map<String, Object>> owners = ownerships.stream().map(ownedBook -> {
            Map<String, Object> owner = new LinkedHashMap<>();
            owner.put("userId", ownedBook.getUserId());
            owner.put("username", userRepository.findById(ownedBook.getUserId())
                .map(User::getUsername).orElse("未知用户"));
            owner.put("bookId", ownedBook.getId());
            owner.put("title", ownedBook.getTitle());
            owner.put("originalFileName", ownedBook.getOriginalFileName());
            return owner;
        }).collect(Collectors.toList());

        Map<String, Object> details = new LinkedHashMap<>();
        details.put("book", convertToResponse(book));
        details.put("owners", owners);
        details.put("ownerCount", owners.size());
        return details;
    }

    public Page<BookResponse> getAllBooks(Long categoryId, Pageable pageable) {
        if (categoryId == null) {
            return bookRepository.findAllByOrderByAddedAtDesc(pageable).map(this::convertToResponse);
        }
        categoryRepository.findById(categoryId)
            .orElseThrow(() -> new RuntimeException("分类不存在"));
        return bookRepository.findByCategoryIdOrderByAddedAtDesc(categoryId, pageable)
            .map(this::convertToResponse);
    }

    public void updateBookCategory(Long currentUserId, boolean admin, Long bookId, Long categoryId) {
        Book book = findAccessibleBook(currentUserId, admin, bookId, "修改");
        Long ownerId = book.getUserId();
        if (categoryId != null) {
            categoryRepository.findByUserIdAndId(ownerId, categoryId)
                .orElseThrow(() -> new RuntimeException("分类不存在"));
        }
        book.setCategoryId(categoryId);
        bookRepository.save(book);
    }

    private Long resolveCategoryId(Long userId, BookSyncRequest request) {
        if (request.getCategoryId() != null) {
            categoryRepository.findByUserIdAndId(userId, request.getCategoryId())
                .orElseThrow(() -> new RuntimeException("分类不存在"));
            return request.getCategoryId();
        }
        String localId = request.getLocalCategoryId();
        if (!isBlank(localId)) {
            Optional<Category> category = categoryRepository.findByUserIdAndLocalId(userId, localId.trim());
            if (category.isPresent()) return category.get().getId();
        }
        String name = request.getCategoryName();
        if (!isBlank(name)) {
            return categoryRepository.findByUserIdAndName(userId, name.trim())
                .orElseGet(() -> {
                    Category category = new Category();
                    category.setUserId(userId);
                    category.setName(name.trim());
                    category.setLocalId(isBlank(localId) ? null : localId.trim());
                    category.setColor("#667eea");
                    return categoryRepository.save(category);
                }).getId();
        }
        return null;
    }

    private boolean hasCategoryInfo(BookSyncRequest request) {
        return request.getCategoryId() != null || !isBlank(request.getLocalCategoryId()) || !isBlank(request.getCategoryName());
    }

    @Transactional
    public void deleteBook(Long currentUserId, boolean admin, Long bookId) {
        Book book = findAccessibleBook(currentUserId, admin, bookId, "删除");
        String hash = book.getFileHash();
        String path = book.getBookPath();
        String cover = book.getCoverPath();
        bookRepository.delete(book);
        bookRepository.flush();

        try {
            if (hash == null || bookRepository.countByFileHash(hash) == 0) {
                if (path != null) Files.deleteIfExists(Paths.get(path));
            }
            if (cover != null && bookRepository.countByCoverPath(cover) == 0 && cover.startsWith("/uploads/covers/")) {
                Files.deleteIfExists(Paths.get("." + cover));
            }
        } catch (IOException e) {
            throw new RuntimeException("删除文件失败: " + e.getMessage(), e);
        }
    }

    @Transactional
    public void deleteAllBooksForUser(Long userId) {
        List<Long> bookIds = bookRepository.findByUserId(userId).stream()
            .map(Book::getId)
            .collect(Collectors.toList());
        for (Long bookId : bookIds) {
            deleteBook(userId, false, bookId);
        }
    }

    public Resource getBookFile(Long currentUserId, boolean admin, Long bookId) {
        Book book = findAccessibleBook(currentUserId, admin, bookId, "下载");
        Path path = Paths.get(book.getBookPath());
        if (!Files.exists(path)) throw new RuntimeException("书籍文件不存在");
        return new FileSystemResource(path);
    }

    public String getBookDownloadName(Long bookId) {
        return bookRepository.findById(bookId)
            .map(book -> book.getOriginalFileName() == null ? book.getTitle() + ".epub" : book.getOriginalFileName())
            .orElse("unknown.epub");
    }

    private Book findAccessibleBook(Long currentUserId, boolean admin, Long bookId, String action) {
        Book book = bookRepository.findById(bookId)
            .orElseThrow(() -> new RuntimeException("书籍不存在"));
        if (!admin && !book.getUserId().equals(currentUserId)) {
            throw new RuntimeException("无权" + action + "此书籍");
        }
        return book;
    }

    private BookResponse convertToResponse(Book book) {
        BookResponse response = new BookResponse();
        response.setId(book.getId());
        response.setTitle(book.getTitle());
        response.setAuthor(book.getAuthor());
        response.setPublisher(book.getPublisher());
        response.setIsbn(book.getIsbn());
        response.setPubDate(book.getPubDate());
        response.setLanguage(book.getLanguage());
        response.setDescription(book.getDescription());
        response.setCoverPath(book.getCoverPath());
        response.setBookPath(book.getBookPath());
        response.setFileHash(book.getFileHash());
        response.setOriginalFileName(book.getOriginalFileName());
        response.setFileSize(book.getFileSize());
        response.setUserId(book.getUserId());
        response.setCategoryId(book.getCategoryId());
        if (book.getCategoryId() != null) {
            categoryRepository.findById(book.getCategoryId())
                .ifPresent(category -> response.setCategoryName(category.getName()));
        }
        response.setAddedAt(book.getAddedAt());
        response.setLastReadAt(book.getLastReadAt());
        return response;
    }
}
