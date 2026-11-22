package com.bookstore.dto;

import lombok.Data;
import lombok.AllArgsConstructor;
import lombok.NoArgsConstructor;

import java.time.LocalDateTime;

@Data
@AllArgsConstructor
@NoArgsConstructor
public class UserResponse {

    private Long id;
    private String username;
    private String email;
    private String phone;
    private String role;
    private String membershipType;
    private Boolean enabled;
    private Long storageUsedBytes;
    private Long storageQuotaBytes;
    private LocalDateTime createdAt;
}
