package com.bookstore.dto;

import lombok.Data;

@Data
public class BookSyncRequest {

    private String title;
    private String author;
    private String publisher;
    private String isbn;
    private String pubDate;
    private String language;
    private String description;
    private String coverPath;
    private String bookPath;
    private Long categoryId;
    private String localCategoryId;
    private String categoryName;
}
