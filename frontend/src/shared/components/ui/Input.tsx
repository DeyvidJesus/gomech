import React from 'react';

export interface InputProps extends React.InputHTMLAttributes<HTMLInputElement> {
  label?: string;
  error?: string;
}

export const Input = React.forwardRef<HTMLInputElement, InputProps>(
  ({ className = '', label, error, ...props }, ref) => {
    return (
      <div className="flex flex-col gap-1 w-full">
        {label && (
          <label className="text-sm font-medium text-text-secondary">
            {label}
          </label>
        )}
        <input
          ref={ref}
          className={`flex h-10 w-full rounded-md border bg-surface px-3 py-2 text-sm text-text-primary file:border-0 file:bg-transparent file:text-sm file:font-medium placeholder:text-text-secondary/50 focus:outline-none focus:ring-2 focus:ring-offset-2 disabled:cursor-not-allowed disabled:opacity-50 ${
            error 
              ? 'border-danger-red focus:ring-danger-red' 
              : 'border-border-divider focus:ring-primary-base focus:border-primary-base'
          } ${className}`}
          {...props}
        />
        {error && (
          <span className="text-xs text-danger-red mt-1 font-medium">{error}</span>
        )}
      </div>
    );
  }
);

Input.displayName = 'Input';
