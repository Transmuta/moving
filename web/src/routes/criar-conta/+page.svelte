<script lang="ts">
	import AuthCard from '$lib/components/AuthCard.svelte';
	import AuthForm from '$lib/components/AuthForm.svelte';
	import type { PageData, ActionData } from './$types';

	let { data, form }: { data: PageData; form: ActionData } = $props();
</script>

<svelte:head><title>Criar conta · Movimento</title></svelte:head>

<AuthCard title="Criar sua conta" subtitle="Comece a encher a sua agenda." theme={data.theme}>
	<AuthForm {form} submitLabel="Criar minha conta" googleLabel="Criar conta com Google" />

	{#snippet footer()}
		Já tem conta? <a href="/entrar" class="font-semibold text-teal-text">Entrar</a>
	{/snippet}
</AuthCard>
