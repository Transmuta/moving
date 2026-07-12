<script lang="ts">
	import Logo from '$lib/components/Logo.svelte';
	import Button from '$lib/components/Button.svelte';
	import type { PageData } from './$types';

	let { data }: { data: PageData } = $props();
	const me = $derived(data.me);
</script>

<svelte:head><title>Movimento</title></svelte:head>

<main class="mx-auto min-h-dvh max-w-2xl bg-canvas px-6 py-12 text-ink">
	<div class="mb-8 flex items-center justify-between">
		<Logo />
		{#if me}
			<a href="/auth/sign-out" class="text-[13px] font-semibold text-muted hover:text-ink">Sair</a>
		{/if}
	</div>

	{#if me}
		<div class="rounded-lg border border-edge bg-surface p-6 shadow-card">
			<p class="text-[13px] text-muted">Sessão ativa</p>
			<h1 class="mt-1 text-[22px] font-bold">Olá, {me.user.nome}</h1>
			<p class="text-[13px] text-muted">{me.user.email}</p>

			{#if me.active_clinic_id}
				{@const active = me.memberships.find(
					(m: { clinic_id: string }) => m.clinic_id === me.active_clinic_id
				)}
				<div class="mt-4 flex items-center gap-2 text-[13px]">
					<span class="rounded-full bg-teal-subtle px-2.5 py-1 font-semibold text-teal-text">
						{active?.clinic_nome}
					</span>
					<span class="text-muted">papel: <strong class="text-ink">{me.papel}</strong></span>
				</div>
			{:else}
				<p class="mt-4 text-[13px] text-muted">Nenhuma clínica ativa ainda.</p>
			{/if}
		</div>
	{:else}
		<div class="rounded-lg border border-edge bg-surface p-6 text-center shadow-card">
			<h1 class="text-[20px] font-bold">O sistema que enche a sua agenda.</h1>
			<p class="mt-1 mb-5 text-[13px] text-muted">Entre para gerenciar sua clínica.</p>
			<div class="mx-auto max-w-[220px]">
				<Button href="/entrar">Entrar</Button>
			</div>
		</div>
	{/if}

	<!-- Prova do pipeline (browser → BFF → API como movimento_app → Postgres). -->
	<div class="mt-8 text-[12px] text-faint">
		{#if data.error}
			<p class="text-danger">⚠ {data.error}</p>
		{:else}
			<p>Pipeline OK · {data.pings.length} ping(s) via Ash JSON:API</p>
		{/if}
	</div>
</main>
