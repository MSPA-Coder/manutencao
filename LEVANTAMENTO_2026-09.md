# Levantamento de setembro/2026 — decisões e riscos vigentes

Este arquivo guarda o que continua valendo do levantamento em profundidade de
07/09/2026 sobre os repositórios da conta `MSPA-Coder`: as decisões tomadas, os
riscos aceitos com o gatilho que deve reabri-los e a matriz de achados, que o
código e os documentos dos outros repositórios citam pelo número (`L01`…`L24`).

A análise de cada achado e o roteiro das fases F0–F7 estão no histórico do Git
deste arquivo, na versão anterior a 14/09/2026. O mesmo vale para a auditoria
de agosto e para a rodada de teste funcional pelo navegador, encerradas e
retiradas do repositório na mesma data.

## Veredito

A pilha — Python, Flask e Django, PostgreSQL, Docker, nginx num VPS, HTML no
servidor com HTMX — é adequada para aplicações de baixo volume mantidas por uma
pessoa. O que faltava não era tecnologia: era prova automática dos invariantes
que a documentação declarava. As fases executadas fecharam a maior parte disso
(suítes contra PostgreSQL, build reprodutível, sentinela de erro de aplicação).

## Decisões do mantenedor

| Item | Decisão (07/09/2026) | Situação em 14/09/2026 |
|---|---|---|
| F2 — backup de mídia e ensaio de RTO | Adiada | Riscos L05 e L06 aceitos (abaixo) |
| L07 — publicar imagem e implantar por digest | Não fazer | Risco aceito; `uv.lock` e base por digest (F3) reduziram a diferença à camada do `apt-get upgrade` |
| L19 — domínio próprio | Manter DuckDNS por enquanto | Risco aceito |
| L11 — GitHub Pro para o repositório do cliente | Fica como está | Risco aceito, mitigado em parte |
| ConfortoTermico | Trilha própria | ADR 008 no repositório dele; seção própria abaixo |

**A frota** é MegaSena, ControleBancario e ControleRendaVariavel, que evoluem
juntos; o MpPortal segue o mesmo padrão operacional. O ConfortoTermico diverge
só no código: continua no VPS, no `deploy.sh`, no vigia, no backup e
consumindo `SharedAuth`.

**Recomendação do levantamento, não regra:** aplicação nova tende a nascer em
Django, porque ele já traz sessão, CSRF, hash de senha e administração que, nos
apps Flask, vêm do `SharedAuth`. Foi o caminho do MpPortal; a escolha continua
aberta a cada projeto novo.

## Riscos aceitos

| Achado | O que se aceita | Revisitar quando | Situação |
|---|---|---|---|
| **L05** — `media_volume` sem backup | Perda do VPS restaura o banco do ControleBancario, mas **não** os comprovantes: as linhas voltam apontando para arquivos que não existem mais. | Os comprovantes deixarem de ser reconstituíveis por outra via, ou surgir obrigação fiscal ou contratual de guardá-los. | Vigente |
| **L06** — RTO desconhecido | Sabe-se que o dump restaura; não se sabe em quanto tempo o ambiente inteiro volta, nem se o `KIT_RECUPERACAO.md` está completo. | Antes de o portal do cliente entrar no ar. | **Gatilho disparado**: o portal está no ar desde 10/09/2026 |
| **L07** — imagem servida ≠ imagem testada | O `deploy.sh` reconstrói a imagem no VPS; com lock e base por digest, só os pacotes do sistema operacional podem variar. | Um deploy falhar por dependência diferente da testada. | Vigente |
| **L19** — DuckDNS no site do cliente | Sufixo compartilhado, sem autoridade de domínio e sem e-mail no domínio. | Antes de divulgar o site em cartão, proposta comercial ou anúncio — trocar depois de indexado exige 301 e paciência. | Vigente; também impede o canal real do titular exigido pela LGPD |
| **L11** — repositório do cliente sem proteção de branch | A `main` do `mp-portal` (privado, plano gratuito) não tem ruleset, status check obrigatório nem CodeQL. | Já disparou: essa `main` derruba o site e toca dado de terceiro. | Alertas e correções de segurança do Dependabot ligados em 14/09/2026; o resto depende de plano pago ou de tornar o repositório público |

## ConfortoTermico (mestrado)

Fora do roteiro da frota, com arquitetura livre (ADR 008 do repositório). O que
o levantamento deixou como sugestão, sem prazo:

- os testes que conferem autorização lendo o código-fonte
  (`inspect.getsource`) passam depois de uma refatoração que quebra
  comportamento e falham depois de uma que não quebra; testes numéricos de
  `app/termico/thermal_indices.py` contra os exemplos das fontes valeriam mais —
  inclusive numa defesa;
- `db_backend.py` e o JavaScript próprio são escolhas do projeto, não dívida de
  padronização.

## Matriz de achados

| # | Eixo | Achado | Situação |
|---|---|---|---|
| L01 | Verificação | Nenhuma aplicação testava contra banco | ✅ F1 |
| L02 | Verificação | Teste de migração não aplicava migração | ✅ F1 |
| L03 | Verificação | Piso de Python declarado e não testado | ✅ F1 — piso passou a 3.14 |
| L04 | Processo | Commits parados em branches locais | ✅ F0 |
| L05 | Persistência | `media_volume` sem backup no VPS | Risco aceito |
| L06 | Persistência | RTO nunca medido | Risco aceito, gatilho disparado |
| L07 | Entrega | Imagem servida nunca testada nem varrida | Risco aceito |
| L08 | Observabilidade | Sem visibilidade de erro de aplicação | ✅ F4 — sentinela de 5xx |
| L09 | Segurança | `manutencao` público com proteções desligadas | ✅ F0 |
| L10 | Segurança | `non_provider_patterns` desligado nos repositórios públicos | Indisponível na plataforma |
| L11 | Segurança | Repositório do cliente sem proteção de branch | Risco aceito |
| L12 | Segurança | `AGENTS.md` negava CodeQL que existe | ✅ F0 |
| L13 | Padronização | ConfortoTermico é outra arquitetura | ✅ F6 — ADR 008 |
| L14 | Padronização | `manutencao` sem ShellCheck e Dependabot | ✅ F0 |
| L15 | Performance | Adequada para o volume atual | Nada a fazer |
| L16 | Site | Dados de contato de exemplo em produção | ✅ F0 — mascarados até haver dados reais |
| L17 | Site | SPA por hash prejudicava o SEO | ✅ F5 |
| L18 | Site | Imagens sem `lazy` e sem dimensão | ✅ F5 |
| L19 | Site | Domínio DuckDNS para cliente | Risco aceito |
| L20 | Site | LGPD entra com o formulário | ✅ F7 — publicado em 10/09/2026 |
| L21 | Site | Portal nasce em Django, em repositório novo | ✅ F7 — o site foi incorporado ao portal (ADR 0003 do MpPortal) |
| L22 | Processo | Documentação viva à deriva | ✅ F0 |
| L23 | Entrega | Engrenagem de token do `SharedAuth` | ✅ F3 |
| L24 | Segurança | Repositórios aceitavam action de terceiro | ✅ F0 |

## O que continua aberto

- **Analytics do site** (item 6 da F5): não feito, porque exige recurso
  externo. O `AGENTS.md` do MpPortal descreve como uma exceção dessas entra.
- As pendências de operação do portal — L06, L19, contatos mascarados e aviso de
  chegada — estão em `MpPortal/docs/operacao.md`. O timer do expurgo e a cópia
  do backup fora do servidor foram resolvidos em 14/09/2026.
