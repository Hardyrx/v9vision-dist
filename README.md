# v9vision-dist

Distribuição do V9 Vision para membros.

Tudo aqui é **cifrado**: o pacote do app (`app.v9pkg`) e os dados do Oracle (`oracle/data/*.enc`). Sem um login de
membro válido, nada disso abre. O que é público é só a lista de membros (`membros.json`), que guarda a chave de
cada um trancada com a senha dele.

- `latest.json`: versão atual do app e a soma de conferência do pacote.
- `app.v9pkg`: o app, cifrado.
- `membros.json`: lista de membros (as senhas não ficam aqui).
- `oracle/data/`: dados do V9 Oracle, cifrados.

Quem instala usa o `Instalar-V9Vision.bat` que recebeu do administrador.
