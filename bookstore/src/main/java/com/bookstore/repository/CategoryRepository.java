package com.bookstore.repository;

import com.bookstore.entity.Category;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;

import java.util.List;
import java.util.Optional;

@Repository
public interface CategoryRepository extends JpaRepository<Category, Long> {

    List<Category> findByUserIdOrderByCreatedAtAsc(Long userId);

    Optional<Category> findByUserIdAndId(Long userId, Long id);

    Optional<Category> findByUserIdAndName(Long userId, String name);

    Optional<Category> findByUserIdAndLocalId(Long userId, String localId);

    boolean existsByUserIdAndName(Long userId, String name);

    void deleteByUserId(Long userId);
}
