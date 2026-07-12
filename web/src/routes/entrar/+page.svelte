<script lang="ts">
	import AuthCard from '$lib/components/AuthCard.svelte';
	import AuthForm from '$lib/components/AuthForm.svelte';
	import type { PageData, ActionData } from './$types';

	let { data, form }: { data: PageData; form: ActionData } = $props();
</script>

<svelte:head><title>Entrar · Movimento</title></svelte:head>

<AuthCard title="Entrar na clínica" subtitle="O sistema que enche a sua agenda." theme={data.theme}>
	<AuthForm {form} submitLabel="Enviar link de acesso" googleLabel="Entrar com Google" />

	{#snippet footer()}
		Novo por aqui? <a href="/criar-conta" class="font-semibold text-teal-text">Criar conta</a>
	{/snippet}
</AuthCard>
