# Manual Técnico — JLP RAG

> Gerado por leitura automatizada do código-fonte (Claude) em 2026-08-06.
> Cobre a arquitetura, o modelo de dados e os fluxos como implementados
> no momento da geração. Não substitui a documentação viva do código —
> se o código mudar, este documento fica desatualizado até ser
> regenerado.

## 1. Visão geral

API em Ruby on Rails (modo `api_only`) que responde perguntas sobre
documentos de averbação de apólices de seguro usando um pipeline de
RAG (Retrieval-Augmented Generation): busca híbrida vetorial +
full-text, reranking com cross-encoder, cache semântico, citação de
fontes e verificação de groundedness/alucinação, sobre PostgreSQL com
a extensão `pgvector`.

**Stack:**

| Componente | Tecnologia |
|---|---|
| Framework | Rails 8.0 (`api_only`) |
| Linguagem | Ruby 3.3.6 |
| Banco de dados | PostgreSQL 16 + pgvector (busca vetorial via HNSW) |
| Fila / background jobs | Sidekiq + Redis |
| LLM / embeddings | OpenAI (`gpt-4o-mini` padrão para chat, `text-embedding-3-small` para embeddings), via gem `openai` e `faraday` |
| Tokenização | `tiktoken_ruby` |
| Deploy | Docker + Kamal (referenciado no Gemfile, não confirmado se em uso ativo) |
| CI | GitHub Actions (`brakeman`, `rubocop`, testes) |

## 2. Arquitetura em camadas

```
Controller (Api::V1::*)
   → Service de orquestração (ex.: Documents::QuestionAnsweringService)
      → Pipeline (Documents::Pipeline::Pipeline)
         → Steps (cada um faz UMA coisa, lê/escreve num Context mutável)
            → Services especializados (busca, reranking, LLM, etc.)
               → Models (ActiveRecord)
```

Dois pipelines coexistem:

- **Pipeline de resposta** (`Documents::QuestionAnsweringService::STEPS`,
  17 steps) — do recebimento da pergunta até a resposta final
  persistida.
- **Pipeline de recuperação** (`Documents::RetrievalPipelineService::STEPS`,
  11 steps) — chamado como um dos steps do pipeline de resposta,
  cuida só da busca e montagem do contexto.

Ambos usam a mesma abstração (`Documents::Pipeline::Pipeline`): uma
lista de `Steps` que recebem um `Context` mutável e o alteram em
sequência. Não há branching dinâmico no pipeline em si — a
ativação/desativação de cada etapa é decidida dentro do próprio Step,
lendo flags de `context.config`.

**Padrões usados de forma consistente:**

- **Injeção de dependência via keyword args com default de classe** —
  quase todo service recebe suas colaborações (`embedding_service:`,
  `chat_completion_service:`, etc.) como parâmetro com valor padrão
  apontando pra classe real. Isso permite substituir por dublês nos
  testes sem mocking framework.
- **Value objects imutáveis (`Data.define`)** no lugar de hashes soltos
  ou muitas variáveis de instância — `Config`, `Result`, `Source`,
  `Plan`, etc.
- **Erros tipados por serviço** (`class Error < StandardError`, com
  subclasses específicas) — cada camada só deixa vazar exceções da sua
  própria hierarquia, nunca o erro bruto de uma dependência externa.

## 3. Modelo de dados

### Núcleo de documentos

- **`Account`** — tenant. Tem `api_key` (gerada automaticamente,
  `SecureRandom.hex(32)`) e `operator` (bool, dá acesso ao namespace
  admin).
- **`Document`** — um documento fonte (ex.: uma apólice averbada).
  Campos de metadado de negócio: `ramo`, `seguradora`, `cliente`,
  `tipo_documento`, `vigencia_ano`. Guarda `status`
  (`pending → queued → processing → completed/failed`),
  `content_hash` (SHA-256 do conteúdo normalizado, usado pra pular
  reingestão de conteúdo idêntico) e `content_version` (incrementada
  só quando o hash muda de fato).
- **`DocumentChunk`** — pedaço de um documento, com `embedding`
  (vetor, via `neighbor`/pgvector), `content_hash` (único por
  documento) e `account_id` (herdado do documento no
  `before_validation`, denormalizado pra evitar JOIN em toda busca).

