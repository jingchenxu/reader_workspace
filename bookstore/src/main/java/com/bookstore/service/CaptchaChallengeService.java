package com.bookstore.service;

import org.springframework.stereotype.Service;

import java.time.Duration;
import java.time.Instant;
import java.util.Map;
import java.util.UUID;
import java.util.concurrent.ConcurrentHashMap;

@Service
public class CaptchaChallengeService {

    private static final Duration CHALLENGE_TTL = Duration.ofMinutes(5);

    private final Map<String, CaptchaChallenge> challenges = new ConcurrentHashMap<>();

    public String createChallenge(String code) {
        removeExpiredChallenges();

        String challengeId = UUID.randomUUID().toString();
        challenges.put(challengeId, new CaptchaChallenge(code, Instant.now().plus(CHALLENGE_TTL)));
        return challengeId;
    }

    public ValidationResult validateAndConsume(String challengeId, String submittedCode) {
        if (challengeId == null || challengeId.trim().isEmpty()) {
            return ValidationResult.EXPIRED;
        }

        CaptchaChallenge challenge = challenges.remove(challengeId.trim());
        if (challenge == null || challenge.expiresAt.isBefore(Instant.now())) {
            return ValidationResult.EXPIRED;
        }

        if (submittedCode == null || !challenge.code.equalsIgnoreCase(submittedCode.trim())) {
            return ValidationResult.INVALID;
        }

        return ValidationResult.VALID;
    }

    private void removeExpiredChallenges() {
        Instant now = Instant.now();
        challenges.entrySet().removeIf(entry -> entry.getValue().expiresAt.isBefore(now));
    }

    public enum ValidationResult {
        VALID,
        INVALID,
        EXPIRED
    }

    private static class CaptchaChallenge {
        private final String code;
        private final Instant expiresAt;

        private CaptchaChallenge(String code, Instant expiresAt) {
            this.code = code;
            this.expiresAt = expiresAt;
        }
    }
}
