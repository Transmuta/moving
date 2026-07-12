<script lang="ts">
	import type { Snippet } from 'svelte';
	import Logo from './Logo.svelte';
	import ThemeToggle from './ThemeToggle.svelte';

	let {
		title,
		subtitle,
		theme = null,
		children,
		footer
	}: {
		title: string;
		subtitle?: string;
		theme?: string | null;
		children: Snippet;
		footer?: Snippet;
	} = $props();
</script>

<!-- Casca da tela de auth (protótipo renderLogin :3473): canvas + barra teal 3px + card
     central com entrada mvScale + toggle de tema no canto. -->
<div
	class="relative grid min-h-dvh w-full place-items-center overflow-hidden bg-canvas px-4 text-ink"
>
	<div class="absolute inset-x-0 top-0 h-[3px] bg-teal"></div>

	<div
		class="w-[380px] max-w-[92vw] animate-scale rounded-lg border border-edge bg-surface px-[30px] py-[34px] shadow-card"
	>
		<div class="mb-6"><Logo /></div>
		<h1 class="mb-1 text-[17px] font-bold text-ink">{title}</h1>
		{#if subtitle}<p class="mb-5 text-[13px] text-muted">{subtitle}</p>{/if}

		{@render children()}

		{#if footer}
			<div class="mt-[14px] text-center text-[12.5px] text-faint">{@render footer()}</div>
		{/if}
	</div>

	<div class="absolute bottom-[18px] right-[18px]">
		<ThemeToggle initial={theme} />
	</div>
</div>
