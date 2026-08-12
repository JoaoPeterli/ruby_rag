# [Nome do Projeto] — Perguntas e Respostas sobre Documentos com RAG

> Este documento é um **template genérico**, derivado de um projeto real
> pela leitura do código-fonte. Foi limpo de qualquer nome de produto e
> de qualquer domínio de negócio específico para servir de ponto de
> partida em outro contexto. Onde aparecer `[algo entre colchetes]`,
> é um valor pra você preencher com o domínio real do seu projeto.

API em Ruby on Rails (`api_only`) que responde perguntas em linguagem
natural sobre uma base de documentos internos, usando um pipeline de
RAG (Retrieval-Augmented Generation): busca híbrida vetorial +
full-text, reranking com cross-encoder, cache semântico, citação
obrigatória de fontes e verificação de groundedness/alucinação — sobre
PostgreSQL com a extensão `pgvector`.

O objetivo do desenho é simples de enunciar e difícil de garantir: a
resposta nunca deve "flutuar" sem apoio em conteúdo real. Se não há
evidência suficiente nos documentos, o sistema recusa a responder em
vez de inventar.

## Por que existe

Bases de conhecimento internas costumam ter duas dores: ninguém lembra
onde está a informação, e quando alguém acha, não confia sem checar a
fonte de novo. Este projeto tenta resolver as duas ao mesmo tempo —
busca que entende sinônimo e contexto (não só palavra exata) e uma
resposta que sempre aponta de onde tirou cada afirmação.

## O que o sistema faz

- Ingere documentos de texto, quebra em pedaços (*chunks*) com
  sobreposição controlada, gera embeddings e indexa pra busca vetorial
  e full-text ao mesmo tempo.
- Responde perguntas combinando os dois tipos de busca, reranking em
  múltiplos estágios e, opcionalmente, expansão/reescrita de consulta
  e busca por múltiplas variações da mesma pergunta.
- Cita a fonte de cada afirmação na resposta (`[FONTE N]`) e calcula
  quanto da resposta está de fato apoiado em citação.
- Calcula um **nível de confiança** (alto/médio/baixo) combinando
  qualidade da busca, cobertura de citação e groundedness — pensado
  pra sinalizar quando uma resposta merece revisão humana.
- Recusa explicitamente responder quando não encontra evidência
  suficiente, em vez de deixar o modelo preencher a lacuna.
- Isola dados por conta/cliente (multi-tenant) como fronteira de
  segurança, separada do filtro de metadados de relevância.
- Expõe um painel administrativo pra acompanhar ingestão, histórico de
  perguntas, avaliação de qualidade e falhas de processamento.

## Arquitetura

```
Controller
  → Service de orquestração
     → Pipeline (lista ordenada de Steps)
        → Steps (cada um faz UMA coisa, lê/escreve num Context mutável)
           → Services especializados (busca, reranking, LLM, ...)
              → Models (ActiveRecord)
```

Dois pipelines coexistem, montados com a mesma abstração:

- **Pipeline de resposta** — do recebimento da pergunta até a resposta
  final persistida (validação, cache, roteamento de pergunta,
  recuperação, geração, citação, checagens de qualidade, persistência).
- **Pipeline de recuperação** — chamado como uma etapa do pipeline de
  resposta; cuida só de buscar e montar o contexto (expansão de
  consulta, busca híbrida, reranking, MMR, expansão de vizinhança,
  compressão de contexto).

Não há branching dinâmico no pipeline em si — cada Step decide
sozinho se tem trabalho a fazer, lendo flags de configuração. Isso
mantém a lista de etapas simples de ler e fácil de reordenar/remover.

**Convenções de código usadas de forma consistente:**

- Injeção de dependência via keyword arguments com default apontando
  pra classe real — troca fácil por dublê nos testes, sem framework de
  mock.
- Value objects imutáveis (`Data.define`) no lugar de hashes soltos ou
  muitas variáveis de instância.
- Hierarquia de erros própria por serviço — nenhuma camada deixa vazar
  a exceção bruta de uma dependência externa.

## Modelo de dados (visão geral)

- **Conta** — tenant. Autentica por chave de API; pode ter privilégio
  de operador (acesso ao painel administrativo).
- **Documento** — a unidade de conteúdo fonte, com campos de metadado
  configuráveis pro seu domínio (ex.: `categoria`, `origem`,
  `cliente_ou_area`, `tipo_documento`, `ano_referencia`) e um hash de
  conteúdo usado pra pular reingestão de algo que não mudou.
- **Chunk** — pedaço de um documento, com seu embedding e um hash
  próprio (único por documento).
- **Consulta / Resposta** — toda pergunta feita e a resposta gerada
  ficam persistidas, com todos os scores intermediários de cada trecho
  usado (útil pra depuração e auditoria).
- **Feedback** — avaliação humana (positiva/negativa + motivo) sobre
  uma resposta específica.
