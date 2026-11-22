package com.bookstore.service;

import com.bookstore.dto.UserResponse;
import com.bookstore.entity.User;
import com.bookstore.repository.AnnotationRepository;
import com.bookstore.repository.BookmarkRepository;
import com.bookstore.repository.CategoryRepository;
import com.bookstore.repository.ReadingProgressRepository;
import com.bookstore.repository.UserRepository;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.List;
import java.util.stream.Collectors;

@Service
public class UserService {

    private final UserRepository userRepository;
    private final StorageQuotaService storageQuotaService;
    private final BookService bookService;
    private final AnnotationRepository annotationRepository;
    private final BookmarkRepository bookmarkRepository;
    private final ReadingProgressRepository readingProgressRepository;
    private final CategoryRepository categoryRepository;

    public UserService(UserRepository userRepository,
                       StorageQuotaService storageQuotaService,
                       BookService bookService,
                       AnnotationRepository annotationRepository,
                       BookmarkRepository bookmarkRepository,
                       ReadingProgressRepository readingProgressRepository,
                       CategoryRepository categoryRepository) {
        this.userRepository = userRepository;
        this.storageQuotaService = storageQuotaService;
        this.bookService = bookService;
        this.annotationRepository = annotationRepository;
        this.bookmarkRepository = bookmarkRepository;
        this.readingProgressRepository = readingProgressRepository;
        this.categoryRepository = categoryRepository;
    }

    public List<UserResponse> getAllUsers() {
        return userRepository.findAll().stream()
            .map(this::convertToResponse)
            .collect(Collectors.toList());
    }

    public UserResponse getUserById(Long id) {
        return convertToResponse(findUser(id));
    }

    public UserResponse updateUserRole(Long currentUserId, Long id, String role) {
        User user = findUser(id);
        String normalizedRole = "USER".equalsIgnoreCase(role) ? "READER" : role;
        if (!"READER".equals(normalizedRole) && !"ADMIN".equals(normalizedRole)) {
            throw new RuntimeException("无效的用户角色");
        }
        if ("admin".equalsIgnoreCase(user.getUsername()) && !"ADMIN".equals(normalizedRole)) {
            throw new RuntimeException("默认管理员角色不能修改");
        }
        if (id.equals(currentUserId) && !"ADMIN".equals(normalizedRole)) {
            throw new RuntimeException("不能取消当前登录管理员的管理员角色");
        }
        user.setRole(normalizedRole);
        return convertToResponse(userRepository.save(user));
    }

    public UserResponse updateMembershipType(Long id, String membershipType) {
        User user = findUser(id);
        if (!"READER".equals(membershipType) && !"MEMBER".equals(membershipType)) {
            throw new RuntimeException("无效的会员类型");
        }
        user.setMembershipType(membershipType);
        return convertToResponse(userRepository.save(user));
    }

    public UserResponse updateEnabled(Long currentUserId, Long id, Boolean enabled) {
        User user = findUser(id);
        if ("admin".equalsIgnoreCase(user.getUsername()) && Boolean.FALSE.equals(enabled)) {
            throw new RuntimeException("默认管理员不能禁用");
        }
        if (id.equals(currentUserId) && Boolean.FALSE.equals(enabled)) {
            throw new RuntimeException("不能禁用当前登录的管理员");
        }
        user.setEnabled(enabled == null || enabled);
        return convertToResponse(userRepository.save(user));
    }

    @Transactional
    public void deleteUser(Long currentUserId, Long id) {
        User user = findUser(id);
        if ("admin".equalsIgnoreCase(user.getUsername())) {
            throw new RuntimeException("默认管理员不能删除");
        }
        if (id.equals(currentUserId)) {
            throw new RuntimeException("不能删除当前登录的管理员");
        }
        annotationRepository.deleteByUserId(id);
        bookmarkRepository.deleteByUserId(id);
        readingProgressRepository.deleteByUserId(id);
        bookService.deleteAllBooksForUser(id);
        categoryRepository.deleteByUserId(id);
        userRepository.delete(user);
    }

    private User findUser(Long id) {
        return userRepository.findById(id)
            .orElseThrow(() -> new RuntimeException("用户不存在"));
    }

    private UserResponse convertToResponse(User user) {
        UserResponse response = new UserResponse();
        response.setId(user.getId());
        response.setUsername(user.getUsername());
        response.setEmail(user.getEmail());
        response.setPhone(user.getPhone());
        response.setRole(user.getRole());
        response.setMembershipType(user.getMembershipType() == null ? "READER" : user.getMembershipType());
        response.setEnabled(user.getEnabled());
        response.setStorageUsedBytes(storageQuotaService.getUsedBytes(user.getId()));
        response.setStorageQuotaBytes(storageQuotaService.getQuotaBytes(user));
        response.setCreatedAt(user.getCreatedAt());
        return response;
    }
}
