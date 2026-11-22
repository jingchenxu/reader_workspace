package com.bookstore.dto;

import lombok.Data;
import lombok.AllArgsConstructor;
import lombok.NoArgsConstructor;
import java.time.LocalDateTime;

@Data
@AllArgsConstructor
@NoArgsConstructor
public class ReadingProgressResponse {
    private Long id;
    private Long bookId;
    private String cfi;
    private Integer page;
    private Double percentage;
    private LocalDateTime updatedAt;
}
