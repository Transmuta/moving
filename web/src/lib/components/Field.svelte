<script lang="ts">
	import type { HTMLInputAttributes } from 'svelte/elements';

	let {
		label,
		name,
		type = 'text',
		value = $bindable(''),
		placeholder = '',
		required = false,
		autocomplete = undefined
	}: {
		label: string;
		name: string;
		type?: HTMLInputAttributes['type'];
		value?: string;
		placeholder?: string;
		required?: boolean;
		autocomplete?: HTMLInputAttributes['autocomplete'];
	} = $props();
</script>

<!-- Campo do protótipo: fld() :1933 (label 12/600 muted) + inputStyle() :1934 (h38, r8, bd). -->
<label class="mb-3 block min-w-0">
	<span class="mb-[5px] block text-[12px] font-semibold text-muted">{label}</span>
	<input
		{name}
		{type}
		{placeholder}
		{required}
		{autocomplete}
		bind:value
		class="h-[38px] w-full rounded-md border border-edge-strong bg-surface px-[11px] text-[13.5px] text-ink placeholder:text-faint"
	/>
</label>
