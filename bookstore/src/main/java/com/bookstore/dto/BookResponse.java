package com.bookstore.dto;

import lombok.Data;
import lombok.AllArgsConstructor;
import lombok.NoArgsConstructor;

import java.time.LocalDateTime;

@Data
@AllArgsConstructor
@NoArgsConstructor
public class BookResponse {

    private Long id;
    private String title;
    private String author;
    private String publisher;
    private String isbn;
    private String pubDate;
    private String language;
    private String description;
    private String coverPath;
    private String bookPath;
    private String fileHash;
    private String originalFileName;
    private Long fileSize;
    private Long userId;
    private Long categoryId;
    private String categoryName;
    private LocalDateTime addedAt;
    private LocalDateTime lastReadAt;
}
