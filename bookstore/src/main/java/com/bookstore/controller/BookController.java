package com.bookstore.controller;

import com.bookstore.dto.ApiResponse;
import com.bookstore.dto.BookResponse;
import com.bookstore.dto.BookSyncRequest;
import com.bookstore.service.BookService;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
import io.swagger.v3.oas.annotations.Parameter;
import org.springframework.core.io.Resource;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.Authentication;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.multipart.MultipartFile;

import java.net.URLEncoder;
import java.nio.charset.StandardCharsets;
import java.util.List;
import java.util.Map;

@RestController
@RequestMapping("/api/books")
@Tag(name = "书籍管理", description = "书籍同步、查询、删除等管理接口")
public class BookController {

    private final BookService bookService;

    public BookController(BookService bookService) {
        this.bookService = bookService;
    }

    @PostMapping("/sync")
    @Operation(summary = "同步书籍", description = "上传EPUB文件和封面图片，同步书籍信息到服务端")
    public ResponseEntity<ApiResponse> syncBook(
            @ModelAttribute BookSyncRequest syncRequest,
            @Parameter(description = "EPUB文件", required = true)
            @RequestParam("file") MultipartFile file,
            @Parameter(description = "封面图片", required = false)
            @RequestParam(value = "coverFile", required = false) MultipartFile coverFile,
            Authentication authentication) {
        try {
            Long userId = getCurrentUserId(authentication);
            BookResponse bookResponse = bookService.syncBook(userId, syncRequest, file, coverFile);
            return ResponseEntity.ok(ApiResponse.success("书籍同步成功", bookResponse));
        } catch (Exception e) {
            return ResponseEntity.badRequest().body(ApiResponse.error(e.getMessage()));
        }
    }

    @GetMapping
    @Operation(summary = "获取个人书架", description = "获取当前登录用户自己账户下的书籍")
    public ResponseEntity<ApiResponse> getUserBooks(Authentication authentication) {
        try {
            com.bookstore.entity.User currentUser = (com.bookstore.entity.User) authentication.getPrincipal();
            List<BookResponse> books = bookService.getUserBooks(currentUser.getId());
            
            return ResponseEntity.ok(ApiResponse.success("获取书籍列表成功", books));
        } catch (Exception e) {
            return ResponseEntity.badRequest().body(ApiResponse.error(e.getMessage()));
        }
    }

    @DeleteMapping("/{id}")
    @Operation(summary = "删除书籍", description = "删除指定ID的书籍及其文件")
    public ResponseEntity<ApiResponse> deleteBook(
            @Parameter(description = "书籍ID", required = true) @PathVariable Long id,
            Authentication authentication) {
        try {
            com.bookstore.entity.User currentUser = getCurrentUser(authentication);
            bookService.deleteBook(currentUser.getId(), isAdmin(currentUser), id);
            return ResponseEntity.ok(ApiResponse.success("删除成功", null));
        } catch (Exception e) {
            return ResponseEntity.badRequest().body(ApiResponse.error(e.getMessage()));
        }
    }

    @PutMapping("/{id}/category")
    @Operation(summary = "更新书籍分类", description = "将指定书籍添加到分类，categoryId 为空时移除分类")
    public ResponseEntity<ApiResponse> updateBookCategory(
            @Parameter(description = "书籍ID", required = true) @PathVariable Long id,
            @RequestBody Map<String, Long> request,
            Authentication authentication) {
        try {
            com.bookstore.entity.User currentUser = getCurrentUser(authentication);
            Long categoryId = request == null ? null : request.get("categoryId");
            bookService.updateBookCategory(currentUser.getId(), isAdmin(currentUser), id, categoryId);
            return ResponseEntity.ok(ApiResponse.success("分类更新成功", null));
        } catch (Exception e) {
            return ResponseEntity.badRequest().body(ApiResponse.error(e.getMessage()));
        }
    }

    @GetMapping("/{id}/download")
    @Operation(summary = "下载书籍", description = "下载指定ID的EPUB书籍文件")
    public ResponseEntity<Resource> downloadBook(
            @Parameter(description = "书籍ID", required = true) @PathVariable Long id,
            Authentication authentication) {
        try {
            com.bookstore.entity.User currentUser = getCurrentUser(authentication);
            Resource resource = bookService.getBookFile(currentUser.getId(), isAdmin(currentUser), id);
            String filename = URLEncoder.encode(bookService.getBookDownloadName(id), StandardCharsets.UTF_8.toString())
                    .replace("+", "%20");

            return ResponseEntity.ok()
                    .contentType(MediaType.parseMediaType("application/epub+zip"))
                    .header(HttpHeaders.CONTENT_DISPOSITION, "attachment; filename*=UTF-8''" + filename)
                    .header(HttpHeaders.ACCESS_CONTROL_EXPOSE_HEADERS, HttpHeaders.CONTENT_DISPOSITION)
                    .body(resource);
        } catch (Exception e) {
            return ResponseEntity.badRequest().build();
        }
    }

    private Long getCurrentUserId(Authentication authentication) {
        return getCurrentUser(authentication).getId();
    }

    private com.bookstore.entity.User getCurrentUser(Authentication authentication) {
        if (authentication == null || !authentication.isAuthenticated()) {
            throw new RuntimeException("未登录");
        }
        return (com.bookstore.entity.User) authentication.getPrincipal();
    }

    private boolean isAdmin(com.bookstore.entity.User user) {
        return "ADMIN".equals(user.getRole());
    }
}
