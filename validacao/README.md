# Medição de cobertura dos projetos locais

Execute no PowerShell, sem Python ou ferramentas de projeto no host:

```powershell
.\validacao\medir-cobertura.ps1 -RaizProjetos C:\Dev\VSCodeProjects
```

`-Saida` escolhe a pasta de evidências; `-Projetos` aceita uma lista de nomes
para uma rodada focada. A saída padrão fica em `CodexTemp`, ao lado dos
repositórios. O script reconstrói e usa os serviços `quality` de cada projeto,
mantendo lint, análise de tipos e a suíte inteira, inclusive PostgreSQL.
FinancasMCP usa a configuração local de leitura já preparada pelo operador.
O runner também inicia o `postgres-permissoes` do FinancasMCP: um banco separado,
em tmpfs e sem porta publicada, para executar provisionamento e recusas com
credenciais sintéticas. Não use `--no-deps` para a suíte completa desse projeto.

Coverage.py 7.16.2 é instalado num diretório de ferramentas por um contêiner
Python 3.15 e montado somente para leitura nos runners. Não altera as
dependências ou as imagens operacionais das aplicações. O coletor inicia antes
da importação dos testes, inclui módulos não executados e mede linhas e
decisões. SharedAuth é medido no pacote instalado, como seus consumidores o
recebem. As migrações dentro dos pacotes medidos permanecem no denominador.

Cada projeto recebe JSON, XML e HTML de cobertura, resultado da suíte e
identificação do commit e das alterações locais. Pytest também recebe JUnit;
BackupRestore mantém seu runner unittest. Os testes e os diretórios de build
e dependências não são código de produto e ficam fora da métrica.

Leia os percentuais junto dos cenários e das recusas comprovadas. Não omita
módulos de produto para atingir uma meta. A medição aqui cobre o Python; os
fluxos Chromium dos quatro aplicativos usam `compose.browser.yaml`, o portal
também tem sua suíte PHP, e Wealthfolio e os scripts VPS têm runners próprios
documentados nos respectivos repositórios. Não há um percentual comparável de
JavaScript, PHP, Rust e Bash produzido por este coletor.

Os bancos de qualidade são descartáveis. O script não publica aplicações,
executa deploy, apaga volumes ou encerra serviços operacionais. Preserve os
bancos de teste se outra validação estiver usando o mesmo Compose. Rodadas deste
script usam uma trava por projeto. Não execute outro pytest ou teste de mutação
contra o mesmo banco enquanto uma suíte estiver rodando: o runner pode criar e
derrubar seu banco. Mutações de Django precisam de um nome de banco de teste
próprio, além de uma cópia separada dos módulos desde o início do interpretador.

`mutacoes.py` comprova cinco erros representativos nas novas asserções (soma de
ganhadores, resposta HTTP, truncamento de leitura, mistura de moedas e hash de
backup). Recebe `PROBE_PROJECT` com MegaSena, Site_Mp-solucoes, FinancasMCP,
ControleBancario ou BackupRestore e grava o resultado em `/evidence`.
Monte esta pasta como `/validation:ro` e a saída como `/evidence` no serviço
`quality`, então execute `python /validation/mutacoes.py`. O código modificado
vive somente em `/tmp`; Django usa um banco de teste próprio. O probe só conta
uma mutação detectada quando houve falha de asserção, não erro de preparação.
Esses probes não são uma medição de cobertura de mutação do sistema inteiro.
