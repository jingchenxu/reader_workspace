package com.bookstore.dto;

import lombok.AllArgsConstructor;
import lombok.Data;
import lombok.NoArgsConstructor;

@Data
@NoArgsConstructor
@AllArgsConstructor
public class StorageQuotaResponse {
    private Long usedBytes;
    private Long quotaBytes;
    private Long remainingBytes;
    private String membershipType;
    private boolean unlimited;
}
