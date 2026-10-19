# Versionamento dos aplicativos

Cada aplicativo tem numeração própria, no formato `vMAIOR.MENOR.CORREÇÃO`
([SemVer](https://semver.org/lang/pt-BR/)), contada desde o primeiro commit de
cada projeto. A numeração anterior (`V2.0`, `V2.1.x`, `V2.5`, `V2.6`) era uma
numeração de suíte aplicada a vários repositórios de uma vez e não dizia nada
sobre o tamanho das mudanças de cada um; foi substituída em 18/10/2026. As tags
e as releases antigas foram removidas, e a tabela de correspondência está no
fim deste documento.

## Regra

| Sobe | Quando |
|---|---|
| **MAIOR** | quebra de contrato, de modelo de dados ou de operação: algo que obriga o consumidor ou o operador a mudar (contrato patrimonial retirado, isolamento dos dados por usuário, moeda por conta, coletor reescrito) |
| **MENOR** | capacidade nova compatível, visível ao usuário ou ao operador (tela, importação, contrato novo, idioma, agente) |
| **CORREÇÃO** | correção, endurecimento de segurança, desempenho, dependências, CI e documentação |

- `v1.0.0` é a primeira versão consolidada de cada projeto (16/08/2026). Os
  projetos que nasceram depois começam em `v0.1.0` (Portal MP e FinancasMCP), e
  o Portal MP chega a `v1.0.0` na entrada em produção.
- A versão em `pyproject.toml` e no `uv.lock` é a da última release.
- Cada release traz a lista dos commits desde a anterior; a tag aponta para o
  último commit do marco.
- O **SharedAuth** já seguia essa lógica desde o início (`v0.1.0` a `v0.14.0`)
  e os aplicativos fixam a versão dele por tag; por isso ele não foi tocado.
- O `manutencao` e o `WealthfolioTeste` são repositórios de ferramenta e de
  operação, não aplicativos, e não têm releases próprias (a tag `V2.5` do
  `manutencao` também foi removida).


## Controle Bancário

Repositório: [MSPA-Coder/sistema-financeiro](https://github.com/MSPA-Coder/sistema-financeiro/releases)

| Versão | Data | Commit | O que mudou |
|---|---|---|---|
| v1.0.0 | 16/08/2026 | `e0c9f6d` | Primeira versão consolidada do Controle Bancário. |
| v1.0.1 | 16/08/2026 | `cfb7429` | Automação e segurança do GitHub, Dependabot e endurecimento do runtime e do PostgreSQL. |
| v1.1.0 | 19/08/2026 | `4f715d3` | Implantação em produção no VPS, com HTTPS, hosts confiáveis e cookies seguros. |
| v1.1.1 | 19/08/2026 | `cbb32fd` | Política de faixas de dependência: mantém os pisos e alarga só o teto. |
| v1.2.0 | 20/08/2026 | `422a9f9` | Passa a consumir o SharedAuth (cabeçalhos e formatação); piso de senha de 8 caracteres; backup local sai para o BackupRestore. |
| v1.2.1 | 21/08/2026 | `98d0bab` | /health consulta o banco; correção do comprovante apagado sem aviso; auditoria de CVE e varredura de imagem. |
| v1.3.0 | 22/08/2026 | `b321538` | Componente comum de confirmação; projeção de recorrências automática uma vez por mês; limpeza de rotas e permissões órfãs. |
| v1.4.0 | 24/08/2026 | `d096fb7` | Sistema de temas sem ícones nem emojis; correções de template. |
| v1.5.0 | 29/08/2026 | `a546b88` | Navegação por HTMX no lugar do AJAX próprio, CSP sem estilo inline e auditoria de agosto. |
| v1.5.1 | 30/08/2026 | `623e2f7` | Revalidação de 29/08: permissões que não guardavam nada, Vary e código morto. |
| v1.6.0 | 03/09/2026 | `096261f` | Ciclo de vida dos lançamentos, correções auditadas, CB-01 a CB-06 e relatório anual. |
| v1.7.0 | 08/09/2026 | `ab15927` | Empacotamento no pyproject, suíte contra PostgreSQL, build reprodutível com uv.lock e Django 6.1. |
| v1.7.1 | 14/09/2026 | `c7e3c51` | Autorização reforçada nas transferências e documentação no estado atual. |
| v2.0.0 | 17/09/2026 | `69edb3b` | Moeda por conta, categoria com tipo, reclassificação e resumo publicado; realizar passa a exigir data. |
| v2.1.0 | 19/09/2026 | `089a36a` | Página de conta, filtro global de moeda, componentes do SharedAuth 0.12 e contrato patrimonial v2. |
| v2.2.0 | 21/09/2026 | `584c7a0` | Contratos patrimoniais v3 somente leitura, com capacidades analíticas. |
| v2.3.0 | 23/09/2026 | `8085bd8` | Projeção de caixa no contrato, ganhos de desempenho e cartão de crédito como tipo de conta. |
| v2.3.1 | 23/09/2026 | `9e759a3` | Correções do encerramento e da projeção de séries recorrentes. |
| v2.4.0 | 23/09/2026 | `17a9b4e` | Fatura de cartão em CSV (C6 e XP), reclassificação em lote, fatura projetada e menu Faturas. |
| v2.4.1 | 24/09/2026 | `44d0c01` | Aplicação conecta com papel restrito; extratos idênticos; fechamento sob lock; IP do cliente na auditoria. |
| v2.5.0 | 26/09/2026 | `452e81a` | Filtros globais de grupos e moeda, dashboard sobre o motor de relatórios e desfazer realização. |
| v2.6.0 | 29/09/2026 | `08e641f` | Contrato patrimonial v4 integrado, com credencial exclusiva; endurecimento de segurança. |
| v2.7.0 | 03/10/2026 | `b05f59b` | Importação de vários extratos de uma vez, conciliação por lote, motor do extrato e PDF da XP. |
| v3.0.0 | 03/10/2026 | `3c37bd3` | Esquema leitura versionado; retira os contratos patrimônio v1 a v3; v4 passa a ser o único, com schema JSON e token próprio. |
| v3.1.0 | 08/10/2026 | `6e1c44d` | Situação das Contas, PDFs do Itaú, Avenue e Mercado Pago, aplicações vinculadas e ajustes da conciliação. |
| v3.2.0 | 09/10/2026 | `f93f8a3` | Formato regional (Brasil/EUA) de datas e números, por usuário. |
| v3.3.0 | 10/10/2026 | `65243ac` | Menu recolhível, filtros preservados, escritas sem recarregar a página e SharedAuth 0.14. |
| v3.4.0 | 11/10/2026 | `653a277` | Interface em português e inglês, com idioma e região por usuário. |
| v3.4.1 | 13/10/2026 | `7656bda` | Padronização de Python, Docker e Dependabot; correções de revisão automática. |
| v3.5.0 | 14/10/2026 | `791bf6b` | Filtros padrão, matriz de transferências, arrastar para rolar e correções de tela. |
| v3.6.0 | 17/10/2026 | `5da9423` | PDF protegido por senha, confiança nas sugestões de categoria e rótulos de transferência acompanhando renomeações. |
| v3.6.1 | 18/10/2026 | `3b5d78d` | Reaproveitamento de parsing, menos consultas e artefatos ARM64 nativos para o VPS. |
| v3.7.0 | 18/10/2026 | (release atual) | Ativo, tipo de renda e liquidação de pregão no lançamento (CB-1) e imagem do PostgreSQL rotulada. |

Tags antigas, removidas:

| Tag antiga | Data | Commit | Dentro de |
|---|---|---|---|
| V2.0 | 16/08/2026 | `e0c9f6d` | v1.0.0 |
| V2.1.0 | 19/08/2026 | `053a2d5` | v1.1.0 |
| V2.1.1 | 22/08/2026 | `822dc62` | v1.4.0 |
| V2.1.2 | 22/08/2026 | `b9ec546` | v1.4.0 |
| V2.1.3 | 24/08/2026 | `d096fb7` | v1.4.0 |
| V2.2.0 | 30/08/2026 | `623e2f7` | v1.5.1 |
| V2.5 | 03/09/2026 | `096261f` | v1.6.0 |
| V2.6 | 13/09/2026 | `79d2d88` | v1.7.1 |

## Controle de Renda Variável

Repositório: [MSPA-Coder/ControleRendaVariavel](https://github.com/MSPA-Coder/ControleRendaVariavel/releases)

| Versão | Data | Commit | O que mudou |
|---|---|---|---|
| v1.0.0 | 16/08/2026 | `a654732` | Primeira versão consolidada do Controle de Renda Variável. |
| v1.0.1 | 16/08/2026 | `a777c18` | Automação do GitHub, endurecimento do host RTD, do PostgreSQL e do build. |
| v1.1.0 | 19/08/2026 | `b50477c` | Agente remoto de cotações e implantação em produção no VPS. |
| v1.2.0 | 20/08/2026 | `bbf903f` | Passa a consumir o SharedAuth (sessão, CSRF, limitador, cabeçalhos, formatação e /health). |
| v1.2.1 | 21/08/2026 | `13bcab9` | Três operações que destruíam histórico passam a perguntar; pool_pre_ping, auditoria de CVE e varredura de imagem. |
| v1.3.0 | 22/08/2026 | `96090c0` | Componente comum de confirmação, um coletor por vez e fim do modo de controlador RTD local. |
| v1.4.0 | 24/08/2026 | `440e313` | Módulo de temas, melhorias de transações e carteiras, gestão de usuários e privacidade visual. |
| v1.5.0 | 29/08/2026 | `644bf7c` | Auditoria de agosto (sessão e segredo) e trilha de auditoria: quem fez o que e quando. |
| v1.5.1 | 30/08/2026 | `8051774` | Cobertura das rotas de administração e limpeza de código morto. |
| v1.6.0 | 03/09/2026 | `6fc23bd` | Prioridades e ciclo de vida, correções de segurança CRV-02 e CRV-03 e privacidade das telas de opções. |
| v2.0.0 | 04/09/2026 | `f87b17f` | Coletor unificado (fases 1 a 4), coleta agrupada em app/collector/ e app/ reorganizado em pacotes de domínio. |
| v2.0.1 | 08/09/2026 | `d65385b` | Console e acentuação do log do coletor, suíte contra PostgreSQL, build reprodutível com uv.lock. |
| v3.0.0 | 13/09/2026 | `ccc99f9` | Isolamento financeiro por usuário: cada dado passa a pertencer a um titular. |
| v3.0.1 | 15/09/2026 | `3632cc2` | Schema legado higienizado, configuração legada do coletor removida e perdas anualizadas pela composta. |
| v3.1.0 | 18/09/2026 | `40f8c03` | Resumo de investimento publicado, página analítica da posição, câmbio e qualidade, métricas para o dashboard. |
| v3.1.1 | 19/09/2026 | `6af0d9e` | Auditoria de segurança e isolamento patrimonial; usuário de runtime separado e checksums do PostgreSQL. |
| v3.2.0 | 21/09/2026 | `e7f9fde` | Contratos patrimoniais v3: atividades e analíticos. |
| v3.2.1 | 22/09/2026 | `7020946` | Fim do N+1 em /risk e /performance, gravação de histórico em lote e estáticos em cache. |
| v3.3.0 | 24/09/2026 | `adb0659` | Remove o delta da cotação; uma posição por chave; fuso de São Paulo no contêiner. |
| v3.4.0 | 26/09/2026 | `dbca58f` | Gráficos de custo médio e bruto; importação de proventos com DY e YOC. |
| v3.5.0 | 29/09/2026 | `a579b5d` | Contrato patrimonial v4 completo (posições e atividades), resultado por ação e proventos. |
| v3.5.1 | 02/10/2026 | `da19b51` | OpenSSL e urllib3 atualizados, provisionamento do banco e importação de histórico estrita. |
| v4.0.0 | 03/10/2026 | `8e7b4b1` | Esquema leitura versionado; retira os contratos patrimônio v1 a v3; v4 é o único, com schema JSON e token novo. |
| v4.1.0 | 05/10/2026 | `528efc2` | Abertura retroativa de posições, correção de lançamentos e substituição de abertura. |
| v4.2.0 | 08/10/2026 | `ede6f5d` | Escala logarítmica nos gráficos de preço e fluxo único de deploy. |
| v4.3.0 | 09/10/2026 | `d12dee4` | Formato regional (Brasil/EUA) de datas e números, por usuário. |
| v4.3.1 | 10/10/2026 | `6064dfb` | Código sem uso removido, SharedAuth 0.14 e outbox v4 com expurgo de 30 dias. |
| v4.3.2 | 13/10/2026 | `ea50025` | Padronização de Python, Docker e Dependabot; correções de confirmação e de decimal regional. |
| v4.3.3 | 16/10/2026 | `b3e25d5` | Conceitos de retorno e exposição corrigidos; revisão manual de dependências. |
| v4.4.0 | 18/10/2026 | `81f048d` | Comandos financeiros protegidos, fronteiras e entrega evoluídas. |
| v4.4.1 | 18/10/2026 | `f631f84` | Artefatos ARM64 nativos validados e publicados para o VPS. |
| v4.5.0 | 18/10/2026 | `b7e9972` | Execuções do myProfit e conferência por pregão (CRV-1) e proventos do Controle Bancário (CRV-2). |
| v4.6.0 | 18/10/2026 | `51dfbfc` | Conciliação mensal com o myProfit: posição e vendas conferidas, com reconhecimento de diferenças. |
| v4.6.1 | 19/10/2026 | (release atual) | Conciliação compara a posição do CRV na mesma data do myProfit; posição com data futura é recusada. |

Tags antigas, removidas:

| Tag antiga | Data | Commit | Dentro de |
|---|---|---|---|
| V2.0 | 16/08/2026 | `a654732` | v1.0.0 |
| V2.1.0 | 19/08/2026 | `ddedd2c` | v1.1.0 |
| V2.1.1 | 22/08/2026 | `e8b6cf9` | v1.4.0 |
| V2.1.2 | 24/08/2026 | `97b8381` | v1.4.0 |
| V2.1.3 | 24/08/2026 | `423cb3c` | v4.5.0 |
| V2.1.4 | 24/08/2026 | `440e313` | v1.4.0 |
| V2.2.0 | 30/08/2026 | `8051774` | v1.5.1 |
| V2.5 | 03/09/2026 | `6fc23bd` | v1.6.0 |
| V2.6 | 13/09/2026 | `ccc99f9` | v3.0.0 |

## Mega-Sena

Repositório: [MSPA-Coder/mega-sena](https://github.com/MSPA-Coder/mega-sena/releases)

| Versão | Data | Commit | O que mudou |
|---|---|---|---|
| v1.0.0 | 16/08/2026 | `58ea471` | Primeira versão consolidada do Mega-Sena. |
| v1.0.1 | 16/08/2026 | `8fb9279` | Automação do GitHub, validação de redirecionamento de login e endurecimento do runtime. |
| v1.1.0 | 19/08/2026 | `3ef937a` | Importação por link e implantação em produção no VPS, com HTTPS. |
| v1.2.0 | 20/08/2026 | `eefedf7` | Passa a consumir o SharedAuth; piso de senha de 8 caracteres; backup local sai para o BackupRestore. |
| v1.2.1 | 21/08/2026 | `4418d0c` | Importar planilha deixa de sobrescrever concurso sem perguntar; auditoria de CVE e varredura de imagem. |
| v1.3.0 | 24/08/2026 | `6eda9f9` | Componente comum de confirmação e aviso. |
| v1.3.1 | 30/08/2026 | `ebca4a1` | Auditoria de agosto: sessão, segredo, CSP; Configurações exige administrador. |
| v1.4.0 | 01/09/2026 | `1ebd158` | Prioridades, auditoria e exclusão de apostas. |
| v1.4.1 | 02/09/2026 | `1771af6` | Correções de segurança MS-01 a MS-04. |
| v1.4.2 | 19/09/2026 | `7d400b6` | Projeto declarado no pyproject, build reprodutível com uv.lock, suíte contra PostgreSQL. |
| v1.5.0 | 30/09/2026 | `86f9a7f` | Histórico de gerações em duas consultas; aplicação conecta com papel restrito; digest do PostgreSQL no Dependabot. |
| v1.6.0 | 09/10/2026 | `60f92e4` | Formato regional (Brasil/EUA) de datas e números, por usuário. |
| v1.6.1 | 13/10/2026 | `8951be9` | Código sem uso removido, SharedAuth 0.14, padronização de Python, Docker e Dependabot. |
| v1.6.2 | 16/10/2026 | `1765472` | Revisão manual de dependências e CA local opcional. |
| v1.7.0 | 18/10/2026 | (release atual) | Comandos atômicos, fluxos no Chromium e entrega validada por digest. |

Tags antigas, removidas:

| Tag antiga | Data | Commit | Dentro de |
|---|---|---|---|
| V2.0 | 16/08/2026 | `58ea471` | v1.0.0 |
| V2.1.0 | 19/08/2026 | `727280d` | v1.1.0 |
| V2.1.1 | 22/08/2026 | `72d4567` | v1.3.0 |
| V2.1.2 | 24/08/2026 | `6eda9f9` | v1.3.0 |
| V2.2.0 | 30/08/2026 | `ebca4a1` | v1.3.1 |
| V2.5 | 02/09/2026 | `1771af6` | v1.4.1 |

## Conforto Térmico

Repositório: [MSPA-Coder/Sistema-de-Controle-de-Indice-de-Conforto-Termico](https://github.com/MSPA-Coder/Sistema-de-Controle-de-Indice-de-Conforto-Termico/releases)

| Versão | Data | Commit | O que mudou |
|---|---|---|---|
| v1.0.0 | 16/08/2026 | `b8e7eee` | Primeira versão consolidada do Conforto Térmico. |
| v1.0.1 | 16/08/2026 | `8445968` | Automação do GitHub, endurecimento do runtime e do PostgreSQL. |
| v1.1.0 | 19/08/2026 | `4b8f1e9` | Implantação segura em produção no VPS. |
| v1.2.0 | 20/08/2026 | `f5922f9` | Passa a consumir o SharedAuth (sessão, CSRF, limitador, cabeçalhos e /health). |
| v1.2.1 | 21/08/2026 | `c6ce5fa` | /api/reset deixa de apagar a série sem trava no servidor; ProxyFix, chave de sessão como segredo e blindagem do db_backend. |
| v1.3.0 | 24/08/2026 | `62f6f1a` | Componente comum de confirmação; correções de exclusão de usuário, login e GET que escrevia no banco. |
| v1.3.1 | 30/08/2026 | `5670282` | Auditoria de agosto: CodeQL, segredo, limitador e áreas não declaradas negadas. |
| v1.4.0 | 01/09/2026 | `bb705fb` | Prioridades, auditoria e manutenção segura. |
| v1.4.1 | 02/09/2026 | `de35224` | Correções de segurança CT-01 a CT-05. |
| v1.4.2 | 14/09/2026 | `5fd42c7` | Empacotamento no pyproject, app/ em pacotes de domínio e trilha própria registrada em ADR. |
| v1.5.0 | 19/09/2026 | `098906a` | IGNU segue Buffington e bulbo úmido acima do seco é recusado. |
| v1.5.1 | 24/09/2026 | `ad35784` | Papel restrito no banco, fila de e-mail que morria ociosa e dia de Brasília nos filtros e gráficos. |
| v1.5.2 | 03/10/2026 | `948f348` | Digest do PostgreSQL, OpenSSL fixado e Dependabot ajustado. |
| v1.6.0 | 09/10/2026 | `ef1c40c` | Formato regional (Brasil/EUA) de datas e números, por usuário. |
| v1.6.1 | 16/10/2026 | `7179e18` | Código sem uso removido, SharedAuth 0.14, padronização de Python, Docker e Dependabot. |
| v1.7.0 | 18/10/2026 | (release atual) | Contratos resilientes, simulação coerente e entrega validada por digest. |

Tags antigas, removidas:

| Tag antiga | Data | Commit | Dentro de |
|---|---|---|---|
| V2.0 | 16/08/2026 | `b8e7eee` | v1.0.0 |
| V2.1.0 | 19/08/2026 | `7c4945f` | v1.1.0 |
| V2.1.1 | 22/08/2026 | `52ea5d3` | v1.3.0 |
| V2.1.2 | 24/08/2026 | `62f6f1a` | v1.3.0 |
| V2.2.0 | 30/08/2026 | `5670282` | v1.3.1 |
| V2.5 | 02/09/2026 | `de35224` | v1.4.1 |

## Portal MP

Repositório: [MSPA-Coder/mp-portal](https://github.com/MSPA-Coder/mp-portal/releases)

| Versão | Data | Commit | O que mudou |
|---|---|---|---|
| v0.1.0 | 08/09/2026 | `18298d3` | Fundação do portal, com contato do site e conformidade LGPD; site institucional incorporado. |
| v0.2.0 | 10/09/2026 | `35708f4` | Tarefas da equipe e autorização interna em um só lugar. |
| v1.0.0 | 10/09/2026 | `01f26dd` | Entrada em produção no VPS dedicado (10/09/2026). |
| v1.1.0 | 10/09/2026 | `8f4259c` | Área autenticada em /painel/ com redirecionamento dos endereços antigos, contas e responsável pelo atendimento. |
| v1.1.1 | 10/09/2026 | `bc3280c` | Higiene pós-lançamento: variável morta, hosts permitidos e Dockerfile. |
| v1.2.0 | 15/09/2026 | `ec9a5d2` | Aviso de chegada de solicitação e regras de segurança do Ruff. |
| v1.2.1 | 24/09/2026 | `3a8d685` | Aplicação conecta com papel restrito e diretrizes de teste. |
| v1.2.2 | 03/10/2026 | `d08a64a` | Postgres por digest e ajuste do Dependabot. |
| v1.3.0 | 10/10/2026 | `9ee21f8` | Logo da MP e telefone comercial publicados; SharedAuth 0.14. |
| v1.4.0 | 11/10/2026 | `a68ba50` | Site estático para a hospedagem compartilhada, com formulário em PHP. |
| v1.4.1 | 18/10/2026 | (release atual) | Verificações de contêiner e dependências padronizadas. |

Tags antigas, removidas:

| Tag antiga | Data | Commit | Dentro de |
|---|---|---|---|
| V0.9_0 | 10/09/2026 | `8f4259c` | v1.1.0 |

## BackupRestore

Repositório: [MSPA-Coder/BackupRestore](https://github.com/MSPA-Coder/BackupRestore/releases)

| Versão | Data | Commit | O que mudou |
|---|---|---|---|
| v1.0.0 | 16/08/2026 | `dc5a849` | Primeira versão consolidada do BackupRestore. |
| v1.0.1 | 16/08/2026 | `ed4c436` | Automação do GitHub, raiz do BackupRestore restringida e sandbox do PostgreSQL endurecido. |
| v1.1.0 | 20/08/2026 | `6ed1a76` | Camada 2 do backup do VPS e escape do argumento entregue ao shell remoto. |
| v1.1.1 | 21/08/2026 | `3436bd5` | Auditoria de CVE das dependências. |
| v1.1.2 | 22/08/2026 | `13fed97` | Código morto removido e sincronização que falha com dump reprovado. |
| v1.2.0 | 29/08/2026 | `4edb70b` | Origem estranha recusada em web.py e sincronização do VPS orquestrada. |
| v1.2.1 | 03/09/2026 | `46242d8` | A falha do backup aparece; indisponibilidade deixa de ser confundida com corrupção. |
| v1.2.2 | 07/09/2026 | `de9afa2` | Ignores alinhados aos projetos irmãos e política de fim de linha (LF) versionada. |
| v1.3.0 | 14/09/2026 | `dcf76f2` | Busca dos backups do portal no VPS dedicado. |
| v1.4.0 | 18/09/2026 | `65710bf` | Backup do NetWorth e kit de recuperação com a foto do patrimônio. |
| v1.5.0 | 22/09/2026 | `5d59591` | Ensaio mensal de restauração, credencial de runtime no kit e totais do acervo em SQL. |
| v1.5.1 | 29/09/2026 | `ae4562a` | Diretrizes de teste; NetWorth retirado do catálogo. |
| v1.6.0 | 03/10/2026 | `d8a0f1f` | Cópia do volume do Wealthfolio, ensaio de RTO e comando para reconstruir o catálogo. |
| v1.7.0 | 10/10/2026 | `c4cf4b8` | Retenção local, sandbox que sobrevive ao reinício do Docker e sincronização que isola a linha estranha. |
| v1.7.1 | 13/10/2026 | `0bbeafd` | Padronização de Python, Docker e Dependabot. |

Tags antigas, removidas:

| Tag antiga | Data | Commit | Dentro de |
|---|---|---|---|
| V1.0 | 16/08/2026 | `dc5a849` | v1.0.0 |
| V1.1.0 | 22/08/2026 | `a18a07d` | v1.1.2 |
| V1.1.1 | 22/08/2026 | `b139bdd` | v1.1.2 |
| V1.1.2 | 22/08/2026 | `13fed97` | v1.1.2 |
| V2.5 | 03/09/2026 | `46242d8` | v1.2.1 |

## FinancasMCP

Repositório: [MSPA-Coder/FinancasMCP](https://github.com/MSPA-Coder/FinancasMCP/releases)

| Versão | Data | Commit | O que mudou |
|---|---|---|---|
| v0.1.0 | 23/09/2026 | `c3f18ae` | Servidor MCP somente leitura sobre o CB, o CRV e o NetWorth. |
| v0.1.1 | 23/09/2026 | `5bd4739` | Produção validada, erros legíveis e instruções do projeto. |
| v0.2.0 | 24/09/2026 | `fa24876` | Carteira com opções, câmbio pela fonte preferida, verificação pós-implantação e grupos de conta do CB. |
| v0.3.0 | 29/09/2026 | `c196eb8` | Sai o sistema NetWorth; cb_lancamentos mostra o status efetivo. |
| v0.3.1 | 30/09/2026 | `4045c7a` | CI com Ruff, pytest e pip-audit; Dependabot. |
| v0.3.2 | 02/10/2026 | `b895dc7` | Regras do CRV atualizadas e dependências travadas no uv.lock. |
| v0.4.0 | 03/10/2026 | `9e889f6` | O servidor lê só as views do esquema leitura; CI com banco contra o main do CB e do CRV. |
| v0.4.1 | 18/10/2026 | (release atual) | Padronização de Python, Docker e Dependabot. |

