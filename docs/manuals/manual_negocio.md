# Manual de Negócio — JLP RAG

> Gerado por leitura automatizada do código-fonte (Claude) em 2026-08-06.
>
> **Aviso de escopo importante:** este documento descreve o que o
> sistema **faz**, inferido do comportamento implementado no código
> (validações, textos fixos, regras de fluxo). Ele **não** é
> conhecimento de negócio validado por um especialista humano em
> averbação de apólices — essa validação ainda não existe na empresa
> (não há documentação nem base de perguntas/respostas de referência
> hoje). Trate as seções abaixo como "o que o software promete fazer",
> não como "o que é correto fazer" no processo real de averbação.

## 1. O que o sistema resolve

O JLP é uma API que responde perguntas em linguagem natural sobre
documentos de averbação de apólices de seguro. Um usuário (ou sistema
cliente, via API) manda uma pergunta; o sistema busca nos documentos
já cadastrados os trechos mais relevantes e gera uma resposta **citando
as fontes usadas**, com um indicador de quão confiável é essa resposta.

Não é um sistema de busca de documentos (tipo "encontre o PDF X") — é
um sistema de resposta a perguntas com evidência (tipo "o que diz a
apólice sobre Y").

## 2. Conceitos de domínio que o sistema já entende

Extraídos dos campos que os documentos carregam hoje:

| Campo | O que representa |
|---|---|
| `ramo` | Ramo do seguro (ex.: automóvel, residencial, vida — os valores concretos não estão fixados no código, é texto livre) |
| `seguradora` | Nome da seguradora responsável pela apólice |
| `cliente` | Cliente/segurado dono da apólice |
| `tipo_documento` | Tipo do documento (ex.: apólice, endosso, averbação — também texto livre) |
| `vigência_ano` | Ano de vigência da apólice/documento |

Esses campos servem tanto pra filtrar buscas (alguém pode perguntar
"o que diz a apólice da Seguradora X de 2025?") quanto pra
organização geral no painel administrativo.

## 3. Quem pode usar o sistema

Duas categorias de conta (`Account`):

- **Conta comum** — consegue perguntar (`/questions`) e dar feedback
  sobre respostas. Não vê o painel administrativo.
- **Conta operadora** (`operator: true`) — além do que a conta comum
  faz, tem acesso ao painel administrativo completo: ver todos os
  documentos, todas as perguntas feitas por todas as contas, disparar
  avaliações de qualidade, reprocessar ingestões com falha, ver
  métricas agregadas de uso e custo.

Cada conta autentica com uma chave própria (`api_key`) — o sistema já
foi desenhado para suportar múltiplos clientes/empresas isolados entre
si (multi-tenant), mesmo que hoje só exista o uso interno.

## 4. Como uma pergunta é respondida — jornada funcional

1. Usuário manda a pergunta (até 2.000 caracteres).
2. O sistema busca nos documentos da própria conta (nunca mistura
   documentos de contas diferentes).
3. Se **não encontrar nada relevante**, o sistema recusa
   explicitamente, com a mensagem:
   > "Não encontrei informações suficientes nas fontes fornecidas
   > para responder a esta pergunta."
   Isso é proposital — o sistema é desenhado pra preferir dizer "não
   sei" a inventar uma resposta.
4. Se encontrar conteúdo relevante, gera uma resposta citando as
   fontes usadas (formato `[FONTE N]` no texto), junto com:
   - **Cobertura de citação** — quantas das fontes recuperadas foram
     de fato citadas na resposta.
   - **Groundedness** (`grounded: true/false`) — indicador de que a
     resposta se apoiou em alguma fonte real (ou recusou
     explicitamente), em vez de "flutuar" sem base.
   - **Nível de confiança** (`alto`/`médio`/`baixo`) — combina
     qualidade da busca, cobertura de citação e groundedness num único
     indicador. Pensado pra sinalizar pro usuário (ou pra um sistema
     de triagem) quando uma resposta merece revisão humana antes de
     ser usada.
5. A resposta, a pergunta e todos os trechos usados ficam registrados
   (para auditoria e para o painel administrativo).

## 5. Feedback do usuário

Toda resposta pode receber feedback do usuário: positivo ou negativo,
com motivo opcional em texto livre. Esse feedback fica associado à
resposta específica e aparece agregado no painel administrativo
(`total` e contagem por tipo). Hoje é só coleta — não há um processo
automático de "aprender" com o feedback negativo (isso exigiria
alguém revisar os casos negativos e ajustar o sistema manualmente).

## 6. O que o time operacional consegue ver (painel admin)

- **Documentos**: status de ingestão de cada documento (pendente, na
  fila, processando, concluído, falhou), quantos pedaços (chunks) cada
  um gerou, se algum trecho foi sinalizado como suspeito de conter
  instrução escondida (proteção contra manipulação via conteúdo do
  próprio documento).
- **Perguntas**: histórico de todas as perguntas feitas, com a
  resposta, se veio de cache, quanto tempo levou, quantos tokens
  custou, e o detalhamento de quais trechos foram usados e com que
  pontuação.
- **Avaliações**: permite disparar uma rodada de avaliação de
  qualidade contra um conjunto de casos de teste cadastrados
  (pergunta + resposta esperada), e ver métricas agregadas
  (precisão/recall de recuperação, relevância dos trechos, fidelidade
  da resposta, cobertura de citação). **Hoje esse conjunto de casos
  está vazio** — a funcionalidade existe mas ninguém alimentou casos
  reais de averbação nela ainda.
- **Falhas**: lista documentos que falharam na ingestão e por quê, com
  botão pra reprocessar todos de uma vez.
- **Dashboard**: visão consolidada — total de documentos por status,
  taxa de acerto do cache, confiança média das respostas, contagem de
  respostas recusadas por falta de evidência, feedback agregado, e uma
  estimativa de custo (baseada em tokens consumidos, não é fatura
  real da OpenAI).

## 7. Garantias que o produto promete (e como cumpre)

| Garantia | Como é cumprida hoje |
|---|---|
| "Não respondo sem evidência" | Recusa explícita quando não há resultado relevante o suficiente |
| "Toda resposta mostra de onde veio" | Exigência de citação `[FONTE N]`, com cobertura calculada |
| "Sinalizo quando não tenho certeza" | Score e nível de confiança em toda resposta |
| "Não misturo dados entre clientes" | Isolamento por conta aplicado antes de qualquer outro filtro de busca |
| "Detecto tentativa de manipulação via documento" | Sinalização (não bloqueio) de padrões de prompt injection na ingestão |

## 8. O que o sistema NÃO cobre hoje (limitações de negócio conhecidas)

- **Sem validação com conhecimento real de averbação.** As regras de
  relevância, os pesos de confiança e os limiares de similaridade são
  valores técnicos plausíveis, não calibrados com casos reais
  validados por quem faz averbação hoje na empresa.
- **Sem cobrança/plano de uso.** Não há limite de perguntas por conta
  além de um limite técnico de 20 por minuto por endereço de rede (que
  nem é por cliente).
- **Sem processo formal de retenção/exclusão de dados.** Documentos e
  histórico de perguntas ficam guardados indefinidamente; não há
  rotina de expurgo ou anonimização.
- **Checagem de alucinação (verificação mais rigorosa, via segundo
  LLM-juiz) vem desligada por padrão** nas respostas do dia a dia — só
  roda quando alguém dispara uma avaliação manual. Ou seja, a
  verificação "ao vivo" de cada resposta é a mais barata (citou ou
  recusou), não a mais rigorosa.
- **Painel administrativo não é dividido por cliente** — quem tem
  acesso de operador vê os dados de todas as contas, sem filtro.

## Glossário rápido

- **Chunk** — pedaço de um documento (alguns parágrafos) usado como
  unidade de busca; um documento vira vários chunks.
- **Embedding** — representação numérica de um texto usada para busca
  por similaridade de significado (não só por palavra exata).
- **Groundedness** — indicador de que a resposta está apoiada em
  conteúdo real, não inventada.
- **Alucinação** — quando o modelo afirma algo que não está de fato
  nas fontes fornecidas.
- **Cache semântico** — reaproveitar a resposta de uma pergunta
  anterior parecida, em vez de gerar uma nova.
- **Reranking** — reordenar os resultados de uma busca inicial por um
  critério mais preciso (e mais caro) antes de montar a resposta.
