<script lang="ts">
	import { enhance } from '$app/forms';
	import { page } from '$app/state';
	import { Mail } from '@lucide/svelte';
	import Field from './Field.svelte';
	import Button from './Button.svelte';
	import GoogleIcon from './GoogleIcon.svelte';

	let {
		form = null,
		submitLabel,
		googleLabel,
		googleHref = '/auth/google'
	}: {
		form?: { sent?: boolean; email?: string; error?: string } | null;
		submitLabel: string;
		googleLabel: string;
		googleHref?: string;
	} = $props();

	let submitting = $state(false);
	// "Usar outro e-mail" volta à própria rota (SPA nav com JS, reload sem JS) — limpa `form`.
	const resetHref = $derived(page.url.pathname);
</script>

{#if form?.sent}
	<!-- Estado neutro: não revela se o e-mail existe (ADR-015). -->
	<div class="rounded-lg border border-teal-border bg-teal-subtle p-4 text-[13px] text-ink">
		<div class="mb-2 flex items-center gap-2 font-semibold text-teal-text">
			<Mail size={16} /> Confira seu e-mail
		</div>
		<p class="text-muted">
			Se <strong class="text-ink">{form.email}</strong> tiver uma conta, enviamos um link de acesso.
			Abra o link para entrar — ele expira em breve.
		</p>
	</div>
	<a
		href={resetHref}
		class="mt-4 flex items-center justify-center gap-1.5 text-[12.5px] font-semibold text-muted hover:text-ink"
	>
		Usar outro e-mail
	</a>
{:else}
	<!-- Progressive enhancement: com JS, envia sem reload e mostra o estado inline; sem JS,
	     submit nativo cai na mesma action e o estado vem por SSR. -->
	<form
		method="POST"
		use:enhance={() => {
			submitting = true;
			return async ({ update }) => {
				await update({ reset: false });
				submitting = false;
			};
		}}
	>
		<Field
			label="E-mail"
			name="email"
			type="email"
			value={form?.email ?? ''}
			placeholder="voce@clinica.com.br"
			required
			autocomplete="email"
		/>

		{#if form?.error}
			<p class="mb-3 text-[12.5px] text-danger">{form.error}</p>
		{/if}

		<div class="mt-[6px]">
			<Button type="submit" disabled={submitting}>
				{submitting ? 'Enviando…' : submitLabel}
			</Button>
		</div>
	</form>

	<div class="my-4 flex items-center gap-3 text-[12px] text-faint">
		<span class="h-px flex-1 bg-edge"></span>
		ou
		<span class="h-px flex-1 bg-edge"></span>
	</div>

	<Button variant="ghost" href={googleHref}>
		<GoogleIcon />
		{googleLabel}
	</Button>
{/if}
