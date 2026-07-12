<script lang="ts">
	// Fontes self-hosted (sem requisição externa): Hanken Grotesk (UI) + Martian Mono (números).
	import '@fontsource-variable/hanken-grotesk';
	import '@fontsource/martian-mono/400.css';
	import '@fontsource/martian-mono/500.css';
	import '@fontsource/martian-mono/600.css';
	// Design system (ADR-010): tokens + tema + base.
	import '$lib/styles/app.css';
	import favicon from '$lib/assets/favicon.svg';

	let { children } = $props();
</script>

<svelte:head>
	<link rel="icon" href={favicon} />
</svelte:head>

{@render children()}
