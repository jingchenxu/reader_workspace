package com.bookstore.repository;

import com.bookstore.entity.Book;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;

import java.util.List;
import java.util.Optional;

@Repository
public interface BookRepository extends JpaRepository<Book, Long> {
    
    List<Book> findByUserId(Long userId);
    
    List<Book> findByUserIdOrderByAddedAtDesc(Long userId);

    Page<Book> findByUserIdOrderByAddedAtDesc(Long userId, Pageable pageable);

    Page<Book> findByUserIdAndCategoryIdOrderByAddedAtDesc(Long userId, Long categoryId, Pageable pageable);
    
    List<Book> findAllByOrderByAddedAtDesc();

    Page<Book> findAllByOrderByAddedAtDesc(Pageable pageable);

    Page<Book> findByCategoryIdOrderByAddedAtDesc(Long categoryId, Pageable pageable);

    long countByUserId(Long userId);

    long countByUserIdAndCategoryId(Long userId, Long categoryId);
    
    boolean existsByUserIdAndBookPath(Long userId, String bookPath);
    
    Optional<Book> findByUserIdAndBookPath(Long userId, String bookPath);

    Optional<Book> findByUserIdAndId(Long userId, Long id);

    Optional<Book> findByUserIdAndTitle(Long userId, String title);

    Optional<Book> findByUserIdAndFileHash(Long userId, String fileHash);

    List<Book> findByFileHash(String fileHash);

    @org.springframework.data.jpa.repository.Query("select coalesce(sum(b.fileSize), 0) from Book b where b.userId = :userId")
    long sumFileSizeByUserId(@org.springframework.data.repository.query.Param("userId") Long userId);

    long countByFileHash(String fileHash);

    long countByCoverPath(String coverPath);

    long countByBookPath(String bookPath);
    
    void deleteByUserIdAndId(Long userId, Long id);
}
