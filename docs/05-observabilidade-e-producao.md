# Observabilidade, Segurança Operacional e Produção

Como o Movimento é observado, implantado e recuperado. As decisões que justificam
este desenho estão em [00-decisoes.md](00-decisoes.md) — em especial ADR-003
(multi-clínica), ADR-007 (dado de saúde é categoria especial da LGPD), ADR-008
(Fly.io + OpenTelemetry sem vendor lock) e ADR-009 (relógio injetável). A arquitetura
dos dois serviços está em [04-arquitetura.md](04-arquitetura.md).

Uma advertência de honestidade vale para todo este documento: **ainda não existe
projeto Elixir nem SvelteKit neste repositório.** Todo trecho de configuração de
biblioteca abaixo foi escrito de memória e está marcado com
`# NAO-VERIFICADO: confirmar contra hexdocs ao scaffoldar`. Trate esses trechos como
intenção de desenho, não como código pronto para colar. Toda afirmação sobre o
protótipo cita a linha verificada em `interface/Movimento.dc.html`.

---

## 1. OpenTelemetry: tracing distribuído do BFF até o Ash

A topologia de rede tem três saltos que importam para um trace: o browser chama o
`movimento-web` (SvelteKit, Node), que chama o `movimento-api` (Phoenix, Elixir),
que fala com o Postgres e com o object storage. Um pedido que renderiza a agenda do
dia atravessa os três. Sem propagação de contexto, cada serviço produz traces
órfãos e a pergunta "por que o SSR da agenda demorou 1,2 s?" fica sem resposta.

A escolha do ADR-008 é **OpenTelemetry puro**: os SDKs de instrumentação são código;
o backend que recebe os spans (Grafana Tempo, Honeycomb, um coletor self-hosted) é
configuração via variável de ambiente. Isso é o que mantém a porta aberta caso um
requisito de jurisdição force sair de um SaaS de telemetria (ver §9).

### 1.1 Lado Elixir (`movimento-api`)

Três pacotes de auto-instrumentação cobrem a maior parte do caminho quente sem
código manual:

- **`opentelemetry_phoenix`** — cria o span raiz de cada requisição HTTP e de cada
  join/handle de Channel, e — crucialmente — **lê o header `traceparent`** que o BFF
  injeta, dando continuidade ao trace que começou no Node.
- **`opentelemetry_ecto`** — anexa um span por query, com o SQL sanitizado e o tempo
  no banco. É aqui que a latência do `filaVagas` e dos agregados de relatório fica
  visível.
- **`opentelemetry_oban`** — liga o span do job ao span da requisição que o
  enfileirou. Materializar a série de um pacote (`:create_with_series` — a rota está
  em [04-arquitetura.md](04-arquitetura.md) §4 e o job em
  [04-arquitetura.md](04-arquitetura.md) §11) vira um filho do POST que a originou.

```elixir
# NAO-VERIFICADO: confirmar contra hexdocs ao scaffoldar
# application.ex — antes de iniciar a supervision tree
OpentelemetryPhoenix.setup(adapter: :bandit)
OpentelemetryEcto.setup([:movimento, :repo])
OpentelemetryOban.setup()
```

O exportador OTLP é configurado por env (`OTEL_EXPORTER_OTLP_ENDPOINT`,
`OTEL_EXPORTER_OTLP_HEADERS`), nunca hard-coded — é o que permite trocar de backend
sem recompilar (ADR-008).

**Instrumentar as ações do Ash.** As quatro máquinas de regra do domínio
([04-arquitetura.md](04-arquitetura.md) §2) não aparecem sozinhas nos spans de
Ecto — elas são código Elixir que roda *antes* de tocar o banco. Vale um span
manual em torno das ações que orquestram lógica cara. O caminho idiomático é o
telemetry do próprio Ash: cada ação emite eventos `[:ash, :domain, :action, ...]`,
e uma ponte telemetry→otel transforma-os em spans sem poluir o código de domínio.

```elixir
# NAO-VERIFICADO: confirmar contra hexdocs ao scaffoldar
# Preferir a ponte via :telemetry sobre os eventos que o Ash já emite,
# em vez de abrir spans à mão dentro de cada action.
:telemetry.attach_many(
  "ash-otel-bridge",
  [[:ash, :movimento, :action, :start], [:ash, :movimento, :action, :stop]],
  &Movimento.Telemetry.OtelBridge.handle/4,
  nil
)
```

Onde um motor específico for suspeito de custo — o `filaVagas`, que varre `DAYS=14`
dias por profissional (`interface/Movimento.dc.html:2533`, `filaVagas` em
`interface/Movimento.dc.html:2531`) — vale um span nomeado explícito
(`waitlist.slot_finder`) com atributos de cardinalidade da busca (nº de
profissionais candidatos, nº de regras ativas, dias varridos). Assim o trace explica
*por que* uma busca específica foi lenta, não só que foi.

**Instrumentar os Phoenix Channels.** O tempo real (ADR-004) não passa pelo BFF: o
browser abre o WebSocket direto contra o Phoenix. Isso significa que o trace do
Channel **não** tem um pai vindo do Node — ele nasce no `movimento-api`. O
`opentelemetry_phoenix` instrumenta join e handle_in; o que importa acrescentar é o
atributo de tópico (`clinic:<id>:agenda:<data>`) para conseguir agrupar latência de
broadcast por clínica e por dia. Um broadcast de `appointment_rescheduled` que chega
lento a todos os clientes de um tópico é um sintoma de fan-out excessivo, e o span
com o tópico é o que torna isso diagnosticável.

### 1.2 Lado Node (`movimento-web`)

O BFF é o **início** do trace na maioria dos fluxos de tela. Ele precisa de duas
coisas: gerar o contexto de trace no `handle` do SvelteKit e **injetar `traceparent`**
em toda chamada `fetch` para a API.

