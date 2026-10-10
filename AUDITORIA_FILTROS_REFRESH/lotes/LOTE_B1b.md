# Lote B1b (CB): reprodução às cegas

Base: http://127.0.0.1:5201

**Território para escrita:** Lançamentos: titular Maridito (owner_id=1), contas 8, 9, 10 e 11. Fechamento de mês: só conta 10. Gerencial, cadastros e tabelas: só entidades criadas por você com prefixo [AUD-B1b]. Reclassificação: conta 8. Dados de teste; o banco será restaurado ao fim.

Leia antes `PROTOCOLO.md`. Este lote **não** traz o resultado que outro agente obteve, de propósito: meça do zero, com a sonda, e classifique com o seu próprio código.

Para cada caso:
1. abra a tela indicada (pode ajustar ids e valores para o seu território, mantendo os **mesmos nomes de filtro**);
2. faça a operação e a variação;
3. registre em `status/ACHADOS_<SEU_ID>.csv`, com a coluna `caso` igual ao **R-número** abaixo.

Se um passo for ambíguo, escolha a leitura mais natural para um usuário e anote em `obs`.

## Casos

- **R001**: tela `/banking/reclassification/?conta=8&categoria=11&currency=BRL`; operação: reclassificacao_revisar; variação: revisar
- **R002**: tela `/banking/statements/`; operação: filtro_global_aplicar; variação: aplicar_grupos
- **R003**: tela `/management/?owner_id=1&institution_id=5&account_id=8&month=2026-09&currency=BRL`; operação: retire_tag; variação: sucesso
- **R004**: tela `/reports/upcoming-movements/?currency=BRL`; operação: Aplicar Titular, Instituicao e Data final (end_date); variação: sucesso
- **R005**: tela `/transactions/?period=2026-11&mode=todos&owner_id=2&institution_id=4&account_id=6&currency=BRL`; operação: Novo lancamento parcelado (3 parcelas) AUD-A1 - Salvar + Confirmar; variação: sucesso
- **R006**: tela `/transactions/?period=2026-11&mode=todos&owner_id=2&institution_id=4&account_id=6&currency=BRL`; operação: Realizar lancamento AUD-A1 (formulario + Confirmar realizacao); variação: cancelar
- **R007**: tela `/banking/reclassification/?conta=8&de=&ate=&categoria=&banco=&texto=&currency=ALL&grupos=bancos%2Ccorretoras%2Ccartoes%2Caplicacoes%2Cadministradas`; operação: reclassificacao (1 lancamento para Outros; prévia com inclusao em lote desmarcada); variação: revisar
- **R008**: tela `/banking/balance/`; operação: filtro_global_aplicar; variação: aplicar_grupos_moeda
- **R009**: tela `/banking/reconciliation/?conta=8&currency=BRL&grupos=bancos%2Ccorretoras%2Ccartoes%2Caplicacoes%2Cadministradas`; operação: filtro_voltar; variação: voltar
- **R010**: tela `/tables/banks/`; operação: excluir instituicao de teste; variação: cancelar
- **R011**: tela `/transactions/?period=2026-11&mode=todos&owner_id=2&institution_id=4&account_id=6&currency=BRL`; operação: Botao Incluir do painel de filtros; variação: nao testado
- **R012**: tela `/management/?owner_id=1&institution_id=5&account_id=8&month=2026-09&currency=BRL`; operação: retire_project; variação: sucesso
- **R013**: tela `/banking/cards/?currency=USD&grupos=bancos%2Ccartoes%2Caplicacoes`; operação: clicar Mostrar todas as contas (filtro de grupos); variação: aplicar
- **R014**: tela `/reports/upcoming-movements/?start_date=2026-10-05&end_date=2026-10-31&mode=a_vencer&owner_id=2&institution_id=4&currency=BRL`; operação: Drilldown Itau / Conta 03 (link da linha) - chegada em Lancamentos; variação: sucesso
- **R015**: tela `/settings/profile/`; operação: tema (Dark e depois Corporate Blue original); variação: sucesso
- **R016**: tela `/banking/balance/?currency=USD&grupos=bancos%2Ccartoes%2Caplicacoes`; operação: navegar pelo menu; variação: navegacao
- **R017**: tela `/management/?owner_id=1&institution_id=5&account_id=8&month=2026-09&currency=BRL`; operação: assign_tag; variação: validacao
- **R018**: tela `/settings/`; operação: politica de senha (salvar mesmo valor 15/0/0/0); variação: sucesso
- **R019**: tela `/tables/accounts/?currency=BRL`; operação: criar conta (Nova conta); variação: sucesso
- **R020**: tela `/transactions/?filter_category=Casa&period=2026-11&mode=a_vencer&owner_id=2&institution_id=4&account_id=6&currency=BRL`; operação: ir ao Dashboard e voltar a Lancamentos pelo menu lateral; variação: sucesso
- **R021**: tela `/banking/imports/?currency=BRL&grupos=bancos%2Ccorretoras%2Ccartoes%2Caplicacoes%2Cadministradas`; operação: filtro_F5; variação: F5
- **R022**: tela `/tables/categories/`; operação: editar grupo de categoria de teste; variação: sucesso
- **R023**: tela `/tables/banks/?filter_type=Banco&currency=BRL`; operação: editar instituicao de teste; variação: sucesso
- **R024**: tela `/transactions/?period=2026-11&mode=todos&owner_id=2&institution_id=4&account_id=6&currency=BRL`; operação: Editar (inline) lancamento AUD-A1; variação: sucesso
- **R025**: tela `/banking/attachments/?currency=BRL&grupos=bancos%2Ccorretoras%2Ccartoes%2Caplicacoes%2Cadministradas`; operação: filtro_voltar; variação: voltar
- **R026**: tela `/reports/projections/?currency=BRL`; operação: Aplicar Titular, Conta e Modo (todos); variação: sucesso
- **R027**: tela `/transactions/?period=2026-11&mode=todos&owner_id=2&institution_id=4&account_id=6&currency=BRL`; operação: Realizar lancamento AUD-A1 (formulario + Confirmar realizacao); variação: sucesso
- **R028**: tela `/banking/reclassification/?conta=8&de=&ate=&categoria=11&banco=&texto=&currency=BRL`; operação: filtro_voltar; variação: voltar
- **R029**: tela `/banking/balance/?currency=ALL&grupos=bancos%2Ccorretoras%2Caplicacoes%2Cadministradas`; operação: filtro global (grupos); variação: F5
- **R030**: tela `/transactions/?period=2026-11&mode=a_vencer`; operação: filtro de coluna Tipo (filter_type); variação: sucesso
- **R031**: tela `/settings/`; operação: politica de bloqueio (salvar mesmo valor 5/1); variação: sucesso
- **R032**: tela `/banking/imports/`; operação: filtro_global_aplicar; variação: aplicar_grupos
- **R033**: tela `/banking/reconciliation/?conta=8&currency=BRL`; operação: filtro_global_aplicar; variação: aplicar_grupos
- **R034**: tela `/reports/account-position/?period=2026-10&mode=realizado&owner_id=1&institution_id=5&currency=BRL`; operação: filtro_menu; variação: menu
- **R035**: tela `/banking/status/`; operação: filtro_global_aplicar; variação: aplicar_grupos
- **R036**: tela `/transactions/?period=2026-11&mode=todos&owner_id=2&institution_id=4&account_id=6&currency=BRL`; operação: Novo lancamento (simples) - abrir formulario; variação: cancelar (link Voltar)
- **R037**: tela `/tables/banks/`; operação: excluir instituicao de teste; variação: sucesso
- **R038**: tela `/banking/accounts/14/?currency=USD&grupos=bancos%2Ccartoes%2Caplicacoes`; operação: period 2026-10 para 2026-09 (conta 14 em dolar) Atualizar; variação: aplicar
- **R039**: tela `/transactions/?filter_type=despesa&period=2026-11&mode=a_vencer&owner_id=2&institution_id=4&account_id=6&currency=BRL`; operação: filtro de coluna Categoria (filter_category); variação: sucesso
- **R040**: tela `/settings/database/?table_name=app_user&currency=BRL`; operação: F5; variação: recarregar
- **R041**: tela `/settings/monthly-close/?filter_account_id=5&filter_year=2026&filter_month=9&filter_status=active`; operação: filtros globais: marcar USD, desmarcar BRL e grupo corretoras, Aplicar; variação: aplicar
- **R042**: tela `/settings/profile/`; operação: filtros globais Aplicar (grupo administradas e desfazer); variação: sucesso
- **R043**: tela `/tables/categories/`; operação: excluir categoria de teste; variação: sucesso
- **R044**: tela `/banking/status/?currency=BRL&grupos=bancos%2Ccorretoras%2Ccartoes%2Caplicacoes%2Cadministradas`; operação: filtro_voltar; variação: voltar
- **R045**: tela `/tables/owners/`; operação: excluir titular de teste; variação: sucesso
- **R046**: tela `/tables/banks/?filter_type=`; operação: aplicar filtro de tipo; variação: sucesso
- **R047**: tela `/transactions/?period=2026-11&mode=todos&owner_id=2&institution_id=4&account_id=6&currency=BRL`; operação: Novo lancamento transferencia entre contas proprias (categoria Transferencia, conta 6 para conta 3) - Salvar + Confirmar; variação: sucesso
- **R048**: tela `/tables/banks/?filter_type=Corretora&currency=BRL`; operação: criar instituicao; variação: sucesso
- **R049**: tela `/banking/reclassification/?conta=8&de=&ate=&categoria=8&banco=&texto=&currency=ALL&grupos=bancos%2Ccorretoras%2Ccartoes%2Caplicacoes%2Cadministradas`; operação: filtros conta e categoria; variação: F5
- **R050**: tela `/permissions/?user_id=2&currency=BRL`; operação: F5; variação: recarregar
- **R051**: tela `/banking/statements/?currency=BRL&grupos=bancos%2Ccorretoras%2Ccartoes%2Caplicacoes%2Cadministradas`; operação: filtro_voltar; variação: voltar
- **R052**: tela `/settings/database/`; operação: verificacao de saude (Health Check); variação: sucesso
- **R053**: tela `/banking/reclassification/?conta=8`; operação: filtro_menu; variação: menu
- **R054**: tela `/tables/owners/`; operação: editar titular de teste; variação: sucesso
- **R055**: tela `/tables/accounts/`; operação: aplicar filtros titular e instituicao; variação: sucesso
- **R056**: tela `/management/?owner_id=1&institution_id=1&account_id=1&month=2026-09&currency=BRL`; operação: save_budget; variação: sucesso
- **R057**: tela `/tables/accounts/?filter_institution_id=3&filter_owner_id=1&currency=BRL`; operação: editar conta de teste (linha em edicao); variação: sucesso
- **R058**: tela `/banking/cards/?currency=USD&grupos=`; operação: F5; variação: apos filtro
- **R059**: tela `/reports/upcoming-movements/`; operação: Links de cabecalho Lancamentos e Parcelas; variação: nao testado
- **R060**: tela `/tables/accounts/?filter_institution_id=3&filter_owner_id=1&currency=BRL`; operação: excluir conta de teste (Excluir); variação: cancelar
