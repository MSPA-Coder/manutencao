# Status — CB (ControleBancario)

Última atualização: **2026-08-31 — auditoria concluída**.

Blocos concluídos: **1 a 7 (7/7)**.

Achados numerados válidos: 16 (`CB-01` a `CB-14`, exceto `CB-15`, mais
`CB-16` e `CB-17`). `CB-15` permanece apenas como nota de método, fora da
contagem.

## Estado confirmado

- Sessão autenticada como `mspa` no navegador interno.
- Nove contêineres Docker `healthy`.
- Dashboard no baseline de 1,13x.
- Tela de Permissões contém somente os quatro usuários reais; `ZZTESTE-cb`
  já foi removido pela limpeza coordenada anterior.
- Todos os demais registros `ZZTESTE` também já foram removidos. Zero resíduo
  de teste segundo `ANDAMENTO.md`.
- A senha do mantenedor já foi restaurada. Nenhuma credencial temporária é
  necessária ou deve ser registrada novamente.

## Bloco 6 — conclusão da retomada

- Trilha de auditoria revisada: confirma usuário e horário para criação de
  usuário, perfil, acessos por titular, reset de senha e fechamento mensal.
- `CB-16` registrado: a grade não exibe IP e não audita tags, projetos nem
  orçamento do Controle gerencial.
- `/change-password/` inspecionada sem digitar ou alterar senha: três campos
  obrigatórios, tipos e `autocomplete` adequados; envio vazio ficou inválido.
- `/admin/` reconfirmado: redireciona para `/admin/login/?next=/admin/` e
  informa que `mspa` está autenticado, porém não autorizado.
- `optimize` não foi executado.
- Correções aplicadas ao relatório: `CB-07` agora descreve o fallback inseguro
  real e não culpa o select visível; `CB-14` é inconsistência de configuração;
  `CB-15` está fora da contagem.

## Bloco 7 — conclusão

- 23 rotas principais abertas; zero erro de console e CSP sem bloqueio.
- Navegação/Voltar coerentes; F5 com formulário aberto e depois de POST/redirect
  não criou nem reenviou dado.
- `/health/` respondeu 200/JSON pelo health check do contêiner; o navegador
  interno bloqueou renderizar diretamente o JSON.
- Filtro por tipo funcionou; não há ordenação/paginação, e a tabela usa rolagem.
- Responsividade passou em 390×844; viewport padrão restaurado.
- Formulário principal sem campo visível sem nome acessível.
- `CB-17` registrado: “Ocultar valores” apenas torna o texto transparente; os
  números exatos permanecem no DOM. É o mesmo padrão de RV-15 e fecha T7.
- Autorização por papel continua não testada por depender de login em conta
  comum, conforme a limitação conhecida da rodada.

## Contagem final

- Bloqueio: 2 (`CB-02`, `CB-11`)
- Defeito: 8 (`CB-03`, `CB-05`, `CB-06`, `CB-07`, `CB-10`, `CB-13`, `CB-16`, `CB-17`)
- Inconsistência: 5 (`CB-01`, `CB-04`, `CB-08`, `CB-12`, `CB-14`)
- Observação: 1 (`CB-09`)
- Melhoria não numerada: 1

Nenhum registro real foi alterado nesta retomada.

## Remediação e revalidação — 2026-08-31

O mantenedor autorizou a implementação local das correções. O estado histórico
acima continua sendo a fotografia da auditoria; esta seção registra o resultado
posterior à correção.

| Achado | Estado após correção |
|---|---|
| CB-01 | Corrigido: Posição por conta ganhou coluna e total de transferências internas. |
| CB-02 | Corrigido globalmente: o núcleo esconde `.edit-row` e mostra `.edit-row.is-editing`; os CSS de página não controlam mais visibilidade. Regressão e conferência em Lançamentos, Titulares e Instituições passaram. |
| CB-03 | Corrigido: titulares e instituições agora rejeitam nomes duplicados sem diferenciar maiúsculas/minúsculas, também por restrição no banco. |
| CB-04 | Corrigido: mensagens de constraint validation são apresentadas em pt-BR. |
| CB-05 | Corrigido no escopo decidido: criar, editar, realizar e excluir lançamentos registram ator e resultado. |
| CB-06 | Corrigido: o resíduo fica na última parcela (`100,00 = 33,33 + 33,33 + 33,34`), inclusive em edição e transferência. |
| CB-07 | Corrigido: o select visível envia `operation_scope`, não há espelho hidden, o padrão é `single` e ausência/inválido em grupo retorna HTTP 400. |
| CB-08 | Corrigido: filtro por operação deriva as contas da própria operação autorizada. |
| CB-09 | Permanece observação/lacuna: upload e autorização cross-user de comprovante não foram exercitados. |
| CB-10 | Corrigido: saldo patrimonial de Projeções é canônico e independe do filtro de status. |
| CB-11 | Investigado e reclassificado: não há exclusão automática; há exclusão explícita, substituição intencional de blocos e cascata de operação bancária. A nova auditoria melhora a rastreabilidade. |
| CB-12 | Corrigido: despesas no Painel gerencial usam sinal negativo. |
| CB-13 | Corrigido: `min_length` usa piso de domínio 8 no HTML. |
| CB-14 | O perfil Operador chegou a ser aplicado à Claudia, que permaneceu `user` (12/31 funcionais, 0/5 críticas). O mantenedor depois informou que esse dado de teste não precisava de nova validação. |
| CB-16 | Atendido no escopo decidido: IP, proxy confiável, request ID, resultado e resumo foram acrescentados aos eventos de lançamentos e fechamento mensal. Tags, projetos e orçamento ficaram deliberadamente fora. |
| CB-17 | Encerrado por decisão de produto: a necessidade é proteção visual contra quem olha a tela, não confidencialidade/autorização. O recurso virou “Modo discreto”, mascara valores e oculta gráficos, mas continua documentado como preferência visual local. |

Validação integrada: `ruff` e **239 testes** passaram no serviço Docker de
qualidade; três migrations foram aplicadas; todos os serviços ficaram
saudáveis. No navegador interno passaram Modo discreto, edição de cadastro,
mensagem pt-BR, piso de senha, auditoria, escopo de exclusão, Posição por conta,
Projeções e Painel gerencial.

Foi criado e removido um parcelamento `ZZTESTE-REVALIDACAO-100-3`. O banco
voltou a **714 lançamentos**, a operação temporária foi removida e há zero
lançamento `ZZTESTE`. Permanecem apenas os eventos esperados de criação e
exclusão na trilha de auditoria. Nenhum commit foi criado.