```javascript
// NAO-VERIFICADO: confirmar contra hexdocs ao scaffoldar
// instrumentation.ts — carregado antes do app (node --import)
import { NodeSDK } from '@opentelemetry/sdk-node';
import { getNodeAutoInstrumentations } from '@opentelemetry/auto-instrumentations-node';

new NodeSDK({
  serviceName: 'movimento-web',
  instrumentations: [getNodeAutoInstrumentations()] // instrumenta o fetch → injeta traceparent
}).start();
```

A auto-instrumentação de `http`/`fetch` já injeta o header de propagação W3C
(`traceparent`) nas chamadas de saída; do outro lado, o `opentelemetry_phoenix` o
lê. Com isso um único trace cobre: `handle` do SvelteKit → `fetch` JSON:API → span
HTTP do Phoenix → spans de Ecto → span do Oban se houver job. Este é o artefato que
responde "onde foi o tempo".

O SvelteKit tem um detalhe: `+page.server.ts` roda `load` no servidor, e é aí que a
instrumentação captura valor; o `+page.svelte` roda no browser e não deve carregar
SDK de OTel de servidor. Instrumentação de browser (RUM) é uma decisão separada e
**não** está no escopo da v1 — o risco de RUM é justamente vazar identificadores para
um script de terceiros, o que colide com ADR-007.

### 1.3 Atributos de span: o que pode e o que nunca

Esta é a regra de ouro do domínio, e ela não é negociável porque os spans **saem do
país** rumo ao backend de telemetria (§9). Um atributo de span é dado exportado.

| Atributo | Permitido? | Razão |
|---|---|---|
| `clinic_id` (tenant) | **Sim** | Chave operacional; agrupa latência e erro por clínica. Não identifica um titular. |
| `professional_id`, `appointment_id`, `waitlist_item_id` | Sim | Identificadores internos e opacos; úteis para correlacionar sem expor pessoa. |
| `action`, `resource`, `http.route`, `topic` | Sim | Estrutura, não conteúdo. |
| `patient_id` | **Nunca** | Liga o trace a um titular identificável. O trace vai para um backend possivelmente fora da jurisdição — isso exportaria uma chave de reidentificação. |
| CPF, nome, e-mail, telefone do paciente | **Nunca** | Dado pessoal direto. |
| `tags` clínicas, `medico`, `crm`, `fila.obs` | **Nunca** | Dado sensível de saúde (LGPD Art. 11, ADR-007). No protótipo `patient.tags` guarda diagnóstico como texto (`interface/Movimento.dc.html` — ver ADR-007). |

Quando um trace precisa referenciar um paciente para depuração — e às vezes precisa —
usa-se o `appointment_id` ou um identificador de correlação opaco por requisição,
nunca o `patient_id`. A regra é operacionalizável: um teste de contrato de telemetria
deve *falhar o build* se um atributo de span com nome em uma denylist
(`patient_id`, `cpf`, `nome`, `tags`, `obs`, `crm`, `medico`) for emitido. É mais
barato barrar na CI do que caçar num backend de terceiros depois.

---

## 2. Os quatro sinais e a política de redação

### 2.1 Traces

Cobertos na §1. São a espinha dorsal do diagnóstico de latência. Amostragem: em
produção, **tail-based sampling** no coletor (manter 100% dos traces com erro ou
lentos, amostrar o resto) mantém custo baixo sem cegar o incidente. Head-sampling no
SDK a 100% em staging, reduzido em produção conforme volume.

### 2.2 Métricas

Séries temporais agregadas, baratas de reter, boas para alerta e dashboard. Duas
fontes:

- **Infra/framework** — via `telemetry_metrics` + `telemetry_metrics_prometheus`
  (ou exportador OTLP de métricas): latência HTTP, throughput, pool de conexão do
  Ecto, VM da BEAM (memória, run queue, GC), filas do Oban.
- **Negócio** — derivadas do domínio, detalhadas na §3. São o que diz se o *produto*
  está saudável, não só o processo.

```elixir
# NAO-VERIFICADO: confirmar contra hexdocs ao scaffoldar
# telemetry.ex — o clinic_id entra como TAG de métrica, com cardinalidade sob controle
Metrics.counter("movimento.appointment.conflict.count", tags: [:clinic_id])
Metrics.distribution("movimento.waitlist.slot_finder.duration",
  unit: {:native, :millisecond}, tags: [:clinic_id])
```

Cardinalidade é o risco central de métrica: `clinic_id` como tag é aceitável (dezenas
a centenas de clínicas); `patient_id` como tag seria catastrófico tanto por
cardinalidade quanto por privacidade — **nunca** vira tag.

### 2.3 Logs estruturados

JSON, um evento por linha, com campos canônicos: `timestamp`, `level`, `trace_id`
(para casar log com trace), `clinic_id`, `actor_id`, `action`, `outcome`. O
`trace_id` no log é o que costura os três sinais: de um span lento você salta para os
logs daquele exato pedido.

No Elixir, `LoggerJSON` (ou formatter equivalente) emite JSON; um metadata middleware
injeta `trace_id` e `clinic_id` em todo log do request. No Node, o logger do
SvelteKit faz o mesmo com o contexto de trace ativo.

### 2.4 O que **nunca** é logado (cross-check com ADR-007)

Esta seção é um critério de aceitação, não uma recomendação. Os campos que o ADR-007
cataloga como sensíveis **não podem aparecer em log, span, métrica, nem em mensagem
de erro serializada**:

- diagnósticos e tags clínicas (`patient.tags`);
- anexos e seus conteúdos (laudos, exames — `anexos[patientId]`);
- queixa clínica da fila (`fila.obs`);
- encaminhamento médico (`medico`, `crm`);
- dados bancários do profissional (`banco`, `agencia`, `conta`, `pix`);
- CPF, e qualquer PII direta do titular.

