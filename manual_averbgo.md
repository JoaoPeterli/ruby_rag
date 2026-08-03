# Manual Técnico do Sistema AverbGo

Versão: 1.0

Este documento descreve o funcionamento técnico do sistema AverbGo utilizado para recepção, validação, processamento e averbação de documentos fiscais eletrônicos.

---

# Capítulo 1 - Visão Geral

O AverbGo é responsável por receber documentos fiscais eletrônicos enviados por APIs, robôs de captura ou integrações diretas.

Os principais documentos suportados são:

- MDFe
- CTe
- NFe

Após o recebimento, o sistema inicia um fluxo de validação antes da averbação.

---

# Capítulo 2 - Recepção

Todo documento recebido é armazenado inicialmente na fila de processamento.

Cada documento recebe um identificador interno único.

O XML é validado contra o schema oficial da SEFAZ.

Caso o XML esteja inválido o processamento é interrompido.

---

# Capítulo 3 - Validação

Durante a validação são conferidos:

- CNPJ do emitente
- Chave de acesso
- Tipo do documento
- Situação fiscal
- Estrutura XML

Caso alguma informação obrigatória esteja ausente o documento será rejeitado.

---

# Capítulo 4 - Busca de Apólice

Após validar o documento o sistema procura uma apólice compatível.

São utilizados:

- CNPJ do emitente
- Transportadora
- Ramo
- Vigência

Caso exista uma apólice válida o processamento continua.

Caso nenhuma apólice seja encontrada o documento permanece pendente.

---

# Capítulo 5 - Averbação

Após localizar uma apólice válida inicia-se o processo de averbação.

A averbação consiste em registrar o documento junto à seguradora.

Após a confirmação o sistema grava:

- número da averbação
- data
- hora
- seguradora

---

# Capítulo 6 - Pendências

Existem diversas situações que podem gerar pendências.

Exemplos:

- XML inválido
- CNPJ inexistente
- Apólice vencida
- Emitente bloqueado
- Erro interno

Pendências podem ser reprocessadas posteriormente.

---

# Capítulo 7 - Cancelamentos

Quando um documento é cancelado o sistema identifica o evento.

Caso exista averbação ativa ela poderá ser cancelada dependendo da seguradora.

Todos os eventos ficam registrados para auditoria.

---

# Capítulo 8 - Reprocessamento

Documentos pendentes podem ser enviados novamente para processamento.

O reprocessamento executa novamente todas as etapas:

- validação
- busca de apólice
- averbação

Caso o problema tenha sido resolvido o documento será processado normalmente.

---

# Capítulo 9 - Usuários

O sistema possui controle de usuários.

Cada usuário possui:

- nome
- email
- senha
- perfil

Os perfis disponíveis são:

- Administrador
- Operador
- Auditor

Cada perfil possui permissões diferentes.

---

# Capítulo 10 - Auditoria

Todas as ações realizadas são registradas.

São armazenados:

- usuário
- data
- IP
- operação
- resultado

Esses registros permitem rastrear qualquer alteração.

---

# Capítulo 11 - API

A API utiliza autenticação JWT.

Todas as requisições devem enviar:

Authorization: Bearer TOKEN

Caso o token seja inválido a API responderá HTTP 401.

---

# Capítulo 12 - Banco de Dados

O sistema utiliza PostgreSQL.

As principais tabelas são:

- documentos
- pessoas
- apolices
- averbacoes
- eventos

Todas as consultas utilizam índices para melhorar desempenho.

---

# Capítulo 13 - Filas

Processamentos assíncronos utilizam Sidekiq.

Cada etapa pode ser executada por um Worker diferente.

Isso reduz o tempo de resposta da API.

---

# Capítulo 14 - Observabilidade

O sistema registra logs estruturados.

São coletadas métricas como:

- tempo de processamento
- quantidade de erros
- documentos processados
- filas pendentes

Essas métricas são enviadas para ferramentas de monitoramento.

---

# Capítulo 15 - Segurança

As senhas nunca são armazenadas em texto puro.

Todos os tokens possuem tempo de expiração.

As comunicações utilizam HTTPS.

Os acessos são registrados para auditoria.

---

# Capítulo 16 - Integração com AWS

O sistema utiliza diversos serviços AWS.

Entre eles:

- Lambda
- SQS
- ECS
- CloudWatch
- Secrets Manager
- RDS PostgreSQL

Os serviços trabalham de forma integrada para garantir escalabilidade.

---

# Capítulo 17 - Arquitetura

O sistema segue arquitetura baseada em microsserviços.

Cada serviço possui responsabilidade única.

A comunicação ocorre principalmente por eventos e filas.

Essa arquitetura reduz o acoplamento entre módulos.

---

# Capítulo 18 - Escalabilidade

O processamento pode ser distribuído entre vários Workers.

O número de consumidores aumenta automaticamente conforme o volume de documentos.

Essa estratégia reduz gargalos durante horários de pico.

---

# Capítulo 19 - Recuperação de Erros

Quando ocorre falha temporária o sistema agenda uma nova tentativa.

Após diversas tentativas sem sucesso o documento é enviado para fila de erro.

Operadores podem iniciar o reprocessamento manual.

---

# Capítulo 20 - Considerações Finais

O AverbGo foi projetado para suportar alto volume de documentos fiscais.

A utilização de PostgreSQL, pgvector, embeddings e inteligência artificial permite criar mecanismos avançados de busca semântica.

Essa abordagem facilita localizar informações técnicas mesmo quando a pergunta utiliza palavras diferentes da documentação original.
