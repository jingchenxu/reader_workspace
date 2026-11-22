package com.bookstore.controller;

import com.bookstore.dto.ApiResponse;
import com.bookstore.entity.User;
import com.bookstore.service.SystemConfigService;
import org.springframework.http.ResponseEntity;
import org.springframework.security.access.AccessDeniedException;
import org.springframework.security.core.Authentication;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.Map;

@RestController
@RequestMapping("/api/admin/config")
public class SystemConfigController {

    private final SystemConfigService systemConfigService;

    public SystemConfigController(SystemConfigService systemConfigService) {
        this.systemConfigService = systemConfigService;
    }

    @GetMapping("/storage")
    public ResponseEntity<ApiResponse> getStorageConfig(Authentication authentication) {
        requireAdmin(authentication);
        return ResponseEntity.ok(ApiResponse.success("获取存储配置成功", systemConfigService.getStorageConfigs()));
    }

    @PutMapping("/storage")
    public ResponseEntity<ApiResponse> updateStorageConfig(
            @RequestBody Map<String, Long> values,
            Authentication authentication) {
        requireAdmin(authentication);
        return ResponseEntity.ok(ApiResponse.success(
            "存储配置更新成功",
            systemConfigService.updateStorageConfigs(values)
        ));
    }

    private void requireAdmin(Authentication authentication) {
        if (authentication == null || !(authentication.getPrincipal() instanceof User)
                || !"ADMIN".equals(((User) authentication.getPrincipal()).getRole())) {
            throw new AccessDeniedException("无权访问");
        }
    }
}