**Política de scrubbing/redaction, em três camadas:**

1. **Na origem.** O logger de request tem uma allowlist de campos, não uma denylist.
   Loga-se o que foi explicitamente marcado como seguro; o resto do payload nunca
   chega ao log. Allowlist erra fechado; denylist erra aberto — e com dado de saúde
   errar aberto é incidente reportável.
2. **Nos erros do Ash.** `Ash.Error.Invalid` carrega o valor que falhou a validação.
   Um erro de validação em `tags` traria o diagnóstico para dentro da mensagem. O
   serializador de erro (para log e para a resposta JSON:API) redige o `value` de
   campos sensíveis, mantendo só o `field` e o código do erro. Isso conversa com o
   §4 de `04-arquitetura.md` (contrato de erro / `source.pointer`): o front recebe
   "campo inválido", não o conteúdo.
3. **No coletor.** Um processador de redação no OTel Collector é a rede de segurança:
   regex para CPF (`\d{3}\.?\d{3}\.?\d{3}-?\d{2}`) e para os nomes de atributo
   proibidos, dropando o span/atributo antes de exportar. É defesa em profundidade —
   a camada 1 deveria bastar, mas o coletor garante que um `dbg/1` esquecido
   (`interface`/dev) não vaze em produção.

O `dbg/1` merece nota: é a ferramenta de depuração recomendada em
`.claude/rules/usage_rules_elixir.md`, ótima em dev, mas em produção imprime valores
crus no stdout. Um lint de CI deve rejeitar `dbg/1` e `IO.inspect/2` fora de
`test/` e `dev`.

---

## 3. Métricas de negócio que valem alerta

Estas não vêm de um manual genérico de SRE — saem das regras reais do protótipo. Cada
uma é um sintoma de que o *produto* está se comportando mal, não só a máquina.

| Métrica | O que mede | Origem no domínio | Por que alerta |
|---|---|---|---|
| **Taxa de conflito de agendamento** | `409`/rejeições da exclusion constraint de sobreposição por profissional, por minuto | A garantia final de não-sobreposição é a exclusion constraint `btree_gist` ([04-arquitetura.md](04-arquitetura.md) §7.1); o detector em memória é `checkConflict` (`interface/Movimento.dc.html:834`) | Pico = a validação Ash (mensagem bonita) está deixando passar o que a constraint barra — bug de validação, ou UI permitindo o impossível |
| **Holds de vaga expirados / abandonados** | Quantos `SlotHold` expiram sem virar agendamento vs. total ofertado | `offerVaga` (`interface/Movimento.dc.html:2596`) e o `SlotHold` com TTL de 5 min ([04-arquitetura.md](04-arquitetura.md) §7.2) | Taxa alta de abandono = atendentes oferecendo e não confirmando; ou o job de expiração parou e vagas ficam presas |
| **`409` de locking otimista** | Remarcações rejeitadas por versão divergente | `version` no `Appointment`, `PATCH .../reschedule` ([04-arquitetura.md](04-arquitetura.md) §7.3) | Um pouco é saudável (é a proteção funcionando); um pico é dois usuários brigando pela mesma agenda — sinal de UX ruim ou de presença não visível |
| **Latência do `filaVagas`** | Distribuição (p50/p95/p99) da busca de vagas | Varre `DAYS=14` dias × profissionais × `STEP=30` min × regras (`interface/Movimento.dc.html:2531`, `:2533`) | É o motor mais caro. p99 crescendo com o nº de agendamentos = falta de índice ou de recorte; degrada a recepção inteira |
| **Profundidade das filas Oban** | Jobs pendentes/atrasados por fila | Materialização de série, expiração de hold, lembretes, purga LGPD ([04-arquitetura.md](04-arquitetura.md) §11) | Fila crescendo = worker morto ou banco lento; a expiração de hold atrasada trava vagas (liga com a métrica de holds) |
| **Lag de PubSub / broadcast** | Tempo entre a mutação e o cliente receber o evento | Notifier Ash → PubSub → Channel ([04-arquitetura.md](04-arquitetura.md) §6) | Lag alto = a agenda "ao vivo" mente; dois atendentes veem estados diferentes e os conflitos que o realtime deveria evitar voltam |
| **Taxa de falta punitiva (no-show que consome pacote)** | Faltas que efetivamente debitam sessão / agendamentos do dia, por clínica | `status==='faltou'` só debita quando o pacote é punitivo **e** a falta não está justificada — `wouldConsume`/`pkgPunitivo` (`interface/Movimento.dc.html:1104` em diante), com o "hoje" de `hoje()` (`interface/Movimento.dc.html:1098`) | É métrica de negócio pura, mas um salto abrupto pode indicar bug no fluxo de confirmação (lembretes não enviados) tanto quanto realidade clínica |

Duas dessas métricas têm **cardinalidade por `clinic_id`** e nada além disso — é o que
permite um alerta "clínica X com taxa de conflito anômala" sem explodir a série
temporal e sem tocar em identificador de paciente.

Nota sobre relógio (ADR-009): métricas de negócio que dependem de "hoje" e "já
começou" — falta, sessão consumida, hold expirado — devem ser calculadas no
**timezone canônico da clínica**, não no fuso do servidor nem em UTC. O protótipo
congela isso (`hoje()` retorna `'2026-06-25'`, `NOW=702`, verificados em
`interface/Movimento.dc.html:1098` e `:2533`); em produção o relógio é injetado, e
uma métrica de falta calculada em UTC contaria faltas do dia errado para clínicas a
oeste. O agregador de métricas de negócio recebe o relógio da clínica, igual às ações
de domínio.

---

## 4. SLOs, error budget, health checks e readiness

