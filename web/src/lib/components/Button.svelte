<script lang="ts">
	import type { Snippet } from 'svelte';

	let {
		variant = 'primary',
		type = 'button',
		href = undefined,
		disabled = false,
		children
	}: {
		variant?: 'primary' | 'ghost';
		type?: 'button' | 'submit';
		href?: string;
		disabled?: boolean;
		children: Snippet;
	} = $props();

	// Botão primário do protótipo (:3484): quase-preto no claro / quase-branco no escuro.
	const base =
		'flex w-full items-center justify-center gap-2 rounded-md px-4 py-[11px] text-[14px] font-bold transition-colors disabled:cursor-not-allowed disabled:opacity-60';
	const variants = {
		primary: 'bg-primary text-on-primary hover:bg-primary-hover',
		ghost: 'border border-edge-strong bg-surface text-ink hover:bg-surface-2'
	} as const;
</script>

{#if href}
	<a {href} class="{base} {variants[variant]}">{@render children()}</a>
{:else}
	<button {type} {disabled} class="{base} {variants[variant]}">{@render children()}</button>
{/if}
