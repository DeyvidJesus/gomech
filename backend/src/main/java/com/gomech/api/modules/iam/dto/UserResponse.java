package com.gomech.api.modules.iam.dto;

import java.util.UUID;

public record UserResponse(
        UUID id,
        String name,
        String email,
        String status
) {}
