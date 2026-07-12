<script lang="ts">
	import { Sun, Moon } from '@lucide/svelte';

	let { initial = null }: { initial?: string | null } = $props();

	// Estado do tema. Sem cookie, deriva do atributo estampado no SSR ou do SO.
	let dark = $state(resolveInitial());

	function resolveInitial(): boolean {
		if (initial) return initial === 'dark';
		if (typeof document !== 'undefined') {
			const attr = document.documentElement.getAttribute('data-theme');
			if (attr) return attr === 'dark';
			return window.matchMedia?.('(prefers-color-scheme: dark)').matches ?? false;
		}
		return false;
	}

	function toggle() {
		dark = !dark;
		const theme = dark ? 'dark' : 'light';
		document.documentElement.setAttribute('data-theme', theme);
		// Persiste 1 ano; o hooks.server.ts estampa no próximo SSR (sem flash).
		document.cookie = `mv-theme=${theme}; path=/; max-age=31536000; samesite=lax`;
	}
</script>

<button
	type="button"
	onclick={toggle}
	aria-label={dark ? 'Ativar tema claro' : 'Ativar tema escuro'}
	class="grid size-9 place-items-center rounded-md border border-edge bg-surface text-muted hover:bg-surface-2"
>
	{#if dark}<Sun size={16} />{:else}<Moon size={16} />{/if}
</button>
