package com.bookstore.service;

import com.bookstore.entity.Book;
import com.bookstore.repository.BookRepository;
import com.bookstore.repository.CategoryRepository;
import com.bookstore.repository.UserRepository;
import org.junit.jupiter.api.Test;

import java.util.Arrays;
import java.util.List;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

class BookServiceAdminGroupingTest {

    @Test
    void groupsSameHashAndPrefersCleanDisplayTitle() {
        BookRepository bookRepository = mock(BookRepository.class);
        BookService service = new BookService(
            bookRepository,
            mock(CategoryRepository.class),
            mock(UserRepository.class),
            mock(StorageQuotaService.class)
        );

        Book generatedName = book(26L, 3L, "book_1782371092169_毛泽东选集", "same-hash");
        Book cleanName = book(18L, 1L, "毛泽东选集", "same-hash");
        when(bookRepository.findAllByOrderByAddedAtDesc()).thenReturn(Arrays.asList(generatedName, cleanName));

        List<Map<String, Object>> rows = service.getAllBooksGroupedForAdmin();

        assertEquals(1, rows.size());
        assertEquals("毛泽东选集", rows.get(0).get("title"));
        assertEquals(2, rows.get(0).get("ownerCount"));
        assertEquals(Arrays.asList(3L, 1L), rows.get(0).get("ownerIds"));
    }

    private Book book(Long id, Long userId, String title, String hash) {
        Book book = new Book();
        book.setId(id);
        book.setUserId(userId);
        book.setTitle(title);
        book.setOriginalFileName(title + ".epub");
        book.setFileHash(hash);
        book.setFileSize(2918518L);
        return book;
    }
}
