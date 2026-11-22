package com.bookstore.entity;

import javax.persistence.*;
import lombok.Data;
import lombok.NoArgsConstructor;
import lombok.AllArgsConstructor;

import java.time.LocalDateTime;

@Data
@NoArgsConstructor
@AllArgsConstructor
@Entity
@Table(
    name = "books",
    uniqueConstraints = @UniqueConstraint(
        name = "uk_books_user_file_hash",
        columnNames = {"user_id", "file_hash"}
    )
)
public class Book {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(nullable = false, length = 500)
    private String title;

    @Column(length = 200)
    private String author;

    @Column(length = 200)
    private String publisher;

    @Column(length = 50)
    private String isbn;

    @Column(name = "pub_date", length = 50)
    private String pubDate;

    @Column(length = 20)
    private String language;

    @Column(columnDefinition = "TEXT")
    private String description;

    @Column(name = "cover_path", length = 500)
    private String coverPath;

    @Column(name = "book_path", nullable = false, length = 500)
    private String bookPath;

    @Column(name = "file_hash", length = 64)
    private String fileHash;

    @Column(name = "original_file_name", length = 500)
    private String originalFileName;

    @Column(name = "file_size")
    private Long fileSize;

    @Column(name = "user_id", nullable = false)
    private Long userId;

    @Column(name = "category_id")
    private Long categoryId;

    @Column(name = "added_at")
    private LocalDateTime addedAt;

    @Column(name = "last_read_at")
    private LocalDateTime lastReadAt;

    @PrePersist
    protected void onCreate() {
        if (addedAt == null) {
            addedAt = LocalDateTime.now();
        }
    }
}
