import axios from 'axios';

const API_URL = import.meta.env.VITE_API_URL || 'http://localhost:8080/api/v1';

export const api = axios.create({
  baseURL: API_URL,
  headers: {
    'Content-Type': 'application/json',
  },
});

export interface LoginRequest {
  email: string;
  password?: string;
}

export interface LoginResponse {
  accessToken: string;
  refreshToken: string;
  expiresIn: number;
}

export const authApi = {
  login: async (data: LoginRequest): Promise<LoginResponse> => {
    if (import.meta.env.DEV && !import.meta.env.VITE_API_URL) {
      return new Promise((resolve, reject) => {
        setTimeout(() => {
          if (data.email === 'admin@oficina.com') {
            resolve({
              accessToken: 'mock-jwt-token-12345',
              refreshToken: 'mock-refresh-token',
              expiresIn: 3600
            });
          } else {
            reject(new Error('Credenciais inválidas'));
          }
        }, 1500);
      });
    }

    const response = await api.post<LoginResponse>('/auth/login', data);
    return response.data;
  }
};
