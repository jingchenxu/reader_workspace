package com.bookstore.controller;

import com.bookstore.dto.ApiResponse;
import com.bookstore.dto.LoginRequest;
import com.bookstore.exception.GlobalExceptionHandler;
import com.bookstore.service.AuthService;
import com.bookstore.service.CaptchaChallengeService;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.authentication.BadCredentialsException;

import javax.servlet.http.HttpSession;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
class AuthControllerTest {

    @Mock
    private AuthService authService;

    @Mock
    private CaptchaChallengeService captchaChallengeService;

    @Mock
    private HttpSession session;

    private AuthController authController;

    @BeforeEach
    void setUp() {
        authController = new AuthController(authService, captchaChallengeService);
    }

    @Test
    void badCredentialsReturnFriendlyMessage() {
        LoginRequest request = new LoginRequest();
        request.setUsername("unknown-user");
        request.setPassword("wrong-password");
        request.setCaptcha("ABCD");
        request.setCaptchaId("captcha-id");

        when(captchaChallengeService.validateAndConsume("captcha-id", "ABCD"))
            .thenReturn(CaptchaChallengeService.ValidationResult.VALID);
        when(authService.login(request)).thenThrow(new BadCredentialsException("Bad credentials"));

        BadCredentialsException exception = assertThrows(
            BadCredentialsException.class,
            () -> authController.login(request, session)
        );

        ResponseEntity<ApiResponse> response =
            new GlobalExceptionHandler().handleBadCredentialsException(exception);

        assertEquals(HttpStatus.BAD_REQUEST, response.getStatusCode());
        assertNotNull(response.getBody());
        assertEquals("用户名或密码错误", response.getBody().getMessage());
    }
}