### 4.1 SLOs propostos (a calibrar com dados reais)

SLO é promessa medível; sem tráfego real os números abaixo são ponto de partida
conservador, não lei.

| Fluxo | SLI | SLO alvo (30 dias) |
|---|---|---|
| Leitura de agenda (o mais quente) | % de `GET /appointments` < 400 ms no p95 | 99,5% |
| Escrita de agendamento (schedule/reschedule/complete/no_show) | % de requisições sem erro 5xx | 99,9% |
| Busca de vaga (`filaVagas`) | % de buscas < 1,5 s no p95 | 99% |
| Entrega de evento realtime | % de broadcasts entregues < 1 s | 99% |
| Disponibilidade geral da API | % de health checks OK | 99,9% |

**Error budget.** 99,9% de disponibilidade mensal ≈ 43 min de indisponibilidade
permitida por mês. A política: enquanto há orçamento, prioriza-se feature; quando o
orçamento de um SLO se esgota, **congela-se deploy de risco** naquele fluxo e o
esforço vira confiabilidade. Isso torna a decisão "lançar ou estabilizar" objetiva em
vez de política.

### 4.2 Health check vs. readiness (e por que separar)

O Fly usa health checks para decidir se manda tráfego para uma instância e se um
deploy pode prosseguir. **Confundir liveness com readiness derruba o serviço em
cascata**, então são dois endpoints com semânticas diferentes:

- **`GET /health` (liveness)** — barato, sem I/O. Responde 200 se o processo BEAM
  está de pé e respondendo. **Não** toca o banco. Se um blip momentâneo do Postgres
  fizesse o liveness falhar, o Fly reiniciaria instâncias saudáveis e transformaria
  uma lentidão do banco numa queda total.
- **`GET /ready` (readiness)** — verifica dependências: `SELECT 1` no Postgres,
  migrações aplicadas, pool de conexão não esgotado. Só entra na rotação de tráfego
  quando pronto. É o que o Fly consulta durante o rolling deploy para saber que a
  nova versão subiu de fato.

```elixir
# NAO-VERIFICADO: confirmar contra hexdocs ao scaffoldar
# router.ex — endpoints crus, sem autenticação, fora do pipeline JSON:API
get "/health", HealthController, :live    # 200 se o processo responde
get "/ready",  HealthController, :ready    # 200 se DB + migrações + pool OK
```

```toml
# NAO-VERIFICADO: confirmar contra hexdocs ao scaffoldar
# fly.toml (movimento-api)
[[http_service.checks]]
  method = "GET"
  path = "/ready"
  interval = "10s"
  timeout = "2s"
  grace_period = "10s"   # tempo pra subir antes do primeiro check contar
```

O `movimento-web` (Node) tem seu próprio `/health`, e seu `/ready` deve verificar que
**consegue alcançar a API** — porque um BFF que sobe sem a API atrás é inútil e não
deve receber tráfego.

---

## 5. Deploy no Fly.io

### 5.1 Dois apps, uma região

Conforme ADR-008: dois apps Fly separados, ambos na região **`gru` (São Paulo)** —
não por latência apenas, mas por jurisdição (§9). O ADR-005 aceita o salto de rede a
mais do SSR justamente porque os dois serviços ficam colados na mesma região.

| App | Runtime | Papel | Escala |
|---|---|---|---|
| `movimento-api` | Elixir/Phoenix release | API JSON:API + Channels + Oban | ≥ 2 instâncias (clustering + HA) |
| `movimento-web` | Node/`adapter-node` | BFF SvelteKit | ≥ 2 instâncias |

Duas instâncias de API não são só disponibilidade: são o mínimo para o clustering
BEAM que o PubSub distribuído exige (§5.3).

### 5.2 Release Elixir e migrações no boot vs. no deploy

O empacotamento é um **release** OTP (`mix release`), imagem enxuta, sem Mix em
produção. As migrações são o ponto delicado, e a escolha aqui é deliberada:

**Migrações rodam no `release_command` do deploy, não no `Application.start`.** O Fly
executa o `release_command` numa máquina efêmera **antes** de subir a nova versão,
com a versão antiga ainda servindo. Isso é o que viabiliza zero-downtime (§6.3):
migração acontece com o app no ar, e só depois o rolling deploy troca as instâncias.
Rodar migração no boot de cada nó seria pior — dois nós subindo em paralelo
competindo pela migração (o Ecto pega advisory lock, então não corrompe, mas serializa
e atrasa boot), e uma migração longa seguraria o health check.

```toml
# NAO-VERIFICADO: confirmar contra hexdocs ao scaffoldar
# fly.toml (movimento-api)
[deploy]
  release_command = "/app/bin/movimento eval 'Movimento.Release.migrate()'"
  strategy = "rolling"
```

```elixir
# NAO-VERIFICADO: confirmar contra hexdocs ao scaffoldar
# lib/movimento/release.ex — módulo de release, não depende de Mix
defmodule Movimento.Release do
  @app :movimento

  def migrate do
    load_app()
    # 1) migrações "públicas" (schema base / tabelas globais)
    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end
    # (ADR-017: tenancy por atributo → NÃO há migração de tenant; ver §5.4)
  end
end
```

### 5.3 Clustering BEAM para PubSub distribuído

O ADR-004 quer `Phoenix.PubSub` distribuído, e o ADR-008 diz que o clustering BEAM
entre nós Fly deixa isso "praticamente de graça". Concretamente: com dois nós de
`movimento-api` conectados num cluster Erlang, um broadcast originado no nó A chega a
um cliente conectado no nó B sem broker externo. Sem cluster, um atendente conectado
ao nó A não veria a remarcação feita por outro atendente cujo request caiu no nó B — e
a agenda "ao vivo" mentiria dependendo de em qual instância cada browser pousou.

