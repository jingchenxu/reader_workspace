package com.bookstore.controller;

import com.bookstore.dto.ApiResponse;
import com.bookstore.entity.User;
import com.bookstore.service.StorageQuotaService;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.Authentication;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/storage")
public class StorageController {

    private final StorageQuotaService storageQuotaService;

    public StorageController(StorageQuotaService storageQuotaService) {
        this.storageQuotaService = storageQuotaService;
    }

    @GetMapping("/quota")
    public ResponseEntity<ApiResponse> getQuota(Authentication authentication) {
        User user = (User) authentication.getPrincipal();
        return ResponseEntity.ok(ApiResponse.success("获取存储配额成功", storageQuotaService.getQuota(user)));
    }
}
