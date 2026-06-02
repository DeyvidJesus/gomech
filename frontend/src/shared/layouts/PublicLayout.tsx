import type { ReactNode } from 'react';
import { Outlet } from '@tanstack/react-router';

export function PublicLayout({ children }: { children: ReactNode }) {
  return (
    <div className="min-h-screen bg-bg-app flex items-center justify-center p-4">
      <div className="w-full max-w-md bg-surface border border-border-divider rounded-lg shadow-sm p-8">
        <div className="flex justify-center mb-8">
          <div className="flex items-center gap-2">
            <div className="w-8 h-8 bg-primary-base rounded-md flex items-center justify-center text-white font-manrope font-bold text-xl">
              G
            </div>
            <span className="font-manrope font-bold text-2xl text-text-primary tracking-tight">GoMech</span>
          </div>
        </div>
        {children || <Outlet />}
      </div>
    </div>
  );
}
