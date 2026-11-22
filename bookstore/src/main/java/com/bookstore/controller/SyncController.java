package com.bookstore.controller;

import com.bookstore.dto.*;
import com.bookstore.entity.User;
import com.bookstore.service.SyncService;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
import io.swagger.v3.oas.annotations.Parameter;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.Authentication;
import org.springframework.web.bind.annotation.*;

import java.util.List;

@RestController
@RequestMapping("/api/sync")
@Tag(name = "阅读同步", description = "阅读进度、书签、批注等同步接口")
public class SyncController {

    private final SyncService syncService;

    public SyncController(SyncService syncService) {
        this.syncService = syncService;
    }

    // Reading Progress APIs
    @PostMapping("/progress")
    @Operation(summary = "保存阅读进度", description = "保存或更新指定书籍的阅读进度")
    public ResponseEntity<ApiResponse> saveProgress(
            @RequestBody ReadingProgressRequest request,
            Authentication authentication) {
        try {
            User currentUser = (User) authentication.getPrincipal();
            ReadingProgressResponse response = syncService.saveProgress(request, currentUser.getId());
            return ResponseEntity.ok(ApiResponse.success("保存阅读进度成功", response));
        } catch (Exception e) {
            return ResponseEntity.badRequest().body(ApiResponse.error(e.getMessage()));
        }
    }

    @GetMapping("/progress/{bookId}")
    @Operation(summary = "获取阅读进度", description = "获取指定书籍的阅读进度")
    public ResponseEntity<ApiResponse> getProgress(
            @Parameter(description = "书籍ID", required = true) @PathVariable Long bookId,
            Authentication authentication) {
        try {
            User currentUser = (User) authentication.getPrincipal();
            ReadingProgressResponse response = syncService.getProgress(bookId, currentUser.getId());
            return ResponseEntity.ok(ApiResponse.success("获取阅读进度成功", response));
        } catch (Exception e) {
            return ResponseEntity.badRequest().body(ApiResponse.error(e.getMessage()));
        }
    }

    // Bookmark APIs
    @PostMapping("/bookmark")
    public ResponseEntity<ApiResponse> saveBookmark(
            @RequestBody BookmarkRequest request,
            Authentication authentication) {
        try {
            User currentUser = (User) authentication.getPrincipal();
            BookmarkResponse response = syncService.saveBookmark(request, currentUser.getId());
            return ResponseEntity.ok(ApiResponse.success("添加书签成功", response));
        } catch (Exception e) {
            return ResponseEntity.badRequest().body(ApiResponse.error(e.getMessage()));
        }
    }

    @GetMapping("/bookmarks/{bookId}")
    public ResponseEntity<ApiResponse> getBookmarks(
            @PathVariable Long bookId,
            Authentication authentication) {
        try {
            User currentUser = (User) authentication.getPrincipal();
            List<BookmarkResponse> bookmarks = syncService.getBookmarks(bookId, currentUser.getId());
            return ResponseEntity.ok(ApiResponse.success("获取书签列表成功", bookmarks));
        } catch (Exception e) {
            return ResponseEntity.badRequest().body(ApiResponse.error(e.getMessage()));
        }
    }

    @DeleteMapping("/bookmark/{id}")
    public ResponseEntity<ApiResponse> deleteBookmark(@PathVariable Long id) {
        try {
            syncService.deleteBookmark(id);
            return ResponseEntity.ok(ApiResponse.success("删除书签成功", null));
        } catch (Exception e) {
            return ResponseEntity.badRequest().body(ApiResponse.error(e.getMessage()));
        }
    }

    // Annotation APIs
    @PostMapping("/annotation")
    public ResponseEntity<ApiResponse> saveAnnotation(
            @RequestBody AnnotationRequest request,
            Authentication authentication) {
        try {
            User currentUser = (User) authentication.getPrincipal();
            AnnotationResponse response = syncService.saveAnnotation(request, currentUser.getId());
            return ResponseEntity.ok(ApiResponse.success("添加批注成功", response));
        } catch (Exception e) {
            return ResponseEntity.badRequest().body(ApiResponse.error(e.getMessage()));
        }
    }

    @GetMapping("/annotations/{bookId}")
    public ResponseEntity<ApiResponse> getAnnotations(
            @PathVariable Long bookId,
            Authentication authentication) {
        try {
            User currentUser = (User) authentication.getPrincipal();
            List<AnnotationResponse> annotations = syncService.getAnnotations(bookId, currentUser.getId());
            return ResponseEntity.ok(ApiResponse.success("获取批注列表成功", annotations));
        } catch (Exception e) {
            return ResponseEntity.badRequest().body(ApiResponse.error(e.getMessage()));
        }
    }

    @PutMapping("/annotation/{id}")
    public ResponseEntity<ApiResponse> updateAnnotation(@PathVariable Long id, @RequestBody AnnotationRequest request) {
        try {
            AnnotationResponse response = syncService.updateAnnotation(id, request);
            return ResponseEntity.ok(ApiResponse.success("更新批注成功", response));
        } catch (Exception e) {
            return ResponseEntity.badRequest().body(ApiResponse.error(e.getMessage()));
        }
    }

    @DeleteMapping("/annotation/{id}")
    public ResponseEntity<ApiResponse> deleteAnnotation(@PathVariable Long id) {
        try {
            syncService.deleteAnnotation(id);
            return ResponseEntity.ok(ApiResponse.success("删除批注成功", null));
        } catch (Exception e) {
            return ResponseEntity.badRequest().body(ApiResponse.error(e.getMessage()));
        }
    }
}
