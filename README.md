# Manutenção — memória de decisão dos seis projetos

Este repositório não guarda produto. Guarda o **porquê**: os planos de cada
rodada de trabalho que atravessa mais de um projeto, e os arquivos de
infraestrutura que vivem no VPS mas não pertencem a repositório nenhum dos
projetos.

Existe porque decisões como *"o Flask-Talisman saiu porque o nginx já faz o
HSTS"* ou *"não deduplicamos o bloco de contrato do Postgres porque acoplaria
dois repositórios a um terceiro por 15 linhas"* não cabem num commit e somem
da memória em duas semanas. Um plano registra a decisão, a alternativa
recusada e o motivo — inclusive quando o motivo foi "tentamos e não
funcionou".

## Os projetos

Seis repositórios, todos privados em `MSPA-Coder`:

| Projeto | O que é |
|---|---|
| ConfortoTermico | Flask + PostgreSQL, índice de conforto térmico animal (ICT + coletor Modbus) |
| ControleBancario | Django + PostgreSQL, controle financeiro |
| ControleRendaVariavel | Flask + PostgreSQL, carteira de investimentos com coletor RTD no host Windows |
| MegaSena | Flask + PostgreSQL, estatística de concursos |
| BackupRestore | ferramenta Flask **de host**, deliberadamente sem contêiner — ela gerencia os contêineres dos outros |
| SharedAuth | biblioteca Python consumida pelos quatro apps |

Os quatro primeiros rodam em produção num VPS Oracle, com deploy por
`~/deploy.sh <projeto>`.

## Os planos

| Plano | Estado |
|---|---|
| [PLANO_MANUTENCAO.md](PLANO_MANUTENCAO.md) | concluído — varredura de análise, limpeza e redocumentação dos 5 projetos |
| [PLANO_RESSINCRONIZACAO_VPS.md](PLANO_RESSINCRONIZACAO_VPS.md) | concluído — fluxo local → GitHub → VPS, e o `deploy.sh` |
| [PLANO_BACKUPRESTORE_VPS.md](PLANO_BACKUPRESTORE_VPS.md) | concluído — backup da produção em duas camadas |
| [PLANO_RETIRAR_BACKUPS_LOCAIS.md](PLANO_RETIRAR_BACKUPS_LOCAIS.md) | concluído — um backup, um dono |
| [PLANO_UNIFICAR_AUTENTICACAO.md](PLANO_UNIFICAR_AUTENTICACAO.md) | concluído — login e mensagens viram o SharedAuth |
| [PLANO_EQUALIZAR_BASE_COMPARTILHADA.md](PLANO_EQUALIZAR_BASE_COMPARTILHADA.md) | concluído — cabeçalhos/CSP, formatação pt-BR, `/health` e convenções de CI |
| [PLANO_SINAL_E_DEFEITOS.md](PLANO_SINAL_E_DEFEITOS.md) | **aberto** — sinal de falha, rollback no deploy, confirmação de operação destrutiva e varredura de vulnerabilidade |
| [INVENTARIO_OPERACOES_DESTRUTIVAS.md](INVENTARIO_OPERACOES_DESTRUTIVAS.md) | referência — 124 operações que mudam estado nos quatro apps, com reversibilidade |

Nenhum plano está aberto no momento. Os dois últimos são a leitura obrigatória
antes de mexer em autenticação ou em política de segurança de qualquer um dos
quatro apps.

**Um plano é histórico, não especificação.** Ele registra o estado do mundo
quando foi escrito. Se o código discordar do plano, o código está certo e o
plano está velho — confira antes de agir sobre o que estiver escrito aqui.

## `vps/` — infraestrutura do servidor

Cinco arquivos que rodam no VPS e não pertencem a nenhum repositório de
projeto, versionados aqui:

| Arquivo | Onde vive no servidor |
|---|---|
| `deploy.sh` | `/home/ubuntu/deploy.sh` |
| `backup-agent.sh` | `/home/ubuntu/backup-agent.sh` — o agente restrito, preso por `command=` no `authorized_keys` |
| `backup-db.sh` | `/home/ubuntu/backup-db.sh` |
| `backup-db.service` · `backup-db.timer` | `/etc/systemd/system/` |

**Editar aqui não implanta nada.** A cópia do servidor é a que roda; esta é
para ter histórico e para poder reconstruir. Depois de mudar um destes,
copie para o VPS e confira com `sha256sum` dos dois lados — foi assim que a
igualdade foi verificada pela última vez em 2026-08-20.

## Nada de credencial aqui

O `.gitignore` recusa `.env`, `.secrets/`, chaves e arquivos com "password" ou
"token" no nome. Mas a guarda real é humana: o conteúdo daqui é texto corrido
escrito à mão, e já aconteceu de uma senha de produção entrar num plano sem
ninguém notar. Em Git isso é permanente — apagar depois não tira do histórico.

Credencial vai para um gerenciador de senhas. Um plano pode dizer *que existe*
uma conta administrativa; nunca a senha dela.
