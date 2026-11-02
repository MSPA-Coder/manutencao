# Arquivos compartilhados entre repositórios

Alguns arquivos são iguais, byte a byte, em vários repositórios. Até 02/11/2026
eles eram mantidos iguais à mão: cada mudança virava uma edição e um commit em
cada repositório, e uma cópia já tinha divergido. Agora cada um tem uma cópia
canônica aqui, e `sincronizar.py` a leva aos demais.

| Canônica | Cópias |
|---|---|
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
alguma cópia divergir.

Ficaram de fora, de propósito, arquivos com o mesmo nome e conteúdo parecido,
mas diferenças legítimas: `.github/dependabot.yml` (`pip` no ConfortoTermico,
`uv` nos outros), `.github/docker-compose.yml` (CI com ou sem testes de
navegador), os testes de segurança de cada app (cada um testa a integração do
próprio app) e `docker/sandbox-postgres/Dockerfile`.
