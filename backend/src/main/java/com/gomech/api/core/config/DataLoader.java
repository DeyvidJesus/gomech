package com.gomech.api.core.config;

import com.gomech.api.modules.iam.models.Tenant;
import com.gomech.api.modules.iam.models.User;
import com.gomech.api.modules.iam.repositories.TenantRepository;
import com.gomech.api.modules.iam.repositories.UserRepository;
import lombok.RequiredArgsConstructor;
import org.springframework.boot.CommandLineRunner;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Component;

import java.util.UUID;

@Component
@RequiredArgsConstructor
public class DataLoader implements CommandLineRunner {

    private final TenantRepository tenantRepository;
    private final UserRepository userRepository;
    private final PasswordEncoder passwordEncoder;

    @Override
    public void run(String... args) throws Exception {
        if (tenantRepository.count() == 0) {
            Tenant defaultTenant = new Tenant();
            defaultTenant.setId(UUID.fromString("00000000-0000-0000-0000-000000000000"));
            defaultTenant.setName("Oficina GoMech System");
            defaultTenant.setCnpj("00.000.000/0001-00");
            tenantRepository.save(defaultTenant);

            User adminUser = new User();
            adminUser.setTenantId(defaultTenant.getId());
            adminUser.setName("System Admin");
            adminUser.setEmail("admin@gomech.com");
            adminUser.setPasswordHash(passwordEncoder.encode("admin123"));
            userRepository.save(adminUser);

            System.out.println("Tenant Zero e Admin criados! Login: admin@gomech.com / admin123");
        }
    }
}