### Núcleo de perguntas e respostas

- **`RagQuery`** — uma pergunta recebida (`question`, `search_query`
  efetivo, `status`, `cache_hit`, `duration_ms`, `total_tokens`).
- **`RagAnswer`** — a resposta gerada, 1:1 com `RagQuery`
  (`answer`, `model`, `grounded`, `refused`, `citation_coverage`,
  `confidence_score`, `confidence_level`, tokens de prompt/completion).
- **`RagRetrievalResult`** — um chunk retornado na busca para aquela
  query, com todos os scores intermediários (`hybrid_score`,
  `rerank_score`, `combined_score`, `mmr_score`, `cited`).
- **`RagFeedback`** — avaliação humana de uma `RagAnswer`
  (`rating`: `positive`/`negative`, `reason` livre).

### Avaliação e cache

- **`RagEvalCase`** — caso de teste (`question`, `expected_answer`
  opcional, `category`, `active`).
- **`RagEvalRun`** / **`RagEvalResult`** — execução de um lote de
  casos contra `Documents::Evaluation::Service`, com métricas
  agregadas e por caso.
- **`RagSemanticCacheEntry`** — cache de pergunta→resposta por
  similaridade de embedding (`question_embedding`), com TTL.

Todas as tabelas de conteúdo/consulta têm `account_id` opcional a
nível de banco, mas a aplicação garante que toda request HTTP real
sempre passa um `account_id` explícito (ver seção 5).

## 4. Autenticação e isolamento por conta (multi-tenancy)

- Autenticação por header `Authorization: Bearer <api_key>`, resolvida
  em `Api::V1::BaseController#authenticate!` contra `Account.active`.
- `Current.account` fica disponível pro resto do request.
- **Duas fronteiras de escopo deliberadamente separadas:**
  - `Documents::AccountScopeBuilder` — fronteira de **segurança**
    (isolamento de tenant). Sempre aplicada primeiro, antes de
    qualquer outro filtro.
  - `Documents::MetadataScopeBuilder` — filtro de **relevância**
    (`ramo`, `seguradora`, `cliente`, `tipo_documento`, `vigencia_ano`).
  - A separação existe pra garantir que um bug no filtro de metadados
    nunca vaze dado de outra conta — são caminhos de código
    independentes.
- `account_id: nil` nos services internos significa "sem restrição" —
  usado por console/testes/avaliação interna, e nunca alcançável a
  partir de uma request HTTP comum (os controllers sempre passam
  `Current.account.id` explicitamente).
- Endpoints `/api/v1/admin/*` exigem `Current.account.operator? == true`
  (`Api::V1::Admin::BaseController`); contas comuns recebem `403`. O
  painel admin **não é escopado por conta** — operador enxerga tudo.
- Rate limit de 20 req/min em `questions#create`/`stream`, aplicado
  **por IP** (`request.remote_ip`), não por conta.

## 5. Fluxo de ingestão de documentos

1. Um `Document` é criado/atualizado com `content` preenchido.
2. `Documents::EnqueueIngestionService.call(document:)`:
   - Pula a ingestão se `document.already_ingested_and_unchanged?`
     (mesmo `content_hash` já indexado), a menos que `force: true`.
   - Marca o documento como `queued`, grava um `run_id` (UUID) nos
     metadados, e enfileira `Documents::IngestionJob` via Sidekiq
     (fila `document_ingestion`).
3. `Documents::IngestionJob#perform`:
   - `Documents::ProcessingGuard` valida que o `run_id` do job ainda é
     o vigente (evita que um job antigo, reprocessado por retry,
     sobrescreva um reprocessamento mais novo do mesmo documento).
   - Chama `Documents::IngestionService`, que:
     1. Quebra o texto com `RecursiveChunker` (chunking recursivo por
        separadores naturais).
     2. Agrupa (`PackingService`, ~425 tokens/chunk por padrão) e
        adiciona sobreposição (`TokenOverlapService`, ~75 tokens).
     3. Valida o tamanho final (`FinalChunkValidator`, máx. 500
        tokens/chunk).
     4. Gera embeddings em lote (`Ai::BatchEmbeddingService`).
     5. Roda `Documents::PromptInjectionDetectionService` em cada
        chunk (heurística por regex — sinaliza, não bloqueia; grava
        `prompt_injection_suspicious`/`risk_score` nos metadados do
        chunk).
     6. Substitui os chunks antigos do documento numa transação
        (`document.with_lock` + `document_chunks.delete_all` +
        recriação) e marca o documento como `completed`.