A descoberta de nós no Fly usa o DNS interno (`<app>.internal`,
`<region>.<app>.internal`). Duas opções, ambas viáveis:

- **`DNSCluster`** (comumente citado como o pacote que os geradores recentes do
  Phoenix incluem — **NAO-VERIFICADO: confirmar contra a doc ao scaffoldar**) —
  consulta o DNS interno periodicamente e conecta os nós. Mais simples.
- **`libcluster`** com a estratégia de DNS — mais configurável, útil se a topologia
  crescer.

```elixir
# NAO-VERIFICADO: confirmar contra hexdocs ao scaffoldar
# application.ex — DNSCluster resolvendo o DNS interno do Fly
{DNSCluster, query: System.get_env("DNS_CLUSTER_QUERY") || :ignore}
# DNS_CLUSTER_QUERY = "movimento-api.internal"
```

Isso exige que o release use nome de nó longo com o IP privado (`RELEASE_DISTRIBUTION=name`,
`RELEASE_NODE=movimento-api@<ipv6-privado>`), configuração que o gerador de release do
Fly costuma preencher no `rel/env.sh.eex`. **NAO-VERIFICADO: confirmar contra hexdocs
ao scaffoldar.**

Nota de resiliência (OTP): um netsplit entre nós parte o PubSub temporariamente. O
sintoma é o "lag de PubSub" da §3. A mitigação de UX já está desenhada — o cliente usa
`invalidate()` do SvelteKit como fallback quando o patch de evento não é aplicável
([04-arquitetura.md](04-arquitetura.md) §6.2 e §8) —, então um netsplit degrada para
polling, não para dado errado.

### 5.4 Migrações no deploy (ADR-017)

**Resolvido pelo [ADR-017](00-decisoes.md): tenancy por atributo (`strategy :attribute`,
coluna `clinic_id`).** Há **um** conjunto de tabelas no schema público; toda linha por-tenant
carrega `clinic_id`. A migração de deploy é a comum — roda as migrações do repo e acabou.
**Não há "migrar tenants"**, nem `priv/repo/tenant_migrations`, nem `Repo.all_tenants/0`, nem
iterar sobre schemas. Uma clínica nova fica pronta assim que sua linha em `clinics` existe (a
criação não provisiona schema nenhum). É a família mais simples de operar e escalar.

> *Histórico:* a v1 começou em `strategy :context` (schema-por-tenant), que exigia rodar
> `priv/repo/tenant_migrations` para cada schema no deploy (`ash_postgres.migrate --tenants` +
> `Repo.all_tenants/0`). O [ADR-017](00-decisoes.md) eliminou esse passo. O `migrate/0` da §5.2
> não tem mais a etapa "2) migrações de tenant".

Com o [ADR-017](00-decisoes.md) (tenancy por `clinic_id`), **este custo operacional some**:
não há N schemas a migrar no `release_command`, então a migração de deploy é O(1) — as
migrações comuns do repo. Some junto o risco de "clínica meia-migrada" e a necessidade de
migração de tenant idempotente/resumível ou de background via Oban. O que **permanece** é a
disciplina expand-only de schema (§6.3), que vale para qualquer estratégia num deploy rolling.

### 5.5 Object storage para anexos

O ADR-007 (item 4) exige: anexos (laudos, exames) em object storage **privado**, com
**URL assinada de vida curta** — nunca o `URL.createObjectURL` persistido do
protótipo. Storage compatível com S3 na mesma pegada de jurisdição (Tigris, Cloudflare
R2 — ADR-008), bucket privado por padrão, sem ACL pública.

O fluxo, sem que o BFF vire proxy de bytes:

1. O browser pede um anexo; o BFF chama a API.
2. O Ash valida a autorização (a `field_policy`/policy de prontuário, ADR-007) e,
   se liberado, **gera uma URL assinada com expiração de minutos** apontando direto
   para o storage.
3. O browser baixa direto do storage com essa URL. A URL expira antes de virar um
   link compartilhável.

Upload é o espelho: URL assinada de `PUT`, o browser envia direto ao bucket, e o
metadado (dono, tipo, clínica) é registrado via API. Os bytes do exame nunca transitam
pelo log nem pelo trace (§2.4). A geração da URL assinada é uma ação Ash como qualquer
outra — passa pela policy e pela auditoria (`AshPaperTrail`), de modo que **cada acesso
a anexo fica na trilha LGPD**, que é exatamente o que o protótipo não tem.

---

## 6. CI/CD com GitHub Actions

### 6.1 Estrutura da pipeline

Dois runtimes, então matriz por serviço, não um pipeline monolítico. Gatilhos: PR
roda tudo menos deploy; merge em `main` faz deploy de staging; deploy de produção é
**disparo manual com aprovação** (GitHub Environments com required reviewers).

```
PR aberto ──▶ [lint+test API] ∥ [lint+test WEB] ──▶ build release (dry) ──▶ ✅ merge liberado
merge main ─▶ (tudo acima) ──▶ deploy STAGING ──▶ smoke tests
tag/manual ─▶ deploy PRODUÇÃO (aprovação obrigatória) ──▶ smoke + verificação de SLO
```

### 6.2 Jobs

**API (Elixir):**

