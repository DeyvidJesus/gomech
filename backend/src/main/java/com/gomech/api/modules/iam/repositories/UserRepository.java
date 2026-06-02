package com.gomech.api.modules.iam.repositories;

import com.gomech.api.modules.iam.models.User;
import org.springframework.data.jpa.repository.EntityGraph;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;

import java.util.Optional;
import java.util.UUID;

@Repository
public interface UserRepository extends JpaRepository<User, UUID> {
    
    // O EntityGraph resolve o problema de N+1 Queries instruindo o Hibernate a usar JOINs para carregar associações lazy em uma única query.
    @EntityGraph(attributePaths = {"userRoles", "userRoles.role", "userRoles.role.permissions", "userRoles.unit"})
    Optional<User> findByEmail(String email);

    boolean existsByEmail(String email);
}