4. Falhas passam por `Documents::FailureStateService`, com política de
   retry diferenciada por tipo de erro (`IngestionJob`):
   rate limit da OpenAI → até 8 tentativas; timeout/indisponibilidade →
   5 tentativas; erro desconhecido → 3 tentativas; erro de
   autenticação/documento inválido → descarta sem retry.
5. Documentos com falha final aparecem em
   `GET /api/v1/admin/failures`, e podem ser reenfileirados em lote via
   `POST /api/v1/admin/failures/retry_all`
   (`Documents::RetryFailedIngestionsService`).

## 6. Fluxo de resposta a uma pergunta

Orquestrado por `Documents::QuestionAnsweringService`, que roda os 17
steps abaixo em sequência sobre um `Documents::Pipeline::AnswerContext`.
Vários steps fazem `return if context.result` no início — um "atalho"
(cache hit, sem evidência, erro de validação) preenche `context.result`
mais cedo e os steps seguintes viram no-op, mas ainda rodam (barato) até
o fim do array.

| # | Step | Função |
|---|---|---|
| 1 | `ValidateQuestionStep` | Rejeita pergunta vazia/malformada |
| 2 | `ResolveEffectiveQuestionStep` | Reescreve a pergunta usando `conversation_history`, se houver (`QueryRewriteService`) |
| 3 | `SemanticCacheLookupStep` | Se `semantic_cache_enabled`, busca resposta cacheada por similaridade de embedding |
| 4 | `RouteQueryStep` | Se `query_router_enabled`, classifica a pergunta em categoria (`factual`, `comparacao`, `resumo`, `procedimento`, `documento_especifico`, `fora_da_base`) via LLM |
| 5 | `AdaptiveRetrievalPlanStep` | Se `adaptive_retrieval_enabled`, decide quais sub-etapas de retrieval ligar com base na complexidade da pergunta |
| 6 | `RetrieveDocumentsStep` | Chama o pipeline de recuperação (seção 7) |
| 7 | `TokenBudgetStep` | Se `token_budget_enabled`, corta candidatos pra caber no orçamento de tokens |
| 8 | `BuildContextStep` | Monta o texto de contexto a partir dos chunks selecionados |
| 9 | `BuildPromptStep` | Monta o prompt final (sistema + contexto + pergunta) |
| 10 | `GenerateAnswerStep` | Chama o chat completion (streaming ou não) |
| 11 | `BuildCitationsStep` | Extrai `[FONTE N]` do texto da resposta e casa com as fontes reais (`CitationEngine::Service`) |
| 12 | `CheckGroundednessStep` | Heurística barata: resposta tem citação OU recusa explícita → `grounded: true` |
| 13 | `CheckHallucinationStep` | Se `hallucination_check_enabled` (desligado por padrão), verifica cada afirmação da resposta contra o contexto via LLM-juiz |
| 14 | `CalculateConfidenceStep` | Combina os sinais acima num score 0–1 e nível (`high`/`medium`/`low`) |
| 15 | `BuildResultStep` | Monta o `Result` final |
| 16 | `StoreCacheStep` | Se `semantic_cache_enabled`, grava a resposta no cache semântico |
| 17 | `PersistStep` | Grava `RagQuery`/`RagAnswer`/`RagRetrievalResult` (se `persist_enabled`) |

Quando não há evidência suficiente (nenhum resultado relevante), o
sistema **recusa explicitamente** com uma mensagem fixa
(`NO_EVIDENCE_ANSWER`) em vez de deixar o LLM tentar responder sem
contexto.

## 7. Pipeline de recuperação (retrieval)

`Documents::RetrievalPipelineService`, 11 steps:

