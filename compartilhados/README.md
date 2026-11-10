# Arquivos compartilhados entre repositórios

Alguns arquivos são iguais, byte a byte, em vários repositórios. Até 02/11/2026
eles eram mantidos iguais à mão: cada mudança virava uma edição e um commit em
cada repositório, e uma cópia já tinha divergido. Agora cada um tem uma cópia
canônica aqui, e `sincronizar.py` a leva aos demais.

| Canônica | Cópias |
|---|---|
| `compartilhados/AGENTS-comum.md` | bloco "Regras comuns" dentro do `AGENTS.md` de treze repositórios, entre os marcadores `<!-- comum: ... -->` |
| `compartilhados/AGENTS-comum-vps.md` | fim do mesmo bloco, só no que o `deploy.sh` implanta (os quatro apps, o WealthfolioTeste, o VivaPasso e o VillaRica) e no `_manutencao`: deploy e dados de produção |
| `docs/TESTES.md` | `docs/TESTES.md` em oito repositórios |
| `docs/contratos/patrimonio-v4.schema.json` | CB, CRV e WealthfolioTeste (ver `docs/contratos/README.md`) |
| `compartilhados/Dockerfile.browser` | os quatro apps (CB, CRV, ConfortoTermico, MegaSena) |
| `compartilhados/provision-db-runtime.sh` | `scripts/` dos quatro apps |
| `compartilhados/gerar_relatorio.py` | `docs/security-audit/` dos quatro apps |

A lista exata está no início de `sincronizar.py`.

## Como mudar um desses arquivos

1. Mude a cópia canônica, aqui.
2. `python compartilhados/sincronizar.py --aplicar` copia para os repositórios
   irmãos (mesma pasta-mãe deste checkout).
3. Em cada repositório alterado, valide como de costume e commite junto com a
   mudança que motivou a cópia.

`python compartilhados/sincronizar.py`, sem argumento, só confere e sai 1 se
alguma cópia divergir. `--pular=Repo` deixa de fora um checkout ocupado.

## O que mais o script reprova (desde 03/11/2026)

A orientação para agentes cresceu de 5 mil para 25 mil palavras em dois meses
no CB, por acúmulo: cada resposta a uma pergunta virava mais um parágrafo,
repetido em cada repositório, e regras velhas ficavam convivendo com as novas.
O script agora barra a volta disso:

- `AGENTS.md` com mais de 900 palavras fora do bloco comum: para acrescentar,
  retire ou funda outra regra;
- caminho citado entre crases (com pasta) que não existe;
- frase do modelo de entrega anterior a 20/10/2026 em `AGENTS.md`, `README.md`
  ou `docs/` (CI que reprova, "abra um PR", checks antes do merge,
  auto-merge). ADRs, `docs/historico/` e relatórios datados ficam de fora;
- menção a dois VPS (só existe o VPS1 desde 05/11/2026);
- seção "Validação proporcional": a validação por tipo de mudança mora na
  seção "Validação" do `AGENTS.md`, e a cópia em `docs/` já tinha divergido
  dela em dois apps.

## Onde mora cada regra

| Lugar | Guarda |
|---|---|
| `~/.claude/CLAUDE.md` (fora do Git) | a máquina: shell, PATH, codificação, acesso ao VPS |
| Bloco comum | o processo igual em todos: quando perguntar, ciclo, dados, dependências, testes |
| Resto do `AGENTS.md` | o que é do repositório, nesta ordem: o sistema, "Validação", limites, armadilhas |
| `docs/` | referência do assunto e ADRs; ADR superado ganha "Substituído por" |

Uma regra aparece num lugar só, e os outros apontam para ele.

Ficaram de fora, de propósito, arquivos com o mesmo nome e conteúdo parecido,
mas diferenças legítimas: `.github/dependabot.yml` (`pip` no ConfortoTermico,
`uv` nos outros), `.github/docker-compose.yml` (CI com ou sem testes de
navegador), os testes de segurança de cada app (cada um testa a integração do
próprio app) e `docker/sandbox-postgres/Dockerfile`.
