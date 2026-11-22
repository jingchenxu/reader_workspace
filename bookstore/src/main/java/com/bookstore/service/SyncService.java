package com.bookstore.service;

import com.bookstore.dto.*;
import com.bookstore.entity.*;
import com.bookstore.repository.*;
import org.springframework.stereotype.Service;

import java.util.List;
import java.util.stream.Collectors;

@Service
public class SyncService {

    private final ReadingProgressRepository progressRepository;
    private final BookmarkRepository bookmarkRepository;
    private final AnnotationRepository annotationRepository;

    public SyncService(ReadingProgressRepository progressRepository,
                      BookmarkRepository bookmarkRepository,
                      AnnotationRepository annotationRepository) {
        this.progressRepository = progressRepository;
        this.bookmarkRepository = bookmarkRepository;
        this.annotationRepository = annotationRepository;
    }

    // Reading Progress
    public ReadingProgressResponse saveProgress(ReadingProgressRequest request, Long userId) {
        ReadingProgress progress = progressRepository.findByBookIdAndUserId(request.getBookId(), userId)
            .orElse(new ReadingProgress());
        
        progress.setBookId(request.getBookId());
        progress.setUserId(userId);
        progress.setCfi(request.getCfi());
        progress.setPage(request.getPage());
        progress.setPercentage(request.getPercentage());
        
        ReadingProgress saved = progressRepository.save(progress);
        return convertToProgressResponse(saved);
    }

    public ReadingProgressResponse getProgress(Long bookId, Long userId) {
        return progressRepository.findByBookIdAndUserId(bookId, userId)
            .map(this::convertToProgressResponse)
            .orElse(null);
    }

    // Bookmarks
    public BookmarkResponse saveBookmark(BookmarkRequest request, Long userId) {
        Bookmark bookmark = new Bookmark();
        bookmark.setBookId(request.getBookId());
        bookmark.setUserId(userId);
        bookmark.setCfi(request.getCfi());
        bookmark.setTitle(request.getTitle());
        bookmark.setNote(request.getNote());
        
        Bookmark saved = bookmarkRepository.save(bookmark);
        return convertToBookmarkResponse(saved);
    }

    public List<BookmarkResponse> getBookmarks(Long bookId, Long userId) {
        return bookmarkRepository.findByBookIdAndUserId(bookId, userId).stream()
            .map(this::convertToBookmarkResponse)
            .collect(Collectors.toList());
    }

    public void deleteBookmark(Long id) {
        bookmarkRepository.deleteById(id);
    }

    // Annotations
    public AnnotationResponse saveAnnotation(AnnotationRequest request, Long userId) {
        Annotation annotation = new Annotation();
        annotation.setBookId(request.getBookId());
        annotation.setUserId(userId);
        annotation.setCfi(request.getCfi());
        annotation.setSelectedText(request.getSelectedText());
        annotation.setAnnotation(request.getAnnotation());
        annotation.setColor(request.getColor());
        
        Annotation saved = annotationRepository.save(annotation);
        return convertToAnnotationResponse(saved);
    }

    public List<AnnotationResponse> getAnnotations(Long bookId, Long userId) {
        return annotationRepository.findByBookIdAndUserId(bookId, userId).stream()
            .map(this::convertToAnnotationResponse)
            .collect(Collectors.toList());
    }

    public AnnotationResponse updateAnnotation(Long id, AnnotationRequest request) {
        Annotation annotation = annotationRepository.findById(id)
            .orElseThrow(() -> new RuntimeException("批注不存在"));
        
        annotation.setCfi(request.getCfi());
        annotation.setSelectedText(request.getSelectedText());
        annotation.setAnnotation(request.getAnnotation());
        annotation.setColor(request.getColor());
        
        Annotation saved = annotationRepository.save(annotation);
        return convertToAnnotationResponse(saved);
    }

    public void deleteAnnotation(Long id) {
        annotationRepository.deleteById(id);
    }

    // Converters
    private ReadingProgressResponse convertToProgressResponse(ReadingProgress progress) {
        ReadingProgressResponse response = new ReadingProgressResponse();
        response.setId(progress.getId());
        response.setBookId(progress.getBookId());
        response.setCfi(progress.getCfi());
        response.setPage(progress.getPage());
        response.setPercentage(progress.getPercentage());
        response.setUpdatedAt(progress.getUpdatedAt());
        return response;
    }

    private BookmarkResponse convertToBookmarkResponse(Bookmark bookmark) {
        BookmarkResponse response = new BookmarkResponse();
        response.setId(bookmark.getId());
        response.setBookId(bookmark.getBookId());
        response.setCfi(bookmark.getCfi());
        response.setTitle(bookmark.getTitle());
        response.setNote(bookmark.getNote());
        response.setCreatedAt(bookmark.getCreatedAt());
        return response;
    }

    private AnnotationResponse convertToAnnotationResponse(Annotation annotation) {
        AnnotationResponse response = new AnnotationResponse();
        response.setId(annotation.getId());
        response.setBookId(annotation.getBookId());
        response.setCfi(annotation.getCfi());
        response.setSelectedText(annotation.getSelectedText());
        response.setAnnotation(annotation.getAnnotation());
        response.setColor(annotation.getColor());
        response.setCreatedAt(annotation.getCreatedAt());
        response.setUpdatedAt(annotation.getUpdatedAt());
        return response;
    }
}
