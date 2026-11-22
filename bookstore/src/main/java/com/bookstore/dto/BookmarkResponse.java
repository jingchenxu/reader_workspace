package com.bookstore.dto;

import lombok.Data;
import lombok.AllArgsConstructor;
import lombok.NoArgsConstructor;
import java.time.LocalDateTime;

@Data
@AllArgsConstructor
@NoArgsConstructor
public class BookmarkResponse {
    private Long id;
    private Long bookId;
    private String cfi;
    private String title;
    private String note;
    private LocalDateTime createdAt;
}
