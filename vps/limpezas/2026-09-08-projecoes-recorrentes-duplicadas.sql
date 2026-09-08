-- Limpeza pontual: lançamentos recorrentes duplicados pela projeção.
--
-- CONTEXTO
--
-- `transactions/recurring_projection.py` do ControleBancario usava como molde
-- todas as linhas da maior data de cada operação recorrente e criava uma linha
-- nova por molde. Quando um mês tinha duas linhas iguais, todo mês seguinte
-- nascia com duas, e o seguinte a esse com quatro. O defeito de propagação foi
-- corrigido no PR #59 do `sistema-financeiro`; este arquivo trata do resíduo
-- que ficou nos dados.
--
-- Os pares originais são de 31/07 e 06/08/2026 e vieram de uma implementação
-- anterior, que não existe mais no repositório.
--
-- Em 08/09/2026 o resíduo era de 8 lançamentos e R$ 7.660,00 no futuro, em
-- quatro operações, igual no banco local e em produção.
--
-- COMO RODAR
--
--   Conferir (não altera nada):
--     psql ... -v aplicar=0 -f 2026-09-08-projecoes-recorrentes-duplicadas.sql
--   Aplicar (exige backup verificado antes):
--     psql ... -v aplicar=1 -f 2026-09-08-projecoes-recorrentes-duplicadas.sql
--
-- O QUE ESTE SCRIPT NÃO APAGA, DE PROPÓSITO
--
-- 1. Nada realizado nem vencido, e nada com vencimento no passado. O resíduo é
--    projeção futura; passado é histórico e não se reescreve por script.
-- 2. Nada de grupo em que alguma linha tenha `source_entry_id`. Duas linhas na
--    mesma data e operação são o desenho normal de uma transferência
--    recorrente -- destino e origem --, e ali duas linhas é o certo.
-- 3. Nada que alguém referencie. As cinco chaves estrangeiras que apontam para
--    `cash_flow_entry` são `NO ACTION`, então uma linha conciliada, anexada,
--    etiquetada ou ligada a projeto faria a transação estourar. Preferir
--    excluí-las aqui deixa o motivo explícito em vez de virar erro de banco.
-- 4. A primeira linha de cada grupo (`MIN(id)`), que é a que fica.

\set ON_ERROR_STOP on
BEGIN;

CREATE TEMP TABLE excedentes ON COMMIT DROP AS
WITH grupos AS (
    SELECT bank_operation_id, due_date, account_id, category_id, entry_type,
           entry_amount, MIN(id) AS manter
    FROM cash_flow_entry
    WHERE bank_operation_id IS NOT NULL AND is_recurring
    GROUP BY 1, 2, 3, 4, 5, 6
    HAVING COUNT(*) > 1 AND COUNT(source_entry_id) = 0
)
SELECT e.id, e.description, e.due_date, e.entry_type, e.entry_amount,
       e.bank_operation_id
FROM cash_flow_entry e
JOIN grupos g
  ON  g.bank_operation_id = e.bank_operation_id
  AND g.due_date          = e.due_date
  AND g.account_id        = e.account_id
  AND g.category_id       = e.category_id
  AND g.entry_type        = e.entry_type
  AND g.entry_amount      = e.entry_amount
WHERE e.id <> g.manter
  AND e.status   = 'a_vencer'
  AND e.due_date >= CURRENT_DATE
  AND NOT EXISTS (SELECT 1 FROM cash_flow_entry         x WHERE x.source_entry_id  = e.id)
  AND NOT EXISTS (SELECT 1 FROM bank_statement_line     x WHERE x.matched_entry_id = e.id)
  AND NOT EXISTS (SELECT 1 FROM cash_flow_entry_project x WHERE x.entry_id         = e.id)
  AND NOT EXISTS (SELECT 1 FROM cash_flow_entry_tag     x WHERE x.entry_id         = e.id)
  AND NOT EXISTS (SELECT 1 FROM entry_attachment        x WHERE x.entry_id         = e.id);

\echo ''
\echo '--- O que seria apagado ---'
SELECT id, description, due_date, entry_type, entry_amount, bank_operation_id
FROM excedentes ORDER BY description, due_date, id;

\echo ''
\echo '--- Resumo ---'
SELECT COUNT(*) AS linhas,
       COUNT(DISTINCT bank_operation_id) AS operacoes,
       SUM(entry_amount) FILTER (WHERE entry_type = 'receita') AS receita_inflada,
       SUM(entry_amount) FILTER (WHERE entry_type = 'despesa') AS despesa_inflada
FROM excedentes;

DELETE FROM cash_flow_entry
WHERE :aplicar = 1 AND id IN (SELECT id FROM excedentes);

\echo ''
\echo '--- Sobrou duplicata? (tem de vir zero depois de aplicar) ---'
SELECT COALESCE(SUM(linhas - 1), 0) AS excedentes_restantes
FROM (
    SELECT COUNT(*) AS linhas
    FROM cash_flow_entry
    WHERE bank_operation_id IS NOT NULL AND is_recurring
    GROUP BY bank_operation_id, due_date, account_id, category_id, entry_type,
             entry_amount
    HAVING COUNT(*) > 1 AND COUNT(source_entry_id) = 0
) t;

COMMIT;
