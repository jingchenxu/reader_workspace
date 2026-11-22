package com.bookstore.controller;

import com.bookstore.dto.BookResponse;
import com.bookstore.dto.CategoryResponse;
import com.bookstore.entity.User;
import com.bookstore.repository.BookRepository;
import com.bookstore.service.BookService;
import com.bookstore.service.CategoryService;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.PageRequest;
import org.springframework.security.core.Authentication;
import org.springframework.stereotype.Controller;
import org.springframework.ui.Model;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestParam;

import javax.servlet.http.HttpServletResponse;

import java.util.List;

@Controller
public class HomeController {

    private static final int BOOKS_PER_PAGE = 10;

    private final BookService bookService;
    private final CategoryService categoryService;
    private final BookRepository bookRepository;

    public HomeController(BookService bookService, CategoryService categoryService, BookRepository bookRepository) {
        this.bookService = bookService;
        this.categoryService = categoryService;
        this.bookRepository = bookRepository;
    }

    @GetMapping("/")
    public String home(Model model) {
        model.addAttribute("appName", "EPUB阅读器");
        model.addAttribute("appDescription", "跨平台EPUB电子书阅读解决方案");
        return "index";
    }

    @GetMapping("/register")
    public String register() {
        return "register";
    }

    @GetMapping("/login")
    public String login() {
        return "login";
    }

    @GetMapping("/books")
    public String books(
            Authentication authentication,
            @RequestParam(defaultValue = "0") int page,
            @RequestParam(required = false) Long categoryId,
            Model model) {
        if (authentication == null || !authentication.isAuthenticated()) {
            return "redirect:/login";
        }

        User currentUser = (User) authentication.getPrincipal();
        if ("ADMIN".equalsIgnoreCase(currentUser.getRole())) {
            return "redirect:/admin";
        }
        int requestedPage = Math.max(page, 0);
        PageRequest pageable = PageRequest.of(requestedPage, BOOKS_PER_PAGE);
        Page<BookResponse> bookPage = bookService.getUserBooks(currentUser.getId(), categoryId, pageable);

        if (bookPage.getTotalPages() > 0 && requestedPage >= bookPage.getTotalPages()) {
            String redirectUrl = "redirect:/books?page=" + (bookPage.getTotalPages() - 1);
            if (categoryId != null) {
                redirectUrl += "&categoryId=" + categoryId;
            }
            return redirectUrl;
        }

        int startPage = Math.max(0, requestedPage - 2);
        int endPage = Math.min(bookPage.getTotalPages() - 1, startPage + 4);
        startPage = Math.max(0, endPage - 4);

        List<CategoryResponse> categories = categoryService.getUserCategories(currentUser.getId());
        String currentCategoryName = categories.stream()
            .filter(category -> category.getId().equals(categoryId))
            .map(CategoryResponse::getName)
            .findFirst()
            .orElse("全部图书");

        model.addAttribute("username", currentUser.getUsername());
        model.addAttribute("role", currentUser.getRole());
        model.addAttribute("books", bookPage.getContent());
        model.addAttribute("bookCount", bookPage.getTotalElements());
        model.addAttribute("allBookCount", bookRepository.countByUserId(currentUser.getId()));
        model.addAttribute("isAdmin", false);
        model.addAttribute("categories", categories);
        model.addAttribute("currentCategoryId", categoryId);
        model.addAttribute("currentCategoryName", currentCategoryName);
        model.addAttribute("currentPage", requestedPage);
        model.addAttribute("totalPages", bookPage.getTotalPages());
        model.addAttribute("hasPrevious", bookPage.hasPrevious());
        model.addAttribute("hasNext", bookPage.hasNext());
        model.addAttribute("startPage", startPage);
        model.addAttribute("endPage", endPage);

        return "books";
    }

    @GetMapping("/admin")
    public String admin(Authentication authentication, Model model, HttpServletResponse response) {
        response.setHeader("Cache-Control", "no-store, no-cache, must-revalidate, max-age=0");
        response.setHeader("Pragma", "no-cache");
        response.setDateHeader("Expires", 0);
        if (authentication == null || !authentication.isAuthenticated()) {
            return "redirect:/login";
        }
        User currentUser = (User) authentication.getPrincipal();
        if (!"ADMIN".equalsIgnoreCase(currentUser.getRole())) {
            return "redirect:/books";
        }
        model.addAttribute("username", currentUser.getUsername());
        return "admin";
    }
}
