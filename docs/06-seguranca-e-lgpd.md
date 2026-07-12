# Segurança e LGPD

Este é o documento que autoriza — ou proíbe — tocar em dado real de paciente.
O protótipo (`interface/Movimento.dc.html`) foi construído para demonstrar fluxo,
não para proteger dado: ele guarda diagnóstico como texto indexável, não tem
autenticação nenhuma, e o controle de acesso é literalmente três rótulos com
texto descritivo e zero enforcement ([`:2408`](../interface/Movimento.dc.html#L2408)).
Nada disso é aceitável quando os dados deixam de ser sintéticos.

As decisões que este documento operacionaliza estão travadas em
[00-decisoes.md](00-decisoes.md), principalmente ADR-003 (multi-tenant desde já),
ADR-007 (dado de saúde é categoria especial do Art. 11) e ADR-009 (relógio
injetável). A arquitetura de onde as peças moram está em
[04-arquitetura.md](04-arquitetura.md).

**Aviso de honestidade.** Não existe ainda projeto Elixir neste repositório. Todo
trecho de código de biblioteca abaixo está marcado com
`# NAO-VERIFICADO: confirmar contra hexdocs ao scaffoldar`; a assinatura exata de
`AshCloak`, `AshPaperTrail`, `AshAuthentication` e `Ash.Policy` deve ser conferida
no momento do scaffold. Onde eu não tenho certeza da API, descrevo o comportamento
em prosa em vez de fingir código. As afirmações sobre o protótipo, essas sim, estão
verificadas por linha.

---

## 1. Inventário de dados

Toda decisão de criptografia, policy e auditoria deriva da classificação de cada
campo. Uso quatro classes:

- **público** — não identifica pessoa e não é segredo (rótulos de configuração,
  cores, nomes de tipo de atendimento).
- **PII comum** — identifica ou permite contatar uma pessoa, mas não revela saúde
  nem é credencial (nome, e-mail, telefone, endereço).
- **PII sensível (Art. 11)** — dado de saúde ou que revela condição de saúde, mais
  as demais categorias especiais do Art. 11 (o protótipo não coleta origem racial,
  convicção religiosa, filiação sindical, dado genético ou biométrico — mas coleta
  saúde em abundância).
- **segredo** — credencial ou dado financeiro cuja exposição é dano direto
  (dados bancários, PIX, tokens de sessão, chaves de cifra).

A fonte é o gerador de fixtures do protótipo, que monta o objeto `patient` entre as
linhas [`:96`](../interface/Movimento.dc.html#L96) e [`:113`](../interface/Movimento.dc.html#L113),
e o formulário de profissional em torno de [`:3130`](../interface/Movimento.dc.html#L3130).

### 1.1 Paciente

| Campo (protótipo) | Linha | Classe | Observação |
|---|---|---|---|
| `id` (`'pac'+n`) | [`:98`](../interface/Movimento.dc.html#L98) | público | Identificador interno; em produção vira UUID, nunca sequencial exposto. |
| `nome`, `nomeSocial` | [`:98`](../interface/Movimento.dc.html#L98) | PII comum | Nome social é obrigatório respeitar; nunca substituir por nome civil na UI. |
| `cpf` | [`:99`](../interface/Movimento.dc.html#L99) | PII comum | Identificador nacional. Alvo de busca ([§3](#3-criptografia-de-campo-e-o-problema-da-busca)). |
| `rg` | [`:99`](../interface/Movimento.dc.html#L99) | PII comum | |
| `genero`, `estadoCivil` | [`:100`](../interface/Movimento.dc.html#L100) | PII comum | Gênero pode revelar identidade de gênero — tratar com cuidado, mas não é saúde. |
| `nasc` (nascimento) | [`:101`](../interface/Movimento.dc.html#L101) | PII comum | Data de nascimento; compõe reidentificação. |
| `tel` | [`:102`](../interface/Movimento.dc.html#L102) | PII comum | Segundo alvo de busca ([`:999`](../interface/Movimento.dc.html#L999)). |
| `email` | [`:102`](../interface/Movimento.dc.html#L102) | PII comum | |
| `endereco`, `numero`, `complemento`, `bairro`, `cidade`, `uf`, `cep` | [`:103`](../interface/Movimento.dc.html#L103) | PII comum | Endereço residencial completo. |
| `emNome`, `emParentesco`, `emTel` | [`:104`](../interface/Movimento.dc.html#L104) | PII comum | Contato de emergência — **dado de terceiro**, tem titular próprio. |
| `resp` (responsável) | [`:105`](../interface/Movimento.dc.html#L105) | PII comum | Menor de idade ⇒ dado de responsável legal, e consentimento muda de titular. |
| `profissao`, `empresa` | [`:106`](../interface/Movimento.dc.html#L106) | PII comum | |
| `convenio`, `carteirinha`, `validade` | [`:107`](../interface/Movimento.dc.html#L107) | PII comum | Vínculo de plano de saúde: fronteiriço, mas o número de carteirinha por si só não é diagnóstico. |
| `atendTipo` | [`:107`](../interface/Movimento.dc.html#L107) | público | `particular`/`convenio`, categoria comercial. |
| **`medico`** (nome do médico encaminhador) | [`:107`](../interface/Movimento.dc.html#L107) | **PII sensível** | Encaminhamento revela que há tratamento em curso; é dado de terceiro **e** revela saúde do paciente. |
| **`crm`** | [`:107`](../interface/Movimento.dc.html#L107) | **PII sensível** | Registro do conselho do médico encaminhador; junto de `medico`, idem acima. |
| **`tags`** (diagnósticos) | [`:108`](../interface/Movimento.dc.html#L108), [`:115`](../interface/Movimento.dc.html#L115) | **PII sensível** | O caso central. Contém `'pós-op joelho'`, `'reabilitação esportiva'` ([`:115`](../interface/Movimento.dc.html#L115)), e o gerador injeta `'hérnia de disco'`, `'gestante'` etc. É diagnóstico clínico em texto livre. |
| `prefs` (profissional preferido) | [`:108`](../interface/Movimento.dc.html#L108) | PII comum | |
| `pacotes` / `sessoes` (grade, datas, estado) | [`:108`](../interface/Movimento.dc.html#L108), [`:117`](../interface/Movimento.dc.html#L117) | **PII sensível** | O histórico de sessões (`concluida`/`falta`/`feriado`) é registro de tratamento: revela adesão terapêutica e frequência de atendimento de saúde. |
| `faltas` | [`:108`](../interface/Movimento.dc.html#L108) | PII sensível | Deriva de sessões; mesma classe. |
| **`lgpd`** (consentimento) | [`:109`](../interface/Movimento.dc.html#L109), [`:2182`](../interface/Movimento.dc.html#L2182) | metadado de conformidade | Hoje é um `boolean` solto. Precisa virar registro versionado ([§2](#2-lgpd-operacional)). |
| `comunicacao` | [`:109`](../interface/Movimento.dc.html#L109), [`:2186`](../interface/Movimento.dc.html#L2186) | metadado de conformidade | Consentimento **separado** para contato por WhatsApp/e-mail; base legal distinta da de saúde. |
| `ci` (código interno?) | [`:109`](../interface/Movimento.dc.html#L109) | público | |

### 1.2 Anexos (laudos e exames)

O protótipo anexa arquivos por paciente em `addAnexos`
([`:954`](../interface/Movimento.dc.html#L954)). Cada item guarda `name`, `type`,
`size`, `url`, `date` ([`:957`](../interface/Movimento.dc.html#L957)).

- **Classe: PII sensível.** Um anexo aqui é laudo, exame de imagem, receita ou
  relatório. O conteúdo é dado de saúde bruto — a classe mais alta.
- O `url` é gerado com `URL.createObjectURL(f)` ([`:957`](../interface/Movimento.dc.html#L957)),
  que é um blob efêmero na memória da aba: não persiste, não é seguro, e não existe
  do lado do servidor. Substituição obrigatória em [§7](#7-anexos-storage-privado-e-url-assinada).
- O filtro de tipo aceita `f.type.startsWith('image/')` ou `application/pdf`
  ([`:955`](../interface/Movimento.dc.html#L955)) — mas `f.type` é o MIME que o
  **browser declara**, derivado da extensão, trivialmente falsificável. Não é
  inspeção de conteúdo real. Detalhe crítico em [§7](#7-anexos-storage-privado-e-url-assinada).

### 1.3 Fila de espera

Os itens de fila trazem `patientId`, `prio`, `profIds`, `janela`, `dias` e **`obs`**
([`:163`](../interface/Movimento.dc.html#L163)–[`:166`](../interface/Movimento.dc.html#L166)).
O campo `obs` é preenchido por um input cujo placeholder é
`"Ex.: dor aguda, encaminhamento…"` ([`:2244`](../interface/Movimento.dc.html#L2244)).

- **`obs`: PII sensível.** É queixa clínica em texto livre — "dor aguda" é sintoma,
  logo dado de saúde. Precisa da mesma proteção das `tags`.
- `prio`, `janela`, `dias`: público/operacional (urgência e preferência de horário
  não revelam condição). Mas ficam **vinculados a um paciente identificável**, então
  a linha da fila como um todo herda a sensibilidade do `patientId` + `obs`.

### 1.4 Profissional

Formulário em torno de [`:3126`](../interface/Movimento.dc.html#L3126)–[`:3139`](../interface/Movimento.dc.html#L3139).

| Campo | Linha | Classe |
|---|---|---|
| Nome, e-mail, especialidade | (cadastro) | PII comum |
| `razaoSocial`, `cnpj` (se PJ) | [`:3127`](../interface/Movimento.dc.html#L3127)–[`:3128`](../interface/Movimento.dc.html#L3128) | PII comum (dado de empresa/titular PJ) |
| **`banco`** | [`:3132`](../interface/Movimento.dc.html#L3132) | **segredo** |
| **`agencia`** | [`:3133`](../interface/Movimento.dc.html#L3133) | **segredo** |
| **`conta`** | [`:3134`](../interface/Movimento.dc.html#L3134) | **segredo** |
| **`contaTipo`** | [`:3137`](../interface/Movimento.dc.html#L3137) | segredo (compõe o dado bancário) |
| **`pix`** | [`:3138`](../interface/Movimento.dc.html#L3138) | **segredo** — a chave PIX pode ser o próprio CPF/e-mail/telefone do profissional |

Os dados bancários existem para repasse (a seção é rotulada "Dados bancários para
repasse", [`:3130`](../interface/Movimento.dc.html#L3130)). São o material mais
sensível do ponto de vista de **fraude financeira** e recebem tratamento de segredo:
cifrados, e visíveis só para `admin` ([§6](#6-authz-rbac-e-field-policies)).

### 1.5 Segredos de sistema (não estão no protótipo, nascem com o backend)

Token de sessão, `Phoenix.Token` efêmero do WebSocket, chave-mestra do `AshCloak`,
`SECRET_KEY_BASE`, credenciais do Postgres e do object storage. Todos são **segredo**,
vivem em Fly secrets ([§3.2](#32-gestao-de-chaves-e-rotacao)), nunca no repositório,
nunca em log, nunca em telemetria.

### 1.6 Agendamento em grupo (turma) — o vazamento lateral entre pacientes

O protótipo tem **atendimento em grupo** ("Novo agendamento em grupo" / "Adicionar à
turma", [`:2005`](../interface/Movimento.dc.html#L2005)). Diferente de um agendamento
individual (que carrega um único `patientId`), o agendamento de turma carrega **um array
`patientIds` de todos os participantes** e, crucialmente, **um mapa `pkgOf` que liga cada
participante ao seu pacote**: `pkgOf:{...(g.pkgOf||{}),[d.patientId]:pkId}`
([`:350`](../interface/Movimento.dc.html#L350)). Adicionar e remover gente da turma mexe
nesse mesmo objeto (`addParticipant`/`removeParticipant`,
[`:1068`](../interface/Movimento.dc.html#L1068)–[`:1069`](../interface/Movimento.dc.html#L1069)),
e o sistema lê o `pkgOf` para resolver a qual pacote debitar a sessão de cada um
([`:1113`](../interface/Movimento.dc.html#L1113)).

- **A consequência de privacidade é séria e específica deste modelo.** O registro de UM
  agendamento contém, num único objeto, os **identificadores de vários pacientes**
  (`patientIds`) **e os identificadores de pacote de cada um** (`pkgOf`). Isso significa
  que o registro operacional de um paciente — o bloco da agenda em que ele está — carrega,
  por construção, dados que apontam para **outros** pacientes da mesma turma. É um vetor
  de **vazamento lateral**: quem consegue ler o agendamento de grupo descobre *quem mais*
  está naquela turma e *que cada um tem tratamento em pacote* — e "faz fisioterapia em
  grupo no horário X" já é, sobre um terceiro identificável, informação de saúde (Art. 11).
- **Classe do `patientIds`/`pkgOf`: PII sensível.** A associação "estas pessoas fazem a
  mesma sessão de fisioterapia" revela condição de saúde de cada participante para os
  demais. O mapa não pode ser servido cru para qualquer ator que veja o agendamento.
- **Consequência de modelagem no backend.** Ao portar a turma para o Ash, os participantes
  devem ser uma relação (uma tabela de junção agendamento↔paciente, cada linha com seu
  `pkgId`), **não** um mapa embutido no registro do agendamento — para que a autorização
  possa filtrar por linha (field/row policy) em vez de tudo-ou-nada sobre um blob. As
  regras de exposição desse conjunto estão em [§6.2](#62-field-policies-quais-campos).

---

## 2. LGPD operacional

O protótipo reduz LGPD a dois checkboxes booleanos
([`:2182`](../interface/Movimento.dc.html#L2182)–[`:2187`](../interface/Movimento.dc.html#L2187)):
um autoriza "tratamento dos meus dados pessoais e dados sensíveis de saúde", outro
autoriza contato. Isso não é registro de consentimento — é um flag que não sabe
quando foi dado, sob qual texto, nem como se revoga.

### 2.1 Base legal — e por que não é "consentimento"

O ponto que mais confunde: **o tratamento de dado de saúde para prestar o cuidado
não se apoia em consentimento.** A base legal é o **Art. 11, II, alínea "a"**:
tutela da saúde, em procedimento realizado por profissionais de saúde. O prontuário,
as `tags`, os anexos e o histórico de sessões existem porque a clínica presta
assistência — não porque o paciente "clicou em concordo". Consequência prática:
revogar consentimento **não** obriga (nem permite) apagar o prontuário de um
tratamento que aconteceu; há dever legal de guarda ([§2.4](#24-retencao)).

O que **é** consentimento (Art. 7, I, ou Art. 11, I) é o **`comunicacao`**
([`:2186`](../interface/Movimento.dc.html#L2186)): contato por WhatsApp/e-mail para
lembrete e marketing terapêutico é finalidade secundária, opcional, e revogável a
qualquer momento sem afetar o cuidado. Por isso os dois flags do protótipo são
corretos em existir separados — o erro é modelá-los igual.

**Regra de schema:** cada base legal é um registro próprio. Não amontoar "aceitou
tudo" num booleano.

### 2.2 Consentimento versionado, datado, revogável

Substituir o booleano `patient.lgpd` por um recurso de consentimento. Cada registro
guarda: titular, **finalidade** (assistência / comunicação / e futuras),
**base legal** aplicada, **versão do texto** apresentado (o texto de
[`:2183`](../interface/Movimento.dc.html#L2183) é a v1 — o texto que a pessoa leu
precisa ser reconstituível), **carimbo de tempo** de concessão, **ator** que
registrou, e **revogação** (data + ator) quando ocorrer. Nunca `UPDATE` destrutivo:
uma revogação é um novo estado, o histórico permanece (isso cai naturalmente no
`AshPaperTrail`, [§4](#4-auditoria-ashpapertrail)).

```elixir
# NAO-VERIFICADO: confirmar contra hexdocs ao scaffoldar
# Esboço de recurso — a intenção, não a assinatura final.
defmodule Movimento.Compliance.Consent do
  # attributes: purpose (:assistencia | :comunicacao), legal_basis (string/atom),
  #   policy_version (string), granted_at (utc_datetime), granted_by (actor id),
  #   revoked_at (utc_datetime | nil), revoked_by, patient_id, clinic_id
  # Regra: revogar é uma ação :revoke que seta revoked_at, jamais um delete.
end
```

O relógio dessas datas obedece ao ADR-009 ([`hoje()` do protótipo é fixo em
`'2026-06-25'`, `:1098`](../interface/Movimento.dc.html#L1098)): o `granted_at` sai
do relógio injetado no `Ash.Scope`, resolvido no timezone da clínica, não do servidor.

### 2.3 Finalidade

Cada tratamento tem finalidade declarada e o dado não pode ser usado além dela.
Consequência de engenharia: a finalidade "comunicação" **não** habilita mandar
marketing para quem só consentiu assistência. Isso vira um check de policy antes de
qualquer job de lembrete/WhatsApp (o protótipo tem botão fake de confirmação; o job
real, listado em [04-arquitetura.md §11](04-arquitetura.md), consulta o consentimento
de comunicação antes de disparar).

### 2.4 Retenção

Prontuário de saúde tem prazo legal de guarda, e esse prazo **não é um número que
possamos inventar aqui**. A norma mais citada para prontuário — **CFM Res. 1.821/2007** —
trata do prontuário **médico** e estabelece guarda por prazo longo; mas **fisioterapia é
regulada pelo COFFITO, não pelo CFM**, então nem a norma nem o prazo dessa resolução se
aplicam automaticamente a esta clínica. A norma e o prazo aplicáveis (resolução do
COFFITO pertinente e o que a LGPD e a legislação de saúde exigem) **precisam ser
confirmados com o jurídico antes de configurar qualquer purga** — não hardcodar prazo
até lá. Independentemente do número exato:

- A **purga LGPD** listada como job Oban em [04-arquitetura.md §11](04-arquitetura.md)
  não pode apagar prontuário dentro do prazo de guarda, mesmo a pedido — o direito de
  eliminação cede ao dever legal de conservação (Art. 16, I).
- Dados sob **consentimento revogável** (comunicação) são elimináveis assim que a
  finalidade se encerra ou o consentimento é revogado.
- O que a purga faz no prazo é **anonimizar/minimizar** o que não precisa mais
  identificar, e eliminar o que não tem base de retenção.

### 2.5 Direitos do titular — o que cada um exige do schema e do endpoint

| Direito (Art. 18) | Exige do schema | Endpoint |
|---|---|---|
| **Acesso** / confirmação | Poder reunir tudo de um titular, incluindo consentimentos e anexos | `GET /api/patients/:id/dossier` — agrega dados + histórico + anexos (URLs assinadas), gera export; **é acesso a dado de saúde, logo auditado** ([§4](#4-auditoria-ashpapertrail)). |
| **Correção** | Campos editáveis com trilha de quem corrigiu | Ações de update já existentes, com `AshPaperTrail` registrando antes/depois. |
| **Portabilidade** | Export em formato estruturado e interoperável (JSON/CSV) | Mesma agregação do dossiê, formato legível por máquina. |
| **Eliminação** | Distinguir dado eliminável de dado sob guarda legal | Ação `:request_erasure` que cria uma solicitação, roteia para revisão (não apaga prontuário sob prazo), e elimina o elegível. Nunca um `DELETE` cego. |

O direito de acesso e portabilidade compartilham a mesma consulta agregadora — DRY:
um `Movimento.Compliance.Dossier` monta a visão completa, e os dois endpoints só
diferem no serializador de saída.

---

## 3. Criptografia de campo e o problema da busca

### 3.1 O que cifrar

Cifra em nível de campo com `AshCloak` (ADR-007, item 1). A lista mínima, derivada
do inventário:

- **Paciente:** `tags`, `medico`, `crm`, e o histórico de `sessoes`/`pacotes`
  enquanto revela tratamento. `cpf` e `tel` são caso especial ([§3.3](#33-o-conflito-real-busca-por-cpf-e-telefone)).
- **Anexos:** metadado sensível cifrado; o **conteúdo** do arquivo é cifrado no
  storage ([§7](#7-anexos-storage-privado-e-url-assinada)).
- **Fila:** `obs`.
- **Profissional:** `banco`, `agencia`, `conta`, `contaTipo`, `pix`, `cnpj`.

```elixir
# NAO-VERIFICADO: confirmar contra hexdocs ao scaffoldar
# AshCloak é uma extensão de recurso; a forma exata do bloco muda entre versões.
defmodule Movimento.Clinical.Patient do
  # use Ash.Resource, extensions: [AshCloak]
  # cloak do
  #   vault Movimento.Vault
  #   attributes [:tags, :medico, :crm]
  # end
end
```

O que a cifra de campo **quebra** é o motivo de este parágrafo existir: um campo
cifrado no banco vira bytes opacos. **Não dá para `WHERE tags ILIKE '%hérnia%'`,
não dá para `ORDER BY`, não dá para índice B-tree útil.** Isso é aceitável para
`tags`, `obs` e dados bancários (ninguém ordena a agenda por diagnóstico nem busca
paciente por conta bancária). É inaceitável para os campos pelos quais o sistema
**busca**.

### 3.2 Gestão de chaves e rotação

- A chave-mestra do vault do `AshCloak` vive em **Fly secrets** (variável de ambiente
  injetada no runtime), nunca no repositório nem em imagem de container. Sem KMS
  dedicado na v1: Fly secrets é o cofre. Reavaliar KMS (AWS KMS / GCP KMS) se um
  requisito de jurisdição ou de separação de custódia surgir — a decisão fica
  registrada aqui como consciente, não esquecida.
- **Rotação — requisito, não afirmação de biblioteca.** Precisamos de um esquema de
  cifra que suporte **rotação com múltiplas chaves**: uma chave **primária** para
  escrita e as **antigas** ainda disponíveis para leitura do legado, de modo que
  rotacionar seja adicionar a chave nova como primária, manter as velhas só para
  decifrar, e reencriptar em lote por um job Oban. **Confirmar se o `AshCloak` (ou o
  `Cloak` por baixo) atende a esse requisito e qual a forma de configurar o conjunto de
  chaves — `# NAO-VERIFICADO`.** Rotação planejada anual, e imediata se houver suspeita
  de vazamento de chave.
- A chave-mestra **nunca** entra em log nem telemetria. O coletor OTel (ADR-008)
  recebe métrica e trace, jamais o valor de campo cifrado nem a chave.

### 3.3 O conflito real: busca por CPF e telefone

O protótipo busca paciente por documento em `byDoc`
([`:999`](../interface/Movimento.dc.html#L999)): compara os dígitos do termo contra
`p.cpf` e `p.tel`, ambos limpos de máscara. É uma varredura em memória sobre a lista
local — trivial no protótipo, impossível se `cpf` estiver cifrado no banco.

Esta é uma decisão de arquitetura, não um detalhe de implementação. As opções:

1. **Deixar `cpf`/`tel` em claro.** Rejeitado: são PII, e CPF em claro num banco
   multi-tenant é exatamente o que um vazamento explora.
2. **Cifrar e buscar decifrando tudo em memória.** Rejeitado: não escala, e obriga
   decifrar a base inteira a cada busca — o oposto de minimização.
3. **Blind index / HMAC determinístico.** **Escolhido.** Guarda-se, ao lado do campo
   cifrado, um **hash HMAC-SHA256 determinístico** do valor normalizado (dígitos, sem
   máscara — a mesma normalização que `byDoc` faz com `replace(/\D/g,'')`,
   [`:999`](../interface/Movimento.dc.html#L999)). A busca vira igualdade exata sobre
   o hash: `WHERE cpf_hash = hmac(:cpf_normalizado)`, indexável, rápida, e o valor
   original nunca aparece na query.

```elixir
# NAO-VERIFICADO: confirmar contra hexdocs ao scaffoldar
# Blind index: atributo cifrado + coluna hash determinística para lookup exato.
# cloak do
#   attributes [:cpf, :tel]     # armazenamento cifrado
# end
# calculate :cpf_hash, :binary, expr(...)   # HMAC(normalize(cpf)) — coluna indexada
# read :by_document do
#   argument :digits, :string
#   filter expr(cpf_hash == ^hmac(normalize(arg(:digits))) or
#               tel_hash == ^hmac(normalize(arg(:digits))))
# end
```

Limitações honestas do blind index, para ninguém se surpreender depois:

- Só faz **igualdade exata**. O `byDoc` do protótipo usa `includes` (substring,
  [`:999`](../interface/Movimento.dc.html#L999)) — busca por "pedaço do telefone" não
  sobrevive à cifra. Isto é uma perda de funcionalidade **deliberada e correta**:
  busca por prontuário de saúde por substring de documento é um vetor de varredura.
  Buscar por CPF completo e telefone completo é o requisito real da recepção.
- A chave do HMAC é um segredo separado da chave de cifra (Fly secrets), e sua
  rotação obriga recomputar todos os hashes — mesmo job de reencriptação de [§3.2](#32-gestao-de-chaves-e-rotacao).
- HMAC determinístico vaza **igualdade**: dá para saber que dois registros têm o
  mesmo CPF sem decifrar. Aceitável — é justamente o que precisamos para deduplicar
  paciente. Não usar essa técnica em campo de altíssima cardinalidade-sensível onde
  "são iguais" já é informação proibida.
- Busca por **nome** (`byName`, [`:998`](../interface/Movimento.dc.html#L998)) fica em
  claro: nome é PII comum, não sensível, e precisa de busca por prefixo/substring. Ele
  não é cifrado ([§3.1](#31-o-que-cifrar) não lista `nome`), então o `ILIKE` continua
  possível.

---

## 4. Auditoria (AshPaperTrail)

Acesso a dado de saúde é auditável — **não só a escrita, a leitura também.** Um
prontuário aberto sem necessidade assistencial é um incidente, e só dá para detectar
se a leitura deixou rastro.

**Eventos que geram registro de auditoria:**

- **Escrita** de qualquer campo sensível: criar/editar paciente, adicionar/remover
  `tags`, subir/remover anexo ([`:954`](../interface/Movimento.dc.html#L954),
  [`:961`](../interface/Movimento.dc.html#L961)), editar `obs` da fila, alterar dados
  bancários do profissional. `AshPaperTrail` registra o **diff antes/depois**.
- **Leitura de prontuário:** abrir a ficha completa de um paciente, gerar o dossiê de
  acesso ([§2.5](#25-direitos-do-titular--o-que-cada-um-exige-do-schema-e-do-endpoint)),
  **baixar um anexo** (a emissão da URL assinada, [§7](#7-anexos-storage-privado-e-url-assinada)).
  Leitura não muda estado, então não é `AshPaperTrail` clássico — é um log de acesso
  explícito, gravado pela própria ação de leitura (uma ação `read` que, num hook
  `after_action`, emite o registro de acesso).
- **Consentimento:** concessão e revogação ([§2.2](#22-consentimento-versionado-datado-revogavel)).
- **Autorização negada:** toda vez que uma policy bloqueia acesso a dado sensível
  (tentativa de ver prontuário de outra clínica, membro tentando ver dado bancário) —
  isso alimenta detecção de abuso, [§8](#8-owasp-aplicado-a-este-sistema).

**Cada registro responde quatro perguntas:** *quem* (ator, resolvido da sessão, nunca
do corpo da requisição), *quando* (relógio injetado, ADR-009), *o quê* (recurso, id,
campos tocados — e no diff, os valores antes/depois), *por quê* (motivo/base: qual
ação de negócio, e em acessos sensíveis um campo de justificativa quando aplicável).

```elixir
# NAO-VERIFICADO: confirmar contra hexdocs ao scaffoldar
# AshPaperTrail cria um recurso de versões por recurso auditado.
# use Ash.Resource, extensions: [AshPaperTrail.Resource]
# paper_trail do
#   change_tracking_mode :full_diff
#   store_action_name? true
#   # o "quem" vem do actor no Ash.Scope; o "quando" do relógio injetado
# end
```

**Cuidado que anula o esforço:** o diff do `AshPaperTrail` sobre um campo cifrado não
pode guardar o valor em claro, senão a trilha de auditoria vira a maior fuga de dado
do sistema. O que se audita de um campo sensível é *que mudou* e *quem mudou*, não
necessariamente *para qual valor em claro*. Confirmar no scaffold como o PaperTrail
interage com o Cloak (provavelmente guardando a forma cifrada ou redigida) —
`# NAO-VERIFICADO`.

A trilha é **append-only** e tem retenção própria, longa (é registro de conformidade),
e ela mesma é dado sensível: só `admin` lê o log de auditoria.

---

## 5. Autenticação (AuthN)

Hoje não existe. `saveMembro` ([`:2497`](../interface/Movimento.dc.html#L2497)) só
muda o estado local; o "convite" é um `input type="email"`
([`:2485`](../interface/Movimento.dc.html#L2485)) que não manda e-mail nenhum.

**`AshAuthentication`** provê o backend. **Sem senha** (ADR-015): as estratégias da v1 são
**Google OAuth** e **Magic Link**. Decisões concretas, alinhadas com
[04-arquitetura.md §5](04-arquitetura.md):

- **Duas estratégias, zero senha (ADR-015):** `oauth2`/`google` e `magic_link`. Não há
  `hashed_password`, reset de senha, política de senha nem verificação contra listas de
  vazamento — toda essa superfície **sai** da v1. Google delega 2FA à conta Google; magic
  link é fator de **posse** do e-mail.
- **Sessão por cookie** `HttpOnly`, `Secure`, `SameSite=Lax`. `HttpOnly` para o JS
  nunca ler o token (defesa contra XSS roubar sessão); `Secure` para só trafegar em
  HTTPS; `SameSite=Lax` como base anti-CSRF ([§8](#8-owasp-aplicado-a-este-sistema)).
- **BFF porta o cookie:** o SvelteKit (`adapter-node`, ADR-005) repassa o cookie de
  sessão nas chamadas server-to-server à API. O browser nunca vê um token de API de
  longa duração.
- **Tenant ativo na sessão (ADR-014):** a sessão guarda qual clínica está ativa; `actor.papel`
  e `actor.professional_id` derivam do `Membership` ativo. Trocar de clínica troca o membership
  ativo (ver [09 §8](09-contrato-api.md)) — nunca por `clinic_id` vindo do cliente.
- **WebSocket com token efêmero:** o BFF emite um `Phoenix.Token` de vida curta
  (minutos) entregue ao cliente no `load`, usado só para abrir o Channel. Carrega o tenant
  **ativo**; o cookie de sessão não vai para o JS ([04-arquitetura.md §5](04-arquitetura.md)).
- **Convite de membro por magic link (ADR-015):** substitui o `saveMembro` fake. Fluxo real:
  criar **`Membership` pendente** → enviar **magic link de uso único, com expiração** (ex.: 72 h)
  → primeiro acesso (magic link ou Google) **vincula/cria o `User`** e ativa o vínculo, com o
  papel e (se `profissional`) o registro da agenda escolhido no formulário
  ([`:2489`](../interface/Movimento.dc.html#L2489)–[`:2493`](../interface/Movimento.dc.html#L2493)).
  Convite expirado ou já usado é rejeitado.
- **MFA — opcional na v1 (revisado por ADR-015).** Sem senha, o app não gerencia segundo
  fator: contas Google trazem seu próprio 2FA e o magic link já é posse. TOTP no app fica como
  reforço **opcional** (não obrigatório) — a exigência de MFA-para-admin do texto anterior cai.
- Sessão com **expiração absoluta e por inatividade**; bloqueio progressivo de reenvio de
  magic link por e-mail/IP (anti-abuso), no lugar do antigo bloqueio por tentativa de senha.

```elixir
# NAO-VERIFICADO: confirmar contra hexdocs ao scaffoldar (ADR-015 — sem password)
# authentication do
#   strategies do
#     magic_link :magic_link do ... identity_field :email ... end
#     oauth2 :google do ... end
#   end
#   tokens do enabled? true; ... end
# end
# Convite = magic link para um Membership pendente. Sem estratégia :password.
```

---

## 6. AuthZ: RBAC e field policies

Este é o buraco mais gritante do protótipo. `roleMeta`
([`:2408`](../interface/Movimento.dc.html#L2408)) define os papéis como **texto
descritivo puro**, sem nenhum enforcement. Viram **4 perfis fixos com capabilities
embarcadas** (ADR-016), do mais forte ao mais fraco:

- **`owner`** (novo, modelo Vercel) — a dona: tudo, **mais** faturamento, exclusão/renome da
  clínica e gestão de owners. Todo tenant tem **≥1 owner** ([§8](#8-owasp-aplicado-a-este-sistema)).
- `admin` — "Acesso total — configurações, equipe, todas as agendas e relatórios"
  ([`:2411`](../interface/Movimento.dc.html#L2411)); gerencia membros **exceto owners**; **não**
  toca faturamento nem exclui a clínica.
- `profissional` — "Gerencia a própria agenda e seus pacientes"
  ([`:2412`](../interface/Movimento.dc.html#L2412));
- `recepcao` (o `membro` do protótipo) — "Opera a agenda de todos, sem configurações sensíveis"
  ([`:2413`](../interface/Movimento.dc.html#L2413)).

São `label`/`desc`/`ícone`. Nada no protótipo impede um `membro` de fazer o que um
`admin` faz — porque não há servidor. O texto vira contrato de policy real no Ash, com o mapa
papel→capabilities fixo em código (`Movimento.Accounts.Capabilities`, [01 §3](01-dominio-ash.md)).

### 6.1 Policies de recurso (quem pode a ação)

`Ash.Policy.Authorizer` em todo recurso sensível. Padrão-base: **tenant primeiro,
papel depois.** O tenant é a coluna **`clinic_id`** (`strategy :attribute`, [ADR-017](00-decisoes.md)):
o Ash injeta `WHERE clinic_id = <tenant ativo>` e **exige** o tenant nos recursos por-atributo
(ler sem tenant é `Ash.Error.Invalid`, não um vazamento). O tenant ativo vem do `Membership`
da sessão (ADR-014), **nunca** de `clinic_id` do cliente. `owner` e `admin` são bypass
**dentro da própria clínica**, jamais global.

> **⚠️ Isolamento lógico (ADR-017), imposto no banco por RLS (ADR-018).** Sem schema-por-tenant,
> a garantia **não** fica só no filtro do Ash: cada tabela por-tenant tem **Row-Level Security**
> por `clinic_id`, e o app conecta como um role `NOSUPERUSER`/`NOBYPASSRLS`. Assim uma query crua
> (`Repo`/`Ecto`), um `authorize?: false` sem tenant ou um bug de filtro **não vaza** — o Postgres
> só devolve linhas do `clinic_id` da GUC `movimento.clinic_id` (sem GUC → 0 linhas, fail-closed).
> O tenant entra por `Api.Repo.with_clinic/2` no plug de scope (ADR-014). O **teste de IDOR no CI**
> conecta como o role restrito e prova que cross-tenant não alcança nada (ver [ADR-018](00-decisoes.md)
> e o checklist de §8). Migrations rodam como `postgres` (bypassa RLS para DDL).

```elixir
# NAO-VERIFICADO: confirmar contra hexdocs ao scaffoldar
# policies do
#   # owner/admin da PRÓPRIA clínica (clinic_id do escopo) podem tudo dentro dela
#   bypass actor_attribute_in(:papel, [:owner, :admin]) do
#     authorize_if always()   # tenant (clinic_id) já filtrado pelo Ash (:attribute)
#   end
#
#   policy action_type(:read) do
#     authorize_if actor_attribute_equals(:papel, :recepcao)  # agenda de todos
#     authorize_if MovimentoChecks.OwnScope                   # profissional: só o próprio
#   end
# end
# Capabilities exclusivas de owner (faturamento, delete_clinic, manage_owners): policy própria.
```

A regra "profissional vê só a própria agenda e seus pacientes"
([`:2412`](../interface/Movimento.dc.html#L2412)) é um **FilterCheck**, não um
SimpleCheck: não é "pode ou não pode ler agendamentos", é "lê **apenas** os
agendamentos onde ele é o profissional, e os pacientes que têm sessão com ele". Um
FilterCheck devolve um filtro que o Ash injeta na query, então o profissional
literalmente não consegue nomear o id de um paciente que não é dele — o dado não
existe na resposta.

```elixir
# NAO-VERIFICADO: confirmar contra hexdocs ao scaffoldar
defmodule Movimento.Checks.OwnPatients do
  # use Ash.Policy.FilterCheck
  # def filter(actor, _authorizer, _opts) do
  #   # paciente é "meu" se existe agendamento/sessão com este profissional
  #   expr(exists(appointments, professional_id == ^actor.professional_id))
  # end
end
```

`membro` "opera a agenda de todos" ([`:2413`](../interface/Movimento.dc.html#L2413)):
lê e mexe em agendamento de qualquer profissional **da sua clínica**, mas não vê
"configurações sensíveis" — o que se traduz em field policies ([§6.2](#62-field-policies-quais-campos)),
não em bloqueio de recurso inteiro.

### 6.2 Field policies (quais campos)

`field_policies` do Ash restringem leitura campo a campo, mesmo quando o recurso é
legível. As regras que o inventário exige:

- **Dados bancários do profissional** (`banco`, `agencia`, `conta`, `pix`,
  [`:3132`](../interface/Movimento.dc.html#L3132)–[`:3138`](../interface/Movimento.dc.html#L3138)):
  **só `admin`.** Nem `membro` nem o próprio `profissional` de outra pessoa veem. (O
  profissional pode ver os próprios dados numa tela de "meu perfil", que é escopo
  dele, não do RBAC de equipe.)
- **`tags` clínicas e anexos** do paciente
  ([`:108`](../interface/Movimento.dc.html#L108), [`:954`](../interface/Movimento.dc.html#L954)):
  **`admin` + o `profissional` vinculado ao paciente.** Um `membro` de recepção agenda
  e remarca sem precisar ler o diagnóstico — ele vê que há sessão às 8h, não que é
  "pós-op joelho". Um profissional que não atende aquele paciente também não vê. Isto é
  minimização real: a recepção opera a agenda sem acessar dado de saúde.
- **`obs` da fila** ([`:163`](../interface/Movimento.dc.html#L163)): mesma regra das
  `tags` — é queixa clínica.
- **`medico`/`crm`** ([`:107`](../interface/Movimento.dc.html#L107)): mesma regra das
  `tags`.
- **Participantes da turma (`patientIds`/`pkgOf` do agendamento de grupo,
  [§1.6](#16-agendamento-em-grupo-turma--o-vazamento-lateral-entre-pacientes),
  [`:350`](../interface/Movimento.dc.html#L350)):** este é o caso que a modelagem tem de
  resolver por **row policy**, não por field policy sobre um blob. Cada participante vira
  uma linha da junção agendamento↔paciente; a autorização de leitura dessas linhas segue a
  mesma regra das `tags` (**`admin` + o `profissional` vinculado àquele paciente**), de
  modo que um `membro` de recepção veja *que existe uma turma às 8h com N vagas* — a
  contagem operacional — mas **não** a lista nominal dos participantes nem o `pkgId` de
  cada um. Assim o registro de um paciente para de carregar, em claro, os identificadores
  dos demais: o vetor de vazamento lateral da [§1.6](#16-agendamento-em-grupo-turma--o-vazamento-lateral-entre-pacientes)
  fecha na policy, não na esperança de que ninguém leia o mapa.

```elixir
# NAO-VERIFICADO: confirmar contra hexdocs ao scaffoldar
# field_policies do
#   field_policy [:banco, :agencia, :conta, :pix, :cnpj] do
#     authorize_if actor_attribute_equals(:role, :admin)
#   end
#   field_policy [:tags, :medico, :crm] do
#     authorize_if actor_attribute_equals(:role, :admin)
#     authorize_if MovimentoChecks.IsLinkedProfessional
#   end
#   field_policy :* do authorize_if always() end
# end
#
# Turma: NÃO expor um mapa pkgOf embutido. Modelar participantes como recurso
# de junção (appointment_participants) com policy de LEITURA por linha:
#   policy action_type(:read) do
#     authorize_if actor_attribute_equals(:role, :admin)   # dentro da própria clínica
#     authorize_if MovimentoChecks.IsLinkedProfessional    # profissional vinculado ao paciente da linha
#   end
# A recepção lê só a contagem/ocupação da turma, nunca a lista nominal + pkgId.
```

Lembrar da armadilha documentada em `.claude/rules/ash.md`: numa policy, **o primeiro
check que decide vence** — encadear dois `authorize_if` é lógica **OU**, não **E**.
Para exigir "admin **E** dono", usar `forbid_unless` na condição obrigatória seguido
de `authorize_if` na final. Onde eu escrevi dois `authorize_if` acima (admin OU
profissional vinculado), a intenção é mesmo OU — está correto. Onde a regra for
conjuntiva, reescrever com `forbid_unless`.

### 6.3 O ator carrega a clínica, sempre

`actor.professional_id`, `actor.role` e `actor.clinic_id` vêm da sessão resolvida no
`Ash.Scope`. O corpo da requisição **nunca** informa papel nem clínica. Isto liga
diretamente ao [§8](#8-owasp-aplicado-a-este-sistema).

---

## 7. Anexos: storage privado e URL assinada

O protótipo aceita `image/*` e `application/pdf`
([`:955`](../interface/Movimento.dc.html#L955)) e serve o arquivo por um blob efêmero
`URL.createObjectURL` ([`:957`](../interface/Movimento.dc.html#L957)) que só existe na
aba aberta. Produção precisa do oposto: persistente, privado, verificado.

1. **Storage privado, nunca público.** Object storage compatível com S3 (Tigris/R2,
   ADR-008), bucket **privado**. Nada de URL pública, nada de "security through
   obscurity" de nome aleatório. O conteúdo é cifrado no repouso (cifra do storage
   e/ou envelope com a chave do sistema).
2. **URL assinada de vida curta.** O download passa por uma ação da API que (a) checa
   a field policy do anexo ([§6.2](#62-field-policies-quais-campos)), (b) registra o
   acesso na auditoria ([§4](#4-auditoria-ashpapertrail)), (c) gera uma **pre-signed
   URL** válida por poucos minutos. A URL nunca é armazenada; é gerada sob demanda a
   cada acesso autorizado.
3. **Upload não confia na extensão.** O `f.type` do browser
   ([`:955`](../interface/Movimento.dc.html#L955)) é declarado pelo cliente e
   falsificável. O servidor faz **sniffing de content-type real** (magic bytes) e
   valida contra uma allowlist (`application/pdf`, `image/png`, `image/jpeg`),
   rejeitando o resto — um `.pdf` que na verdade é executável não entra.
4. **Antivírus.** Todo upload passa por varredura antivírus (ex.: ClamAV como serviço,
   ou o scanner do provedor de storage) **antes** de ficar disponível para download. O
   anexo entra em estado `pendente` e só vira `disponível` após varredura limpa.
5. **Limite de tamanho** por arquivo e por paciente, validado no servidor (o protótipo
   só formata bytes para exibição em `fmtBytes`,
   [`:953`](../interface/Movimento.dc.html#L953), sem impor teto).
6. **Content-Disposition e sandbox de visualização.** Servir anexo com
   `Content-Disposition: attachment` e sem permitir execução inline no contexto do app,
   para um PDF/imagem maliciosa não rodar script no domínio autenticado.

O processamento pesado (antivírus, sniffing, cifra) roda em job Oban, coerente com o
padrão de [04-arquitetura.md §11](04-arquitetura.md).

---

## 8. OWASP aplicado a este sistema

Concreto, não genérico. A ordem reflete o risco **deste** produto.

**A01 — Broken Access Control / IDOR entre clínicas (risco #1).** Dado o ADR-003
(multi-tenant), o pior caso é a clínica A ler o prontuário da clínica B trocando um id
na URL. **Defesa inegociável: o tenant nunca vem do cliente.** Ele é resolvido da
sessão no `Ash.Scope` ([04-arquitetura.md §4](04-arquitetura.md): "um `clinic_id` no
corpo da requisição é ignorado ou rejeitado, jamais confiado"). Toda policy filtra por
clínica **antes** de qualquer outra regra ([§6.1](#61-policies-de-recurso-quem-pode-a-acao)).
Ids são UUID, não sequenciais, para não convidar à enumeração. Um acesso negado por
tenant é logado como possível abuso ([§4](#4-auditoria-ashpapertrail)).

**A02 — Cryptographic Failures.** Dado de saúde e bancário cifrado em campo
([§3](#3-criptografia-de-campo-e-o-problema-da-busca)); TLS obrigatório em trânsito
(cookie `Secure`); chave em Fly secrets, fora do repositório
([§3.2](#32-gestao-de-chaves-e-rotacao)); blind index para não sacrificar cifra em
nome de busca.

**A03 — Injection.** Ash gera queries parametrizadas; não construir SQL por
interpolação. O maior vetor de injeção **não-óbvio** aqui é o **texto livre** —
`tags`, `obs` ([`:2244`](../interface/Movimento.dc.html#L2244)), nome — renderizado na
UI: Svelte escapa por padrão, mas qualquer `{@html}` sobre dado de paciente é proibido
(XSS via diagnóstico).

**A04 — Insecure Design.** Segurança é critério de aceitação por fatia, não fase
(ADR-007). Este documento é o design; [§9](#9-checklist-de-aceitacao-e-bloqueantes) é o
gate.

**A05 — Security Misconfiguration.** Cabeçalhos de segurança no BFF e na API
(HSTS, CSP restritiva, `X-Content-Type-Options: nosniff`, `X-Frame-Options`/frame
sandbox); erro de produção não vaza stacktrace nem SQL; bucket de anexos privado por
padrão ([§7](#7-anexos-storage-privado-e-url-assinada)); telemetria OTel sem dado
sensível ([§3.2](#32-gestao-de-chaves-e-rotacao)).

**A07 — Identification & Authentication Failures.** Cobertos em
[§5](#5-autenticacao-authn): sem senha (Google OAuth + magic link, ADR-015), convite/magic
link de uso único com expiração, sessão `HttpOnly`/`Secure`, token efêmero de WS, anti-abuso
de reenvio de link.

**A08 — Software & Data Integrity.** Locking otimista em remarcação e exclusion
constraint de agenda ([04-arquitetura.md §7](04-arquitetura.md)) protegem integridade
de dado concorrente; dependências travadas e auditadas (mix.lock, `mix deps.audit`).

**A09 — Logging & Monitoring Failures.** Prontuário é auditado na **escrita** (diff via
`AshPaperTrail`) **e na leitura** (log de acesso explícito emitido pela própria ação de
leitura num hook `after_action` — **não** é `AshPaperTrail`, que só rastreia mutação),
como detalhado em [§4](#4-auditoria-ashpapertrail); acessos negados alimentam alerta; log
nunca contém campo sensível nem chave.

**A10 — SSRF.** Vetor entra se algum dia buscarmos anexo por URL fornecida pelo
usuário, ou integrarmos convênio externo. Hoje não existe; **manter assim** — anexo é
upload direto, não fetch de URL. Se surgir, allowlist de destino.

**CSRF** (fora do top-10 nominal, mas concreto aqui): o BFF é quem muta via form
actions com cookie `SameSite=Lax`; toda mutação exige token anti-CSRF do SvelteKit, e
a API só aceita mutação com a sessão válida, nunca por GET.

---

## 9. Checklist de aceitação e bloqueantes

O princípio (ADR-007): **segurança é critério de aceitação de cada fatia que toca
prontuário, não um épico separado no fim.** Abaixo, o que cada fatia precisa provar, e
o que é **BLOQUEANTE** — a linha vermelha antes de qualquer dado real de paciente
entrar no sistema.

### 9.1 Bloqueantes absolutos (nada de dado real sem isto)

- [ ] **Tenant resolvido só da sessão.** Existe teste que prova que injetar
  `clinic_id` no corpo/URL não vaza dado de outra clínica (A01/IDOR).
- [ ] **AuthN real ligada.** Sessão `HttpOnly`/`Secure`/`SameSite`, login por Google OAuth
  + magic link (sem senha, ADR-015), sem rota anônima que leia prontuário ([§5](#5-autenticacao-authn)).
- [ ] **RBAC com enforcement**, não rótulo. Policies e FilterChecks de
  [§6](#6-authz-rbac-e-field-policies) ativas; teste prova que `profissional` não lê
  paciente alheio e que `membro` não lê `tags`/anexos/dado bancário.
- [ ] **Campos sensíveis cifrados** ([§3.1](#31-o-que-cifrar)) e busca por CPF/telefone
  funcionando via blind index ([§3.3](#33-o-conflito-real-busca-por-cpf-e-telefone)).
- [ ] **Anexos em storage privado** com URL assinada curta, sniffing de content-type e
  antivírus ([§7](#7-anexos-storage-privado-e-url-assinada)) — sem `URL.createObjectURL`
  ([`:957`](../interface/Movimento.dc.html#L957)) em lugar nenhum do caminho persistente.
- [ ] **Auditoria de leitura e escrita** de prontuário ativa
  ([§4](#4-auditoria-ashpapertrail)), sem valor sensível em claro no diff.
- [ ] **Consentimento versionado/datado** substituindo o booleano `patient.lgpd`
  ([`:2182`](../interface/Movimento.dc.html#L2182)), com base legal registrada
  ([§2](#2-lgpd-operacional)).
- [ ] **Chaves fora do repositório** (Fly secrets), TLS obrigatório, nenhum segredo em
  log/telemetria.
- [ ] **Região `gru` confirmada** para API, Postgres e réplica (ADR-008): dado de
  titular brasileiro não sai da jurisdição sem decisão explícita.

### 9.2 Por fatia de entrega

- **Fatia "cadastro de paciente":** field policies de `tags`/`medico`/`crm`;
  auditoria de escrita; consentimento versionado; cifra dos campos sensíveis.
- **Fatia "agenda":** `membro` opera sem ver diagnóstico (field policy); tenant nunca
  do cliente; auditoria de quem remarcou o quê.
- **Fatia "busca de paciente":** blind index de CPF/telefone; busca por nome não vaza
  entre clínicas; rate limit na busca (anti-enumeração).
- **Fatia "anexos":** os seis itens de [§7](#7-anexos-storage-privado-e-url-assinada),
  todos; download é evento auditado.
- **Fatia "equipe & acessos":** convite real por magic link expirável
  ([§5](#5-autenticacao-authn)); troca de tenant estilo Vercel (ADR-014); ≥1 owner por tenant
  (ADR-016); papel definido no servidor a partir do `Membership` ativo, nunca aceito do cliente.
- **Fatia "profissional/repasse":** dados bancários cifrados e restritos a `admin`
  (field policy de [§6.2](#62-field-policies-quais-campos)).
- **Fatia "direitos do titular":** dossiê de acesso/portabilidade e fluxo de
  eliminação que respeita a guarda legal de prontuário
  ([§2.4](#24-retencao)–[§2.5](#25-direitos-do-titular--o-que-cada-um-exige-do-schema-e-do-endpoint)).

### 9.3 Contínuo (todo deploy)

- [ ] `mix deps.audit` / dependências sem CVE conhecida (A06).
- [ ] Cabeçalhos de segurança e CSP verificados (A05).
- [ ] Testes de policy verdes — uma policy que regride é build quebrado, não warning.
- [ ] Nenhum `# NAO-VERIFICADO` deste documento sobreviveu ao scaffold sem ser
  confirmado contra hexdocs.

---

## Correções desta revisão

Auditoria adversarial deste documento. As 56 citações de linha do protótipo foram
reconferidas e permanecem corretas; os defeitos eram outros. O que mudou e por quê:

**Cinco referências de seção ao 04-arquitetura.md — corrigidas após a renumeração
daquele documento.** O 04 foi renumerado e este documento apontava para os números
antigos. Corrigido: **Autenticação** era citada como §3, agora **§5** (dois pontos: a
introdução da §5 deste doc e a nota do WebSocket); **"o tenant nunca vem do cliente"** era
§3, agora **§4** (é onde o 04 traz a frase citada, "um `clinic_id` no corpo da requisição
é ignorado ou rejeitado, jamais confiado"); **concorrência** era §5, agora **§7**;
**jobs Oban** era §6, agora **§11** (três ocorrências: job de lembrete/WhatsApp, purga
LGPD e processamento de anexos); **ambientes** era §7, agora **§12**. O resumo de
referências cruzadas ao final foi reescrito com os cinco números certos.

**Afirmação de biblioteca sem marcador — a rotação de chaves do Cloak
([§3.2](#32-gestao-de-chaves-e-rotacao)).** O texto afirmava, em prosa fora de bloco
marcado, que "o Cloak suporta múltiplas chaves (primária para escrita, antigas para
leitura)". Reescrito como **requisito** ("precisamos de um esquema de cifra que suporte
rotação com leitura de chaves antigas; confirmar se o `AshCloak`/`Cloak` atende"), com
`# NAO-VERIFICADO` embutido — deixamos de afirmar comportamento de biblioteca que não
pudemos conferir contra o hexdocs.

**Contradição interna sobre auditoria de leitura — resolvida
([§8/A09](#8-owasp-aplicado-a-este-sistema) vs. [§4](#4-auditoria-ashpapertrail)).** O
A09 dizia que "`AshPaperTrail` cobre escrita **e** leitura de prontuário", mas a §4 é
explícita em que **leitura não é `AshPaperTrail`** (que só rastreia mutação) e sim um log
de acesso custom emitido num hook `after_action`. O A09 foi reescrito para dizer
exatamente isso: escrita via `AshPaperTrail`, leitura via log de acesso explícito. As
duas seções agora concordam.

**Prazo de retenção sem fonte confiável — corrigido ([§2.4](#24-retencao)).** O texto
cravava "tipicamente 20 anos do último registro (CFM Res. 1.821/2007)" para fisioterapia.
Dois problemas: é afirmação jurídica que não podemos inventar, e **fisioterapia é regulada
pelo COFFITO, não pelo CFM** — a Res. 1.821/2007 trata do prontuário **médico**. Removido
o número como se fosse aplicável a fisio; o texto agora registra que a norma e o prazo
aplicáveis (resolução do COFFITO pertinente + exigências da LGPD/legislação de saúde)
devem ser **confirmados com o jurídico antes de configurar qualquer purga**, sem hardcodar
prazo.

**Lacuna preenchida — vazamento lateral da turma (`pkgOf`), nova
[§1.6](#16-agendamento-em-grupo-turma--o-vazamento-lateral-entre-pacientes).** O inventário
não cobria o agendamento em grupo. Verifiquei no protótipo que a turma
([`:2005`](../interface/Movimento.dc.html#L2005)) guarda, num único registro de
agendamento, um array `patientIds` de todos os participantes e um mapa `pkgOf` que liga
cada paciente ao seu pacote ([`:350`](../interface/Movimento.dc.html#L350),
lido em [`:1113`](../interface/Movimento.dc.html#L1113)). Ou seja: o registro de um
paciente contém identificadores de outros pacientes da mesma turma — vetor de vazamento
lateral e, sobre terceiros, informação de saúde. Classifiquei como PII sensível e
prescrevi em [§6.2](#62-field-policies-quais-campos) que os participantes virem recurso de
junção com **row policy** de leitura (admin + profissional vinculado), nunca um blob
`pkgOf` exposto — a recepção vê ocupação da turma, não a lista nominal.

**Marcadores `# NAO-VERIFICADO` — completos.** Os oito blocos de código Elixir (incluindo
`AshCloak`, `AshPaperTrail`, `AshAuthentication` e `field_policies`) e agora também as duas
afirmações de biblioteca em prosa (rotação do Cloak em §3.2, interação PaperTrail×Cloak em
§4) carregam o marcador.

**Mantido o que estava certo.** Inventário de dados, análise LGPD e base legal do Art. 11,
blind index HMAC para busca por CPF/telefone, RBAC com FilterCheck e a armadilha do
"primeiro check vence", storage privado com URL assinada, e o checklist de bloqueantes —
tudo permaneceu, com ajustes apenas onde a §1.6 nova tornou a redação mais precisa.

---

### Referências cruzadas

- Decisões: [00-decisoes.md](00-decisoes.md) (ADR-003, ADR-007, ADR-008, ADR-009).
- Arquitetura: [04-arquitetura.md](04-arquitetura.md) (§4 contrato/tenant fora do
  cliente, §5 autenticação, §7 concorrência, §11 jobs Oban, §12 ambientes).
- Regras do repo consultadas: `.claude/rules/ash.md` (policies, field policies, a
  armadilha do "primeiro check vence"), `.claude/rules/ash_postgres.md` (cifra,
  constraints), `.claude/rules/ash_phoenix.md` (erro com campo no formulário).
</content>
</invoke>
