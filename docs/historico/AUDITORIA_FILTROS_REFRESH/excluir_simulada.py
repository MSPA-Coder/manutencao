"""Exclui a carteira Simulada (id 3) e tudo o que pende dela -- pedido do mantenedor, 09/10/2026.

Roda DENTRO do contêiner web do CRV (`python /tmp/excluir_simulada.py [--executar]`).
Sem `--executar`, faz tudo numa transação e desfaz no fim (ensaio). Segue o
caminho das rotas do app: para cada posição, a linha aberta espelhada e a
posição (os movimentos vão em cascata); depois a carteira (as associações de
ticker vão em cascata). Recusa se a carteira não for a simulada esperada ou se
houver opção, transação ou arquivo vinculado -- nesse caso o caso muda e o
script precisa ser revisto, não forçado.
"""
import sys

from sqlalchemy import func, select

from app import create_app, db
from app.accounts.auditoria import registrar
from app.models import (
    OptionPosition,
    Portfolio,
    PortfolioTicker,
    Position,
    PositionLedgerArchive,
    PositionMovement,
    PositionMovementArchive,
    Transaction,
)
from app.positions.closure import delete_open_transaction_for_position

CARTEIRA_ID = 3
EXECUTAR = "--executar" in sys.argv


def contar(modelo, *criterios):
    return db.session.scalar(select(func.count()).select_from(modelo).where(*criterios))


app = create_app()
with app.app_context():
    carteira = db.session.get(Portfolio, CARTEIRA_ID)
    assert carteira is not None, "carteira 3 não existe"
    assert carteira.simulated, "a carteira 3 NÃO é simulada; abortado"

    antes = {
        "posicoes": contar(Position, Position.portfolio_id == CARTEIRA_ID),
        "movimentos": contar(PositionMovement, PositionMovement.position_id.in_(
            select(Position.id).where(Position.portfolio_id == CARTEIRA_ID))),
        "tickers_associados": contar(PortfolioTicker, PortfolioTicker.portfolio_id == CARTEIRA_ID),
        "opcoes": contar(OptionPosition, OptionPosition.portfolio_id == CARTEIRA_ID),
        "transacoes": contar(Transaction, Transaction.portfolio_id == CARTEIRA_ID),
        "arquivo_posicoes": contar(PositionLedgerArchive, PositionLedgerArchive.portfolio_id == CARTEIRA_ID),
        "arquivo_movimentos": contar(PositionMovementArchive, PositionMovementArchive.portfolio_id == CARTEIRA_ID),
    }
    print("ANTES", antes)
    for chave in ("opcoes", "transacoes", "arquivo_posicoes", "arquivo_movimentos"):
        assert antes[chave] == 0, f"há {chave} vinculados; revisar o script antes de excluir"

    posicoes = db.session.scalars(select(Position).where(Position.portfolio_id == CARTEIRA_ID)).all()
    for posicao in posicoes:
        delete_open_transaction_for_position(posicao.id, posicao.owner_id)
        db.session.delete(posicao)
    db.session.flush()
    registrar(
        "carteira", "excluir",
        entidade_id=CARTEIRA_ID,
        detalhes={"motivo": "Simulada excluída a pedido do mantenedor (auditoria 09/10/2026)",
                  "posicoes": antes["posicoes"], "movimentos": antes["movimentos"]},
        usuario_id=carteira.owner_id,
    )
    db.session.delete(carteira)
    db.session.flush()

    depois = {
        "carteira": db.session.get(Portfolio, CARTEIRA_ID) is not None,
        "posicoes": contar(Position, Position.portfolio_id == CARTEIRA_ID),
        "tickers_associados": contar(PortfolioTicker, PortfolioTicker.portfolio_id == CARTEIRA_ID),
    }
    print("DEPOIS (na transação)", depois)
    assert depois == {"carteira": False, "posicoes": 0, "tickers_associados": 0}

    if EXECUTAR:
        db.session.commit()
        print("GRAVADO")
    else:
        db.session.rollback()
        print("ENSAIO: nada gravado (use --executar)")
