package com.gomech.api.core.tenancy;

import org.hibernate.context.spi.CurrentTenantIdentifierResolver;
import org.springframework.stereotype.Component;

import java.util.UUID;

@Component
public class HibernateTenantIdentifierResolver implements CurrentTenantIdentifierResolver<UUID> {

    @Override
    public UUID resolveCurrentTenantIdentifier() {
        UUID tenantId = TenantContextHolder.getTenantId();
        if (tenantId == null) {
            // Em rotas públicas ou threads assíncronas sem tenant.
            // Para não quebrar o Hibernate 6, retornamos null, 
            // mas algumas rotinas exigem que o schema tenha um valor padrão.
            return UUID.fromString("00000000-0000-0000-0000-000000000000"); // Tenant Zero (System) fallback
        }
        return tenantId;
    }

    @Override
    public boolean validateExistingCurrentSessions() {
        return true;
    }
}
