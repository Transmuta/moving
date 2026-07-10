# Frontend — SvelteKit 2 + Svelte 5

Este documento é o desenho do frontend do Movimento e a resposta ao peso que o
[ADR-006](00-decisoes.md#adr-006--frontend-em-svelte-5-runes--typescript) deposita nele: o
port de React para Svelte 5 é "o maior risco do programa"
([08-roadmap.md §7](08-roadmap.md#7-riscos-do-programa-e-mitigação)). A [seção 9](#9-riscos-do-port-react--svelte-5)
é a catalogação concreta desse risco, com mitigação por item.

A fonte de origem é `interface/Movimento.dc.html` — 3.501 linhas numa única classe
`Component extends DCLogic`, servida por `interface/support.js`, com 79 screenshots em
`interface/screenshots/` como baseline de aceitação ([ADR-001](00-decisoes.md#adr-001--o-protótipo-é-a-especificação-de-origem)).
Toda regra e todo número citados aqui vêm de linha verificada do protótipo.

> **Sobre `01-dominio-ash.md`.** Vários pontos deste documento (o que vira agregado no
> servidor, os nomes de recurso, os campos criptografados) dependem do documento de domínio
> Ash. Na data desta escrita **`docs/01-dominio-ash.md` não existe no repositório**. Onde a
> afirmação depende dele, está marcado *"depende de 01-dominio-ash.md"*, e o número/rota vem
> do contrato ([09-contrato-api.md](09-contrato-api.md)) ou da arquitetura
> ([04-arquitetura.md](04-arquitetura.md)), que já existem.

---

## 1. Stack

**Base travada pelo ADR-006:** SvelteKit 2.x, Svelte 5 com runes, TypeScript estrito,
`adapter-node`. O serviço web é BFF, nunca cliente de banco
([ADR-005](00-decisoes.md#adr-005--sveltekit-como-bff-nunca-como-cliente-de-banco)).

### 1.1 CSS — Tailwind v4, em duas camadas

**Travado pelo [ADR-010](00-decisoes.md#adr-010--css-utilitário-com-tailwind-v4).** Um único
`src/lib/styles/app.css` com `@import "tailwindcss"`, organizado em duas camadas
([seção 4](#4-design-system)):

1. **Proveniência** — as custom properties `--mv-*`/`--cat-*` com os hex **verbatim** do
   protótipo, trocadas por `[data-theme]`.
2. **Utilitários** — um bloco `@theme inline` que mapeia aquelas variáveis para os namespaces
   do Tailwind, gerando `bg-surface`, `text-muted`, `border-edge`, etc.

> **Por que não CSS vanilla.** Era a recomendação anterior deste documento, e o argumento
> merece ser preservado em vez de apagado: o protótipo não tem folha de estilo nem uma única
> classe — são **1.205 objetos de estilo inline** (`style=${{…}}`, contagem verificada) e
> **zero** `class=`, com toda cor derivada de um switch `dark` via `theme()`
> ([`:301`](../interface/Movimento.dc.html#L301)) e `tint(hex,a)`
> ([`:314`](../interface/Movimento.dc.html#L314)). Portar para utilitários pareceria "dois
> trabalhos": traduzir cada objeto **e** reconstruir a paleta como config.
>
> Esse argumento mira o **v3**, onde a paleta morava num `tailwind.config.js` divorciado das
> custom properties que o `data-theme` exige. No **v4 a paleta é CSS**: `@theme inline` emite
> as variáveis *e* deriva os utilitários delas, de uma fonte só — a duplicação some. O ADR-010
> registra a reversão e o que ela custa.

O que o protótipo tem de forte continua mapeando como antes — a paleta Okabe-Ito e o par
claro/escuro são custom properties na camada 1, e é **de lá** que os utilitários saem. O ganho
concreto é o `tint()`: 58 chamadas que viravam `color-mix` na proposta vanilla agora são o
modificador de opacidade nativo (`bg-danger/10`).

**Duas coisas não viram utilitário, e isso é estrutural, não preguiça:**

| O quê | Por que não | Como fica |
|---|---|---|
| Cor categórica de profissional/paciente | `cat[]` é indexado por um `ci` de **runtime** ([`:315`](../interface/Movimento.dc.html#L315)–[`:316`](../interface/Movimento.dc.html#L316)); o Tailwind gera classe em **build**. | Custom property setada inline (`style="--appt: var(--cat-3)"`) + `bg-(--appt)`. Ver [§4.5](#45-cores-categóricas-o-limite-do-utilitário). |
| Densidade da grade (`--mv-ppm`) | É aritmética dentro de `calc()` ([`:1228`](../interface/Movimento.dc.html#L1228)), não um valor de escala. | Custom property pura, trocada por `[data-density]`. |

### 1.2 Restante da stack

| Preocupação | Recomendação | Porquê curto |
|---|---|---|
| Testes de unidade/domínio | **Vitest** | `layoutAppts` e os espelhos de validação são funções TS puras; [07 §7.1](07-estrategia-de-testes.md#71-domínio-puro-no-cliente-vitest) já fixou Vitest. |
| e2e / drag / teclado | **Playwright** | Drag por `PointerEvent` e a alternativa por teclado; [07 §7.2](07-estrategia-de-testes.md#72-e2e-com-playwright--drag-and-drop-e-a-alternativa-por-teclado). |
| Regressão visual | **Playwright screenshots, baseline nativo Svelte** | Os 79 PNGs são gabarito de tradução, não assert de pixel; [07 §7.3](07-estrategia-de-testes.md#73-regressão-visual-contra-os-79-screenshots--avaliação-honesta). |
| Lint / format | **ESLint (flat config) + `eslint-plugin-svelte` + Prettier + `prettier-plugin-svelte` + `prettier-plugin-tailwindcss`** | Padrão do ecossistema SvelteKit. `svelte-check` no CI para os tipos dos componentes. O plugin do Tailwind normaliza a ordem das classes ([ADR-010](00-decisoes.md#adr-010--css-utilitário-com-tailwind-v4)) — sem ele, a ordem vira ruído de diff. |
| Build do CSS | **`@tailwindcss/vite`** | Plugin de Vite do Tailwind v4; dispensa `postcss.config.js` e `tailwind.config.js` — a config é o próprio `app.css` ([§4](#4-design-system)). |
| Formulários | **Form actions nativas do SvelteKit + validação progressiva**; avaliar `sveltekit-superforms` na fatia de prontuário | O protótipo faz máscaras e validação client-side (`maskCPF` [`:1957`](../interface/Movimento.dc.html#L1957), `lookupCep` [`:1939`](../interface/Movimento.dc.html#L1939)); superforms só se o custo de boilerplate justificar. |

```
// NAO-VERIFICADO: confirmar contra a doc ao scaffoldar
// Versões exatas de SvelteKit 2 / Svelte 5 / adapter-node, e a API de
// eslint-plugin-svelte para flat config, confirmar no momento do scaffold.
// Idem para o Tailwind v4: a sintaxe de @theme inline, @custom-variant,
// @source inline() e do modificador bg-(--var) é citada aqui de memória e
// NAO foi executada contra um build real — não há package.json no repo.
```

---

## 2. Dados no cliente — fonte de verdade e invalidação

A regra-mãe vem da arquitetura: **o servidor é autoridade; o cliente espelha**
([04 §10](04-arquitetura.md#10-fronteira-espelho-do-cliente-vs-autoridade-do-servidor)). Três
canais alimentam a tela e precisam conviver sem se contradizer:

1. **`load` server-side (BFF).** `+page.server.ts` chama a API do Phoenix repassando o
   cookie de sessão ([09 §8](09-contrato-api.md#8-autenticação)); é o SSR e o estado inicial.
2. **Form actions.** Mutação com `<form>` que degrada sem JS; a action chama a API e devolve
   o recurso ou o erro.
3. **Phoenix Channels.** WebSocket direto do browser contra o Phoenix (ADR-004), fora do
   BFF, autenticado pelo token efêmero que o `load` entregou
   ([09 §8](09-contrato-api.md#8-autenticação): `GET /realtime/token`).

### 2.1 Onde vive a fonte de verdade

A fonte de verdade **é o servidor**. No cliente há um **espelho** — o estado que o `load`
trouxe, guardado num store de runes, patcheado pelos eventos de Channel. Esse espelho nunca
decide regra de negócio; ele exibe e dá feedback otimista. Toda decisão autoritativa
(não-sobreposição, hold de vaga, versão, débito de pacote, tenant, policy) só o servidor toma
([04 §10](04-arquitetura.md#10-fronteira-espelho-do-cliente-vs-autoridade-do-servidor)).

O que **pode** ser espelhado, verbatim de [04 §10](04-arquitetura.md#10-fronteira-espelho-do-cliente-vs-autoridade-do-servidor):
`layoutAppts` ([`:1576`](../interface/Movimento.dc.html#L1576)), sombreamento de
disponibilidade via `dayPeriods` ([`:854`](../interface/Movimento.dc.html#L854)), prévia da
série via `computeSerie` ([`:1081`](../interface/Movimento.dc.html#L1081)) e a dica de
sobreposição via `checkConflict` ([`:834`](../interface/Movimento.dc.html#L834)) no dia já
carregado. Onde há espelho, a função pura TS é validada por **contrato de teste
compartilhado** com a Elixir, nunca por cópia
([04 §10](04-arquitetura.md#10-fronteira-espelho-do-cliente-vs-autoridade-do-servidor);
[07 §7.1](07-estrategia-de-testes.md#71-domínio-puro-no-cliente-vitest)).

### 2.2 Como o socket invalida o que o `load` trouxe

Os eventos são semânticos, com o recurso já serializado — não "invalide tudo"
([09 §7.2](09-contrato-api.md#72-eventos-da-agenda);
[04 §6.2](04-arquitetura.md#62-payload)). A política é **patch otimista no store de runes**,
com `invalidate()` do SvelteKit como fallback:

- **Patch (caminho normal).** O evento chega com o recurso e a `version`. O cliente aplica o
  patch mutando o proxy `$state` do store — troca só o agendamento afetado, o que dispara os
  `$derived` que dependem dele ([seção 7](#7-derived-e-performance)). Se o evento é para um
  recurso que o cliente não tem no recorte visível, **ignora**
  ([09 §7.2](09-contrato-api.md#72-eventos-da-agenda)).
- **`invalidate()` (fallback).** Quando o patch não é aplicável — payload leve da visão mês
  (`{day, change: :count}`, [04 §6.1](04-arquitetura.md#61-granularidade-de-tópico--e-por-que-ela-muda-com-a-visão)),
  ou reconexão — o cliente chama `invalidate()` do recurso e o `load` re-busca do BFF. É
  também o contrato de reconexão: ao (re)entrar num tópico de agenda, faz `GET /appointments`
  do dia para ressincronizar ([09 §7.5](09-contrato-api.md#75-contrato-de-reconexão)).

```svelte
<!-- NAO-VERIFICADO: confirmar API de $state/$effect (Svelte 5) e Socket/Channel
     do pacote npm `phoenix` ao scaffoldar -->
<script lang="ts">
  import { Socket } from "phoenix";
  import { invalidate } from "$app/navigation";
  import { agenda } from "$lib/stores/agenda.svelte";      // store de runes ($state)

  let { data } = $props();                                  // vem do +page.server.ts (load)
  agenda.hydrate(data.appointments);                        // espelho inicial

  $effect(() => {
    const socket = new Socket("/socket", { params: { token: data.realtimeToken } });
    socket.connect();
    const ch = socket.channel(`clinic:${data.clinicId}:agenda:${data.date}`, {});
    ch.on("appointment_rescheduled", (p) => agenda.patch(p.appointment)); // patch otimista
    ch.on("appointment_scheduled",  (p) => agenda.patch(p.appointment));
    ch.on("appointment_status_changed", (p) => agenda.patchStatus(p.appointment, p.package_debit));
    ch.join()
      .receive("ok", () => invalidate(`agenda:${data.date}`))  // ressincroniza no join
      .receive("error", () => { /* degrada: mostra “tempo real indisponível” */ });
    return () => { ch.leave(); socket.disconnect(); };        // cleanup obrigatório
  });
</script>
```

Os nomes de evento e os campos de payload acima são **exatamente** os do contrato
([09 §7.2](09-contrato-api.md#72-eventos-da-agenda) e [§7.3](09-contrato-api.md#73-eventos-da-fila)):
`appointment_scheduled`, `appointment_rescheduled`, `appointment_status_changed`
(com `package_debit?`), `appointment_canceled`, `participant_added/removed`;
`waitlist_entry_added/removed`, `slot_held`, `slot_released`. Os tópicos são
`clinic:<id>:agenda:<YYYY-MM-DD>`, `clinic:<id>:agenda:month:<YYYY-MM>`,
`clinic:<id>:waitlist`, `clinic:<id>:presence`
([04 §6.1](04-arquitetura.md#61-granularidade-de-tópico--e-por-que-ela-muda-com-a-visão)).
Não invente outros.

> **Nota de reconciliação.** [09 §7.1](09-contrato-api.md#71-tópicos) lista **três** tópicos e
> diz "verbatim de 04 §4"; a numeração atual de [04-arquitetura.md](04-arquitetura.md) põe
> Tempo Real em **§6**, e [04 §6.1](04-arquitetura.md#61-granularidade-de-tópico--e-por-que-ela-muda-com-a-visão)
> define **quatro** tópicos, incluindo o de resolução mensal `agenda:month:<YYYY-MM>`. O
> cliente deve seguir a versão de quatro tópicos de [04 §6.1](04-arquitetura.md#61-granularidade-de-tópico--e-por-que-ela-muda-com-a-visão):
> visão dia assina 1 tópico de dia; semana assina os 5–7 dias; mês assina 1 tópico de mês e
> trata o payload leve com `invalidate()`.

### 2.3 Cuidados de SSR e hidratação

O protótipo faz várias coisas que quebram ou divergem sob SSR. Cada uma vira uma regra:

- **`toLocaleDateString('pt-BR', …)`** aparece na régua de datas e no cabeçalho
  ([`:1740`](../interface/Movimento.dc.html#L1740), [`:1538`](../interface/Movimento.dc.html#L1538)).
  Formatação de data **depende de locale e timezone do runtime**; no SSR é o do servidor Node,
  no cliente é o do browser — divergem e causam *hydration mismatch*. **Regra:** formatar
  datas de exibição de forma determinística (locale e timezone fixados, o timezone canônico
  da clínica por [ADR-009](00-decisoes.md#adr-009--relógio-injetável-timezone-por-clínica)),
  não deixar ao acaso do runtime.
- **`new Date(date+'T00:00')`** sem offset, usado à larga (ex.: `navDay`
  [`:1183`](../interface/Movimento.dc.html#L1183), `vagaLabel`
  [`:2593`](../interface/Movimento.dc.html#L2593)) e **`new Date(2026,5,30)`** cravado em
  `idadeDe` ([`:317`](../interface/Movimento.dc.html#L317)). `Date` sem timezone é interpretado
  no fuso local do runtime — mesma armadilha SSR/cliente. **Regra:** datas viajam ISO-8601 com
  offset explícito ([ADR-009](00-decisoes.md#adr-009--relógio-injetável-timezone-por-clínica));
  o cliente nunca deriva "hoje" do relógio do browser para **decisão**, só para exibição.
- **`URL.createObjectURL(f)`** em `addAnexos` ([`:957`](../interface/Movimento.dc.html#L957)) é
  API só-de-browser e não pode rodar no SSR. Além disso [ADR-007](00-decisoes.md#adr-007--dado-de-saúde-é-tratado-como-categoria-especial-da-lgpd)
  o proíbe em produção: anexos vão por URL assinada de vida curta
  ([09 §3.9](09-contrato-api.md#39-anexos)). **Regra:** upload/preview de anexo é estritamente
  client-only (`{#if browser}` / dentro de `$effect`), e a URL vem assinada da API.
- **`fetch('https://viacep.com.br/ws/'+cep+'/json/')`** em `lookupCep`
  ([`:1945`](../interface/Movimento.dc.html#L1945)) é uma chamada a **terceiro** direto do
  cliente. Sob SSR falharia/vazaria; e há corrida de resposta que o protótipo já trata
  guardando `this._cepReq` ([`:1942`](../interface/Movimento.dc.html#L1942)). **Regra:**
  ViaCEP é lookup client-only, disparado por evento, com guarda de request stale — e é
  candidato a **proxiar pelo BFF** para não expor origem e poder cachear.
- **`lucide` via UMD global** ([`:14`](../interface/Movimento.dc.html#L14)) com ícone por
  **nome dinâmico** (`<${Icon} name=${tp.icon}/>`, ex. [`:1691`](../interface/Movimento.dc.html#L1691)):
  ver [seção 9](#9-riscos-do-port-react--svelte-5), item ícones — o pacote tree-shakeável do
  Svelte exige import estático, incompatível com nome em runtime sem um mapa.

---

## 3. Árvore de rotas

### 3.1 Multi-tenant: `/c/[clinicSlug]/…`, tenant resolvido pela sessão

**Recomendação: usar `/c/[clinicSlug]/…` na URL, mas resolver o tenant pela sessão, nunca
pelo slug.** Parece contradição com
[04 §4](04-arquitetura.md#4-contrato-de-api) ("o tenant nunca vem do cliente"); não é. A
distinção:

- O **slug é navegação**, não autorização — como o `id` numa URL de recurso. Ele dá URLs
  compartilháveis/marcáveis e permite que um usuário com acesso a mais de uma clínica troque
  de unidade pela barra de endereço.
- A **autoridade é a sessão.** O `+layout.server.ts` de `/c/[clinicSlug]` resolve o tenant da
  sessão (o `clinic_id` que a API confirma em `GET /auth/me`,
  [09 §8](09-contrato-api.md#8-autenticação)) e **verifica** que o `clinicSlug` da URL pertence
  às clínicas do usuário. Se não pertencer → `404` (a mesma política de não confirmar
  existência entre tenants de [09 §3](09-contrato-api.md#3-catálogo-de-endpoints)). O slug
  jamais entra numa chamada de API como parâmetro de tenant; ele só é validado contra o que a
  sessão já autoriza.

Isso concilia o requisito de segurança (tenant da sessão) com a ergonomia de SaaS
multi-clínica ([ADR-003](00-decisoes.md#adr-003--saas-multi-clínica-desde-o-primeiro-commit)):
o slug é conveniência de UX; a policy do servidor é a lei.

### 3.2 As rotas

As telas de topo do protótipo são seis, verificadas no dispatch de `screen`
([`:1311`](../interface/Movimento.dc.html#L1311)–[`:1316`](../interface/Movimento.dc.html#L1316)):
`agenda`, `pacientes`, `fila`, `profissionais`, `config`, `relatorios`. A agenda tem três
vistas, verificadas em ([`:1559`](../interface/Movimento.dc.html#L1559)): `dia`, `semana`,
`mes`.

| Rota | `load` busca | Actions | Client-only |
|---|---|---|---|
| `/login` | — | `default` → `POST /auth/sign_in` | — |
| `/c` | `GET /auth/me` → lista de clínicas do usuário | escolher clínica → redirect a `/c/[slug]/agenda` | — |
| `/convite/[token]` | valida token | `default` → aceite de membro ([09 §3.7](09-contrato-api.md#37-membros-equipe--acessos)) | — |
| `/c/[slug]` (layout) | tenant da sessão + `realtimeToken` + perfil/permissões de UI | — | conexão do `Socket` |
| `/c/[slug]/agenda/[date]?view=dia\|semana\|mes` | `GET /appointments` por intervalo da vista (§9.3), `include` de paciente/tipo/pacote; `GET /availability` do recorte | `POST /appointments` (:schedule) | grade absoluta, `layoutAppts`, drag/pan, linha do agora |
| `/c/[slug]/pacientes` | `GET /patients?sort=nome` | — | busca/scroll-spy do formulário |
| `/c/[slug]/pacientes/novo` · `/[id]/editar` | `GET /patients/:id` (edição) | `default` → `POST`/`PATCH /patients` | máscaras, ViaCEP, scroll-spy |
| `/c/[slug]/pacientes/[id]` | `GET /patients/:id` `include` pacotes/anexos (metadados) | transições de pacote ([09 §3.4](09-contrato-api.md#34-pacotes-de-sessões)) | pop-over de gerir pacote; upload por URL assinada |
| `/c/[slug]/fila` | `GET /waitlist` | `POST /waitlist` (:enqueue), `.../offer`, `.../convert` | célula de disponibilidade; `filaVagas` **é servidor** ([§6](#6-os-cinco-portes-difíceis)) |
| `/c/[slug]/profissionais` · `/[id]/editar` | `GET /professionals` | `POST`/`PATCH /professionals`; `PATCH /clinic-hours` (com confirmação de `futureConflicts`, [09 §3.5](09-contrato-api.md#35-profissionais-tipos-horário-feriados)) | grade de disponibilidade semanal, scroll-spy |
| `/c/[slug]/config` | `GET /clinic-hours`, `/holidays`, `/appointment-types` | `PATCH`/`POST`/`DELETE` respectivos | toggles de operação, cinco abas (`cfg*`) |
| `/c/[slug]/relatorios` | `GET /reports/summary` (agregado servidor, [09 §3.8](09-contrato-api.md#38-relatórios)) | — | gráficos |

O `date` na rota da agenda substitui `state.date`; a vista é query param para não multiplicar
rotas. Navegar de dia troca a rota (e o tópico de Channel), não muta estado global — é o que
elimina o `_navLock` de navegação do protótipo.

---

## 4. Design system

Derivado **verbatim** de `theme()` ([`:301`–`:313`](../interface/Movimento.dc.html#L301)),
`tint()` ([`:314`](../interface/Movimento.dc.html#L314)), a paleta `cat`
([`:51`](../interface/Movimento.dc.html#L51)), as fontes
([`:13`](../interface/Movimento.dc.html#L13)), e a densidade `ppm()`
([`:1228`](../interface/Movimento.dc.html#L1228)).

A forma é a do [ADR-010](00-decisoes.md#adr-010--css-utilitário-com-tailwind-v4): **camada 1**
guarda o hex de origem numa custom property e é a que troca com o tema; **camada 2** (`@theme
inline`) só dá nome de utilitário ao que a camada 1 já definiu. Nenhum hex aparece duas vezes,
e todo hex tem linha de proveniência no protótipo.

### 4.1 `src/lib/styles/app.css`

```css
/* NAO-VERIFICADO: sintaxe do Tailwind v4 (@theme inline, @custom-variant,
   @keyframes em @theme) citada de memória — confirmar ao scaffoldar.
   Derivado de Movimento.dc.html theme() :301-313, cat :51, ppm() :1228 */
@import "tailwindcss";

/* Dark por atributo, não por classe nem media pura: o SSR estampa data-theme
   no <html> e não há flash (§4.4). */
@custom-variant dark (&:where([data-theme="dark"], [data-theme="dark"] *));

/* ══ CAMADA 1 — proveniência. Hex verbatim do protótipo. ══════════════════ */

:root {
  /* Tipografia — fontes carregadas em :13 (Hanken Grotesk 400/500/600/700/800,
     Martian Mono 400/500/600). Martian Mono é o mono de horários/números. */
  --mv-font-sans: "Hanken Grotesk", system-ui, sans-serif;
  --mv-font-mono: "Martian Mono", ui-monospace, monospace;

  /* Raios (verificados em uso: 8px campos, 999px pill do switch :1182, 14px cards) */
  --mv-radius-sm: 6px;
  --mv-radius: 8px;
  --mv-radius-lg: 14px;
  --mv-radius-pill: 999px;

  /* Sombra (:1683 — sombra sutil só no claro) */
  --mv-shadow-1: 0 1px 1px rgba(20, 24, 30, .03);
  --mv-shadow-pop: 0 8px 24px rgba(8, 10, 12, .18);

  /* Densidade — px por minuto da grade. compacto/confortável/espaçoso (:1228).
     NÃO entra no @theme: é aritmética de calc(), não valor de escala (§1.1). */
  --mv-ppm: 1.05;              /* confortável (default) */

  /* Paleta categórica Okabe-Ito (cat :51) — segura para daltonismo.
     profColor = cat[(ci-1)%7] :315 ; patientColor desloca +7 :316 — ver §4.5 */
  --cat-1: #E69F00;  /* laranja      */
  --cat-2: #0072B2;  /* azul         */
  --cat-3: #009E73;  /* verde        */
  --cat-4: #D55E00;  /* vermelho-tijolo */
  --cat-5: #CC79A7;  /* rosa         */
  --cat-6: #56B4E9;  /* azul-céu     */
  --cat-7: #7A52CC;  /* roxo         */

  /* Semânticas compartilhadas claro/escuro (:311) */
  --mv-success: #2DA160;
  --mv-warning: #F5A623;
  --mv-danger:  #E5484D;
  --mv-info:    #2B7FFF;

  /* Teal — cor de marca / foco. solid/hover iguais nos dois temas (:303) */
  --mv-teal-solid: #0FB5A6;
  --mv-teal-hover: #0BA294;
}

[data-density="compacto"]   { --mv-ppm: 0.82; }
[data-density="confortavel"]{ --mv-ppm: 1.05; }
[data-density="espacoso"]   { --mv-ppm: 1.40; }

/* ---- Tema claro (theme() com d=false) ---- */
:root, :root[data-theme="light"] {
  --mv-canvas:   #FBFCFD;
  --mv-surface:  #FFFFFF;
  --mv-surface2: #F6F8F9;
  --mv-rail:     #16181C;
  --mv-rail-item:#26292F;
  --mv-bs: #E4E7EB;           /* borda sutil  */
  --mv-bd: #CDD3D9;           /* borda densa  */
  --mv-text:  #161A1E;
  --mv-muted: #5C6670;
  --mv-faint: #8A929B;        /* atenção: contraste — ver 8.4 */
  --mv-primary:      #16181C;
  --mv-primary-hover:#2A2E34;
  --mv-on-primary:   #FFFFFF;
  --mv-teal-text:   #0A7E73;
  --mv-teal-subtle: #E5F7F4;
  --mv-teal-border: #7FDACD;
  --mv-on-warning:  #8a5d00;  /* órfão de :768, promovido a token — §4.3 */
}

/* ---- Tema escuro (theme() com d=true) ---- */
:root[data-theme="dark"] {
  --mv-canvas:   #0C0D0E;
  --mv-surface:  #16181C;
  --mv-surface2: #1C1F24;
  --mv-rail:     #08090A;
  --mv-rail-item:#1A1D22;
  --mv-bs: #24282E;
  --mv-bd: #313640;
  --mv-text:  #ECEEF0;
  --mv-muted: #9AA3AC;
  --mv-faint: #6B747D;
  --mv-primary:      #ECEEF0;
  --mv-primary-hover:#FFFFFF;
  --mv-on-primary:   #16181C;
  --mv-teal-text:   #3FD6C7;
  --mv-teal-subtle: rgba(15, 181, 166, .16);
  --mv-teal-border: rgba(127, 218, 205, .45);
  --mv-on-warning:  #F5D08A;  /* NAO-VERIFICADO: âmbar claro a definir — §4.3 */
}

@media (prefers-color-scheme: dark) {
  :root:not([data-theme]) {   /* respeita SO quando não há escolha explícita */
    --mv-canvas: #0C0D0E; --mv-surface: #16181C; --mv-surface2: #1C1F24;
    --mv-rail: #08090A; --mv-rail-item: #1A1D22; --mv-bs: #24282E; --mv-bd: #313640;
    --mv-text: #ECEEF0; --mv-muted: #9AA3AC; --mv-faint: #6B747D;
    --mv-primary: #ECEEF0; --mv-primary-hover: #FFFFFF; --mv-on-primary: #16181C;
    --mv-teal-text: #3FD6C7; --mv-teal-subtle: rgba(15,181,166,.16);
    --mv-teal-border: rgba(127,218,205,.45); --mv-on-warning: #F5D08A;
  }
}

/* ══ CAMADA 2 — utilitários. `inline` faz o utilitário referenciar var(--mv-…) ══
   em vez de copiar o valor; sem isso a troca por data-theme não funcionaria.   */

@theme inline {
  --font-sans: var(--mv-font-sans);
  --font-mono: var(--mv-font-mono);

  /* sobrescreve a escala de raio do Tailwind pela do protótipo, de propósito */
  --radius-sm:   var(--mv-radius-sm);
  --radius-md:   var(--mv-radius);
  --radius-lg:   var(--mv-radius-lg);
  --radius-full: var(--mv-radius-pill);

  --shadow-sm:  var(--mv-shadow-1);
  --shadow-pop: var(--mv-shadow-pop);

  /* superfícies → bg-canvas, bg-surface, bg-surface-2, bg-rail, bg-rail-item */
  --color-canvas:    var(--mv-canvas);
  --color-surface:   var(--mv-surface);
  --color-surface-2: var(--mv-surface2);
  --color-rail:      var(--mv-rail);
  --color-rail-item: var(--mv-rail-item);

  /* bordas → border-edge / border-edge-strong  (bs = sutil, bd = densa) */
  --color-edge:        var(--mv-bs);
  --color-edge-strong: var(--mv-bd);

  /* texto → text-ink / text-muted / text-faint  (`ink` evita o feio `text-text`) */
  --color-ink:   var(--mv-text);
  --color-muted: var(--mv-muted);
  --color-faint: var(--mv-faint);

  --color-primary:       var(--mv-primary);
  --color-primary-hover: var(--mv-primary-hover);
  --color-on-primary:    var(--mv-on-primary);

  --color-teal:        var(--mv-teal-solid);
  --color-teal-hover:  var(--mv-teal-hover);
  --color-teal-text:   var(--mv-teal-text);
  --color-teal-subtle: var(--mv-teal-subtle);
  --color-teal-border: var(--mv-teal-border);

  --color-success:    var(--mv-success);
  --color-warning:    var(--mv-warning);
  --color-danger:     var(--mv-danger);
  --color-info:       var(--mv-info);
  --color-on-warning: var(--mv-on-warning);

  --color-cat-1: var(--cat-1);
  --color-cat-2: var(--cat-2);
  --color-cat-3: var(--cat-3);
  --color-cat-4: var(--cat-4);
  --color-cat-5: var(--cat-5);
  --color-cat-6: var(--cat-6);
  --color-cat-7: var(--cat-7);
}

/* As 7 animações do <style> do protótipo viram tokens --animate-* → animate-* */
@theme {
  --animate-pulse-dot: mvPulse 1.6s ease-in-out infinite;
  --animate-pulse-row: mvPulseRow 1.6s ease-in-out infinite;
  --animate-fade:      mvFade .18s ease-out;
  --animate-scale:     mvScale .14s ease-out;
  --animate-slide:     mvSlide .22s ease-out;
  --animate-slide-l:   mvSlideL .22s ease-out;
  --animate-ring:      mvRing 1.4s ease-out infinite;

  @keyframes mvPulse    { 0%,100%{opacity:1;transform:scale(1)} 50%{opacity:.3;transform:scale(.62)} }
  @keyframes mvPulseRow { 0%,100%{opacity:1} 50%{opacity:.45} }
  @keyframes mvFade     { from{opacity:0;transform:translateY(8px)} to{opacity:1;transform:none} }
  @keyframes mvScale    { from{opacity:0;transform:scale(.975)} to{opacity:1;transform:none} }
  @keyframes mvSlide    { from{transform:translateX(100%)} to{transform:translateX(0)} }
  @keyframes mvSlideL   { from{transform:translateX(-100%)} to{transform:translateX(0)} }
  @keyframes mvRing     { 0%{transform:scale(.9);opacity:.5} 70%{opacity:0} 100%{transform:scale(2.3);opacity:0} }
}

/* O que o preflight do Tailwind não cobre, do <style> do protótipo.
   `#dc-root` e `margin:0` ficam de fora: são do runtime do protótipo / do preflight. */
@layer base {
  html, body { overscroll-behavior-y: none; }

  ::-webkit-scrollbar            { width: 10px; height: 10px; }
  ::-webkit-scrollbar-thumb      { background: rgba(140,150,160,.32); border-radius: 8px;
                                   border: 2px solid transparent; background-clip: padding-box; }
  ::-webkit-scrollbar-thumb:hover{ background: rgba(140,150,160,.5); }
  ::-webkit-scrollbar-track      { background: transparent; }

  :where(input, select, button, textarea, [tabindex]):focus-visible {
    outline: 2px solid var(--mv-teal-solid);   /* era o literal #0FB5A6 */
    outline-offset: 1px;
  }

  @media (prefers-reduced-motion: reduce) {
    *, *::before, *::after {
      animation-duration: .001ms !important;
      transition-duration: .001ms !important;
    }
  }
}
```

### 4.2 `tint(hex, a)` → modificador de opacidade

O protótipo escurece/clareia cores compondo alpha sobre o fundo: `tint(hex,a)` retorna
`rgba(r,g,b,a)` ([`:314`](../interface/Movimento.dc.html#L314)), usado em dezenas de fundos
(ex. `this.tint(c.danger,.1)` [`:1996`](../interface/Movimento.dc.html#L1996)). São **58
chamadas** — o padrão mais repetido do protótipo. No Tailwind v4 isso é o modificador de
opacidade, sem `color-mix` à mão:

```html
<!-- tint(danger,.10) --> <span class="bg-danger/10 text-danger">…</span>
<!-- tint(warning,.14) --> <span class="bg-warning/14 text-on-warning">…</span>
```

Atenção a uma sutileza do protótipo: **o alpha muda com o tema** (ex.
`this.tint(m.base,c.d?0.18:0.1)` no bloco da agenda,
[`:1674`](../interface/Movimento.dc.html#L1674)). Isso vira um par de utilitários, não um
valor único — e é onde a variante `dark:` paga por si:

```html
<div class="bg-(--appt)/10 dark:bg-(--appt)/18">…</div>
```

### 4.3 O hex órfão de *warning* fora de `theme()`

Há **uma** cor hardcoded fora da paleta: `color:'#8a5d00'` — um âmbar-escuro usado como cor de
**texto** dentro de uma faixa de aviso (`tint(warning,.12)`). Aparece em
[`:768`](../interface/Movimento.dc.html#L768), na faixa "Este agendamento foi remarcado…" do
modal de mudança em massa / remarcação de pacote (o ramo `fromDrag`). É um valor solto porque
`theme()` não expõe um "texto sobre warning" — a paleta tem `warning` de fundo mas não o
*on-warning* legível.

**Resolvido na [§4.1](#41-srclibstylesappcss):** promovido a `--mv-on-warning` e exposto como
`text-on-warning`. O claro é o `#8a5d00` verificado; **o escuro está marcado NAO-VERIFICADO** —
o `#F5D08A` é um chute de âmbar claro e precisa passar por contraste contra
`bg-warning/14` antes de valer ([§8.4](#8-acessibilidade)). O literal sai do markup.

### 4.4 Dark mode via `data-theme`, sem flash

O protótipo alterna pelo booleano `state.dark` recomputando `theme()` — não persiste e não
tem SSR, então o problema de *flash of wrong theme* nem existe lá. Em SvelteKit com SSR, ele
existe e se resolve com **cookie + `+layout.server.ts`**:

```ts
// NAO-VERIFICADO: confirmar API de cookies/locals do SvelteKit ao scaffoldar
// src/routes/+layout.server.ts
export const load = ({ cookies }) => {
  const theme = cookies.get("mv-theme") ?? "light";      // "light" | "dark"
  const density = cookies.get("mv-density") ?? "confortavel";
  return { theme, density };
};
```

O `data-theme` e o `data-density` são **estampados no `<html>` no HTML servido** (via
`%sveltekit.html%` com atributo, ou `handle` no `hooks.server.ts`), de modo que a primeira
pintura já tem o tema certo — sem flash. A troca em runtime muta `document.documentElement`
`data-theme` e grava o cookie. Isso também corrige o `<html>` sem `lang`
([seção 8.5](#8-acessibilidade)): o mesmo ponto que estampa `data-theme` estampa
`lang="pt-BR"`.

### 4.5 Cores categóricas: o limite do utilitário

A cor de um profissional ou paciente **não é conhecida em build**. `profColor` indexa `cat[]`
por `(ci-1)%7` ([`:315`](../interface/Movimento.dc.html#L315)) e `patientColor` desloca o
mesmo índice ([`:316`](../interface/Movimento.dc.html#L316)) — o `ci` vem do registro, do
banco. O Tailwind gera classe varrendo o **texto do código-fonte**; uma classe interpolada
como `bg-cat-{n}` nunca é gerada, porque esse literal não existe em lugar nenhum.

A saída não é lutar contra isso: é passar a cor como custom property inline e deixar o
utilitário consumi-la. O `ci → --cat-n` fica num helper tipado, único ponto que conhece o `%7`:

```svelte
<!-- NAO-VERIFICADO: sintaxe bg-(--var) do Tailwind v4, confirmar ao scaffoldar -->
<script lang="ts">
  import type { Appt, Prof } from "$lib/api/types";
  let { appt, prof }: { appt: Appt; prof: Prof } = $props();

  // espelha profColor :315 — o único lugar que sabe do %7
  const catVar = (ci: number) => `var(--cat-${((ci - 1) % 7) + 1})`;
</script>

<div
  class="border-l-2 bg-(--appt)/10 border-(--appt) dark:bg-(--appt)/18"
  style="--appt: {catVar(prof.ci)}"
>…</div>
```

Repare que o `dark:` continua resolvendo o **alpha** (risco de [§4.2](#42-tinthex-a--modificador-de-opacidade)),
enquanto a **cor** vem do inline — as duas coisas compõem. A alternativa de forçar a geração
das 7 classes (`@source inline("bg-cat-{1..7}")`) existe, mas gera 7 × cada utilitário × cada
variante e não resolve o alpha por tema; fica descartada.

Esta é a exceção à regra "sem estilo inline" do risco 1 ([§9](#9-riscos-do-port-react--svelte-5)),
e é deliberada: o inline carrega **um** valor, não um objeto de estilo.

---

## 5. Inventário de componentes

O protótipo tem **235 métodos** na classe (contagem verificada), dos quais **78 produzem
markup** (contêm `html\``) — são estes que viram componente ou `{#snippet}`, não os 235. Há
**25** métodos `render*`, **16 modais** no switch de `renderModal`
([`:1913`–`:1930`](../interface/Movimento.dc.html#L1913)) mais o invólucro `modalShell`
([`:` ](../interface/Movimento.dc.html#L1911) região), **8** métodos de sidebar `sb*` e **5**
de configuração `cfg*`.

> A estimativa de "~180 métodos-render" que motivou este documento é uma superestimativa: o
> número verificado é 235 métodos no total, 78 deles produzindo markup. O port trata os 78, e
> a maioria dos 157 restantes são helpers de domínio/estado que **não** viram componente (viram
> `$lib/domain` ou vão para o servidor).

Critério: **componente** quando tem estado próprio, ciclo de vida (socket, observer, listener)
ou é reusado entre telas; **`{#snippet}`** quando é fragmento de markup parametrizado, local a
um componente e sem estado — o equivalente direto dos helpers de markup do protótipo (`fld`,
`btnP`, `btnS`, `avatar`).

| Componente / snippet | Substitui (protótipo) | Props principais | Notas |
|---|---|---|---|
| `AppShell.svelte` | `render` raiz [`:1281`](../interface/Movimento.dc.html#L1281) | `screen`, `mobile` | grid de layout; decide rail vs bottom-nav |
| `Sidebar.svelte` + `{#snippet}` por tela | `sbPacientes/sbFila/sbRelatorios/sbConfig/sbProfissionais` (8 `sb*`) | contexto da tela | os 8 `sb*` viram snippets de um só `Sidebar` |
| `AgendaGrid.svelte` | `renderDayGrid` [`:1587`](../interface/Movimento.dc.html#L1587), `renderWeek`, `renderMonth` | `date`, `view`, `appts`, `ppm` | grade absoluta; ver [§6](#6-os-cinco-portes-difíceis) |
| `AgendaColumn.svelte` | `renderColumn` [`:1624`](../interface/Movimento.dc.html#L1624) | `col`, `lay`, `colW`, `appts` | gutter/lanes por coluna |
| `AppointmentBlock.svelte` | `renderBlock` [`:1665`](../interface/Movimento.dc.html#L1665) | `appt`, `slot`, `dragging` | focável/operável por teclado ([§8](#8-acessibilidade)) |
| `NowLine` `{#snippet}` | linha do agora [`:1617`](../interface/Movimento.dc.html#L1617) | `nowTop` | só quando `isToday` |
| `AppointmentDrawer.svelte` | `renderDrawer` [`:1797`](../interface/Movimento.dc.html#L1797) | `apptId` | **drawer único** de detalhe; precisa focus trap |
| `Modal.svelte` (shell) | `modalShell` [`:` shell](../interface/Movimento.dc.html#L1911) | `title`, children | invólucro dos 16; **focus trap + Esc + aria-modal** |
| 16 × `modais` (ver 5.1) | `renderModal` switch [`:1913`](../interface/Movimento.dc.html#L1913) | por modal | conteúdo dentro de `Modal.svelte` |
| `Switch.svelte` | **`switchEl` [`:1182`](../interface/Movimento.dc.html#L1182) + `switchToggle` [`:3212`](../interface/Movimento.dc.html#L3212)** | `checked`, `disabled?` | **duplicação a unificar** (ver 5.2) |
| `useScrollSpy` (action) | scroll-spy **duplicado** (ver 5.2) | `sections` | `IntersectionObserver` ([§6](#6-os-cinco-portes-difíceis)) |
| `Field` `{#snippet}` | `fld` [`:1933`](../interface/Movimento.dc.html#L1933) | `label`, children | label+campo |
| `ButtonPrimary/Secondary` `{#snippet}` | `btnP`/`btnS` [`:1935`/`:1936`](../interface/Movimento.dc.html#L1935) | `label`, `onclick`, `disabled` | |
| `Avatar` `{#snippet}` | `avatar` (usado em [`:1633`](../interface/Movimento.dc.html#L1633)) | `nome`, `cor`, `size` | cor de `profColor`/`patientColor` |
| `PatientField.svelte` | `patientField` (usado em [`:1982`](../interface/Movimento.dc.html#L1982)) | `multi?`, `selectedIds`, `onPick` | autocomplete; **falta ARIA combobox** ([§8](#8-acessibilidade)) |
| `Toast.svelte` | `toast` [`:1030`](../interface/Movimento.dc.html#L1030) | `message` | **precisa `aria-live`** ([§8](#8-acessibilidade)) |
| `MaskedInput.svelte` | `maskCPF/RG/Tel/CEP/Date/MY/CNPJ` [`:1957`–`:1963`](../interface/Movimento.dc.html#L1957) | `mask`, `value` | máscaras client-side |
| `WaitlistSlots.svelte` | `filaDispCell` [`:2596`+](../interface/Movimento.dc.html#L2596) | `entry`, `slots` | slots vêm do servidor ([§6](#6-os-cinco-portes-difíceis)) |
| `PackageMenu` (pop-over) | `pkgMenu` overlay [`:457`](../interface/Movimento.dc.html#L457) | `pkg` | **não passa por `Modal`** (ver 5.3) |
| `ConfigTabs.svelte` + 5 `{#snippet}` | 5 `cfg*` (`cfgOperacao` [`:3218`](../interface/Movimento.dc.html#L3218), …) | aba ativa | |

### 5.1 Os 16 modais (via `renderModal`, [`:1913`](../interface/Movimento.dc.html#L1913))

`modalNovoAgendamento`, `modalPacote` (agendarPacote), `modalPacoteMassa`, `modalRenovar`,
`modalSessoes` (pkgSessoes), `modalAjustarGrade` (pkgGrade), `modalPkgCancelar`,
`modalAddFila`, `modalQuemCabe`, `modalOferecer`, `modalProf`, `modalTipo`, `modalMembro`,
`modalOverride`, `modalRemarcar`, `modalHorarioConflitos`. Todos renderizados dentro do
invólucro `modalShell` — que vira o `Modal.svelte` com focus trap.

### 5.2 Duplicações a unificar (confirmadas)

- **Dois toggles quase idênticos.** `switchEl(on,onClick)`
  ([`:1182`](../interface/Movimento.dc.html#L1182); `role="switch"`, `40×23`, pill `999px`) e
  `switchToggle(c,on,onToggle,disabled)`
  ([`:3212`](../interface/Movimento.dc.html#L3212); `role="switch"`, `38×22`, raio `11px`,
  com estado `disabled`). Mesma semântica, geometria e sombra levemente diferentes. **Unificar
  num só `Switch.svelte`** com prop `disabled`, adotando o `role="switch"`/`aria-checked` que
  ambos já têm.
- **Dois scroll-spies idênticos.** Os blocos `secTop`/`scrollableAncestor`/`secEl`/`goSec`/
  `onScroll` do formulário de **paciente** ([`:2043`–`:2047`](../interface/Movimento.dc.html#L2043))
  e do formulário de **profissional** ([`:3019`–`:3023`](../interface/Movimento.dc.html#L3019))
  são **byte-a-byte iguais**, incluindo o uso dos campos de instância `_navLock`/`_navT`.
  **Extrair para uma única action `use:scrollSpy`** ([§6](#6-os-cinco-portes-difíceis)).

### 5.3 Pop-overs que **não** passam por `renderModal`

Nem toda camada flutuante é modal. Estes usam overlay/estado próprio e precisam do mesmo
tratamento de acessibilidade (foco, Esc, clique-fora) sem serem `Modal.svelte`:

- **Menu "gerir pacote"** (`pkgMenu`): click-catcher `position:fixed;inset:0`
  ([`:457`](../interface/Movimento.dc.html#L457)) mais o menu ancorado.
- **Autocomplete de paciente** (`patientField`): dropdown de resultados controlado por
  `state.pac` ([`:1982`](../interface/Movimento.dc.html#L1982)).
- **Toast** (`toast`, [`:1030`](../interface/Movimento.dc.html#L1030)): notificação transitória.
- **Menu de exceção do profissional** e o pop-over de status do bloco, na mesma família.

---

## 6. Os cinco portes difíceis

### 6.1 Grade da agenda (posicionamento absoluto)

O protótipo posiciona tudo em pixels a partir de minutos, com o fator `ppm` (px/min). Os
números são verificados em `renderDayGrid` ([`:1587`](../interface/Movimento.dc.html#L1587)) e
`renderColumn` ([`:1624`](../interface/Movimento.dc.html#L1624)):

- `HEADER=66`, `GUT=54` (gutter de horas), `PAD=14`; `ppm()` ∈ `{0.82, 1.05, 1.4}`
  ([`:1228`](../interface/Movimento.dc.html#L1228)) → vira `--mv-ppm`.
- Janela vertical: minuto `480` (08:00) a `1080` (18:00); `gridH = PAD+(1080-480)*ppm+10`
  ([`:1590`](../interface/Movimento.dc.html#L1590)); horas `8..18`
  ([`:1598`](../interface/Movimento.dc.html#L1598)).
- **Largura de coluna**: `lay.maxLanes>1 ? maxLanes*152 : 210`
  ([`:1594`](../interface/Movimento.dc.html#L1594)) — colunas alargam com o número de raias.
- **Gutter de horas sticky**: `position:sticky;left:0`
  ([`:1609`](../interface/Movimento.dc.html#L1609)).
- **Linha do agora**: só quando `isToday`, em `nowTop = HEADER+PAD+(702-480)*ppm`
  ([`:1600`](../interface/Movimento.dc.html#L1600)), com o rótulo literal `11:42`
  ([`:1619`](../interface/Movimento.dc.html#L1619)) — congelado ([ADR-009](00-decisoes.md#adr-009--relógio-injetável-timezone-por-clínica),
  ver [§9](#9-riscos-do-port-react--svelte-5)).
- **Faixa de almoço**: bloco listrado de `720` (12:00) por `60*ppm` de altura
  ([`:1649`](../interface/Movimento.dc.html#L1649)).

Em Svelte, o cálculo de `top`/`height` fica em `$derived` a partir de `appt.start`/`appt.dur`
e de `--mv-ppm`; o posicionamento é `style:top`/`style:height` no bloco. Manter os números
como constantes nomeadas em `$lib/agenda/geometry.ts` (não literais espalhados).

### 6.2 `layoutAppts` — coloração de intervalos (o único motor no cliente)

[04 §2](04-arquitetura.md#2-fronteiras-e-responsabilidades) é explícito: `layoutAppts` é o
**único** dos motores que fica no cliente. É a coloração de grafo de intervalos que atribui
cada agendamento a uma raia sem que dois sobrepostos caiam na mesma
([`:1576`–`:1585`](../interface/Movimento.dc.html#L1576)): ordena por início, agrupa em
clusters contíguos e, por cluster, encaixa cada item na primeira raia cujo fim `<= start`,
devolvendo `{byId:{lane,lanes}, maxLanes}`.

Vai para **`$lib/domain/layoutAppts.ts`** como função pura, sem qualquer dependência de DOM ou
de Svelte, testada em **Vitest** table-driven ([07 §2.5](07-estrategia-de-testes.md#25-layoutappts--coloração-de-grafo-de-intervalos-cliente-vitest),
[07 §7.1](07-estrategia-de-testes.md#71-domínio-puro-no-cliente-vitest)). É o primeiro teste
de fogo do port não-mecânico ([08 Fatia 1](08-roadmap.md#3-fatia-1--agenda-do-dia-leitura--criar-agendamento)):
transcrever o algoritmo, cobrir com os mesmos casos, e só então plugar no componente.

```ts
// $lib/domain/layoutAppts.ts — port puro de :1576-1585, testável isolado
export interface Slot { lane: number; lanes: number; }
export function layoutAppts(appts: { id: string; start: number; dur: number }[]) {
  const items = appts
    .map(a => ({ id: a.id, start: a.start, end: a.start + a.dur }))
    .sort((x, y) => x.start - y.start || x.end - y.end);
  const byId: Record<string, Slot> = {};
  let maxLanes = 1, cluster: typeof items = [], clusterEnd = -1;
  const flush = () => {
    if (!cluster.length) return;
    const laneEnds: number[] = [];
    for (const it of cluster) {
      let lane = laneEnds.findIndex(e => e <= it.start);
      if (lane === -1) { lane = laneEnds.length; laneEnds.push(it.end); }
      else laneEnds[lane] = it.end;
      (it as any).lane = lane;
    }
    const lanes = laneEnds.length;
    for (const it of cluster) byId[it.id] = { lane: (it as any).lane, lanes };
    maxLanes = Math.max(maxLanes, lanes);
    cluster = []; clusterEnd = -1;
  };
  for (const it of items) {
    if (cluster.length && it.start >= clusterEnd) flush();
    cluster.push(it); clusterEnd = Math.max(clusterEnd, it.end);
  }
  flush();
  return { byId, maxLanes };
}
```

### 6.3 Drag-and-drop + ghost + pan → action com cleanup, e teclado obrigatório

O drag do protótipo é `PointerEvent`: `startDrag(e,a)`
([`:1231`](../interface/Movimento.dc.html#L1231)) fixa `drag`/`ghost`, adiciona
`pointermove`/`pointerup` **no `window`** e os remove no `up`
([`:1252`](../interface/Movimento.dc.html#L1252)); acha a coluna sob o cursor iterando
`[data-col]` por `getBoundingClientRect`; quantiza o horário em passos de 15min
(`Math.round(mins/15)*15`, clamp `480..1080-dur`, [`:1248`](../interface/Movimento.dc.html#L1248)).
O pan é `startPan` ([`:1269`](../interface/Movimento.dc.html#L1269)).

Vira uma **Svelte action** `use:draggableAppointment` cujo retorno de `$effect`/action faz o
`removeEventListener` — o *cleanup* que hoje é manual e propenso a vazamento vira garantido
pelo ciclo da action.

**Alternativa por teclado é obrigatória**, não opcional
([07 §7.2](07-estrategia-de-testes.md#72-e2e-com-playwright--drag-and-drop-e-a-alternativa-por-teclado)):
foco no `AppointmentBlock`, setas mudam horário/coluna, Enter confirma, Esc cancela. É o
caminho e2e primário (determinístico, sem pixel) e satisfaz acessibilidade de brinde.

> **GAP a não copiar.** No `up`, o protótipo valida **só conflito** — chama `checkConflict`
> ([`:1257`](../interface/Movimento.dc.html#L1257)) e, se colide, abre o modal `override`
> ([`:1258`](../interface/Movimento.dc.html#L1258));
> **não** chama `checkAvail`/`dayPeriods`. Ou seja, **arrastar para fora do expediente é
> permitido** no protótipo. Isso é um GAP, não requisito. No port, o drop (por ponteiro **e**
> por teclado) deve espelhar disponibilidade **e** conflito para feedback, e o servidor
> revalida ambos ([09 §3.1](09-contrato-api.md#31-agenda--agendamentos): `422` fora do
> expediente / `409` conflito).

```svelte
<!-- NAO-VERIFICADO: confirmar assinatura de Action e $effect (Svelte 5) ao scaffoldar -->
<script lang="ts">
  import type { Action } from "svelte/action";
  export const draggableAppointment: Action<HTMLElement, { id: string; onDrop: Fn }> =
    (node, params) => {
      const onMove = (ev: PointerEvent) => {/* ghost + coluna sob cursor */};
      const onUp   = () => {
        window.removeEventListener("pointermove", onMove);
        window.removeEventListener("pointerup", onUp);
        params.onDrop(/* {colId, start} quantizado a 15min */);
      };
      const onDown = (e: PointerEvent) => {
        if (e.button !== 0) return;
        window.addEventListener("pointermove", onMove);
        window.addEventListener("pointerup", onUp);
      };
      node.addEventListener("pointerdown", onDown);
      return { destroy() { node.removeEventListener("pointerdown", onDown); } }; // cleanup
    };
</script>
```

### 6.4 Scroll-spy dos formulários → action reutilizável

Extrair o scroll-spy duplicado ([§5.2](#52-duplicações-a-unificar-confirmadas)) para uma
`use:scrollSpy` que usa **`IntersectionObserver`** em vez da medição manual por
`getBoundingClientRect`/`scrollTop` do protótipo. Uma action, dois formulários (paciente e
profissional). O `_navLock`/`_navT` do protótipo — a trava para o scroll programático não
disparar o spy — vira estado interno da action (variável no closure), não campo de instância.

### 6.5 `filaVagas` — roda no servidor (concordo)

[04 §2](04-arquitetura.md#2-fronteiras-e-responsabilidades) e
[04 §10](04-arquitetura.md#10-fronteira-espelho-do-cliente-vs-autoridade-do-servidor) já
decidiram: `filaVagas` ([`:2531`](../interface/Movimento.dc.html#L2531)) é
`Movimento.Waitlist.SlotFinder`, no servidor, exposto por `GET /waitlist/:id/slots`
([09 §3.6](09-contrato-api.md#36-fila-de-espera)). **Concordo, sem contestar**, e a razão é
técnica: `filaVagas` varre 14 dias × todos os profissionais e depende do estado **global** de
`dayAppts` (ocupação de todo mundo, incluindo o que abriu por cancelamento/falta) — dados que
o cliente **não** tem no recorte visível, exatamente o critério de "servidor obrigatório" de
[04 §10](04-arquitetura.md#10-fronteira-espelho-do-cliente-vs-autoridade-do-servidor). Além
disso ele prioriza vagas `freed` na ordenação final
([`:2591`](../interface/Movimento.dc.html#L2591)) — ordem de domínio, não `?sort` do cliente.
O cliente só renderiza os slots e chama `.../offer` → `.../convert`
([09 §3.6](09-contrato-api.md#36-fila-de-espera)), onde mora a corrida do hold.

---

## 7. `$derived` e performance

O protótipo recomputa a cada render por varredura de `appts`. Verificado:

- **`pkgUsadas(pk)`** ([`:326`](../interface/Movimento.dc.html#L326)) faz `pkgAppts(pk)`
  (filtra **todos** os `appts`) e reduz com `wouldConsume` ([`:1104`](../interface/Movimento.dc.html#L1104))
  por sessão. `pkgRemaining`/`pkgEnding`/`pkgDone` dependem dele
  ([`:327`–`:329`](../interface/Movimento.dc.html#L327)).
- **Ocupação/carga** por coluna (`colLoad`, usado em [`:1627`](../interface/Movimento.dc.html#L1627))
  varre os agendamentos da coluna a cada render.
- **Relatórios** (`renderRelatorios`, KPIs em [`:3367`+](../interface/Movimento.dc.html#L3367))
  varrem a base inteira.

Divisão recomendada:

| Cálculo | Onde | Por quê |
|---|---|---|
| `layoutAppts` (raias) | **`$derived` no cliente** | Puramente visual, só do recorte na tela ([04 §2](04-arquitetura.md#2-fronteiras-e-responsabilidades)). |
| `top`/`height`/largura de bloco | **`$derived` no cliente** | Deriva de `appt` + `--mv-ppm`. |
| Contador de sessões do pacote na tela | **`$derived` no cliente**, semeado pelo servidor | O evento `appointment_status_changed` traz `package_debit?` ([09 §7.2](09-contrato-api.md#72-eventos-da-agenda)) — o cliente ajusta o contador sem refazer `wouldConsume`. |
| `pkgUsadas`/`pkgRemaining` autoritativo | **servidor** (agregado/calculation) | Débito é efeito de negócio ([04 §10](04-arquitetura.md#10-fronteira-espelho-do-cliente-vs-autoridade-do-servidor)); **depende de 01-dominio-ash.md** para os nomes de aggregate/calculation. |
| Ocupação / KPIs de relatório | **servidor**, agregado empurrado ao SQL + snapshot noturno | [09 §3.8](09-contrato-api.md#38-relatórios), [04 §11](04-arquitetura.md#11-jobs-em-background-oban). |

Regra prática: no cliente, `$derived` só para o que é **visual e local ao recorte**; débito,
ocupação e KPIs são **servidor**. Com runes, `$derived` memoiza e só recomputa quando a
dependência muda — o oposto do "varre `appts` a cada render". A confirmação dos nomes dos
agregados **depende de `01-dominio-ash.md`**, que ainda não existe.

---

## 8. Acessibilidade

Checklist acionável, ancorado no que o protótipo **já** tem e no que **falta**. Marcado
**[BLOQUEANTE v1]** o que não pode passar do port.

### 8.1 O que o protótipo já acerta (preservar)

- **`focus-visible` global** com outline teal `#0FB5A6`, `outline-offset:1px`
  ([`:32`](../interface/Movimento.dc.html#L32)). Manter no `@layer base` de `app.css`, com o
  literal trocado por `var(--mv-teal-solid)` ([§4.1](#41-srclibstylesappcss)).
- **`prefers-reduced-motion: reduce`** zera durações de animação/transição
  ([`:33`](../interface/Movimento.dc.html#L33)). As keyframes (`mvPulse`, `mvSlide`, …
  [`:20`–`:26`](../interface/Movimento.dc.html#L20)) só rodam quando permitido. Manter.
- **`role="switch"` + `aria-checked`** nos dois toggles
  ([`:1182`](../interface/Movimento.dc.html#L1182), [`:3212`](../interface/Movimento.dc.html#L3212)).
  Preservar ao unificar em `Switch.svelte`.
- **`overscroll-behavior-y:none`** ([`:18`](../interface/Movimento.dc.html#L18)) e
  `inputMode` nos campos numéricos (ex. [`:2099`](../interface/Movimento.dc.html#L2099)).

### 8.2 O que falta (implementar)

- **Focus trap em modal e drawer.** `modalShell` e `renderDrawer`
  ([`:1797`](../interface/Movimento.dc.html#L1797)) não prendem foco nem fecham no Esc de forma
  sistemática. `Modal.svelte`/`AppointmentDrawer.svelte` precisam de `role="dialog"`,
  `aria-modal="true"`, trap de foco, restauração de foco ao fechar e Esc. **[BLOQUEANTE v1]**
- **`aria-live` no toast.** `toast` ([`:1030`](../interface/Movimento.dc.html#L1030)) só troca
  texto; leitor de tela não anuncia. `Toast.svelte` precisa de região `aria-live="polite"`
  (ou `assertive` para erro). **[BLOQUEANTE v1]**
- **Blocos da agenda focáveis e operáveis por teclado.** `renderBlock`
  ([`:1665`](../interface/Movimento.dc.html#L1665)) responde a `onPointerDown`/`onClick`, sem
  `tabindex` nem teclado. É o mesmo requisito da alternativa por teclado ao drag
  ([§6.3](#6-os-cinco-portes-difíceis)): `tabindex="0"`, `role`, `aria-label` com
  paciente/horário/status, setas/Enter. **[BLOQUEANTE v1]** (acessibilidade **e** testabilidade).
- **ARIA combobox no autocomplete.** `patientField`
  ([`:1982`](../interface/Movimento.dc.html#L1982)) não expõe `role="combobox"`/`listbox`/
  `option`, `aria-expanded`, `aria-activedescendant`. `PatientField.svelte` precisa do padrão
  combobox completo, com navegação por seta. **[BLOQUEANTE v1]** (é o campo mais usado).
- **`lang="pt-BR"` no `<html>`.** O protótipo abre `<html>` sem `lang`
  ([`:2`](../interface/Movimento.dc.html#L2)). Estampar no mesmo ponto que estampa `data-theme`
  ([§4.4](#4-design-system)). **[BLOQUEANTE v1]** (trivial e afeta pronúncia/idioma inteiro).
- **Contraste do token `faint`.** `--mv-faint` é `#8A929B` (claro) / `#6B747D` (escuro)
  ([`:309`](../interface/Movimento.dc.html#L309)), usado em legendas/mono
  (ex. [`:1636`](../interface/Movimento.dc.html#L1636)). Sobre `surface`/`canvas` é limítrofe
  para texto pequeno WCAG AA (4.5:1). Auditar por par de fundo; reservar `faint` para texto
  ≥ certo tamanho/peso ou escurecer. **[BLOQUEANTE v1]** para qualquer texto essencial.
- **Cor de aviso sem *on-color* legível.** O órfão `#8a5d00`
  ([`:768`](../interface/Movimento.dc.html#L768)) vira `--mv-on-warning`
  ([§4.3](#4-design-system)), com par escuro definido — hoje a faixa de aviso no tema escuro
  pode ficar ilegível.

### 8.3 Não-bloqueante mas recomendado

`aria-label` nos botões-ícone `lucide` (muitos são só ícone), landmark roles (`main`/`nav`),
e ordem de foco coerente no rail vs conteúdo.

---

## 9. Riscos do port React → Svelte 5

Esta é a seção que o [ADR-006](00-decisoes.md#adr-006--frontend-em-svelte-5-runes--typescript)
cita. Cada risco com mitigação concreta. Alinhada com
[08 §7](08-roadmap.md#7-riscos-do-programa-e-mitigação).

| # | Risco | Evidência no protótipo | Mitigação |
|---|---|---|---|
| 1 | **Estilo inline em massa.** 1.205 objetos de estilo computados por render, e **zero** `class=`. | `theme()` [`:301`](../interface/Movimento.dc.html#L301) + `tint()` [`:314`](../interface/Movimento.dc.html#L314) em quase todo elemento. | `app.css` ([§4](#4-design-system)) uma vez; cada estilo vira utilitário Tailwind sobre os tokens, traduzido contra o hex de origem ([ADR-010](00-decisoes.md#adr-010--css-utilitário-com-tailwind-v4)). **Não** transcrever objeto-a-objeto: o número de objetos não é o número de componentes. |
| 2 | **`setState` imutável vs. mutação de proxy `$state`.** React funde estado com `map`/`filter`/spread; runes mutam o proxy. Transcrição literal quebra reatividade ou vaza bug. | `setState(st=>({appts:st.appts.map(…)}))` em toda mutação (ex. `commitMove` [`:1268`](../interface/Movimento.dc.html#L1268)). | Reescrever updaters como mutação idiomática de `$state`; **não** portar o padrão spread. Cobrir cada motor por teste antes de plugar na UI. |
| 3 | **235 métodos, 78 com markup, viram componentes/snippets.** Fronteira componente vs. snippet erra fácil. | Contagem verificada; `render*`=25, modais=16, `sb*`=8, `cfg*`=5. | Critério de [§5](#5-inventário-de-componentes): estado/ciclo de vida → componente; fragmento parametrizado → `{#snippet}`. Unificar as duplicações confirmadas ([§5.2](#52-duplicações-a-unificar-confirmadas)). |
| 4 | **`modalData` como buffer compartilhado dos 16 modais.** Um único objeto serve de rascunho a todos; vazamento de campo entre modais. | `setMD(patch)` funde em `state.modalData` [`:1938`](../interface/Movimento.dc.html#L1938); `openModal`/`closeModal` resetam ([`:1208`](../interface/Movimento.dc.html#L1208)). | Cada modal recebe **suas próprias props** e tem seu próprio `$state` local; nada de buffer global. O reset ao fechar deixa de ser necessário. |
| 5 | **Listeners globais e Pointer Events.** Handlers em `window`, limpos à mão. | `startDrag` adiciona/remove `pointermove`/`pointerup` no `window` [`:1252`](../interface/Movimento.dc.html#L1252). | Svelte actions com cleanup no `destroy` ([§6.3](#6-os-cinco-portes-difíceis)); o ciclo da action garante o `removeEventListener`. |
| 6 | **Refs e medição de DOM.** Mede `getBoundingClientRect`, seta `scrollTop`, guarda `_gridEl`. | `_gridRef`/`_mountGrid` [`:285`](../interface/Movimento.dc.html#L285)/[`:1586`](../interface/Movimento.dc.html#L1586); scroll-spy mede DOM. | `bind:this` + `$effect` para medição pós-mount; `IntersectionObserver` no scroll-spy ([§6.4](#6-os-cinco-portes-difíceis)). |
| 7 | **Campos de instância NÃO-reativos.** `_afterDrag`, `_navLock`, `_scrolled`, `_navT`, `_cepReq` são estado de controle que **não deve** virar `$state` (dispararia render à toa). | `_afterDrag` [`:1260`](../interface/Movimento.dc.html#L1260); `_navLock`/`_navT` [`:2045`](../interface/Movimento.dc.html#L2045); `_scrolled` [`:285`](../interface/Movimento.dc.html#L285); `_cepReq` [`:1942`](../interface/Movimento.dc.html#L1942). | Ficam como **variáveis comuns** no closure do componente/action (não runes). Regra: se muda a tela, é `$state`; se é trava/guarda, é variável simples. |
| 8 | **SSR / hidratação.** `toLocaleDateString`, `Date` sem TZ, `URL.createObjectURL`, ViaCEP — divergem servidor/cliente. | [§2.3](#23-cuidados-de-ssr-e-hidratação): [`:1740`](../interface/Movimento.dc.html#L1740), [`:317`](../interface/Movimento.dc.html#L317), [`:957`](../interface/Movimento.dc.html#L957), [`:1945`](../interface/Movimento.dc.html#L1945). | Formatação determinística com TZ da clínica; APIs de browser em `{#if browser}`/`$effect`; datas ISO com offset ([ADR-009](00-decisoes.md#adr-009--relógio-injetável-timezone-por-clínica)). |
| 9 | **Relógio congelado.** `hoje()`='2026-06-25' [`:1098`](../interface/Movimento.dc.html#L1098); `NOW=702` e `TODAY` em `filaVagas` [`:2533`](../interface/Movimento.dc.html#L2533); `today`='2026-06-25' em `futureConflicts` [`:866`](../interface/Movimento.dc.html#L866); `new Date(2026,5,30)` em `idadeDe` [`:317`](../interface/Movimento.dc.html#L317); rótulo `11:42` [`:1619`](../interface/Movimento.dc.html#L1619). | Contamina ~dez lugares. | Relógio **injetável** ([ADR-009](00-decisoes.md#adr-009--relógio-injetável-timezone-por-clínica)); o cliente recebe "agora" do servidor/TZ da clínica para exibição (linha do agora, botões de transição), nunca do `Date.now()` do browser para **decisão**. |
| 10 | **Ícones `lucide` por nome dinâmico.** `<${Icon} name=${var}/>` não sobrevive ao tree-shaking por import estático. | UMD global [`:14`](../interface/Movimento.dc.html#L14); nome dinâmico ex. [`:1691`](../interface/Movimento.dc.html#L1691), [`:334`](../interface/Movimento.dc.html#L334). | Mapa explícito `name → componente` importado estaticamente (só os ícones usados), ou `@lucide/svelte` com whitelist. Sem UMD global, sem CDN. |
| 11 | **Keys do `{#each}`.** React usa `key=${a.id}`; Svelte exige `{#each list as item (item.id)}` para reordenar sem recriar (crítico com patch de socket). | `key=${a.id}` em blocos/colunas (ex. [`:1683`](../interface/Movimento.dc.html#L1683), [`:1641`](../interface/Movimento.dc.html#L1641)). | Todo `{#each}` de agendamento/coluna/lista com `(id)` explícito; sem isso, o patch otimista ([§2.2](#22-como-o-socket-invalida-o-que-o-load-trouxe)) recria nós e perde foco/estado. |
| 12 | **Derivações que varrem `appts`.** Recomputam a cada render. | `pkgUsadas` [`:326`](../interface/Movimento.dc.html#L326), `colLoad`, KPIs. | `$derived` memoizado no cliente só para o visual; débito/ocupação/KPIs no servidor ([§7](#7-derived-e-performance)). |
| 13 | **Cor categórica em runtime vs. classe em build.** O Tailwind varre o fonte para gerar classe; `bg-cat-{n}` interpolado nunca é gerado, e o bug é silencioso — a classe some, o elemento fica sem cor. | `profColor` [`:315`](../interface/Movimento.dc.html#L315) e `patientColor` [`:316`](../interface/Movimento.dc.html#L316) indexam `cat[]` por `ci` vindo do banco. | Custom property inline + `bg-(--appt)`, com o `%7` isolado num helper ([§4.5](#45-cores-categóricas-o-limite-do-utilitário)). Única exceção autorizada ao risco 1. Risco **novo**, criado pelo [ADR-010](00-decisoes.md#adr-010--css-utilitário-com-tailwind-v4) — não existia na proposta vanilla. |

```svelte
<!-- NAO-VERIFICADO: confirmar $state/$derived/keyed each (Svelte 5) ao scaffoldar -->
<script lang="ts">
  import { layoutAppts } from "$lib/domain/layoutAppts";
  let { appts } = $props();
  let lay = $derived(layoutAppts(appts));          // memoiza; só recomputa se appts muda
</script>
{#each appts as a (a.id)}                            <!-- key obrigatória (risco 11) -->
  <AppointmentBlock appt={a} slot={lay.byId[a.id]} />
{/each}
```

---

## 10. Estrutura de diretórios

```
movimento-web/
├─ src/
│  ├─ app.html                      # %sveltekit.html% com <html lang="pt-BR" data-theme data-density>
│  ├─ hooks.server.ts               # sessão (cookie) → locals; estampa theme/lang no HTML
│  ├─ lib/
│  │  ├─ api/                       # cliente BFF → Phoenix (repassa cookie); tipos do contrato
│  │  │  ├─ client.ts
│  │  │  └─ types.ts                # espelho de 09-contrato-api.md (recursos, eventos)
│  │  ├─ realtime/
│  │  │  └─ channels.ts             # Socket/Channel (pacote npm `phoenix`), tópicos de 04 §6.1
│  │  ├─ domain/                    # FUNÇÕES PURAS, testadas em Vitest
│  │  │  ├─ layoutAppts.ts          # único motor no cliente (04 §2)
│  │  │  ├─ geometry.ts             # HEADER/GUT/PAD/janela 480-1080, top/height por ppm
│  │  │  └─ mirrors/                # espelhos de validação (contrato de teste com Elixir)
│  │  │     ├─ dayPeriods.ts        #   sombreamento de disponibilidade (04 §10)
│  │  │     ├─ checkConflict.ts     #   dica de sobreposição no dia carregado
│  │  │     └─ computeSerie.ts      #   prévia da série
│  │  ├─ stores/
│  │  │  ├─ agenda.svelte.ts        # $state espelho + patch/patchStatus (socket)
│  │  │  └─ theme.svelte.ts
│  │  ├─ actions/
│  │  │  ├─ draggableAppointment.ts # Pointer Events + cleanup + teclado (§6.3)
│  │  │  └─ scrollSpy.ts            # IntersectionObserver (§6.4, unifica os 2 duplicados)
│  │  ├─ components/
│  │  │  ├─ AppShell.svelte
│  │  │  ├─ Sidebar.svelte
│  │  │  ├─ Modal.svelte            # shell: focus trap, aria-modal, Esc (§8)
│  │  │  ├─ Toast.svelte            # aria-live (§8)
│  │  │  ├─ Switch.svelte           # unifica switchEl + switchToggle (§5.2)
│  │  │  ├─ PatientField.svelte     # ARIA combobox (§8)
│  │  │  ├─ MaskedInput.svelte
│  │  │  └─ agenda/
│  │  │     ├─ AgendaGrid.svelte
│  │  │     ├─ AgendaColumn.svelte
│  │  │     └─ AppointmentBlock.svelte
│  │  ├─ modals/                    # os 16 (§5.1), cada um com $state próprio (risco 4)
│  │  └─ styles/
│  │     └─ app.css                 # §4.1 — @import "tailwindcss" + as 2 camadas
│  └─ routes/
│     ├─ +layout.server.ts          # theme/density (cookie), sem flash (§4.4)
│     ├─ login/
│     ├─ c/
│     │  ├─ +page.server.ts         # seletor de clínica (GET /auth/me)
│     │  └─ [clinicSlug]/
│     │     ├─ +layout.server.ts    # tenant da sessão + valida slug + realtimeToken (§3.1)
│     │     ├─ agenda/[date]/+page.server.ts
│     │     ├─ pacientes/[...]
│     │     ├─ fila/
│     │     ├─ profissionais/[...]
│     │     ├─ config/
│     │     └─ relatorios/
│     └─ convite/[token]/
├─ tests/
│  ├─ unit/                         # Vitest: layoutAppts, mirrors, geometry
│  └─ e2e/                          # Playwright: drag-por-teclado, fila via Channel (07 §7.2)
├─ svelte.config.js                 # adapter-node
├─ vite.config.ts                   # sveltekit() + tailwindcss() — sem tailwind.config.js (§1.2)
└─ eslint.config.js
```

---

## 11. Plano de port em fatias

### 11.1 Concordância com o roadmap

**Concordo com [08-roadmap.md](08-roadmap.md) §3: a Fatia 1 é a agenda do dia (leitura +
criar).** Não há divergência. A razão é a mesma do roadmap — a agenda concentra o risco: ela
exercita numa tacada tenancy/auth reais, RBAC, `dayPeriods`, `checkConflict` + exclusion
constraint, `layoutAppts` no cliente e o primeiro evento de PubSub
([08 Fatia 1](08-roadmap.md#3-fatia-1--agenda-do-dia-leitura--criar-agendamento)). Do lado do
frontend, é também onde os portes difíceis 6.1–6.3 ([§6](#6-os-cinco-portes-difíceis)) e os
riscos 1, 2, 5, 6, 8, 9, 11, 13 ([§9](#9-riscos-do-port-react--svelte-5)) aparecem primeiro — o
que é desejável: falhar cedo no que é difícil. O 13 entra na lista porque o bloco da agenda é
justamente o elemento colorido por `profColor`.

Ordem de ataque **dentro** da Fatia 1, do frontend:

1. `app.css` (as 2 camadas) + shell + tema sem flash ([§4](#4-design-system)) — destrava tudo
   visual. Junto, o helper `catVar` de [§4.5](#45-cores-categóricas-o-limite-do-utilitário):
   sem ele o bloco da agenda nasce sem cor, e o modo de falha é silencioso (risco 13).
2. `layoutAppts.ts` puro + Vitest ([§6.2](#6-os-cinco-portes-difíceis)) — antes de qualquer
   componente, prova o port não-mecânico.
3. `AgendaGrid`/`Column`/`Block` com posicionamento absoluto ([§6.1](#6-os-cinco-portes-difíceis)),
   `{#each}` keyed (risco 11).
4. Drag por **teclado** primeiro, ponteiro depois ([§6.3](#6-os-cinco-portes-difíceis)).
5. `load` + Channel do dia + patch otimista ([§2.2](#22-como-o-socket-invalida-o-que-o-load-trouxe)).
6. Modal de novo agendamento com espelho de disponibilidade/conflito e canal de erro global
   (o erro sem-campo de [09 §5.2](09-contrato-api.md#52-o-canal-de-erro-não-de-campo-a-correção-do-3),
   exigido desde a Fatia 1 por [08 §7](08-roadmap.md#7-riscos-do-programa-e-mitigação)).

As fatias seguintes do frontend acompanham as do roadmap
([08 §4](08-roadmap.md#4-fatias-seguintes-por-risco--valor)): ciclo de vida do atendimento
(Fatia 2), pacotes/série (Fatia 3), fila + hold (Fatia 4), turma (Fatia 5), prontuário + anexos
(Fatia 6, LGPD), profissionais/horários + `futureConflicts` (Fatia 7), config (Fatia 8),
relatórios (Fatia 9), membros (Fatia 10).

### 11.2 Testes — referência, não duplicação

A estratégia de teste do frontend **já está definida** em
[07-estrategia-de-testes.md §7](07-estrategia-de-testes.md#7-front-vitest-playwright-e-a-verdade-sobre-os-screenshots)
e este documento a **referencia**, não a reescreve:

- **Vitest** para `layoutAppts` e os espelhos de validação, com **contrato de teste
  compartilhado** com a implementação Elixir ([07 §7.1](07-estrategia-de-testes.md#71-domínio-puro-no-cliente-vitest)).
  Os arquivos vivem em `tests/unit/` sobre `$lib/domain/` ([§10](#10-estrutura-de-diretórios)).
- **Playwright** para drag e a **alternativa por teclado** como jornada e2e primária
  (determinística, sem pixel), afirmando estado final, não o meio do gesto
  ([07 §7.2](07-estrategia-de-testes.md#72-e2e-com-playwright--drag-and-drop-e-a-alternativa-por-teclado)).
- **Regressão visual**: os 79 PNGs são **gabarito de tradução / oráculo de aceitação humana**,
  não assert de pixel contra outro framework; o baseline automático nasce **nativo do Svelte**,
  Svelte-contra-Svelte, depois da aceitação manual tela a tela
  ([07 §7.3](07-estrategia-de-testes.md#73-regressão-visual-contra-os-79-screenshots--avaliação-honesta)).
  O tema escuro (`*-dark.png`) e os estados de fila são bons primeiros alvos.

> **# NAO-VERIFICADO: `@testing-library/svelte` com Svelte 5 runes** — compatibilidade e API
> de montagem/atualização de componente em teste, a confirmar ao montar o projeto
> ([07 §7.1](07-estrategia-de-testes.md#71-domínio-puro-no-cliente-vitest)).
