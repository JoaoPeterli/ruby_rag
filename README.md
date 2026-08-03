# AverbGo — RAG de averbação de apólices

API em Rails (modo `api_only`) que responde perguntas sobre documentos de
averbação de apólices usando um pipeline de RAG (busca híbrida vetorial +
full-text, reranking, cross-encoder, cache semântico, citações,
verificação de groundedness/alucinação) sobre PostgreSQL + pgvector.

## Requisitos

- Ruby 3.3.6 (ver `.ruby-version`)
- Docker + Docker Compose (Postgres com pgvector, Redis)
- Uma chave de API da OpenAI (embeddings + chat completion)

## Setup

1. Suba os serviços de infraestrutura:

   ```bash
   docker compose up -d
   ```

   Isso sobe Postgres (`pgvector/pgvector:pg16`, porta 5432) e Redis
   (porta 6379, usado pelo Sidekiq). Se você já tiver um Redis local
   rodando na 6379 (ex.: `redis-server` via systemd), pare-o antes
   (`sudo systemctl stop redis-server`) ou o container vai falhar ao
   subir por conflito de porta.

2. Crie um `.env` na raiz com as variáveis abaixo:

   ```
   DATABASE_HOST=localhost
   DATABASE_PORT=5432
   DATABASE_NAME=ruby_rag_development
   DATABASE_TEST_NAME=ruby_rag_test
   DATABASE_USERNAME=postgres
   DATABASE_PASSWORD=postgres
   REDIS_URL=redis://localhost:6379/0

   OPENAI_API_KEY=sk-...
   OPENAI_BASE_URL=https://api.openai.com/v1
   OPENAI_EMBEDDING_ENDPOINT=/embeddings
   OPENAI_EMBEDDING_MODEL=text-embedding-3-small
   OPENAI_CHAT_COMPLETION_ENDPOINT=/chat/completions
   OPENAI_CHAT_MODEL=gpt-4o-mini
   OPENAI_CHAT_TEMPERATURE=0.2
   OPENAI_HTTP_OPEN_TIMEOUT=5
   OPENAI_HTTP_READ_TIMEOUT=60
   ```

3. Instale as dependências e prepare o banco:

   ```bash
   bundle install
   bin/rails db:create db:migrate
   ```

   A migration `AddAccountIdToMultipleTables` cria duas contas
   seed (uma padrão e uma "operadora") e imprime as `api_key`
   geradas no log da migration — copie-as, elas não ficam
   guardadas em nenhum outro lugar do código. Se perder, crie uma
   conta nova pelo console (`Account.create!(name: "...")`, o
   `api_key` é gerado automaticamente).

4. Suba o worker do Sidekiq (necessário pra ingestão de documentos,
   que roda em background):

   ```bash
   bundle exec sidekiq -C config/sidekiq.yml
   ```

5. Suba o servidor:

   ```bash
   bin/rails server
   ```

## Autenticação

Toda a API (exceto quando explicitamente indicado) exige um header
`Authorization: Bearer <api_key>` com a `api_key` de uma `Account`
ativa. Contas com `operator: true` também têm acesso aos endpoints
`/api/v1/admin/*`; contas comuns recebem `403` nesses endpoints.

## Testes

```bash
RAILS_ENV=test bin/rails db:test:prepare
bin/rails test
```

O schema é versionado via `db/structure.sql` (não `schema.rb`), porque
alguns triggers/funções são SQL puro e o `schema.rb` não os captura.
Depois de qualquer migration nova, regenere-o com:

```bash
docker exec ruby-rag-database pg_dump --schema-only --no-privileges --no-owner -U postgres ruby_rag_development > db/structure.sql
```

(usamos o `pg_dump` de dentro do container porque a versão do Postgres
do container, 16.x, costuma ser mais nova que a instalada localmente).

## Lint e análise estática

```bash
bin/rubocop
bin/brakeman
```
