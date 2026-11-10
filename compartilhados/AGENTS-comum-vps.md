**Deploy (o que roda no VPS).** Só com o "sim", a cada vez. `~/deploy.sh <app>`
no VPS1 leva o checkout ao `main`, monta a imagem no servidor, confere
`/health` e volta sozinho se falhar; a volta não desfaz migração nem dado. O
VPS só espelha o `main`: nada se edita lá. Imagem-base nova (correção do Debian
ou do Python) só quando ele pedir: testa na máquina e depois
`~/deploy.sh <app> --refresh`.

**Dados de produção.** Mudança destrutiva, migração que transforma dado ou
conversão começa por um dump novo, feito com `~/backup-db.sh --forcar` no VPS e
conferido no catálogo do BackupRestore. Dump feito à mão não tem `.sha256` e
reprova a sincronização.
