package com.bookstore.controller;

import com.bookstore.dto.ApiResponse;
import com.bookstore.dto.JwtResponse;
import com.bookstore.dto.LoginRequest;
import com.bookstore.dto.RegisterRequest;
import com.bookstore.entity.User;
import com.bookstore.service.AuthService;
import com.bookstore.service.CaptchaChallengeService;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import javax.servlet.http.HttpSession;
import javax.validation.Valid;

@RestController
@RequestMapping("/api/auth")
@Tag(name = "用户认证", description = "用户注册、登录等认证相关接口")
public class AuthController {

    private final AuthService authService;
    private final CaptchaChallengeService captchaChallengeService;

    public AuthController(AuthService authService, CaptchaChallengeService captchaChallengeService) {
        this.authService = authService;
        this.captchaChallengeService = captchaChallengeService;
    }

    @PostMapping("/login")
    @Operation(summary = "用户登录", description = "使用用户名、密码和验证码登录，返回 JWT Token")
    public ResponseEntity<ApiResponse> login(@Valid @RequestBody LoginRequest loginRequest, HttpSession session) {
        validateCaptcha(loginRequest, session);
        JwtResponse jwtResponse = authService.login(loginRequest);
        return ResponseEntity.ok(ApiResponse.success("登录成功", jwtResponse));
    }

    @PostMapping("/register")
    @Operation(summary = "用户注册", description = "创建新用户账号，默认角色为 USER")
    public ResponseEntity<ApiResponse> register(@Valid @RequestBody RegisterRequest registerRequest) {
        try {
            User user = authService.register(registerRequest);
            return ResponseEntity.ok(ApiResponse.success("注册成功", user));
        } catch (Exception e) {
            return ResponseEntity.badRequest().body(ApiResponse.error(e.getMessage()));
        }
    }

    private void validateCaptcha(LoginRequest loginRequest, HttpSession session) {
        if (loginRequest.getCaptchaId() != null && !loginRequest.getCaptchaId().trim().isEmpty()) {
            CaptchaChallengeService.ValidationResult result = captchaChallengeService.validateAndConsume(
                loginRequest.getCaptchaId(),
                loginRequest.getCaptcha()
            );

            if (result == CaptchaChallengeService.ValidationResult.EXPIRED) {
                throw new RuntimeException("验证码已过期，请刷新后重试");
            }
            if (result == CaptchaChallengeService.ValidationResult.INVALID) {
                throw new RuntimeException("验证码错误");
            }
            return;
        }

        Object expectedCaptcha = session.getAttribute(CaptchaController.CAPTCHA_SESSION_KEY);
        session.removeAttribute(CaptchaController.CAPTCHA_SESSION_KEY);

        if (expectedCaptcha == null) {
            throw new RuntimeException("验证码已过期，请刷新后重试");
        }

        String submittedCaptcha = loginRequest.getCaptcha();
        if (submittedCaptcha == null || !expectedCaptcha.toString().equalsIgnoreCase(submittedCaptcha.trim())) {
            throw new RuntimeException("验证码错误");
        }
    }
}
