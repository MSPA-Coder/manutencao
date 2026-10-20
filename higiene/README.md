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
- O Dropbox não interpreta `.dropboxignore` dentro dos projetos. A configuração
  nativa atual é `rules.dropboxignore` na raiz da conta Dropbox, por dispositivo.
  A raiz atual dos projetos está fora da pasta Dropbox configurada; não é
  necessário alterar a sincronização para este workspace.

Se o workspace voltar a uma pasta sincronizada, confirme primeiro a localização
na configuração local do Dropbox. Só então configure regras na raiz daquela
conta, limitadas à árvore de desenvolvimento. Não exclua a pasta de projetos
inteira, nem use sincronização seletiva para preservar arquivos exclusivamente
locais. As regras novas não removem conteúdo já sincronizado. A sintaxe e esses
limites estão na [documentação oficial do Dropbox](https://help.dropbox.com/sync/how-to-prevent-files-from-syncing).

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