```yaml
# NAO-VERIFICADO: confirmar contra hexdocs ao scaffoldar
jobs:
  api:
    strategy:
      matrix:
        elixir: ["1.17"]   # confirmar versões alvo ao scaffoldar
        otp: ["27"]
    services:
      postgres: { image: postgres:16, ports: ["5432:5432"], env: { POSTGRES_PASSWORD: postgres } }
    steps:
      - uses: actions/checkout@v4
      - uses: erlef/setup-beam@v1
        with: { elixir-version: ${{ matrix.elixir }}, otp-version: ${{ matrix.otp }} }
      - uses: actions/cache@v4              # cache de deps + _build + PLT do dialyzer
        with:
          path: |
            deps
            _build
            priv/plts
          key: mix-${{ runner.os }}-${{ matrix.otp }}-${{ hashFiles('**/mix.lock') }}
      - run: mix deps.get
      - run: mix format --check-formatted
      - run: mix credo --strict
      - run: mix dialyzer                    # PLT cacheado; senão o job leva minutos
      - run: mix test
      # Ash-específico: garantir que não há migração pendente não commitada.
      # Opção A (se a flag existir): mix ash.codegen --check
      #   **NAO-VERIFICADO: confirmar a existência da flag contra hexdocs ao scaffoldar**
      # Opção B (não depende de flag nenhuma; preferida enquanto a flag não for confirmada):
      #   roda o codegen de verdade e falha se o repositório ficou sujo.
      - run: mix ash.codegen ci_check --yes    # gera migrações/recursos derivados
      - run: git diff --exit-code              # falha (código ≠ 0) se algo mudou
```

Garantir que **não há migração pendente não commitada** é um guarda importante para
este projeto: como as migrações são geradas a partir dos recursos Ash
(`.claude/rules/ash_postgres.md`), a CI deve falhar se alguém alterou um recurso sem
gerar a migração — senão o `release_command` de produção tentaria rodar um schema que
ninguém revisou. Há duas formas de implementar o guarda:

- **Opção A — flag dedicada.** `mix ash.codegen --check` (ou equivalente) falharia se o
  schema divergiu das migrações. É a mais limpa, **mas a existência e o nome exato da
  flag são NAO-VERIFICADO: confirmar contra hexdocs ao scaffoldar**.
- **Opção B — sem depender de flag.** Rodar o `mix ash.codegen` de verdade no runner e,
  em seguida, `git diff --exit-code`: se a geração produziu qualquer arquivo novo ou
  alterado, o working tree fica sujo e o `git diff` retorna código diferente de zero,
  reprovando o job. Esse mecanismo não pressupõe nenhuma flag do Ash — só o comportamento
  de `git diff --exit-code`, que é estável — e por isso é o caminho recomendado até que a
  flag da Opção A seja confirmada.

**Web (Node/SvelteKit):**

```yaml
# NAO-VERIFICADO: confirmar contra hexdocs ao scaffoldar
  web:
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with: { node-version: "22", cache: "pnpm" }
      - run: pnpm install --frozen-lockfile
      - run: pnpm run check      # svelte-check + tsc (TS estrito, ADR-006)
      - run: pnpm run lint
      - run: pnpm run test
      - run: pnpm run build      # valida o build do adapter-node
```

**Deploy** usa `flyctl deploy` por app, com o `FLY_API_TOKEN` como secret. O deploy de
produção fica atrás de um GitHub Environment `production` com required reviewers — a
"aprovação" do enunciado. O `flyctl deploy` dispara o `release_command` (migrações,
§5.2) automaticamente antes do rolling.

### 6.3 Migrações zero-downtime: expand/contract

Durante um rolling deploy, por alguns segundos **código velho e código novo rodam
contra o mesmo banco**. Uma migração que quebra o código velho derruba requisições em
voo. A disciplina é **expand/contract**, em deploys separados:

1. **Expand** (deploy N) — só adições compatíveis para trás: adicionar coluna
   *nullable*, criar tabela, criar índice `CONCURRENTLY`. O código velho ignora o
   novo; o código novo já pode usar. **Nunca** renomear ou dropar aqui.
2. **Migração de dados** (se preciso) — backfill em background (Oban), idempotente,
   em lotes, para não travar tabela.
3. **Contract** (deploy N+1, depois que ninguém mais roda o código velho) — remover a
   coluna antiga, apertar `NOT NULL`, dropar o que ficou órfão.

Exemplo concreto do domínio: introduzir o `version` do locking otimista
([04-arquitetura.md](04-arquitetura.md) §7.3) num `Appointment` que já existe em
produção é expand puro — adiciona `version` com default `1`, o código novo passa a
exigi-lo, e nenhuma linha some. Já um `rename` de coluna vira sempre três passos
(adiciona nova → backfill → dropa velha), nunca um `ALTER ... RENAME` direto.

Índices em tabelas grandes usam `CREATE INDEX CONCURRENTLY` (o AshPostgres suporta via
`custom_indexes` com `concurrently: true`, ver `.claude/rules/ash_postgres.md`) para
não travar escrita — importante para a tabela de agendamentos, que é a mais quente.

---

## 7. Backup, restore e DR

### 7.1 Backup

- **Postgres:** snapshots automáticos diários do volume (Fly Postgres), retenção de ao
  menos 7 dias, mais recuperação a um ponto no tempo (PITR via WAL) se a oferta de
  Postgres em uso suportar. **Testar o restore é parte do backup** — snapshot que
  nunca foi restaurado é hipótese, não backup.
- **Object storage (anexos):** versionamento do bucket ligado, e replicação para uma
  segunda localização (dentro da mesma jurisdição, §9). Anexos são laudos e exames —
  perdê-los é perder prontuário.
- **Segredos:** os secrets do Fly (chaves de storage, endpoint OTLP, chave de
  criptografia do `AshCloak`) fora do backup de dados, num cofre à parte. **Perder a
  chave do `AshCloak` torna todo campo criptografado ilegível** — o backup do banco
  sem a chave é lixo cifrado. A custódia da chave é um procedimento por si.

### 7.2 Restore — e o problema do restore por clínica

Restore total (recriar o banco de um snapshot) é o caminho fácil. O difícil, e
específico deste produto multi-tenant (ADR-003), é **restaurar uma única clínica** —
por exemplo, uma clínica que apagou dados por engano e quer voltar ao estado de ontem
sem afetar as outras. **Decidido pelo [ADR-017](00-decisoes.md): coluna `clinic_id`** — então
vale o procedimento mais trabalhoso, e ele precisa ser **escrito e testado antes de ser
preciso**, não durante o incidente:

