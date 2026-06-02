import { useState } from 'react';
import { useForm as useRHForm } from 'react-hook-form';
import { zodResolver } from '@hookform/resolvers/zod';
import { z } from 'zod';
import { useMutation } from '@tanstack/react-query';
import { Button } from '@/shared/components/ui/Button';
import { Input } from '@/shared/components/ui/Input';
import { authApi } from '../api/auth';
import { useAuthStore } from '../stores/authStore';
import { AlertCircle } from 'lucide-react';

const loginSchema = z.object({
  email: z.string().min(1, 'O e-mail é obrigatório').email('Formato de e-mail inválido'),
  password: z.string().min(1, 'A senha é obrigatória'),
});

type LoginFormValues = z.infer<typeof loginSchema>;

export function LoginForm() {
  const [globalError, setGlobalError] = useState<string | null>(null);
  const setAuth = useAuthStore(state => state.setAuth);

  const {
    register,
    handleSubmit,
    formState: { errors },
  } = useRHForm<LoginFormValues>({
    resolver: zodResolver(loginSchema),
  });

  const mutation = useMutation({
    mutationFn: authApi.login,
    onSuccess: (data) => {
      setGlobalError(null);
      setAuth(data.accessToken);
      alert('Login efetuado com sucesso!');
    },
    onError: (error: unknown) => {
      setGlobalError((error as { message: string }).message || 'Falha ao autenticar. Verifique suas credenciais.');
    },
  });

  const onSubmit = (data: LoginFormValues) => {
    mutation.mutate(data);
  };

  return (
    <form onSubmit={handleSubmit(onSubmit)} className="space-y-6">
      <div className="text-center mb-8">
        <h1 className="text-2xl font-manrope font-bold text-text-primary">Acesse sua conta</h1>
        <p className="text-sm text-text-secondary mt-2">Bem-vindo de volta à plataforma GoMech</p>
      </div>

      {globalError && (
        <div className="bg-danger-red/10 border border-danger-red/20 text-danger-red px-4 py-3 rounded-md flex items-center gap-3 text-sm">
          <AlertCircle className="w-5 h-5 shrink-0" />
          <span>{globalError}</span>
        </div>
      )}

      <div className="space-y-4">
        <Input
          label="E-mail"
          type="email"
          placeholder="admin@oficina.com"
          {...register('email')}
          error={errors.email?.message}
        />

        <Input
          label="Senha"
          type="password"
          placeholder="••••••••"
          {...register('password')}
          error={errors.password?.message}
        />
      </div>

      <Button
        type="submit"
        className="w-full"
        size="lg"
        isLoading={mutation.isPending}
      >
        Entrar na Plataforma
      </Button>
    </form>
  );
}
