package com.bookstore.controller;

import com.bookstore.dto.ApiResponse;
import com.bookstore.dto.CategoryRequest;
import com.bookstore.dto.CategoryResponse;
import com.bookstore.dto.CategorySyncRequest;
import com.bookstore.entity.User;
import com.bookstore.service.CategoryService;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.Authentication;
import org.springframework.web.bind.annotation.*;

import javax.validation.Valid;
import java.util.List;
import java.util.Map;

@RestController
@RequestMapping("/api/categories")
@Tag(name = "分类管理", description = "书籍分类查询与创建")
public class CategoryController {

    private final CategoryService categoryService;

    public CategoryController(CategoryService categoryService) {
        this.categoryService = categoryService;
    }

    @GetMapping
    @Operation(summary = "获取分类列表")
    public ResponseEntity<ApiResponse> getCategories(Authentication authentication) {
        try {
            Long userId = getCurrentUserId(authentication);
            List<CategoryResponse> categories = categoryService.getUserCategories(userId);
            return ResponseEntity.ok(ApiResponse.success("获取分类列表成功", categories));
        } catch (Exception e) {
            return ResponseEntity.badRequest().body(ApiResponse.error(e.getMessage()));
        }
    }

    @PostMapping
    @Operation(summary = "新建分类")
    public ResponseEntity<ApiResponse> createCategory(
            @Valid @RequestBody CategoryRequest request,
            Authentication authentication) {
        try {
            Long userId = getCurrentUserId(authentication);
            CategoryResponse category = categoryService.createCategory(userId, request);
            return ResponseEntity.ok(ApiResponse.success("分类创建成功", category));
        } catch (Exception e) {
            return ResponseEntity.badRequest().body(ApiResponse.error(e.getMessage()));
        }
    }

    @PostMapping("/sync")
    @Operation(summary = "同步本地分类", description = "批量同步 EPUB_READER 本地分类，并可同步书籍与分类的绑定关系")
    public ResponseEntity<ApiResponse> syncCategories(
            @RequestBody CategorySyncRequest request,
            Authentication authentication) {
        try {
            Long userId = getCurrentUserId(authentication);
            Map<String, Object> result = categoryService.syncCategories(userId, request);
            return ResponseEntity.ok(ApiResponse.success("分类同步成功", result));
        } catch (Exception e) {
            return ResponseEntity.badRequest().body(ApiResponse.error(e.getMessage()));
        }
    }

    private Long getCurrentUserId(Authentication authentication) {
        if (authentication == null || !authentication.isAuthenticated()) {
            throw new RuntimeException("未登录");
        }
        return ((User) authentication.getPrincipal()).getId();
    }
}
