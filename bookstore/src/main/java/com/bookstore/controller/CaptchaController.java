package com.bookstore.controller;

import com.bookstore.service.CaptchaChallengeService;
import org.springframework.http.CacheControl;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import javax.imageio.ImageIO;
import javax.servlet.http.HttpSession;
import java.awt.*;
import java.awt.image.BufferedImage;
import java.io.ByteArrayOutputStream;
import java.security.SecureRandom;
import java.util.concurrent.TimeUnit;

@RestController
@RequestMapping("/api/auth")
public class CaptchaController {

    public static final String CAPTCHA_SESSION_KEY = "LOGIN_CAPTCHA";
    public static final String CAPTCHA_ID_HEADER = "X-Captcha-Id";

    private static final String CAPTCHA_CHARS = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
    private static final int WIDTH = 120;
    private static final int HEIGHT = 42;
    private static final SecureRandom RANDOM = new SecureRandom();

    private final CaptchaChallengeService captchaChallengeService;

    public CaptchaController(CaptchaChallengeService captchaChallengeService) {
        this.captchaChallengeService = captchaChallengeService;
    }

    @GetMapping(value = "/captcha", produces = MediaType.IMAGE_PNG_VALUE)
    public ResponseEntity<byte[]> captcha(HttpSession session) throws Exception {
        String code = generateCode(4);
        session.setAttribute(CAPTCHA_SESSION_KEY, code);
        String captchaId = captchaChallengeService.createChallenge(code);

        BufferedImage image = new BufferedImage(WIDTH, HEIGHT, BufferedImage.TYPE_INT_RGB);
        Graphics2D graphics = image.createGraphics();
        try {
            graphics.setRenderingHint(RenderingHints.KEY_ANTIALIASING, RenderingHints.VALUE_ANTIALIAS_ON);
            graphics.setColor(new Color(245, 247, 255));
            graphics.fillRect(0, 0, WIDTH, HEIGHT);

            drawNoise(graphics);
            drawCode(graphics, code);
        } finally {
            graphics.dispose();
        }

        ByteArrayOutputStream outputStream = new ByteArrayOutputStream();
        ImageIO.write(image, "png", outputStream);

        return ResponseEntity.ok()
            .cacheControl(CacheControl.maxAge(0, TimeUnit.SECONDS).noStore().mustRevalidate())
            .contentType(MediaType.IMAGE_PNG)
            .header(CAPTCHA_ID_HEADER, captchaId)
            .body(outputStream.toByteArray());
    }

    private String generateCode(int length) {
        StringBuilder code = new StringBuilder(length);
        for (int i = 0; i < length; i++) {
            code.append(CAPTCHA_CHARS.charAt(RANDOM.nextInt(CAPTCHA_CHARS.length())));
        }
        return code.toString();
    }

    private void drawNoise(Graphics2D graphics) {
        for (int i = 0; i < 10; i++) {
            graphics.setColor(randomColor(130, 210));
            int x1 = RANDOM.nextInt(WIDTH);
            int y1 = RANDOM.nextInt(HEIGHT);
            int x2 = RANDOM.nextInt(WIDTH);
            int y2 = RANDOM.nextInt(HEIGHT);
            graphics.drawLine(x1, y1, x2, y2);
        }

        for (int i = 0; i < 35; i++) {
            graphics.setColor(randomColor(140, 230));
            graphics.fillOval(RANDOM.nextInt(WIDTH), RANDOM.nextInt(HEIGHT), 2, 2);
        }
    }

    private void drawCode(Graphics2D graphics, String code) {
        graphics.setFont(new Font(Font.SANS_SERIF, Font.BOLD, 28));
        for (int i = 0; i < code.length(); i++) {
            graphics.setColor(randomColor(40, 120));
            double angle = (RANDOM.nextInt(25) - 12) * Math.PI / 180;
            graphics.rotate(angle, 24 + i * 23, 28);
            graphics.drawString(String.valueOf(code.charAt(i)), 16 + i * 24, 30);
            graphics.rotate(-angle, 24 + i * 23, 28);
        }
    }

    private Color randomColor(int min, int max) {
        int bound = max - min + 1;
        return new Color(
            min + RANDOM.nextInt(bound),
            min + RANDOM.nextInt(bound),
            min + RANDOM.nextInt(bound)
        );
    }
}
