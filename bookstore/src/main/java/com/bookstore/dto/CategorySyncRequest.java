package com.bookstore.dto;

import lombok.Data;

import java.util.List;

@Data
public class CategorySyncRequest {

    private List<CategoryItem> categories;

    private List<BookCategoryItem> bookCategories;

    @Data
    public static class CategoryItem {
        private String localId;
        private Long localCategoryId;
        private String name;
        private String color;
    }

    @Data
    public static class BookCategoryItem {
        private Long bookId;
        private String title;
        private String localCategoryId;
        private Long categoryId;
        private String categoryName;
    }
}
