# Configurações do nginx do VPS

Cópia de `/etc/nginx/sites-available/` do VPS (`ubuntu@163.176.214.214`),
puxada em 2026-08-20 com a chave de administração. `sites-enabled/` é só
link simbólico para estes arquivos — copiar `sites-available` já cobre tudo.

Não tem segredo dentro (domínio, porta, caminho de certificado). Não é
artefato do BackupRestore — atualizar à mão sempre que mudar rota/domínio no
servidor, com o mesmo comando:

```
scp -i "C:\Users\MSPA\Downloads\OracleKeys\ssh-key-2026-08-17.key" ubuntu@163.176.214.214:/etc/nginx/sites-available/<nome> .
```

Ver decisão D5 em `PLANO_BACKUPRESTORE_VPS.md`.
