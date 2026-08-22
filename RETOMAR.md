# Retomar — coletor único no ControleRendaVariavel

Gravado em 2026-08-22, ao se aproximar o limite de uso. **Nada aqui está
perdido**: o trabalho está commitado e enviado.

## Estado

Branch **`fix/coletor-unico-por-vez`** no ControleRendaVariavel, commit
`cffcc9e`, enviado ao GitHub. **Não revisado, sem PR aberto.**

Os seis outros repositórios estão limpos e em dia — nada pendente neles.

## O que já está feito

1. **A tarefa agendada antiga foi removida da máquina Windows.**
   `ControleRendaVariavel RTD` (modelo pré-VPS) estava instalada junto com
   `ControleRendaVariavel Coletor Remoto`, contra a regra que o próprio
   `README.md` enuncia. Disparava a cada logon e falhava com código 1 desde a
   migração para o VPS; a última coleta real foi 15/08 (ver
   `.docker-local/rtd-control.stdout.log`). Removida com
   `scripts\rtd-host.ps1 -Action Uninstall`; conferido que o agente remoto
   seguiu de pé (`-Action Status` → `enabled`, processo vivo).

2. **`app/__init__.py`** — com `REMOTE_COLLECTOR_ENABLED=true` a aplicação
   deixa de instanciar cliente de controlador local. Em produção ela
   instanciava `RemoteRtdService` apontando para `host.docker.internal:8765`,
   que **não resolve num Linux** — porque `compose.yaml` fixa a URL e o
   segredo `rtd_control_token` está montado no VPS. Não aparecia na tela
   porque `settings.html` já escolhe o bloco por `remote_collector_enabled`:
   interface certa, objeto errado por baixo.

3. **`app/__init__.py`** — `TESTING` passa a desligar o supervisor do
   `RtdServiceManager`. No Windows, `available` vale `sys.platform == "win32"`,
   então **cada `create_app()` da suíte subia uma thread sondando o ProfitChart
   por `powershell.exe` a cada 2 s**, com timeout de 5. A suíte ficava
   inexecutável localmente (dezenas de PowerShell vivos, travamento) e verde no
   CI Linux — a pior combinação para quem precisa verificar antes de commitar.

4. **`tests/test_coletor_unico.py`** — 7 testes. Conferido que **reprovam sem a
   correção**, e com a falha reveladora
   `RuntimeError: Controlador RTD do Windows indisponível`, provando que a
   chamada HTTP condenada de fato acontecia.

5. **`README.md` e `AGENTS.md`** atualizados. O `AGENTS.md` descrevia **só** o
   modelo antigo, afirmando que "a aplicação fala com ele por
   `host.docker.internal`" — falso no VPS. Agora descreve os dois modos e onde
   cada um vale.

## O que falta

- [ ] **Rodar a suíte completa.** Só rodei subconjuntos (19 testes, instantâneos
      depois da correção 3). A execução completa foi interrompida duas vezes:
      antes da correção 3 porque travava, e depois porque o limite se
      aproximava. Comando:
      `.venv\Scripts\python.exe -m pytest -q -p no:cacheprovider`
- [ ] **`python -m ruff check .`** — passou nos arquivos alterados; falta o
      repositório inteiro. **Não rode `ruff format`** em `app/__init__.py`:
      reformataria código pré-existente (`PUBLIC_ENDPOINTS`), e o CI só roda
      `ruff check`.
- [ ] Abrir PR, esperar CI, mesclar, `~/deploy.sh renda`.
- [ ] Depois do deploy, conferir no contêiner que a aplicação não fala mais com
      `host.docker.internal`.

## Decisão pendente do mantenedor

**O modo de controlador local deve continuar existindo?** Hoje ele é o par
`scripts/rtd-host.ps1` + `app/rtd_control_server.py` + `app/host_bootstrap.py`
+ `app/host_env.py`, mais `test_rtd_control_server.py`,
`test_rtd_control_security.py`, `test_host_env.py` e `test_host_bootstrap.py`.

Não é código morto: está testado, documentado, e **funcionou até 15/08**. Só
ficou redundante quando a aplicação foi para o VPS e o agente remoto assumiu.
Serve hoje para rodar RTD contra a pilha local em Docker no Windows.

Minha recomendação foi **manter** — o dano real (as duas coisas instaladas ao
mesmo tempo) já foi eliminado, e agora o código impede a metade que cabe ao
servidor. Remover apaga a única forma de exercitar RTD sem o VPS.

`scripts/rtd-host-common.ps1` **não** pode sair de qualquer forma: o script do
agente remoto também o carrega.

## Não mexer

`app/rtd_service.py` e `tests/test_rtd_service.py` têm alterações **suas**, não
commitadas, de 22/08 05:16 — escondem o console de subprocessos no Windows
(`CREATE_NO_WINDOW`, `SW_HIDE`). Não toquei em nenhum dos dois. Continuam na
árvore de trabalho.
