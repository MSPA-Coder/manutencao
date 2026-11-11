## Regras comuns aos repositórios

**O que espera o "sim" do mantenedor:** deploy ou publicação, qualquer ação no
VPS, e apagar dados, volumes ou backups (`docker compose down -v` inclusive).
Commit e push não esperam. Na dúvida sobre algo irreversível, pergunte; no
resto, decida e diga o que decidiu.

**Ciclo.** Altere, rode a verificação completa deste repositório (seção
"Validação"), commite direto no `main` quando o bloco de trabalho estiver
pronto e dê `git push`: sem PR, sem push forçado, sem rebase do `main`
publicado. A CI roda depois, só como aviso, mas vermelho no `main` se
investiga. O Dependabot chega por PR, com merge manual. Ao terminar, diga o que
rodou, o resultado e o que deixou de validar.

**Dados e segredos.** Os bancos desta máquina são de teste: não provam nada
sobre valores reais e não pedem backup. Segredos ficam fora do Git (`.secrets/`
ou configuração do usuário) e não aparecem em código, imagem, log, diff,
documento nem relatório.

**Dependências.** Alargue o teto e preserve o piso já verificado: elevar o piso
afirma uma incompatibilidade, e isso exige prova. Vulnerabilidade se corrige
atualizando; exceção só explícita, com motivo e data. O Dependabot propõe
atualização do `uv.lock` por PR (PRs de 08 e 09/11/2026), mas não se confirmou
que o grafo de dependências do GitHub acompanha o lock (última conferência:
parado no lock de 13/10/2026): não conte só com o alerta do GitHub, confira
pela versão travada no repositório e atualize à mão
(`uv lock --upgrade-package <pacote>`, onde há `uv.lock`) quando o `pip-audit`
ou o Trivy apontarem.

**Testes.** `docs/TESTES.md`, onde existe, diz o que testar e como. Diante de
vermelho, decida de quem é o defeito; nunca escreva código para um teste
passar. Não rode duas verificações do mesmo repositório ao mesmo tempo: a
segunda recria o ambiente de teste e derruba a primeira.

**Cópias.** Este bloco, `docs/TESTES.md` e os arquivos listados em
`_manutencao/compartilhados/sincronizar.py` são cópias: mude a canônica lá e
rode `python compartilhados/sincronizar.py --aplicar` no `_manutencao`.

**Este arquivo.** Guarde aqui só o que o código não diz: limites, decisões com
o motivo, armadilhas e comandos. Cada regra mora num lugar só: o que este bloco
ou `docs/` já dizem não se repete. História fica no `git log`; decisão com
alternativas vira ADR, que abre com a linha `Estado:` (vigente, ou substituído
por qual); detalhe de implementação fica no código. Para acrescentar uma
regra, retire ou funda
outra: `sincronizar.py` reprova este arquivo acima de 900 palavras fora deste
bloco.