- **Caso de avaliação / Execução de avaliação** — conjunto de
  perguntas com resposta esperada, usado pra medir qualidade do
  sistema de forma repetível.
- **Entrada de cache semântico** — pergunta→resposta reaproveitável
  por similaridade de embedding, com expiração.

## Como funciona, passo a passo

### Ingestão

1. Um documento é criado com conteúdo de texto.
2. Se o conteúdo já foi indexado sem mudança, a ingestão é pulada.
3. Caso contrário, é enfileirado em background: o texto é quebrado
   recursivamente por separadores naturais, agrupado em blocos de
   tamanho controlado, com sobreposição entre blocos vizinhos.
4. Cada chunk final passa por geração de embedding em lote e por uma
   checagem heurística de conteúdo suspeito (tentativa de manipular o
   modelo através do próprio texto do documento — sinaliza, não
   bloqueia).
5. Os chunks são persistidos numa transação, substituindo qualquer
   versão anterior do mesmo documento.
6. Falhas têm política de retry diferenciada por tipo de erro (rate
   limit externo tolera mais tentativas que erro de autenticação, que
   não é reprocessado).

### Resposta a uma pergunta

1. Validação da pergunta e, se houver histórico de conversa, reescrita
   pra uma forma autocontida.
2. Checagem opcional de cache semântico.
3. Roteamento opcional da pergunta por categoria (factual, comparação,
   resumo, procedimento, etc.), usado pra decidir dinamicamente quais
   etapas de recuperação valem o custo.
4. Recuperação: busca híbrida (vetorial + full-text), fusão de
   candidatos, reranking em dois estágios (score combinado e depois
   cross-encoder), diversificação por MMR, expansão de vizinhança de
   documento e compressão do contexto final.
5. Se nada relevante for encontrado, a resposta é uma recusa explícita
   — não uma tentativa de responder sem base.
6. Geração da resposta (com suporte a streaming via SSE).
7. Extração e validação das citações, checagem de groundedness,
   cálculo de confiança.
8. Persistência de tudo: pergunta, resposta, trechos usados e scores.

## Camadas de qualidade

| Camada | O que faz | Custo |
|---|---|---|
| Citação | Casa `[FONTE N]` do texto da resposta com as fontes reais retornadas na busca | Nenhum (parsing) |
| Groundedness | Resposta citou alguma fonte OU recusou explicitamente | Nenhum (heurística) |
| Verificação de alucinação | Extrai cada afirmação da resposta e julga, via um segundo LLM, se está apoiada no contexto | 1 chamada extra de LLM — desligada por padrão em produção, usada em avaliação |
| Confiança | Média ponderada dos sinais acima + qualidade de retrieval | Nenhum (agregação) |
| Detecção de manipulação de conteúdo | Heurística por padrão de texto (tentativa de sobrescrever instrução, vazamento de prompt, conteúdo oculto) | Nenhum (regex) — só sinaliza |

## Configuração

A maior parte da sofisticação do pipeline de recuperação é **ligada
por padrão** (expansão de consulta, múltiplas variações de busca,
extração de metadados, expansão de vizinhança, compressão de contexto,
cross-encoder). Ficam desligadas por padrão só as funcionalidades que
mudam o comportamento observável de forma perceptível — cache
semântico, orçamento de tokens, plano adaptativo de recuperação e
roteamento de pergunta — pra que ativá-las seja uma decisão
consciente, não um efeito colateral de atualizar a versão.

## API

Autenticação por `Authorization: Bearer <chave-de-api>` em toda a
superfície. Endpoints principais:

- `POST /questions` — pergunta síncrona.
- `POST /questions/stream` — mesma coisa via Server-Sent Events.
- `POST /answers/:id/feedbacks` — feedback humano sobre uma resposta.
- `/admin/*` — documentos, histórico de perguntas, avaliações, falhas
  de ingestão e um dashboard consolidado. Requer privilégio de
  operador.

## Rodando localmente

```bash
docker compose up -d          # Postgres com pgvector, Redis
bundle install
bin/rails db:create db:migrate
bundle exec sidekiq -C config/sidekiq.yml   # worker de ingestão
bin/rails server
```

## Testes e qualidade de código

Suíte de testes unitários por serviço/step, usando dublês simples
(classes anônimas) em vez de framework de mock, alinhado ao estilo de
injeção de dependência do projeto. CI com análise estática de
segurança, linter de estilo e testes contra banco real.

## Limitações conhecidas deste template

- Rate limit implementado por IP, não por conta — vale revisar pra
  ambiente multi-tenant real.
- O framework de avaliação existe estruturalmente, mas precisa ser
  alimentado com casos reais do seu domínio antes de virar sinal
  confiável de qualidade.
- Sem billing/medição de uso por conta além do rate limit técnico.
- Sem rotina de retenção/expurgo de dados — definir política de
  acordo com a regulamentação aplicável ao seu domínio.
