# STATUS B1b (CB) - lote concluido

- Aba: tab-2 (viewport 1366x900, fechada ao final). A tab-8 original foi perdida; a sessao voltou apos o login do mantenedor.
- Casos: R001 a R060 tratados. Nao executados: R015 (tema sem salvar visivel) e R056 (orcamento sem nome para prefixo, evitado). R052 nao medido (sem saida visivel e sonda nao instalada).
- Contagem (ACHADOS_B1b.csv): R=28, M=6, F=7, OK=16, NAO_EXECUTADO=2, NAO_MEDIDO=1 (total 60).
- Casos mais relevantes: R014 (drill-down perde intervalo de datas), R020 e R036 (menu/voltar sem filtros), R039 (coluna Categoria descarta filtro Tipo), R053/R034/R059 (menu perde conta/periodo/titular), R001 e R007 (Revisar de reclassificacao recarrega e perde todos os filtros).
- Desfazer: concluido. Excluidos (todos com prefixo [AUD-B1b]): tag R003 e projeto R012 (retirados), categoria R022 (R043), instituicao R010/R023 (R037), titular R045 e R054 (excluido), corretora R048, conta R019 (id 27), transferencia de teste conta 8 para conta 9 e parcelado R005 (todas as parcelas). Verificado: nenhum [AUD-B1b] restante na gestao, nas listas de contas, categorias, instituicoes, titulares e lancamentos da conta 8 e 9 no periodo.
- Entidades de outros agentes ([AUD-B1] etiqueta teste, [AUD-B1] categoria teste) nao foram tocadas.
- Notas de metodo:
  - Formularios HTMX (hx-trigger=change) trocam appMain; refs ficam obsoletos. Releitura por find.
  - Botoes de cadastro/edicao/exclusao abrem modal SharedAuth; o OK so grava com Confirmar/Salvar do modal.
  - Acionamento por foco (DOM) + tecla Enter, quando o clique por ref caia em celula ou fora da area.
  - Varios casos foram lidos direto pela URL (sonda nao reinstalada em todos); anotado em obs.
  - Territorio: usei titular 1, instituicao 5 e conta 8 nas escritas; titular 2 e conta 6 so em leitura.
