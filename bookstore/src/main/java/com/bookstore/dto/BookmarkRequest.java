package com.bookstore.dto;

import lombok.Data;

@Data
public class BookmarkRequest {
    private Long bookId;
    private String cfi;
    private String title;
    private String note;
}
