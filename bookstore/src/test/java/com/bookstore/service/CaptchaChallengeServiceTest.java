package com.bookstore.service;

import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertEquals;

class CaptchaChallengeServiceTest {

    private final CaptchaChallengeService service = new CaptchaChallengeService();

    @Test
    void validatesChallengeWithoutAnHttpSession() {
        String challengeId = service.createChallenge("ABCD");

        assertEquals(
            CaptchaChallengeService.ValidationResult.VALID,
            service.validateAndConsume(challengeId, "abcd")
        );
    }

    @Test
    void challengeCanOnlyBeUsedOnce() {
        String challengeId = service.createChallenge("ABCD");

        assertEquals(
            CaptchaChallengeService.ValidationResult.INVALID,
            service.validateAndConsume(challengeId, "WXYZ")
        );
        assertEquals(
            CaptchaChallengeService.ValidationResult.EXPIRED,
            service.validateAndConsume(challengeId, "ABCD")
        );
    }
}