1. **QueryExpansionStep** — reformula a pergunta (`QueryExpansionService`) pra melhorar recall.
2. **MultiQueryStep** — gera variações da pergunta (até 4, por padrão) e busca por cada uma (`MultiQueryService` + `MultiQueryResultMerger`).
3. **MetadataExtractionStep** — tenta extrair filtros estruturados (`ramo`, `seguradora` etc.) do texto da pergunta.
4. **EmbeddingStep** — gera o embedding da(s) query(ies).
5. **HybridSearchStep** — combina busca vetorial (`VectorSearchService`, cosseno via pgvector/HNSW) com busca full-text (`FullTextSearchService`, `tsvector`/`search_vector`).
6. **MergeStep** — funde os candidatos de múltiplas queries/estratégias.
7. **RerankStep** — reordena por `hybrid_score` combinando os sinais anteriores.
8. **CrossEncoderRerankStep** — reranking mais caro e mais preciso via LLM em lote (`CrossEncoder::LlmBatchStrategy`), combinando score do cross-encoder com o score de retrieval por um peso configurável.
9. **MmrStep** — Maximal Marginal Relevance (`mmr_lambda = 0.70` por padrão): penaliza redundância entre os chunks escolhidos.
10. **ParentDocumentRetrievalStep** — expande cada chunk citado com uma janela de chunks vizinhos do mesmo documento, pra dar mais contexto ao LLM.
11. **ContextCompressionStep** — remove sentenças pouco relevantes dos chunks finais antes de montar o prompt (`ContextCompression::SimilarityStrategy`).

Se, ao final, nenhum resultado passar do `minimum_similarity`
(`0.30` por padrão), o pipeline levanta `NoRelevantResultsError`, que o
step 6 do pipeline de resposta transforma na recusa explícita.

**Defaults reais (o que roda "de fábrica", verificado no código, não
suposto):**

| Flag | Default | Onde |
|---|---|---|
| `query_expansion_enabled` | `true` | `RetrievalPipelineService` |
| `multi_query_enabled` | `true` | `RetrievalPipelineService` |
| `metadata_extraction_enabled` | `true` | `RetrievalPipelineService` |
| `parent_retrieval_enabled` | `true` | `RetrievalPipelineService` |
| `context_compression_enabled` | `true` | `RetrievalPipelineService` |
| `cross_encoder_enabled` | `true` | `RetrievalPipelineService` |
| `citation_engine_enabled` | `true` | `QuestionAnsweringService` |
| `groundedness_check_enabled` | `true` | `QuestionAnsweringService` |
| `confidence_score_enabled` | `true` | `QuestionAnsweringService` |
| `hallucination_check_enabled` | **`false`** | `QuestionAnsweringService` — só ligado explicitamente no fluxo de avaliação |
| `semantic_cache_enabled` | **`false`** | muda comportamento de forma perceptível (pode reaproveitar resposta de pergunta "parecida mas diferente") |
| `token_budget_enabled` | **`false`** | idem |
| `adaptive_retrieval_enabled` | **`false`** | idem |
| `query_router_enabled` | **`false`** | idem |
| `query_rewrite_enabled` | `true` | só tem efeito se `conversation_history` for passado |

Se `adaptive_retrieval_enabled` estiver ligado, o `AdaptiveRetrievalPlan`
pode sobrescrever os defaults acima por pergunta (perguntas curtas
pulam expansão/multi-query/cross-encoder; perguntas de
comparação/resumo ligam tudo).

## 8. Serviços de qualidade de resposta

- **`CitationEngine::Service`** — faz parsing de padrões `[FONTE N]`
  (incluindo listas `[FONTE 1, 3]` e ranges `[FONTE 1 a 3]`) no texto
  da resposta e casa com as fontes reais retornadas pelo retrieval.
  Calcula `citation_coverage` = fontes citadas / fontes disponíveis.
- **`GroundednessCheckService`** — heurística barata (sem chamada de
  LLM): `grounded = recusou_explicitamente OR citou_alguma_fonte`.
  Roda em toda resposta por padrão.
- **`HallucinationCheckService`** — verificação cara (1 chamada extra
  de LLM-juiz): extrai cada afirmação factual da resposta e julga se
  está apoiada no contexto. Retorna `hallucination_rate`. **Desligada
  por padrão** em produção; usada no fluxo de avaliação.
