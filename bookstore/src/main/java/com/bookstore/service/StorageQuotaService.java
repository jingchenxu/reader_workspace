package com.bookstore.service;

import com.bookstore.dto.StorageQuotaResponse;
import com.bookstore.entity.User;
import com.bookstore.repository.BookRepository;
import org.springframework.stereotype.Service;

@Service
public class StorageQuotaService {

    private final BookRepository bookRepository;
    private final SystemConfigService systemConfigService;

    public StorageQuotaService(BookRepository bookRepository, SystemConfigService systemConfigService) {
        this.bookRepository = bookRepository;
        this.systemConfigService = systemConfigService;
    }

    public long getUsedBytes(Long userId) {
        return bookRepository.sumFileSizeByUserId(userId);
    }

    public long getQuotaBytes(User user) {
        if (isAdmin(user)) {
            return Long.MAX_VALUE;
        }
        return "MEMBER".equalsIgnoreCase(user.getMembershipType())
            ? systemConfigService.getMemberQuotaBytes()
            : systemConfigService.getReaderQuotaBytes();
    }

    public void assertCanStore(User user, long additionalBytes) {
        if (additionalBytes <= 0 || isAdmin(user)) {
            return;
        }
        long used = getUsedBytes(user.getId());
        long quota = getQuotaBytes(user);
        if (used > quota - additionalBytes) {
            throw new RuntimeException("云端存储空间不足，当前配额为 " + formatBytes(quota));
        }
    }

    public StorageQuotaResponse getQuota(User user) {
        long used = getUsedBytes(user.getId());
        boolean unlimited = isAdmin(user);
        long quota = getQuotaBytes(user);
        long remaining = unlimited ? Long.MAX_VALUE : Math.max(0, quota - used);
        return new StorageQuotaResponse(
            used,
            quota,
            remaining,
            user.getMembershipType() == null ? "READER" : user.getMembershipType(),
            unlimited
        );
    }

    private boolean isAdmin(User user) {
        return user != null && "ADMIN".equalsIgnoreCase(user.getRole());
    }

    private String formatBytes(long bytes) {
        if (bytes >= 1024L * 1024 * 1024) {
            return (bytes / (1024L * 1024 * 1024)) + "GB";
        }
        return (bytes / (1024L * 1024)) + "MB";
    }
}
