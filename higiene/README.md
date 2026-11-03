# Higiene local dos projetos

O workspace atual é `C:\Dev\VSCodeProjects`. Git controla o código; Docker
executa aplicações e validações. Arquivos intermediários e evidências ficam
em `CodexTemp`, ao lado dos repositórios. Os diretórios `CodexTemp` que já
existem dentro de um projeto também precisam ser ignorados pelo Git e pelo
contexto Docker.

## Limpar caches com conferência de alvos

No PowerShell, a partir deste repositório:

```powershell
# Simula; cada execução recebe uma pasta de evidências própria.
.\higiene\limpar-caches.ps1

# Aplica apenas aos caches reconhecidos e inteiramente ignorados pelo Git.
.\higiene\limpar-caches.ps1 -Aplicar
```

`-RaizProjetos` escolhe a pasta que contém os repositórios; `-Saida` escolhe uma
pasta nova dentro dessa raiz. O CSV registra caminho absoluto, quantidade e
tamanho dos arquivos. A ferramenta só remove `__pycache__`, `.pytest_cache`,
`.ruff_cache` e `.mypy_cache`, depois de conferir que não contêm arquivos
versionados nem arquivos novos não ignorados. Links e reparse points interrompem
a operação antes da exclusão do alvo.

Ambientes virtuais, `node_modules`, `.git`, `CodexTemp`, dados, segredos,
certificados, logs operacionais, backups e volumes não são alvos dessa rotina.
Caches e exportações de scanners em `CodexTemp` exigem análise individual:
confira o manifesto, se há consumidor ativo e se a imagem exportada continua
disponível antes de descartar uma cópia. Não use `git clean -fdx` ou uma poda
global do Docker como substituto dessa conferência.

## Três mecanismos diferentes de ignore

- `.gitignore` protege arquivos novos. Arquivos já rastreados continuam no
  índice, mesmo quando casam com uma regra. Confira com `git ls-files --cached
  --ignored --exclude-standard`; exemplos públicos devem ter exceções explícitas.
- `.dockerignore` limita o contexto enviado ao builder. Padrões para caches em
  subpastas precisam cobrir essa profundidade, por exemplo `**/__pycache__`.
  Confira também que fontes, testes e migrações necessários ao Dockerfile
  continuam disponíveis.
- O Dropbox não lê arquivo de ignore dentro dos projetos. A proteção
  preventiva usa duas camadas, descritas abaixo.

## Dropbox: proteção preventiva em duas camadas

O workspace fica fora do Dropbox, mas qualquer projeto pode voltar para lá. Duas
camadas impedem que segredos, dados e ambientes subam junto. Ambas foram
conferidas em 03/11/2026: o item ignorado fica sem o atributo `ReparsePoint`
(0x400), que o Dropbox põe em tudo o que sincroniza.

1. **Marca por item (`.dropignore` + `dropignore.py`).** Cada pasta do workspace
   tem um `.dropignore` com a sintaxe do `.gitignore`. A ferramenta grava em cada
   item que casa o fluxo NTFS `com.dropbox.ignored`, e o Windows leva essa marca
   junto quando a pasta é movida dentro do mesmo disco. Pasta marcada protege
   tudo o que nascer nela; arquivo solto perde a marca se for apagado e
   recriado, então rode `--aplicar` de novo antes de mover.

   ```powershell
   py -3 .\higiene\dropignore.py C:\Dev\VSCodeProjects            # confere; sai 1 se faltar marca
   py -3 .\higiene\dropignore.py C:\Dev\VSCodeProjects --aplicar  # grava o que falta
   ```

2. **Regras nativas (`rules.dropboxignore` na raiz do Dropbox).** Valem para
   conteúdo novo, inclusive segredo criado depois dentro de pasta sincronizada.
   O arquivo não sincroniza, então cada computador precisa da sua cópia. As
   regras ficam restritas a `/Programacao/VSCodeProjects/` e
   `/Programacao/PycharmProjects/`: um `*.dump` global cortaria a cópia que o
   BackupRestore grava em `Programacao/Backups`.

Limites do Dropbox: regra nova não remove o que já subiu; renomear um arquivo
sincronizado para um nome que casa com a regra apaga a cópia em dropbox.com; e
negação com `**` no meio não funciona, então `.env.example` também fica de fora
(ele já está no Git). Não use sincronização seletiva para manter arquivos só na
máquina. Sintaxe e limites na [documentação oficial do Dropbox](https://help.dropbox.com/sync/how-to-prevent-files-from-syncing).

## Migrações e scripts

Migrações aplicadas são histórico operacional. Não as apague pela idade, por
não aparecerem em imports ou por um banco local estar atualizado. Verifique o
grafo com o loader oficial da aplicação, em Docker, sem executar manutenção
de dados. Bytecode residual de migrações pertence aos caches descartáveis;
revisões e dependências permanecem no repositório.

Uma busca sem referências é apenas um candidato a revisão: scripts podem ser
chamados com `python -m`, por CI, pelo Agendador do Windows ou manualmente.
Confirme esses consumidores antes de arquivar. Preserve prompts e planos ainda
pendentes, artefatos de release e evidências de validação.
