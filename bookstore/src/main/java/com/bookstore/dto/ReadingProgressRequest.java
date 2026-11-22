package com.bookstore.dto;

import lombok.Data;
import java.time.LocalDateTime;

@Data
public class ReadingProgressRequest {
    private Long bookId;
    private String cfi;
    private Integer page;
    private Double percentage;
}
