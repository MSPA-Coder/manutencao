# Plano de ressincronização do VPS — iniciado 2026-08-19

Fluxo alvo definido pelo mantenedor: **local → GitHub → VPS**.
Verdade do código: o `main` local/GitHub. Verdade dos dados: o VPS.

VPS: `ubuntu@163.176.214.214` · chave em `C:\Users\MSPA\Downloads\OracleKeys\ssh-key-2026-08-17.key`
(exige `chmod 600` numa cópia; a permissão original de `Downloads` é recusada pelo OpenSSH).
`sudo` sem senha disponível. Código em `/home/ubuntu/apps/<projeto>`.

Backup de segurança: `C:\Users\MSPA\VPS-Backup-20260819\` (fora do Dropbox — contém senhas).

## Estado das fases

| Fase | Descrição | Status |
|---|---|---|
| 0 | Rede de segurança: segredos, dumps, snapshot do código do VPS | ✅ 2026-08-19 |
| 1 | Faxina: repos privados, branches `codex/*`, `fetch --prune` | ✅ 2026-08-19 |
| 1b | Acesso do VPS ao GitHub via deploy keys somente-leitura | ✅ 2026-08-19 |
| 2 | Ressincronizar os 4 projetos do VPS a partir do `main` | ✅ 2026-08-19 (os 4) |
| 3 | Script de deploy no VPS + documentação dos 4 projetos | ✅ 2026-08-19 |
| 4 | Zerar pendências: Dependabot, docs incorretas, arquivos órfãos | ✅ 2026-08-19 |

Decisões do mantenedor (2026-08-19): pode derrubar cada app alguns minutos na Fase 2
(um por vez); Dependabot fica ligado, os 8 PRs abertos são tratados depois da Fase 2;
repos públicos não foram intencionais — tornar privados.

## Achados da Fase 0

- **Dados vivem em volumes Docker**, fora da pasta do código. Reclonar o código
  não encosta nos dados. É isso que torna a Fase 2 segura.
- **Dentro da pasta do código, fora do Git**: `.secrets/` (senha do Postgres, chave
  de sessão, tokens) e `.env.vps` / `.env.docker`. Perder isso deixa os dados
  inacessíveis. Já copiados para o backup.
- **Nenhum segredo real versionado** nos 4 repos — só arquivos `.example`.
- **39 arquivos editados direto no servidor**: 30 idênticos ao `main`; 9 (todos no
  ControleRendaVariavel) são uma migração pela metade misturando o desenho antigo
  (`operational_profile`) com o novo (agente remoto). O `main` V2.1.0 já concluiu
  essa migração. Nada de valor a recuperar.
- **ConfortoTermico no VPS não é um clone válido** (branch `master` sem commits) —
  na Fase 2 é substituído por um clone limpo, como os outros.
- Portas dos containers presas em `127.0.0.1`; só 22/80/443 expostas. nginx +
  Let's Encrypt para `bancario-`, `conforto-`, `megasena-`, `renda-mspa.duckdns.org`.

## Procedimento da Fase 2 (por projeto, um de cada vez)

1. `docker compose down` na pasta do projeto
2. Mover a pasta atual para `<projeto>.old` (não apagar até o app voltar)
3. `git clone` do `main` para `/home/ubuntu/apps/<projeto>`
4. Restaurar `.secrets/` e `.env.vps` / `.env.docker` do backup
5. `docker compose up -d --build`
6. Conferir `healthy` + abrir o endereço HTTPS no navegador
7. Só então remover `<projeto>.old`

## Branches locais `codex/*` apagadas na Fase 1 (2026-08-19)

Recuperáveis por ~90 dias com `git branch <nome> <sha>` dentro do projeto.

| Projeto | Branch | SHA | Último commit |
|---|---|---|---|
| ControleBancario | `codex/controle-bancario-vps-pilot` | `92d960dcf6e0c7adf36bf46ab7a48c534c935584` | Preparar Controle Bancário para VPS |
| ConfortoTermico | `codex/pre-sync-v2.1.0-conforto` | `17ca888f761f295f7c67a0c9f82fbdbe4c463346` | feat: aprimora operação e interface |
| MegaSena | `codex/megasena-vps-pilot` | `ae7725566acc1493b139f0b7d3eb06355002a179` | Preparar MegaSena para importação por link e VPS |
| ControleRendaVariavel | `codex/pre-sync-v2.1.0-renda` | `35f79afd9fb3cd1a1a01543a4cb6ea50b5ca4db7` | fix: preserva supervisor RTD no Windows |

## Acesso do VPS ao GitHub (Fase 1b, 2026-08-19)

Os 4 repositórios são privados. O VPS usa **deploy keys somente-leitura**, uma por
projeto, em `/home/ubuntu/.ssh/deploy_<nome>` com apelidos em `/home/ubuntu/.ssh/config`.
Cada chave só enxerga o seu repositório (isolamento verificado) e não pode fazer push.

| Apelido | Repositório | URL de clone |
|---|---|---|
| `github-bancario` | MSPA-Coder/sistema-financeiro | `git@github-bancario:MSPA-Coder/sistema-financeiro.git` |
| `github-conforto` | MSPA-Coder/Sistema-de-Controle-de-Indice-de-Conforto-Termico | `git@github-conforto:MSPA-Coder/Sistema-de-Controle-de-Indice-de-Conforto-Termico.git` |
| `github-megasena` | MSPA-Coder/mega-sena | `git@github-megasena:MSPA-Coder/mega-sena.git` |
| `github-renda` | MSPA-Coder/ControleRendaVariavel | `git@github-renda:MSPA-Coder/ControleRendaVariavel.git` |

Para revogar: GitHub → repositório → Settings → Deploy keys → remover
"VPS Oracle (deploy, somente leitura)".


## Armadilhas descobertas na Fase 2 (aplicam-se aos 3 projetos restantes)

1. **`.certs/` e `.secrets/` são ignorados pelo Git** e ficam dentro da pasta do
   projeto. Ambos precisam ser devolvidos após o clone, ou o *build* falha
   (`.certs`) ou o banco fica inacessível (`.secrets`). Confirmado: os 3 projetos
   restantes também têm as duas pastas.
2. **`secret_key` pertence ao UID 999 com modo 400** — copiar com
   `sudo cp -a`, senão dá "Permission denied" e o arquivo não vai.
3. **Só o `mega-sena/.env.vps` tinha `
` literal** (barra invertida + n) no fim
   de uma linha, o que derrubava o app em laço de reinício porque o código atual
   valida os valores. Os `.env` dos outros 3 projetos estão limpos — verificado
   com `grep -cF '
' <arquivo>`. **Não usar Perl/sed com `/\n/` para detectar:**
   nessa forma o padrão vira uma quebra de linha real e casa com todas as linhas.
4. **`docker compose up -d` não recria o container** quando só o `.env` mudou e o
   container está em laço de reinício. Usar `--force-recreate`.
5. Ordem que funcionou: `down` (sem `-v`) → renomear para `.old` → `git clone` →
   devolver `.secrets` e `.certs` (com `sudo cp -a`) → devolver `.env` **já
   corrigido** → `up -d --build` → conferir `healthy` e HTTP.

## MegaSena — concluído 2026-08-19

Código: `727280d` idêntico ao `main`, 0 alterações locais.
Dados preservados: 3.045 sorteios, 1 usuário.
Acesso: `/login` HTTP 200, `/` 302, redirecionamento HTTP→HTTPS 301.
Pasta antiga preservada em `/home/ubuntu/apps/mega-sena.old` (remover após o
mantenedor confirmar o acesso pelo navegador).

## ConfortoTermico — concluído 2026-08-19

Código: `22f04bf` (V2.1.0) idêntico ao `main`, 0 alterações locais. O repositório
quebrado (branch `master` sem commits) deixou de existir; o clone trouxe 0 arquivos
novos — o código do servidor já era o mesmo, só não estava sob controle do Git.
Dados preservados: 42 equipamentos, 19 configurações, 6 usuários, 5 zonas.
Acesso: `/login` 200, `/` 302, HTTP→HTTPS 301. Coletor e schema OK
(`schema` sai com código 0 por natureza — é serviço de migração de uso único).
Pasta antiga em `/home/ubuntu/apps/conforto-termico.old` até confirmação.

**Melhoria de procedimento:** clonar para uma área de preparo *antes* de derrubar
os containers e só então trocar as pastas. Reduz o tempo fora do ar a segundos.

## ControleBancario — concluído 2026-08-19

Código: `053a2d5` (PR #16) idêntico ao `main`, 0 alterações locais. Clone trouxe
0 arquivos novos. Dados preservados: 860 auditoria, 717 lançamentos, 307 operações,
136 permissões, 107 linhas de extrato, 52 migrações (nenhuma nova aplicada — schema
inalterado). `collectstatic` regenerou 196 arquivos estáticos (esperado: o serviço
`migrate` roda com `--clear`). Volume de mídia estava e segue vazio.
Acesso: `/` 302, `/admin/` 302, HTTP→HTTPS 301. `migrate` sai com 0 por natureza.
Pasta antiga em `/home/ubuntu/apps/controle-bancario.old` até confirmação.

## ControleRendaVariavel — concluído 2026-08-19

Único projeto com divergência real de código: o servidor tinha o desenho antigo
(`operational_profile`) misturado com pedaços do novo. O `main` V2.1.0 concluiu
essa migração. Clone trouxe 1 arquivo novo (`tests/test_collector_settings.py`);
o `compose.yaml` do servidor já era idêntico ao do `main`.

Ponto que tornou a troca segura: o banco **já estava** na última revisão
(`20260819_0008_schedule`), a mesma que o `main` espera — nenhuma migração rodou.
Isso confirma que as migrações foram aplicadas no servidor sem commit correspondente.

Dados preservados: 7.356 cotações, 100 dividendos, 31 ativos, 29 vencimentos de
opções, 27 movimentos, 26 ativos em carteira, 21 posições, 18 transações.
Acesso: `/login` 200, `/` 302, HTTP→HTTPS 301.
Flags booleanas aqui são tolerantes (`getenv(...).lower() == "true"`), então o modo
de falha do MegaSena não se repete.

Arquivo só do servidor, arquivado em `VPS-Backup-20260819/.../renda-avulsos.tgz`:
`scripts/rtd-production-runner.ps1` (tarefa agendada do Windows para o controlador
RTD). **Candidato a entrar no repositório** — hoje existe só no servidor.

## Fase 2 encerrada — estado final verificado

| Projeto | VPS | GitHub | Alterações locais | `/login` |
|---|---|---|---|---|
| conforto-termico | `22f04bf` | `22f04bf` | 0 | 200 |
| controle-bancario | `053a2d5` | `053a2d5` | 0 | 200 |
| mega-sena | `727280d` | `727280d` | 0 | 200 |
| controle-renda-variavel | `ddedd2c` | `ddedd2c` | 0 | 200 |

Resta remover `/home/ubuntu/apps/controle-renda-variavel.old` após confirmação.

## Fase 3 — concluída 2026-08-19

### Script de deploy

`/home/ubuntu/deploy.sh` (cópia versionada em `_manutencao/vps/deploy.sh`).

```
~/deploy.sh --status            estado dos quatro projetos
~/deploy.sh <projeto> --check   mostra o que mudaria, sem alterar
~/deploy.sh <projeto>           implanta
```

Projetos: `bancario` · `conforto` · `megasena` · `renda`.

O script **aborta se a árvore do servidor estiver suja** (testado), avança só em
`--ff-only`, espera os health checks e exige HTTP 200 no endereço público antes
de declarar sucesso. É isso que impede a repetição do problema original.

### Documentação

PRs mesclados: sistema-financeiro #17, Conforto-Termico #13, mega-sena #16,
ControleRendaVariavel #12. CI passou nos quatro antes do merge.

Em cada projeto: seção "Implantação em produção" no `AGENTS.md`, seção
"Produção" no `README.md` e `docs/deployment-vps.md` atualizado — clone por
deploy key (as URLs HTTPS não funcionam mais, repos privados), atualização por
`deploy.sh`, o que não é versionado e onde ficam os dados.

Criados no ConfortoTermico, que não tinha nenhum dos dois:
`docs/deployment-vps.md` e `docs/adr/006-implantacao-vps.md`.

Corrigido: o README do ControleRendaVariavel apontava
`rendavariavel-mspa.duckdns.org`; o domínio real é `renda-mspa.duckdns.org`.

### Versionamento no GitHub

Já estava correto — nada a fazer. Os quatro repositórios têm as tags `V2.0` e
`V2.1.0` publicadas e uma *Release* `V2.1.0` marcada como "Latest", apontando
para o commit que foi para produção.

### Observação sobre repositórios privados

No plano gratuito, regras de proteção de branch só existem em repositório
público. Os quatro não tinham proteção antes nem depois; a convenção de PR é
disciplina, não imposição do GitHub.

### Correção de registro

Uma leitura anterior desta manutenção afirmava que os `.env` de conforto,
bancário e renda tinham `
` literal. Falso: só o `mega-sena/.env.vps` tinha.
O comando de detecção usava um padrão Perl que casava com todas as linhas.

## Fase 4 — zerar pendências, 2026-08-19

### Dependabot: 8 PRs → 0

Consolidados em um PR por repositório, cada um validado localmente **antes** de
subir (estágio `quality` reconstruído sem cache + verificação da imagem de
runtime), depois CI, merge, e os PRs originais fechados com justificativa.

| Repositório | PR | Mudanças | Validação local |
|---|---|---|---|
| ControleRendaVariavel | #13 | `python:3.12→3.14` | ruff limpo · 119 testes · `create_app` com 71 rotas em 3.14.7 |
| sistema-financeiro | #18 | pdfplumber ≥0.11.10 · pytest 9 · pytest-django ≥4.14 | ruff limpo · 76 testes · Django 5.2.17 + pdfplumber 0.11.10 |
| mega-sena | #18 | **Flask-Limiter 3→4** · `python:3.13→3.14` · ruff 0.16 · pytest 9 | ruff limpo · 44 testes · limitador registrado · `GET /login` 200 |

O único salto com efeito em produção foi o Flask-Limiter (major), que protege o
login contra força bruta — por isso a verificação foi além dos testes.

ConfortoTermico não tinha PRs: Dependabot está ativo e configurado (pip, docker,
github-actions) e não encontrou nada desatualizado. **Zero alertas de segurança
abertos nos quatro repositórios.**

### Documentação incorreta

`MegaSena/AGENTS.md` e `README.md` afirmavam que CodeQL cobria análise de código.
Não existe workflow de CodeQL nem configuração automática, e o histórico de
execuções não registra nenhuma análise. Corrigido (PR mega-sena #17): a
documentação agora diz o que existe — CI (Compose + `quality`) e Dependabot — e
declara explicitamente a ausência de varredura de código, para que seja decisão
visível e não esquecimento. Só o MegaSena tinha essa afirmação.

### Arquivo órfão resolvido

`scripts/rtd-production-runner.ps1` existia só no servidor. **Não entra no
repositório**: `scripts/rtd-host.ps1` registra a tarefa agendada chamando
`python -m app.rtd_control_server` diretamente, nada referencia o runner, e ele
menciona `operational_profile` — o desenho removido no V2.1.0. É resto da
migração inacabada. Arquivado em
`VPS-Backup-20260819/.../codigo-vps/renda-avulsos.tgz`.

### Pendência que permanece por decisão

`deploy.sh` não pertence a nenhum dos 4 repositórios — é infraestrutura do VPS.
Vive em `/home/ubuntu/deploy.sh` e versionado aqui em `_manutencao/vps/`.
Os quatro `docs/deployment-vps.md` o documentam. Decidir se merece repositório
próprio quando houver mais infraestrutura compartilhada.

## Correção dentro da Fase 4 — política de faixas de dependência

Ao consolidar os PRs do Dependabot eu aceitei as faixas como vinham e **elevei
os pisos mínimos**. Isso contraria a política do mantenedor, que estava
registrada apenas num comentário do PR #7 do ConfortoTermico, já fechado:

> eleva o mínimo para pytest 9.1.1, o que contraria a política de manter o piso
> 8.3 por compatibilidade deliberada. A configuração `widen` permitirá versões
> compatíveis sem alterar esse mínimo.

O padrão correto está no PR #10 do mesmo projeto: `pytest>=8.3,<9` →
`pytest>=8.3,<10`. **Alarga o teto, mantém o piso.** Os quatro repositórios
usam `versioning-strategy: widen`.

Corrigido em sistema-financeiro #19 e mega-sena #19. As versões instaladas não
mudaram em nenhum caso — o pip já resolvia para a mais nova permitida; o piso só
declara a compatibilidade mínima verificada.

**Para não repetir:** a regra passou a constar na seção de versões do
`AGENTS.md` dos quatro projetos, com o motivo.

## Ponto cego do Dependabot descoberto aqui

Fechar um PR do Dependabot faz ele registrar "não aviso mais sobre esta versão".
No ConfortoTermico, o lote inicial de 5 PRs foi fechado em 16/08 com a nota de
que "a próxima execução agendada reavaliará" — mas o Dependabot não recria um PR
idêntico já fechado. Quatro daquelas propostas estavam certas de ficar fechadas
(só elevavam pisos), mas a do `python:3.14` era legítima e sumiu em silêncio: o
projeto ficou em 3.13 enquanto os outros três foram para 3.14. Retomada em
Conforto-Termico #14.

Ao fechar um PR do Dependabot no futuro, verificar depois se a proposta volta.

## Decisões do mantenedor, 2026-08-19

- Repositórios permanecem **privados**. A única perda relevante é a proteção de
  branch (indisponível em repo privado no plano gratuito); o ganho é não
  publicar domínios, portas, caminhos e nomes de arquivos de segredo que a
  documentação de implantação agora contém.
- `deploy.sh` fica onde está: `/home/ubuntu/deploy.sh` no VPS e versionado em
  `_manutencao/vps/`. Não vira repositório próprio enquanto for um script só.
- Teto do pytest no ControleRendaVariavel alargado para `<10`, alinhando os
  quatro projetos.

## Verificado e sem ação necessária

- **CodeQL nunca esteve ativo** em nenhum dos quatro. Só o MegaSena afirmava o
  contrário na documentação; corrigido em mega-sena #17.
- **Zero alertas de segurança abertos** nos quatro repositórios.
- Dependabot ativo e configurado nos quatro (pip, docker, github-actions).