- **`ConfidenceScoreService`** — combina em média ponderada: score de
  retrieval (25%), score do cross-encoder (20%), cobertura de citação
  (25%), groundedness (15%), faithfulness/hallucination (15%). Níveis:
  `high ≥ 0.75`, `medium ≥ 0.45`, senão `low`.
- **`PromptInjectionDetectionService`** — heurística por regex
  (override de instrução, sequestro de papel, vazamento de
  system prompt, conteúdo oculto/zero-width). Roda na ingestão, só
  **sinaliza** (não bloqueia) — a defesa real contra prompt injection
  vindo do conteúdo dos documentos é instrução explícita nos prompts
  de sistema dos serviços que consomem esse conteúdo (cross-encoder,
  hallucination check) pra nunca seguir instruções vindas do contexto.

## 9. API

Base: `/api/v1`. Todos os endpoints exigem `Authorization: Bearer <api_key>`.

| Método | Rota | Descrição |
|---|---|---|
| `POST` | `/questions` | Pergunta síncrona, retorna JSON completo |
| `POST` | `/questions/stream` | Mesma coisa via SSE (`event: delta` por pedaço, `event: done` no final, `event: error` se falhar depois de iniciado) |
| `POST` | `/answers/:answer_id/feedbacks` | Registra feedback humano (`positive`/`negative` + motivo opcional) sobre uma resposta |
| `GET` | `/admin/documents`, `/admin/documents/:id` | Lista/detalha documentos (operador) |
| `GET` | `/admin/queries`, `/admin/queries/:id` | Lista/detalha perguntas feitas, com scores de retrieval (operador) |
| `GET`/`POST` | `/admin/evaluations`, `/admin/evaluations/:id` | Lista execuções de avaliação / dispara uma nova (operador) |
| `GET` | `/admin/failures` | Lista documentos com falha de ingestão (operador) |
| `POST` | `/admin/failures/retry_all` | Reenfileira todas as ingestões falhadas (operador) |
| `GET` | `/admin/dashboard` | Métricas agregadas: documentos por status, taxa de cache hit, confiança média, feedback, custo estimado (operador) |

`questions#create`/`#stream` limitam pergunta a 2.000 caracteres e
aceitam `conversation_history` opcional (`[{role, content}, ...]`).

## 10. Testes e qualidade

- 122 arquivos de teste (`Minitest`, padrão Rails) para 141 arquivos em
  `app/`. Testes de service usam dublês simples (classes anônimas com
  `define_singleton_method`) em vez de framework de mock — consistente
  com o estilo de DI do projeto.
- CI (`.github/workflows/ci.yml`): `brakeman` (segurança estática),
  `rubocop` (estilo, `rubocop-rails-omakase`), suíte de testes contra
  Postgres real.
- Estado no momento da geração: Brakeman com 1 warning de confiança
  "Weak" (falso positivo — nome de coluna interpolado em
  `MetadataScopeBuilder#apply_case_insensitive_filter`, mas sempre um
  literal hardcoded, nunca input de usuário). Rubocop com 17 ofensas
  de estilo em 298 arquivos, quase todas autocorrigíveis.

## 11. Rodando localmente

Ver `README.md` na raiz — resumo:

```bash
docker compose up -d          # Postgres+pgvector e Redis
bundle install
bin/rails db:create db:migrate
bundle exec sidekiq -C config/sidekiq.yml   # worker de ingestão
bin/rails server
```

A migration `AddAccountIdToMultipleTables` cria duas contas seed e
imprime as `api_key` no log — não ficam salvas em nenhum outro lugar.

## 12. Limitações técnicas conhecidas

- Rate limit de `questions#create` é por IP, não por `account_id` —
  em ambiente multi-tenant real isso mistura clientes atrás do mesmo
  IP e não impede abuso de uma conta que troca de IP.
- `RagEvalCase` não tem nenhum caso populado via seed — o framework de
  avaliação existe mas não tem gabarito carregado.
- Sidekiq/Redis está comentado no job de teste do CI — o caminho de
  ingestão em background não tem cobertura de integração real no CI,
  só testes unitários com dublês.
- Sem billing, sem limite de uso por conta além do rate limit por IP,
  sem métrica de custo por conta (o dashboard tem custo agregado
  global, não por `account_id`).
- Sem mecanismo de retenção/expurgo de dados (LGPD) documentado no
  código.
