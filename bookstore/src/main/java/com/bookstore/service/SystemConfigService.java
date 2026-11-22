package com.bookstore.service;

import com.bookstore.entity.SystemConfig;
import com.bookstore.repository.SystemConfigRepository;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.LinkedHashMap;
import java.util.Map;

@Service
public class SystemConfigService {

    public static final String READER_QUOTA_KEY = "storage.reader.quota-bytes";
    public static final String MEMBER_QUOTA_KEY = "storage.member.quota-bytes";
    public static final long DEFAULT_READER_QUOTA = 10L * 1024 * 1024;
    public static final long DEFAULT_MEMBER_QUOTA = 1024L * 1024 * 1024;

    private final SystemConfigRepository repository;

    public SystemConfigService(SystemConfigRepository repository) {
        this.repository = repository;
    }

    @Transactional
    public void initializeDefaults() {
        createIfMissing(READER_QUOTA_KEY, DEFAULT_READER_QUOTA, "普通阅读器用户云端存储配额");
        createIfMissing(MEMBER_QUOTA_KEY, DEFAULT_MEMBER_QUOTA, "会员阅读器用户云端存储配额");
    }

    public long getReaderQuotaBytes() {
        return getPositiveLong(READER_QUOTA_KEY, DEFAULT_READER_QUOTA);
    }

    public long getMemberQuotaBytes() {
        return getPositiveLong(MEMBER_QUOTA_KEY, DEFAULT_MEMBER_QUOTA);
    }

    public Map<String, Long> getStorageConfigs() {
        Map<String, Long> result = new LinkedHashMap<>();
        result.put(READER_QUOTA_KEY, getReaderQuotaBytes());
        result.put(MEMBER_QUOTA_KEY, getMemberQuotaBytes());
        return result;
    }

    @Transactional
    public Map<String, Long> updateStorageConfigs(Map<String, Long> values) {
        if (values == null) {
            throw new RuntimeException("系统配置不能为空");
        }
        updatePositiveLong(READER_QUOTA_KEY, values.get(READER_QUOTA_KEY));
        updatePositiveLong(MEMBER_QUOTA_KEY, values.get(MEMBER_QUOTA_KEY));
        return getStorageConfigs();
    }

    private void createIfMissing(String key, long value, String description) {
        if (!repository.findByConfigKey(key).isPresent()) {
            SystemConfig config = new SystemConfig();
            config.setConfigKey(key);
            config.setConfigValue(String.valueOf(value));
            config.setDescription(description);
            repository.save(config);
        }
    }

    private long getPositiveLong(String key, long defaultValue) {
        return repository.findByConfigKey(key)
            .map(SystemConfig::getConfigValue)
            .map(value -> parsePositiveLong(value, defaultValue))
            .orElse(defaultValue);
    }

    private long parsePositiveLong(String value, long defaultValue) {
        try {
            long parsed = Long.parseLong(value);
            return parsed > 0 ? parsed : defaultValue;
        } catch (NumberFormatException ignored) {
            return defaultValue;
        }
    }

    private void updatePositiveLong(String key, Long value) {
        if (value == null) {
            return;
        }
        if (value <= 0) {
            throw new RuntimeException("存储配额必须大于0");
        }
        SystemConfig config = repository.findByConfigKey(key).orElseGet(SystemConfig::new);
        config.setConfigKey(key);
        config.setConfigValue(String.valueOf(value));
        if (config.getDescription() == null) {
            config.setDescription(key.equals(READER_QUOTA_KEY)
                ? "普通阅读器用户云端存储配额"
                : "会员阅读器用户云端存储配额");
        }
        repository.save(config);
    }
}
