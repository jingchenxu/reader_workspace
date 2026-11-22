package com.bookstore.config;

import com.bookstore.entity.Book;
import com.bookstore.repository.BookRepository;
import com.bookstore.util.EpubParser;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.boot.CommandLineRunner;
import org.springframework.core.annotation.Order;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Transactional;

import java.io.InputStream;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.security.MessageDigest;
import java.util.HashMap;
import java.util.Map;

@Component
@Order(20)
public class BookStorageInitializer implements CommandLineRunner {

    private static final Logger logger = LoggerFactory.getLogger(BookStorageInitializer.class);

    private final BookRepository bookRepository;

    public BookStorageInitializer(BookRepository bookRepository) {
        this.bookRepository = bookRepository;
    }

    @Override
    @Transactional
    public void run(String... args) {
        Map<String, String> canonicalPaths = new HashMap<>();
        Map<String, String> isbnByHash = new HashMap<>();
        int isbnUpdated = 0;

        for (Book book : bookRepository.findAll()) {
            try {
                if (book.getBookPath() == null) continue;
                Path currentPath = Paths.get(book.getBookPath());
                if (!Files.exists(currentPath)) continue;

                String hash = book.getFileHash();
                if (hash == null || hash.trim().isEmpty()) {
                    hash = calculateSha256(currentPath);
                    book.setFileHash(hash);
                }
                if (book.getOriginalFileName() == null || book.getOriginalFileName().trim().isEmpty()) {
                    book.setOriginalFileName(book.getTitle() + ".epub");
                }

                if (book.getIsbn() == null || book.getIsbn().trim().isEmpty()) {
                    String isbn;
                    if (isbnByHash.containsKey(hash)) {
                        isbn = isbnByHash.get(hash);
                    } else {
                        Object parsedIsbn = EpubParser.parseEpub(currentPath).get("isbn");
                        isbn = parsedIsbn instanceof String ? ((String) parsedIsbn).trim() : null;
                        isbnByHash.put(hash, isbn);
                    }
                    if (isbn != null && !isbn.isEmpty()) {
                        book.setIsbn(isbn);
                        isbnUpdated++;
                    }
                }

                String canonical = canonicalPaths.putIfAbsent(hash, book.getBookPath());
                String duplicatePath = null;
                if (canonical != null && !canonical.equals(book.getBookPath()) && Files.exists(Paths.get(canonical))) {
                    duplicatePath = book.getBookPath();
                    book.setBookPath(canonical);
                }
                bookRepository.saveAndFlush(book);

                if (duplicatePath != null && bookRepository.countByBookPath(duplicatePath) == 0) {
                    Files.deleteIfExists(Paths.get(duplicatePath));
                    logger.info("Removed duplicate stored EPUB: {}", duplicatePath);
                }
            } catch (Exception e) {
                logger.warn("Unable to migrate stored book {}", book.getId(), e);
            }
        }
        logger.info("Historical EPUB metadata migration completed: ISBN updated for {} book records", isbnUpdated);
    }

    private String calculateSha256(Path path) throws Exception {
        MessageDigest digest = MessageDigest.getInstance("SHA-256");
        try (InputStream input = Files.newInputStream(path)) {
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
    }
}
