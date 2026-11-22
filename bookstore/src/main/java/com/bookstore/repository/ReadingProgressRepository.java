package com.bookstore.repository;

import com.bookstore.entity.ReadingProgress;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;

import java.util.Optional;

@Repository
public interface ReadingProgressRepository extends JpaRepository<ReadingProgress, Long> {
    
    Optional<ReadingProgress> findByBookIdAndUserId(Long bookId, Long userId);
    
    void deleteByBookIdAndUserId(Long bookId, Long userId);

    void deleteByUserId(Long userId);
}
