import { createRootRoute, Outlet } from '@tanstack/react-router';
import React from 'react';

export const Route = createRootRoute({
  component: () => (
    <React.Fragment>
      <Outlet />
    </React.Fragment>
  ),
});
