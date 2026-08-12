# [Nome do Projeto] — Assistente de Perguntas e Respostas sobre Documentos

> Este documento é um **template genérico** de README de produto,
> derivado de um projeto real pela leitura do código-fonte, limpo de
> qualquer nome de produto ou domínio de negócio específico. Preencha
> `[algo entre colchetes]` com o contexto real de onde for reaproveitar.

## O problema

Toda organização acumula documentos que alguém precisa consultar sob
pressão: "o que diz o documento X sobre Y?". Encontrar o documento
certo é uma dor; confiar na resposta sem reabrir o PDF é outra. A
maioria das ferramentas de busca resolve só a primeira.

## O que este produto faz

Um usuário faz uma pergunta em linguagem natural. O sistema busca nos
documentos já cadastrados os trechos mais relevantes e devolve uma
resposta que **cita explicitamente de onde tirou cada afirmação**,
junto com um indicador de quão confiável é essa resposta.

Não é uma ferramenta de busca de documentos — é uma ferramenta de
resposta com evidência.

## Como funciona, da perspectiva de quem usa

1. Você faz uma pergunta.
2. O sistema busca só nos documentos da sua própria conta/organização
   — nunca mistura dados de clientes diferentes.
3. **Se não houver informação suficiente, o sistema recusa
   explicitamente**, em vez de arriscar uma resposta inventada.
4. Se houver, a resposta vem com:
   - As fontes citadas dentro do próprio texto.
   - Um indicador de **cobertura de citação** — quanto da resposta
     está de fato apoiado em fonte.
   - Um **nível de confiança** (alto / médio / baixo), pra sinalizar
     quando vale a pena checar a resposta manualmente antes de usar.
5. Pergunta, resposta e fontes usadas ficam registradas — dá pra
   auditar depois o que foi perguntado e por quê a resposta saiu do
   jeito que saiu.

## Quem usa

- **Conta padrão** — pergunta e avalia respostas (feedback
  positivo/negativo).
- **Conta com privilégio administrativo** — além disso, acompanha
  todo o histórico de uso, o estado de ingestão dos documentos, roda
  avaliações formais de qualidade e vê métricas agregadas (volume,
  taxa de reaproveitamento de cache, confiança média, custo estimado).

O sistema já nasce desenhado para múltiplas contas isoladas entre si
(multi-tenant), mesmo que o uso inicial seja de um único time ou
cliente.

## Feedback contínuo

Toda resposta pode ser avaliada por quem a recebeu. Isso é coletado e
fica visível de forma agregada no painel administrativo — é o insumo
mais direto pra saber se o sistema está errando em algum tipo
específico de pergunta.

## O que o painel administrativo mostra

- Estado de ingestão de cada documento (na fila, processando,
  concluído, com falha) e alertas de conteúdo suspeito de tentar
  manipular o sistema.
- Histórico completo de perguntas feitas, com tempo de resposta, custo
  em tokens e o detalhamento de quais trechos foram usados.
- Execuções de avaliação de qualidade contra um conjunto de perguntas
  de referência com resposta esperada.
- Documentos que falharam ao processar, com opção de reprocessar tudo
  de uma vez.
- Um painel consolidado com volume, taxa de cache, confiança média,
  feedback e custo estimado.

## Garantias de produto

| Promessa | Como é cumprida |
|---|---|
| Não responde sem evidência | Recusa explícita quando a busca não encontra nada relevante o suficiente |
| Toda resposta mostra a fonte | Exigência de citação embutida no próprio texto da resposta, com cobertura calculada |
| Sinaliza quando não tem certeza | Nível de confiança em toda resposta, combinando múltiplos sinais de qualidade |
| Não mistura dados entre clientes | Isolamento por conta aplicado antes de qualquer outro filtro de busca |
| Detecta tentativa de manipulação via conteúdo | Sinalização de padrões suspeitos nos documentos no momento da ingestão |

## O que ainda não está pronto (honestidade antes de vender)

- **A qualidade das respostas ainda não foi validada por um
  especialista do domínio real.** Os parâmetros de relevância e
  confiança são valores tecnicamente razoáveis, não calibrados com
  casos reais do seu contexto — isso exige um conjunto de perguntas
  com resposta certa conhecida, revisado por quem entende do assunto.
- **Sem plano de cobrança ou limite de uso por conta** além de um
  limite técnico básico de requisições.
- **Sem política de retenção/exclusão de dados** definida — documentos
  e histórico ficam guardados indefinidamente até alguém decidir o
  contrário.
- **A verificação mais rigorosa de alucinação fica desligada no dia a
  dia** — roda só quando alguém dispara uma avaliação manual. A
  checagem "ao vivo" de cada resposta é a mais barata (citou uma fonte
  ou recusou), não a mais profunda.
- **O painel administrativo não é segmentado por cliente** — quem tem
  acesso administrativo vê os dados de todas as contas.

## Glossário

- **Trecho (chunk)** — pedaço de um documento usado como unidade de
  busca.
- **Groundedness** — a resposta está apoiada em conteúdo real, não
  inventada.
- **Alucinação** — o modelo afirma algo que não está nas fontes
  fornecidas.
- **Cache semântico** — reaproveitar a resposta de uma pergunta
  anterior parecida em vez de gerar uma nova.
- **Reranking** — reordenar resultados de uma busca inicial por um
  critério mais preciso antes de montar a resposta final.
