package com.gomech.api.modules.iam.services;

import com.gomech.api.core.security.JwtUtil;
import com.gomech.api.modules.iam.dto.AuthResponse;
import com.gomech.api.modules.iam.dto.LoginRequest;
import com.gomech.api.modules.iam.models.User;
import com.gomech.api.modules.iam.models.UserSession;
import com.gomech.api.modules.iam.repositories.UserRepository;
import com.gomech.api.modules.iam.repositories.UserSessionRepository;
import lombok.RequiredArgsConstructor;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDateTime;
import java.util.UUID;

@Service
@RequiredArgsConstructor
public class AuthService {

    private final UserRepository userRepository;
    private final UserSessionRepository userSessionRepository;
    private final PasswordEncoder passwordEncoder;
    private final JwtUtil jwtUtil;

    @Value("${jwt.expiration}")
    private long jwtExpiration;

    @Value("${jwt.refresh-expiration}")
    private long jwtRefreshExpiration;

    @Transactional
    public AuthResponse login(LoginRequest request) {
        User user = userRepository.findByEmail(request.email())
                .orElseThrow(() -> new IllegalArgumentException("Credenciais inválidas"));

        if (!passwordEncoder.matches(request.password(), user.getPasswordHash())) {
            throw new IllegalArgumentException("Credenciais inválidas");
        }

        if (!"ACTIVE".equals(user.getStatus())) {
            throw new IllegalArgumentException("Usuário inativo ou suspenso");
        }

        user.setLastLogin(LocalDateTime.now());
        userRepository.save(user);

        String accessToken = jwtUtil.generateToken(user.getId(), user.getTenantId());
        String refreshToken = UUID.randomUUID().toString(); // Refresh token opaco

        UserSession session = new UserSession();
        session.setUser(user);
        session.setRefreshToken(refreshToken);
        session.setExpiresAt(LocalDateTime.now().plusSeconds(jwtRefreshExpiration / 1000));
        userSessionRepository.save(session);

        return new AuthResponse(accessToken, refreshToken, jwtExpiration / 1000);
    }
}
