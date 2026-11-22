package com.bookstore.controller;

import com.bookstore.dto.ApiResponse;
import com.bookstore.dto.UserResponse;
import com.bookstore.entity.User;
import com.bookstore.service.BookService;
import com.bookstore.service.UserService;
import org.springframework.http.ResponseEntity;
import org.springframework.security.access.AccessDeniedException;
import org.springframework.security.core.Authentication;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;
import java.util.Map;

@RestController
@RequestMapping("/api/admin")
public class AdminController {

    private final UserService userService;
    private final BookService bookService;

    public AdminController(UserService userService, BookService bookService) {
        this.userService = userService;
        this.bookService = bookService;
    }

    @GetMapping("/books")
    public ResponseEntity<ApiResponse> getAllBooks(Authentication authentication) {
        requireAdmin(authentication);
        List<Map<String, Object>> books = bookService.getAllBooksGroupedForAdmin();
        return ResponseEntity.ok(ApiResponse.success("获取全部书籍成功", books));
    }

    @GetMapping("/books/{id}")
    public ResponseEntity<ApiResponse> getBookDetails(
            @PathVariable Long id,
            Authentication authentication) {
        requireAdmin(authentication);
        return ResponseEntity.ok(ApiResponse.success("获取书籍详情成功", bookService.getAdminBookDetails(id)));
    }

    @GetMapping("/users")
    public ResponseEntity<ApiResponse> getAllUsers(Authentication authentication) {
        requireAdmin(authentication);
        List<UserResponse> users = userService.getAllUsers();
        return ResponseEntity.ok(ApiResponse.success("获取用户列表成功", users));
    }

    @PutMapping("/users/{id}/role")
    public ResponseEntity<ApiResponse> updateUserRole(
            @PathVariable Long id,
            @RequestBody Map<String, String> request,
            Authentication authentication) {
        requireAdmin(authentication);
        UserResponse updatedUser = userService.updateUserRole(currentUser(authentication).getId(), id, request.get("role"));
        return ResponseEntity.ok(ApiResponse.success("用户角色更新成功", updatedUser));
    }

    @PutMapping("/users/{id}/membership")
    public ResponseEntity<ApiResponse> updateUserMembership(
            @PathVariable Long id,
            @RequestBody Map<String, String> request,
            Authentication authentication) {
        requireAdmin(authentication);
        UserResponse updatedUser = userService.updateMembershipType(id, request.get("membershipType"));
        return ResponseEntity.ok(ApiResponse.success("会员类型更新成功", updatedUser));
    }

    @PutMapping("/users/{id}/enabled")
    public ResponseEntity<ApiResponse> updateUserEnabled(
            @PathVariable Long id,
            @RequestBody Map<String, Boolean> request,
            Authentication authentication) {
        requireAdmin(authentication);
        UserResponse updatedUser = userService.updateEnabled(currentUser(authentication).getId(), id, request.get("enabled"));
        return ResponseEntity.ok(ApiResponse.success("用户状态更新成功", updatedUser));
    }

    @DeleteMapping("/users/{id}")
    public ResponseEntity<ApiResponse> deleteUser(@PathVariable Long id, Authentication authentication) {
        requireAdmin(authentication);
        userService.deleteUser(currentUser(authentication).getId(), id);
        return ResponseEntity.ok(ApiResponse.success("用户删除成功", null));
    }

    private void requireAdmin(Authentication authentication) {
        if (authentication == null || !(authentication.getPrincipal() instanceof User)
                || !"ADMIN".equals(((User) authentication.getPrincipal()).getRole())) {
            throw new AccessDeniedException("无权访问");
        }
    }

    private User currentUser(Authentication authentication) {
        requireAdmin(authentication);
        return (User) authentication.getPrincipal();
    }
}
