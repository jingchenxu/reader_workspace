package com.bookstore.dto;

import lombok.Data;

@Data
public class AnnotationRequest {
    private Long bookId;
    private String cfi;
    private String selectedText;
    private String annotation;
    private String color;
}
