package com.bookstore.service;

import com.bookstore.dto.CategoryRequest;
import com.bookstore.dto.CategoryResponse;
import com.bookstore.dto.CategorySyncRequest;
import com.bookstore.entity.Book;
import com.bookstore.entity.Category;
import com.bookstore.repository.BookRepository;
import com.bookstore.repository.CategoryRepository;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.*;
import java.util.stream.Collectors;

@Service
public class CategoryService {

    private final CategoryRepository categoryRepository;
    private final BookRepository bookRepository;

    public CategoryService(CategoryRepository categoryRepository, BookRepository bookRepository) {
        this.categoryRepository = categoryRepository;
        this.bookRepository = bookRepository;
    }

    public List<CategoryResponse> getUserCategories(Long userId) {
        return categoryRepository.findByUserIdOrderByCreatedAtAsc(userId).stream()
            .map(this::toResponse)
            .collect(Collectors.toList());
    }

    public CategoryResponse createCategory(Long userId, CategoryRequest request) {
        Category category = findOrCreateCategory(userId, null, request.getName(), request.getColor());
        return toResponse(category);
    }

    @Transactional
    public Map<String, Object> syncCategories(Long userId, CategorySyncRequest request) {
        Map<String, Long> localIdToCloudId = new LinkedHashMap<>();
        List<CategoryResponse> syncedCategories = new ArrayList<>();

        if (request.getCategories() != null) {
            for (CategorySyncRequest.CategoryItem item : request.getCategories()) {
                String localId = normalizeLocalId(item.getLocalId(), item.getLocalCategoryId());
                Category category = findOrCreateCategory(userId, localId, item.getName(), item.getColor());
                syncedCategories.add(toResponse(category));
                if (localId != null) {
                    localIdToCloudId.put(localId, category.getId());
                }
            }
        }

        int updatedBookCount = syncBookCategoryMappings(userId, request.getBookCategories(), localIdToCloudId);

        Map<String, Object> result = new LinkedHashMap<>();
        result.put("categories", syncedCategories);
        result.put("localIdToCloudId", localIdToCloudId);
        result.put("updatedBookCount", updatedBookCount);
        return result;
    }

    public void validateCategoryBelongsToUser(Long userId, Long categoryId) {
        if (categoryId == null) {
            return;
        }

        categoryRepository.findByUserIdAndId(userId, categoryId)
            .orElseThrow(() -> new RuntimeException("分类不存在"));
    }

    public Category findOrCreateCategory(Long userId, String localId, String name, String color) {
        String normalizedName = normalizeName(name);
        String normalizedLocalId = normalizeLocalId(localId, null);

        Optional<Category> existingCategory = Optional.empty();
        if (normalizedLocalId != null) {
            existingCategory = categoryRepository.findByUserIdAndLocalId(userId, normalizedLocalId);
        }
        if (!existingCategory.isPresent()) {
            existingCategory = categoryRepository.findByUserIdAndName(userId, normalizedName);
        }

        Category category = existingCategory.orElseGet(Category::new);
        category.setName(normalizedName);
        category.setColor(normalizeColor(color));
        category.setLocalId(normalizedLocalId != null ? normalizedLocalId : category.getLocalId());
        category.setUserId(userId);
        return categoryRepository.save(category);
    }

    private int syncBookCategoryMappings(
            Long userId,
            List<CategorySyncRequest.BookCategoryItem> bookCategories,
            Map<String, Long> localIdToCloudId) {
        if (bookCategories == null || bookCategories.isEmpty()) {
            return 0;
        }

        int updatedCount = 0;
        for (CategorySyncRequest.BookCategoryItem item : bookCategories) {
            Optional<Book> book = findBookForMapping(userId, item);
            if (!book.isPresent()) {
                continue;
            }

            Long categoryId = resolveCategoryId(userId, item, localIdToCloudId);
            book.get().setCategoryId(categoryId);
            bookRepository.save(book.get());
            updatedCount++;
        }

        return updatedCount;
    }

    private Optional<Book> findBookForMapping(Long userId, CategorySyncRequest.BookCategoryItem item) {
        if (item.getBookId() != null) {
            Optional<Book> byId = bookRepository.findByUserIdAndId(userId, item.getBookId());
            if (byId.isPresent()) {
                return byId;
            }
        }

        if (item.getTitle() != null && !item.getTitle().trim().isEmpty()) {
            return bookRepository.findByUserIdAndTitle(userId, item.getTitle().trim());
        }

        return Optional.empty();
    }

    private Long resolveCategoryId(
            Long userId,
            CategorySyncRequest.BookCategoryItem item,
            Map<String, Long> localIdToCloudId) {
        if (item.getCategoryId() != null) {
            validateCategoryBelongsToUser(userId, item.getCategoryId());
            return item.getCategoryId();
        }

        String localCategoryId = normalizeLocalId(item.getLocalCategoryId(), null);
        if (localCategoryId != null && localIdToCloudId.containsKey(localCategoryId)) {
            return localIdToCloudId.get(localCategoryId);
        }

        if (localCategoryId != null) {
            Optional<Category> category = categoryRepository.findByUserIdAndLocalId(userId, localCategoryId);
            if (category.isPresent()) {
                return category.get().getId();
            }
        }

        if (item.getCategoryName() != null && !item.getCategoryName().trim().isEmpty()) {
            return findOrCreateCategory(userId, localCategoryId, item.getCategoryName(), null).getId();
        }

        return null;
    }

    private CategoryResponse toResponse(Category category) {
        return new CategoryResponse(
            category.getId(),
            category.getLocalId(),
            category.getName(),
            category.getColor(),
            bookRepository.countByUserIdAndCategoryId(category.getUserId(), category.getId())
        );
    }

    private String normalizeName(String name) {
        if (name == null || name.trim().isEmpty()) {
            throw new RuntimeException("分类名称不能为空");
        }
        return name.trim();
    }

    private String normalizeLocalId(String localId, Long localCategoryId) {
        if (localId != null && !localId.trim().isEmpty()) {
            return localId.trim();
        }
        if (localCategoryId != null) {
            return String.valueOf(localCategoryId);
        }
        return null;
    }

    private String normalizeColor(String color) {
        if (color == null || color.trim().isEmpty()) {
            return "#667eea";
        }

        String trimmedColor = color.trim();
        if (!trimmedColor.matches("^#[0-9a-fA-F]{6}$")) {
            return "#667eea";
        }

        return trimmedColor;
    }
}
