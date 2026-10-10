# Lote B1 (CB): reprodução às cegas

Base: http://127.0.0.1:5201

**Território para escrita:** Lançamentos: titular Esposita (owner_id=2), contas 3, 4, 6, 15 e 22. Fechamento de mês: só conta 15. Gerencial, cadastros e tabelas: só entidades criadas por você com prefixo [AUD-B1]. Reclassificação: conta 6. Dados de teste; o banco será restaurado ao fim.

Leia antes `PROTOCOLO.md`. Este lote **não** traz o resultado que outro agente obteve, de propósito: meça do zero, com a sonda, e classifique com o seu próprio código.

Para cada caso:
1. abra a tela indicada (pode ajustar ids e valores para o seu território, mantendo os **mesmos nomes de filtro**);
2. faça a operação e a variação;
3. registre em `status/ACHADOS_<SEU_ID>.csv`, com a coluna `caso` igual ao **R-número** abaixo.

Se um passo for ambíguo, escolha a leitura mais natural para um usuário e anote em `obs`.

## Casos

- **R001**: tela `/banking/reclassification/?conta=8`; operação: filtro_categoria_aplicar; variação: aplicar
- **R002**: tela `/banking/reclassification/?currency=ALL&grupos=bancos%2Ccorretoras%2Ccartoes%2Caplicacoes%2Cadministradas`; operação: filtros conta e categoria; variação: aplicar
- **R003**: tela `/settings/audit-log/?entity_name=app_user&action=create&currency=BRL`; operação: voltar; variação: historico
- **R004**: tela `/management/`; operação: filtro_aplicar; variação: aplicar
- **R005**: tela `/banking/balance/?currency=BRL&grupos=bancos%2Ccorretoras%2Ccartoes%2Caplicacoes%2Cadministradas`; operação: filtro_global_voltar; variação: voltar
- **R006**: tela `idem`; operação: reclassificacao (gravar e confirmar dialogo Reclassificar); variação: gravar
- **R007**: tela `/settings/database/`; operação: aplicar filtro de tabela; variação: sucesso
- **R008**: tela `/management/?owner_id=1&institution_id=5&account_id=8&month=2026-09&currency=BRL`; operação: assign_tag; variação: sucesso
- **R009**: tela `/tables/categories/`; operação: excluir categoria de teste; variação: cancelar
- **R010**: tela `/banking/balance/?currency=ALL&grupos=bancos%2Ccorretoras%2Ccartoes%2Caplicacoes%2Cadministradas`; operação: filtro global (grupos); variação: aplicar
- **R011**: tela `/banking/attachments/`; operação: filtro_global_aplicar; variação: aplicar_grupos
- **R012**: tela `/settings/monthly-close/?filter_account_id=5&filter_year=2026&filter_month=10&filter_status=active&currency=BRL`; operação: core:settings_reopen_month (reabrir 2026-10 conta 5); variação: sucesso
- **R013**: tela `/banking/imports/?currency=BRL&grupos=bancos%2Ccorretoras%2Ccartoes%2Caplicacoes%2Cadministradas`; operação: filtro_voltar; variação: voltar
- **R014**: tela `idem`; operação: reclassificacao (devolver a categoria original); variação: gravar
- **R015**: tela `/tables/accounts/?filter_institution_id=3&filter_owner_id=1&currency=BRL`; operação: voltar; variação: historico
- **R016**: tela `/tables/categories/?filter_type=normal&currency=BRL`; operação: criar categoria; variação: sucesso
- **R017**: tela `/transactions/?period=2026-11&mode=todos&owner_id=2&institution_id=4&account_id=6&currency=BRL`; operação: Ver operacao (link na linha); variação: sucesso
- **R018**: tela `/operations/?currency=BRL`; operação: Aplicar filtros Tipo (operation_type), Status (status) e Inicio (start); variação: sucesso
- **R019**: tela `/reports/projections/?start_month=2026-04&end_month=2027-04&mode=todos&owner_id=2&account_id=6&detail=complete&currency=BRL`; operação: Drilldown do mes 2026-04 (link da tabela) - chegada em Lancamentos; variação: sucesso
- **R020**: tela `/management/?owner_id=1&institution_id=1&account_id=1&month=2026-09&currency=BRL`; operação: create_project; variação: F5
- **R021**: tela `/management/?owner_id=1&institution_id=1&account_id=1&month=2026-09&currency=BRL`; operação: create_tag; variação: sucesso
- **R022**: tela `/tables/owners/`; operação: criar titular; variação: sucesso
- **R023**: tela `/transactions/?period=2026-11&mode=todos&owner_id=2&institution_id=4&account_id=6&currency=BRL`; operação: voltar (back) apos exclusao; variação: sucesso
- **R024**: tela `/transactions/?period=2026-11&mode=todos&owner_id=2&institution_id=4&account_id=6&currency=BRL`; operação: Desfazer realizacao lancamento AUD-A1 (formulario + Desfazer); variação: sucesso
- **R025**: tela `/banking/reconciliation/?currency=ALL&grupos=bancos%2Ccorretoras%2Ccartoes%2Caplicacoes%2Cadministradas`; operação: filtros globais; variação: voltar
- **R026**: tela `/settings/monthly-close/`; operação: aplicar filtros conta/ano/mes/status; variação: sucesso
- **R027**: tela `/settings/profile/`; operação: rolagem de tabela (25 e depois 20 original); variação: sucesso
- **R028**: tela `/reports/projections/`; operação: Links de cabecalho Lancamentos e Parcelas; variação: nao testado
- **R029**: tela `/management/?owner_id=1&institution_id=1&account_id=1&month=2026-09&currency=BRL`; operação: filtro_voltar; variação: voltar
- **R030**: tela `/settings/profile/`; operação: sem filtro na tela; variação: N/A
- **R031**: tela `/settings/`; operação: data inicial do sistema (salvar mesma data); variação: sucesso
- **R032**: tela `/tables/banks/`; operação: criar instituicao; variação: erro de validacao
- **R033**: tela `/management/?owner_id=1&institution_id=1&account_id=1&month=2026-10&currency=BRL`; operação: menu_ir_voltar; variação: menu
- **R034**: tela `/transactions/?period=2026-11&mode=todos&owner_id=2&institution_id=4&account_id=6&currency=BRL`; operação: Novo lancamento recorrente mensal AUD-A1 - Salvar + Confirmar; variação: sucesso
- **R035**: tela `/banking/reconciliation/`; operação: filtros globais (moeda e grupos); variação: aplicar
- **R036**: tela `/banking/reclassification/?currency=ALL&grupos=bancos%2Ccorretoras%2Ccartoes%2Caplicacoes%2Cadministradas`; operação: filtros conta e categoria; variação: ir e voltar pelo menu (Conciliacao e volta)
- **R037**: tela `/tables/categories/`; operação: criar grupo de categoria; variação: erro de validacao
- **R038**: tela `/tables/categories/`; operação: aplicar filtro de tipo (Normal); variação: sucesso
- **R039**: tela `/banking/reclassification/?conta=8&de=&ate=&categoria=8&banco=&texto=&currency=ALL&grupos=bancos%2Ccorretoras%2Ccartoes%2Caplicacoes%2Cadministradas`; operação: filtros conta e categoria; variação: voltar
- **R040**: tela `/banking/balance/?currency=ALL&grupos=bancos%2Ccorretoras%2Ccartoes%2Caplicacoes%2Cadministradas`; operação: comparar saldo (previa; variação:  sem gravar)
- **R041**: tela `/dashboard/?currency=BRL`; operação: Aplicar filtros Titular, Instituicao, Conta, Tipo (filter_type) e Agrupamento (categorias); variação: sucesso
- **R042**: tela `/transactions/?period=2026-11&mode=todos&owner_id=2&institution_id=4&account_id=6&currency=BRL`; operação: Limpar filtros de coluna (link); variação: sucesso
- **R043**: tela `/settings/monthly-close/?filter_account_id=5&filter_year=2026&filter_month=9&filter_status=active`; operação: core:settings_close_month (fechar 2026-10 conta 5); variação: sucesso
- **R044**: tela `/transactions/?period=2026-11&mode=todos&owner_id=2&institution_id=4&account_id=6`; operação: voltar (back) apos sucesso; variação: sucesso
- **R045**: tela `/permissions/?user_id=2&currency=BRL`; operação: voltar; variação: historico
- **R046**: tela `/tables/categories/`; operação: criar grupo de categoria; variação: sucesso
- **R047**: tela `/management/?owner_id=1&institution_id=5&account_id=8&month=2026-09&currency=BRL`; operação: assign_project; variação: sucesso
- **R048**: tela `/settings/monthly-close/?filter_account_id=5&filter_year=2026&filter_month=9&filter_status=active`; operação: core:settings_close_month (fechar 2026-09 conta 5 - desfazer); variação: sucesso
- **R049**: tela `/dashboard/?period=2026-10&mode=todos&owner_id=2&institution_id=4&account_id=6&filter_type=receita&categorias=categoria&currency=BRL`; operação: F5; variação: sucesso
- **R050**: tela `/reports/account-position/?period=2026-10&mode=realizado&owner_id=1&institution_id=5&currency=BRL`; operação: filtro_voltar; variação: voltar
- **R051**: tela `/tables/categories/`; operação: excluir grupo de categoria de teste; variação: sucesso
- **R052**: tela `/management/?owner_id=1&institution_id=5&account_id=8&month=2026-09&currency=BRL`; operação: assign_tag; variação: F5
- **R053**: tela `/management/?owner_id=1&institution_id=5&account_id=8&month=2026-09&currency=BRL`; operação: retire_tag; variação: voltar
- **R054**: tela `/management/?owner_id=1&institution_id=1&account_id=1&month=2026-09&currency=BRL`; operação: create_tag; variação: cancelar
- **R055**: tela `/management/?owner_id=1&institution_id=1&account_id=1&month=2026-09&currency=BRL`; operação: create_project; variação: sucesso
- **R056**: tela `/tables/accounts/?filter_owner_id=1&currency=BRL`; operação: ir e voltar pelo menu (Instituicoes e Contas); variação: menu
- **R057**: tela `/settings/monthly-close/?filter_account_id=5&filter_year=2026&filter_month=9&filter_status=active`; operação: core:settings_reopen_month (reabrir 2026-09 conta 5 - desfazer); variação: sucesso
- **R058**: tela `/tables/categories/`; operação: editar categoria de teste; variação: sucesso
- **R059**: tela `/transactions/?period=2026-11&mode=todos&owner_id=2&institution_id=4&account_id=6&currency=BRL`; operação: Novo lancamento (simples) - Salvar + Confirmar lancamento; variação: sucesso
- **R060**: tela `/settings/database/?table_name=app_user&currency=BRL`; operação: voltar; variação: historico
- **R061**: tela `/tables/accounts/?filter_institution_id=3&filter_owner_id=1&currency=BRL`; operação: excluir conta de teste (Excluir); variação: sucesso
