import type { LayoutServerLoad } from './$types';

// Tema atual (para o ThemeToggle saber o estado inicial). A estampagem sem flash é feita
// no hooks.server.ts; aqui só expomos a escolha ao cliente.
export const load: LayoutServerLoad = ({ cookies }) => {
	const theme = cookies.get('mv-theme');
	return { theme: theme === 'dark' ? 'dark' : theme === 'light' ? 'light' : null };
};
