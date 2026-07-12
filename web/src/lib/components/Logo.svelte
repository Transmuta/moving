<script lang="ts">
	import { Activity } from '@lucide/svelte';
</script>

<!-- Marca do protótipo (renderLogin :3477): quadrado teal + ícone Activity + wordmark 800. -->
<div class="flex items-center gap-[10px]">
	<div class="grid size-9 place-items-center rounded-[9px] bg-teal">
		<Activity size={21} color="#fff" strokeWidth={2.4} />
	</div>
	<span class="text-[20px] font-extrabold tracking-[-0.02em] text-ink">Movimento</span>
</div>
