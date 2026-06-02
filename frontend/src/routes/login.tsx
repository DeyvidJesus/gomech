import { createFileRoute } from '@tanstack/react-router';
import { PublicLayout } from '@/shared/layouts/PublicLayout';
import { LoginForm } from '@/features/iam/components/LoginForm';

export const Route = createFileRoute('/login')({
  component: Login,
});

// eslint-disable-next-line react-refresh/only-export-components
function Login() {
  return (
    <PublicLayout>
      <LoginForm />
    </PublicLayout>
  );
}
