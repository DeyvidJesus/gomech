package com.gomech.api.modules.iam.dto;

import jakarta.validation.constraints.Email;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotEmpty;

import java.util.List;
import java.util.UUID;

public record CreateUserRequest(
        @NotBlank String name,
        @NotBlank @Email String email,
        @NotBlank String password,
        @NotEmpty List<RoleAssignmentDto> roles
) {
    public record RoleAssignmentDto(
            UUID roleId,
            UUID unitId
    ) {}
}
