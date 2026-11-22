package com.bookstore.dto;

import lombok.Data;
import lombok.AllArgsConstructor;
import lombok.NoArgsConstructor;
import java.time.LocalDateTime;

@Data
@AllArgsConstructor
@NoArgsConstructor
public class AnnotationResponse {
    private Long id;
    private Long bookId;
    private String cfi;
    private String selectedText;
    private String annotation;
    private String color;
    private LocalDateTime createdAt;
    private LocalDateTime updatedAt;
}