- **Coluna `clinic_id` (nosso caso):** não há como restaurar "só as linhas da clínica X" de
  um snapshot completo sem um **export/import filtrado por `clinic_id`**, linha a linha,
  respeitando a ordem de FKs. É o custo operacional escondido da estratégia por atributo — e a
  contrapartida que aceitamos no [ADR-017](00-decisoes.md) ao trocar o isolamento físico do
  schema pela simplicidade de migration/operação. **Ação:** um runbook de restore-por-`clinic_id`
  (com ordem de FKs e verificação) entra no Gate de produção antes do go-live.
- *(Descartado — schema-por-tenant:* seria `pg_dump --schema=tenant_<id>` de um schema só,
  trivial; deixou de valer com o ADR-017.)*

Em ambos os casos, restaurar dados de saúde exige que a **chave do `AshCloak`** do
período correspondente esteja disponível; rotação de chave sem versionamento
inviabilizaria o restore de dados antigos. Isso deve ser resolvido no desenho de
criptografia ([01-dominio-ash.md](01-dominio-ash.md), seção de campos sensíveis do
ADR-007), e aqui só se registra a dependência.

### 7.3 RPO / RTO (alvos propostos)

| | Alvo | Como se sustenta |
|---|---|---|
| **RPO** (perda máxima de dados) | ≤ 24 h com snapshot diário; ≤ 5 min se PITR estiver ativo | Frequência do snapshot / retenção de WAL |
| **RTO** (tempo até voltar) | ≤ 2 h para restore total; ≤ 4 h para restore de uma clínica | Ensaiado num game-day; sem ensaio, o RTO é ficção |

O restore por clínica tem RTO maior de propósito — é operação manual e rara, e não deve
ditar o dimensionamento do caso comum.

---

## 8. Alertas e runbooks mínimos

Alerta bom aponta para uma ação. Estes cinco cobrem os modos de falha reais do
domínio; cada um tem um runbook de uma frase.

| Alerta | Condição | Runbook mínimo |
|---|---|---|
| **Pico de conflito de agenda** | Taxa de rejeição da exclusion constraint acima do baseline por 5 min | Ver §3; checar se um deploy recente afrouxou a validação Ash vs. a constraint; a constraint é a verdade — a validação é que está deixando passar. Inspecionar traces `appointment.schedule` com erro |
| **Fila Oban travada** | `expirar SlotHold` com jobs atrasados > 2 min | Vagas presas por hold não expirado; verificar worker Oban vivo e latência do banco; reprocessar a fila. Liga com "holds abandonados" |
| **Lag de PubSub / netsplit** | Broadcast > 1 s no p95, ou nós do cluster < 2 | Provável partição de cluster; conferir DNS interno do Fly e conectividade dos nós (§5.3); a UX degrada para `invalidate()`, então é urgente mas não corrompe dado |
| **Falha de migração no deploy** | `release_command` retornou erro | Deploy **não** promoveu a versão nova (o rolling só troca após o `release_command` OK); versão antiga segue no ar; corrigir a migração e reenviar. (Tenancy por `clinic_id`, ADR-017: uma migração só, sem tenants meio-migrados.) |
| **Erro em URL assinada de anexo** | Taxa de 5xx em geração/download de anexo | Prontuário inacessível; checar credenciais do storage e clock skew (assinatura é sensível a relógio); confirmar que não virou proxy de bytes pelo BFF |
| **Orçamento de erro esgotado** | Error budget de um SLO zerado no mês | Congelar deploy de risco no fluxo afetado (§4.1); priorizar confiabilidade |

Regra de higiene de alerta: todo alerta carrega `clinic_id` quando aplicável (para
saber *quem* está afetado) e **nunca** carrega identificador de paciente — a mesma
denylist da §1.3 vale para o payload do alerta, porque ele também trafega por sistemas
de terceiros (PagerDuty, Slack).

---

## 9. Jurisdição: dado de saúde de titulares brasileiros

Este é o ponto que atravessa todo o resto, e não é opcional. O Movimento guarda dado
pessoal **sensível** de saúde de titulares brasileiros (LGPD Art. 11, ADR-007):
diagnósticos, laudos, exames, queixa clínica. Três frentes de residência de dados:

1. **Postgres na região `gru` (São Paulo).** O banco primário e **toda réplica de
   leitura** ficam em `gru`. Uma réplica criada por conveniência de latência noutra
   região exportaria dado de saúde para fora do país sem base legal clara. O ADR-008 já
   pede para "verificar a região do Fly e a localização das réplicas antes de qualquer
   dado real" — aqui isso é uma trava: réplica só em `gru`.
2. **Object storage na mesma jurisdição.** O bucket de anexos (Tigris/R2) configurado
   para região brasileira ou, no mínimo, para não replicar automaticamente para fora.
   Confirmar a política de residência do provedor antes de subir o primeiro laudo real.
3. **Backend de telemetria — o vazamento silencioso.** Traces, logs e métricas saem do
   país se forem para um SaaS de observabilidade (Grafana Cloud US, Honeycomb US). É
   por isso que a §1.3 e a §2.4 são tão rígidas: **desde que nenhum dado de saúde nem
   identificador de titular entre em span/log/métrica, a telemetria pode sair da
   jurisdição sem carregar dado sensível.** O que exporta é `clinic_id` e latência —
   operacional, não pessoal. Essa disciplina é o que permite usar um backend de
   telemetria estrangeiro *legalmente*; se ela falhar, a saída de telemetria vira um
   vazamento transfronteiriço. A allowlist da §2.4 e a redação no coletor da §2.4
   existem exatamente para isso.

