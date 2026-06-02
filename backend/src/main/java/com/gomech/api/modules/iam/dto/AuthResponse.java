package com.gomech.api.modules.iam.dto;

public record AuthResponse(
        String accessToken,
        String refreshToken,
        long expiresIn
) {}
