<script lang="ts">
	import type { PageData } from './$types';

	let { data }: { data: PageData } = $props();
</script>

<svelte:head>
	<title>Movimento — andaime</title>
</svelte:head>

<main>
	<h1>Movimento — andaime da Fatia 0</h1>
	<p>Prova do pipeline: browser → BFF (SvelteKit) → API (Phoenix/Ash) → Postgres.</p>

	{#if data.error}
		<p class="err">⚠ {data.error} (API: {data.source})</p>
	{:else}
		<p class="ok">Dados vindos do Postgres via Ash JSON:API (fonte: {data.source}):</p>
		<ul>
			{#each data.pings as ping (ping.id)}
				<li><strong>{ping.message}</strong> <code>{ping.id}</code></li>
			{/each}
		</ul>
		{#if data.pings.length === 0}
			<p>Nenhum ping no banco ainda.</p>
		{/if}
	{/if}
</main>

<style>
	main {
		font-family: system-ui, sans-serif;
		max-width: 42rem;
		margin: 3rem auto;
		padding: 0 1rem;
		line-height: 1.5;
	}
	.ok {
		color: #15803d;
	}
	.err {
		color: #b91c1c;
	}
	code {
		font-size: 0.85em;
		color: #666;
	}
</style>
