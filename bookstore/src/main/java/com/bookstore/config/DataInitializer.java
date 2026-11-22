package com.bookstore.config;

import com.bookstore.entity.User;
import com.bookstore.repository.UserRepository;
import com.bookstore.service.SystemConfigService;
import org.springframework.boot.CommandLineRunner;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Transactional;

@Component
public class DataInitializer implements CommandLineRunner {

    private final UserRepository userRepository;
    private final PasswordEncoder passwordEncoder;
    private final SystemConfigService systemConfigService;

    public DataInitializer(UserRepository userRepository,
                           PasswordEncoder passwordEncoder,
                           SystemConfigService systemConfigService) {
        this.userRepository = userRepository;
        this.passwordEncoder = passwordEncoder;
        this.systemConfigService = systemConfigService;
    }

    @Override
    @Transactional
    public void run(String... args) {
        systemConfigService.initializeDefaults();
        normalizeReaderRoles();
        createDefaultAdministrator();
    }

    private void normalizeReaderRoles() {
        userRepository.findAll().forEach(user -> {
            boolean changed = false;
            if (user.getRole() == null || "USER".equalsIgnoreCase(user.getRole())) {
                user.setRole("READER");
                changed = true;
            }
            if (user.getMembershipType() == null || user.getMembershipType().trim().isEmpty()) {
                user.setMembershipType("READER");
                changed = true;
            }
            if (changed) {
                userRepository.save(user);
            }
        });
    }

    private void createDefaultAdministrator() {
        User admin = userRepository.findByUsername("admin").orElse(null);
        if (admin == null) {
            admin = new User();
            admin.setUsername("admin");
            admin.setPassword(passwordEncoder.encode("admin"));
            admin.setEmail("admin@localhost.local");
        }
        admin.setRole("ADMIN");
        admin.setMembershipType("MEMBER");
        admin.setEnabled(true);
        userRepository.save(admin);
    }
}
