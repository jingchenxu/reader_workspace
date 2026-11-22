package com.bookstore.repository;

import com.bookstore.entity.Annotation;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;

import java.util.List;

@Repository
public interface AnnotationRepository extends JpaRepository<Annotation, Long> {
    
    List<Annotation> findByBookIdAndUserId(Long bookId, Long userId);
    
    void deleteByBookIdAndUserId(Long bookId, Long userId);

    void deleteByUserId(Long userId);
}
