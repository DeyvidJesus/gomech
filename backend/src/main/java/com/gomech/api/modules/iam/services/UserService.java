package com.gomech.api.modules.iam.services;

import com.gomech.api.core.tenancy.TenantContextHolder;
import com.gomech.api.modules.iam.dto.CreateUserRequest;
import com.gomech.api.modules.iam.dto.UserResponse;
import com.gomech.api.modules.iam.models.Role;
import com.gomech.api.modules.iam.models.Unit;
import com.gomech.api.modules.iam.models.User;
import com.gomech.api.modules.iam.models.UserRole;
import com.gomech.api.modules.iam.repositories.RoleRepository;
import com.gomech.api.modules.iam.repositories.UnitRepository;
import com.gomech.api.modules.iam.repositories.UserRepository;
import lombok.RequiredArgsConstructor;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
@RequiredArgsConstructor
public class UserService {

    private final UserRepository userRepository;
    private final RoleRepository roleRepository;
    private final UnitRepository unitRepository;
    private final PasswordEncoder passwordEncoder;

    @Transactional
    public UserResponse createUser(CreateUserRequest request) {
        if (userRepository.existsByEmail(request.email())) {
            throw new IllegalArgumentException("E-mail já cadastrado");
        }

        User user = new User();
        user.setName(request.name());
        user.setEmail(request.email());
        user.setPasswordHash(passwordEncoder.encode(request.password()));
        user.setTenantId(TenantContextHolder.getTenantId());

        for (CreateUserRequest.RoleAssignmentDto assignment : request.roles()) {
            Role role = roleRepository.findById(assignment.roleId())
                    .orElseThrow(() -> new IllegalArgumentException("Role inválida: " + assignment.roleId()));
            
            Unit unit = null;
            if (assignment.unitId() != null) {
                unit = unitRepository.findById(assignment.unitId())
                        .orElseThrow(() -> new IllegalArgumentException("Unit inválida: " + assignment.unitId()));
            }

            UserRole userRole = new UserRole();
            userRole.setUser(user);
            userRole.setRole(role);
            userRole.setUnit(unit);
            userRole.setTenantId(TenantContextHolder.getTenantId());
            
            user.getUserRoles().add(userRole);
        }

        User savedUser = userRepository.save(user);

        return new UserResponse(
                savedUser.getId(),
                savedUser.getName(),
                savedUser.getEmail(),
                savedUser.getStatus()
        );
    }
}