**Se um requisito de jurisdição forçar infraestrutura própria (VPS no Brasil).** Pode
acontecer — uma exigência contratual, um parecer jurídico mais estrito, um cliente do
setor público. O ADR-008 antecipou isso ao escolher **OpenTelemetry puro, sem SDK
proprietário**: o backend de telemetria é configuração, não código. A migração para
VPS própria, se necessária, tem custo, mas não reescrita:

- **Telemetria:** apontar o `OTEL_EXPORTER_OTLP_ENDPOINT` para um stack self-hosted
  (Grafana + Tempo + Loki + Prometheus, ou um coletor OTel próprio) rodando no Brasil.
  Zero mudança de código de instrumentação — é o dividendo do "sem vendor lock".
- **Compute:** o release Elixir e o build Node são portáveis; o que se perde é a
  malha de rede privada e o DNS interno do Fly que o clustering usa (§5.3). Num VPS o
  clustering BEAM passa a usar `libcluster` com estratégia de gossip ou uma lista
  estática de hosts em vez do DNS do Fly — troca de estratégia de descoberta, não de
  arquitetura de PubSub.
- **Postgres e storage:** Postgres autogerido (com o custo operacional de backup/PITR
  que o Fly hoje absorve) e MinIO ou equivalente para os anexos, ambos no data center
  brasileiro. O `AshPostgres` e a assinatura de URL S3-compat funcionam igual contra
  MinIO — é literalmente o que o ambiente de dev já usa ([04-arquitetura.md](04-arquitetura.md) §12).

Ou seja: a saída de jurisdição é uma mudança de *onde* roda e de *como os nós se
descobrem*, não de *o que* o código faz. Foi para preservar essa opção que o ADR-008
recusou o SDK proprietário. O que **não** é negociável em nenhum cenário é a §2.4: dado
de saúde não vaza para telemetria, esteja o coletor em São Paulo ou em Ashburn.

---

## Resumo das dependências ainda abertas

Este documento apoia-se em decisões travadas; dois pontos ainda dependem de trabalho que
vive noutros documentos e **não** devem ser fechados por palpite aqui:

- ~~**Estratégia de tenancy**~~ **Resolvida ([ADR-017](00-decisoes.md)): `strategy :attribute`
  (`clinic_id`).** Simplifica §5.4 (sem migração de tenant) e define §7.2 (restore por
  `clinic_id`, que precisa de runbook). O que resta é **escrever/testar o runbook de restore
  por `clinic_id`** antes do go-live.
- **Versionamento da chave do `AshCloak`** — vem do desenho de criptografia de campo
  (ADR-007 / [01-dominio-ash.md](01-dominio-ash.md)) e é pré-requisito de §7.1 e §7.2.
- **Números de SLO/RPO/RTO** (§4.1, §7.3) — são pontos de partida conservadores; só
  viram compromisso depois de tráfego real e de um game-day de restore.

---

## Correções desta revisão

Reparos de referência cruzada e de precisão; o corpo técnico e os fatos do protótipo
(9 citações, todas verificadas) foram mantidos.

- **Referências de seção ao 04-arquitetura.md realinhadas à renumeração.** O 04 foi
  renumerado depois que este documento foi escrito; todas as âncoras defasadas foram
  corrigidas para o mapa atual:
  - exclusion constraint `btree_gist` — §5 → **§7.1** (métrica de conflito na §3);
  - `SlotHold` / TTL de 5 min — §5 → **§7.2** (métrica de holds na §3);
  - locking otimista / `version` — §5 → **§7.3** (métrica de 409 na §3 e exemplo de
    expand/contract na §6.3);
  - filas/jobs Oban — §6 → **§11** (métrica de profundidade de fila na §3);
  - Notifier Ash → PubSub → Channel — §4 → **§6** (métrica de lag de PubSub na §3);
  - contrato de erro / `source.pointer` — §3 → **§4** (política de scrubbing na §2.4);
  - `invalidate()` como fallback — §4 → **§6.2 e §8** (nota de netsplit na §5.3);
  - MinIO no dev — §7 → **§12** (cenário de VPS própria na §9);
  - `:create_with_series` — §6 → **rota na §4 e job na §11** (span de Oban na §1.1).
- **Regra de consumo de sessão corrigida na métrica de no-show (§3).** A afirmação
  anterior — "`status==='faltou'`, que debita sessão de pacote" — era incondicional e
  falsa. Verifiquei `wouldConsume` (`interface/Movimento.dc.html:1104`): falta só debita
  quando o pacote é punitivo (`pkgPunitivo`) **e** a falta não está justificada
  (`faltaJustificada`). A métrica foi renomeada para "taxa de falta punitiva" e a origem
  no domínio reflete a condição real, já que o alerta se apoia nela.
- **Proveniência do `DNSCluster` (§5.3).** A afirmação de que "o Phoenix 1.7+ já sugere
  no gerador" era comportamento de ferramenta escrito de memória; foi marcada como
  **NAO-VERIFICADO: confirmar contra a doc ao scaffoldar**.
- **Guarda de codegen na CI (§6.2) ganhou alternativa sem flag.** Mantida a Opção A
  (`mix ash.codegen --check`, ainda NAO-VERIFICADO), foi adicionada a **Opção B**,
  preferida e independente de qualquer flag: rodar `mix ash.codegen` e reprovar o job
  com `git diff --exit-code` se o working tree ficar sujo.
- **Dependência do 01-dominio-ash.md tornada explícita (§5.4 e §7.2).** As duas
  variantes de migração e de restore (`:attribute` vs. schema-por-tenant) foram
  rotuladas e passou a constar que **uma delas será descartada quando o 01 fechar a
  decisão de tenancy** — sem presumir a escolha.
