#!/bin/bash
# =============================================================================
# Instalador do V9 Vision para Mac (13/10/2026). Cola no Terminal:
#
#   curl -fsSL https://raw.githubusercontent.com/Hardyrx/v9vision-dist/main/instalar_mac.sh | bash
#
# Roda em todo Mac com chip Apple (M1 a M5, Pro/Max/Ultra, Mac mini) e se ajusta pela memoria (8 GB ate' 64 GB+).
# Nao pede senha de administrador nem conta de desenvolvedor da Apple: tudo fica na pasta do usuario, e o que e'
# baixado pelo Terminal nao recebe a "quarentena" do Mac. Rodar de novo = atualizar/consertar.
# Mesmo fluxo do instalador do Windows: termo -> login de membro -> chave -> pacote cifrado -> preparo -> .env -> IA.
# =============================================================================
set -u
DIST_URL="${V9_BASE_URL:-https://raw.githubusercontent.com/Hardyrx/v9vision-dist/main}"
FLOW_URL="${V9_FLOW_BASE_URL:-https://raw.githubusercontent.com/Hardyrx/v9flow-dist/main}"
DESTINO="${V9_DESTINO:-$HOME/V9Vision}"
DADOS="$HOME/Library/Application Support/V9Vision"
APP="$HOME/Applications/V9 Vision.app"
NOME="V9 Vision"
TMP="$(mktemp -d -t v9visioninst)"
AVISOS=()
TOTAL=9

azul()  { printf '\n\033[36m[%s/%s] %s\033[0m\n' "$1" "$TOTAL" "$2"; }
ok()    { printf '      \033[32mOK -- %s\033[0m\n' "$1"; }
aviso() { printf '      \033[33mAVISO: %s\033[0m\n' "$1"; AVISOS+=("$1"); }
parar() { printf '\n      \033[31mPAROU: %s\033[0m\n\n' "$1"; rm -rf "$TMP"; exit 1; }
# o script chega pelo "curl | bash": o teclado e' o /dev/tty, nao a entrada padrao
pergunta() { local r; read -r -p "$1" r < /dev/tty; printf '%s' "$r"; }
segredo()  { local r; read -r -s -p "$1" r < /dev/tty; echo > /dev/tty; printf '%s' "$r"; }

[ "$(uname)" = "Darwin" ] || parar "Este instalador e' para Mac. No Windows use o Instalar-V9Vision.bat."
echo ""
echo "  ===================  Instalador do V9 Vision (Mac)  ==================="
MEM_GB=$(( $(sysctl -n hw.memsize) / 1073741824 ))
LIVRE_GB=$(( $(df -k "$HOME" | tail -1 | awk '{print $4}') / 1048576 ))
echo "      Este Mac: $(sysctl -n machdep.cpu.brand_string 2>/dev/null), ${MEM_GB} GB de memoria, ${LIVRE_GB} GB livres."
[ "$(sw_vers -productVersion | cut -d. -f1)" -ge 12 ] 2>/dev/null || parar "O V9 Vision precisa do macOS 12 (Monterey) ou mais novo."
[ "$LIVRE_GB" -ge 8 ] || parar "Pouco espaco livre (${LIVRE_GB} GB). O programa ocupa cerca de 3 GB e cada video mais alguns GB. Libere espaco e rode de novo."
[ "$LIVRE_GB" -ge 25 ] || aviso "So ${LIVRE_GB} GB livres: da para instalar, mas cada video ocupa alguns GB. Apague projetos antigos ou use um disco externo para os videos."
[ "$MEM_GB" -ge 12 ] || echo "      Mac de ${MEM_GB} GB: o programa vai fazer uma coisa pesada por vez (o video sai igual, so' demora mais)."

# ---------- 1) Python (uv: sem administrador, sem Homebrew) ----------
azul 1 "Python"
export PATH="$HOME/.local/bin:$PATH"
if ! command -v uv >/dev/null 2>&1; then
  echo "      Instalando o gerenciador de Python (uv, so para este usuario)..."
  curl -LsSf https://astral.sh/uv/install.sh | sh >/dev/null 2>&1 || parar "Nao consegui instalar o Python. Confira a internet e rode de novo."
  export PATH="$HOME/.local/bin:$PATH"
fi
command -v uv >/dev/null 2>&1 || parar "Nao consegui preparar o Python."
uv python install 3.12 >/dev/null 2>&1 || parar "Nao consegui baixar o Python 3.12. Confira a internet e rode de novo."
ok "Python 3.12 pronto."

# ---------- 2) termo e login de membro ----------
azul 2 "Acesso: este programa e' so' para membros"
# 13/10 (Mac da Roberta): este passo ficava mudo por um bom tempo e parecia travado. Agora diz o que esta' fazendo,
# usa o "uv pip" (bem mais rapido que o pip) e tem limite de tempo.
echo "      Preparando a verificacao de acesso (uns segundos)..."
uv venv --python 3.12 --seed "$TMP/venv" >/dev/null 2>&1 || parar "Nao consegui preparar a verificacao de acesso."
VPY="$TMP/venv/bin/python"
UV_HTTP_TIMEOUT=60 uv pip install -q --python "$VPY" cryptography >/dev/null 2>&1 \
  || "$VPY" -m pip install -q --disable-pip-version-check --timeout 30 --retries 2 cryptography >/dev/null 2>&1 \
  || parar "Nao consegui preparar a verificacao de acesso. Confira a internet."
echo "      Buscando a lista de membros..."
curl -fsSL "$DIST_URL/v9_cofre.py" -o "$TMP/v9_cofre.py" || parar "Nao consegui baixar o verificador de acesso. Confira a internet."
echo ""
echo "      TERMO DE USO (resumo)"
echo "      - O acesso e' pessoal: um login por pessoa, sem emprestar nem dividir."
echo "      - E' proibido copiar, repassar ou vender o programa, o codigo ou os dados do Oracle."
echo "      - Um codigo seu e' gravado nos dados do Oracle que o programa baixa:"
echo "        uma copia que vazar pode ser rastreada ate' voce."
echo "      - O administrador pode remover o acesso em caso de uso indevido."
echo ""
ACEITE="$(pergunta '      Para aceitar, digite ACEITO e aperte Enter: ')"
[ "$(echo "$ACEITE" | tr '[:lower:]' '[:upper:]' | xargs)" = "ACEITO" ] || parar "O termo de uso nao foi aceito; instalacao cancelada."
CHAVE=""; LOGIN=""; SENHA_FLOW=""; MODO="login"
# ---- ACESSO POR CODIGO (16/10): sem login nem senha. Mostra o codigo DESTE Mac (o mesmo do app), o suporte libera no
# painel e o servidor entrega a chave que abre o pacote. Login e senha continuam como alternativa (tecla L).
campo() { printf '%s' "$J" | "$VPY" -c 'import json,sys;print(json.load(sys.stdin).get(sys.argv[1]) or "")' "$1" 2>/dev/null; }
AVISOU=0; ESPERAS=0
while [ "${V9_SO_LOGIN:-}" != "1" ]; do
  J="$("$VPY" "$TMP/v9_cofre.py" codigo --app vision 2>/dev/null | tail -1)"
  ESTADO="$(campo estado)"; [ -n "$ESTADO" ] || ESTADO="funcao_antiga"
  CODIGO="$(campo codigo)"; LS="$(campo login_senha)"
  case "$ESTADO" in
    liberado) CHAVE="$(campo chave | tr -d '[:space:]')"; MODO="codigo"; LOGIN="Mac $CODIGO"; ok "este Mac esta liberado (codigo $CODIGO)."; break ;;
    negado) parar "Este Mac (codigo $CODIGO) nao tem acesso ao V9 Vision. Fale com o administrador." ;;
    sem_chave) parar "Este Mac (codigo $CODIGO) esta liberado, mas sem direito a instalar. Fale com o administrador." ;;
    sem_rede) echo "      Nao consegui falar com o servidor de licencas. Confira a internet."; break ;;
    aguardando) ;;
    *) break ;;
  esac
  if [ "$AVISOU" = 0 ]; then
    AVISOU=1
    echo ""
    echo "      Codigo deste Mac:  $CODIGO"
    echo "      Mande este codigo para o suporte e espere. Confiro a cada 20 segundos se ja foi liberado."
    [ "$LS" = "True" ] && echo "      (Se voce tem login e senha, aperte a tecla L para entrar com eles.)"
  fi
  ESPERAS=$((ESPERAS+1))
  if [ -n "${V9_CODIGO_TENTATIVAS:-}" ] && [ "$ESPERAS" -gt "$V9_CODIGO_TENTATIVAS" ]; then parar "Modo de teste: o Mac nao foi liberado."; fi
  K=""; read -r -s -n 1 -t "${V9_CODIGO_INTERVALO:-20}" K < /dev/tty 2>/dev/null
  if [ "$LS" = "True" ] && { [ "$K" = "l" ] || [ "$K" = "L" ]; }; then break; fi
  echo "      ...ainda nao liberado, conferindo de novo."
done

if [ "$MODO" = "login" ]; then
  curl -fsSL "$DIST_URL/membros.json" -o "$TMP/membros.json" || parar "Nao consegui buscar a lista de membros. Avise o administrador se a internet estiver normal."
fi
for t in 1 2 3; do
  [ "$MODO" = "login" ] || break
  [ "$t" -gt 1 ] && echo "      Login ou senha incorretos. Tente de novo."
  LOGIN="$(pergunta '      Login (o que o administrador cadastrou para voce): ')"
  SENHA="$(segredo '      Senha: ')"
  [ -n "$LOGIN" ] && [ -n "$SENHA" ] || continue
  CHAVE="$(printf '%s\n%s\n' "$LOGIN" "$SENHA" | "$VPY" "$TMP/v9_cofre.py" abrir --membros "$TMP/membros.json" 2>/dev/null | head -1 | tr -d '[:space:]')"
  if [ -n "$CHAVE" ]; then SENHA_FLOW="$SENHA"; break; fi
done
SENHA=""
[ -n "$CHAVE" ] || parar "Login ou senha incorretos 3 vezes. Fale com o administrador para cadastrar ou redefinir o seu acesso."
[ "$MODO" = "login" ] && ok "acesso liberado para $LOGIN."

# ---------- 3) programa ----------
azul 3 "Baixando o programa para $DESTINO"
curl -fsSL "$DIST_URL/latest.json" -o "$TMP/latest.json" || parar "Nao consegui ver a versao atual. Confira a internet."
VERSAO="$("$VPY" -c 'import json,sys;print(json.load(open(sys.argv[1]))["versao"])' "$TMP/latest.json")"
ARQ="$("$VPY" -c 'import json,sys;print(json.load(open(sys.argv[1])).get("arquivo") or "app.v9pkg")' "$TMP/latest.json")"
SHA="$("$VPY" -c 'import json,sys;print(json.load(open(sys.argv[1]))["sha256"].lower())' "$TMP/latest.json")"
# 15/10 (unificacao Windows+Mac): o latest.json diz em quais sistemas o pacote roda. Sem "mac" na lista o pacote e' so'
# de Windows -- instalar por cima quebraria o app deste Mac. Para ANTES de baixar/copiar qualquer coisa.
"$VPY" -c 'import json,sys;sys.exit(0 if "mac" in (json.load(open(sys.argv[1])).get("plataformas") or []) else 1)' "$TMP/latest.json" \
  || parar "A versao publicada agora ($VERSAO) ainda nao e' para Mac. Nada foi mudado neste Mac. Avise o administrador."
ATUAL=""; [ -f "$DESTINO/VERSAO" ] && ATUAL="$(tr -d '[:space:]' < "$DESTINO/VERSAO")"
if [ -f "$DESTINO/server.py" ] && [ "$ATUAL" = "$VERSAO" ]; then
  ok "ja esta na versao mais recente ($VERSAO)."
else
  if [ -d "$DESTINO" ] && [ ! -f "$DESTINO/server.py" ] && [ -n "$(ls -A "$DESTINO" 2>/dev/null)" ]; then
    parar "A pasta $DESTINO ja existe e nao e' deste programa. Renomeie essa pasta e rode de novo."
  fi
  echo "      Baixando (pode levar alguns minutos)..."
  # Logo depois de uma publicacao o GitHub entrega por uns minutos o indice (latest.json) e o pacote de versoes
  # diferentes (cache) e a conferencia falha (visto 13/10). Espera e tenta de novo sozinho, sem assustar ninguem.
  BATEU=0
  for TENTATIVA in 1 2 3 4 5 6 7 8; do
    curl -fsSL "$DIST_URL/$ARQ" -o "$TMP/$ARQ" || parar "Nao consegui baixar o programa. Confira a internet."
    if [ "$(shasum -a 256 "$TMP/$ARQ" | cut -d' ' -f1)" = "$SHA" ]; then BATEU=1; break; fi
    echo "      A versao nova acabou de ser publicada e ainda esta chegando. Esperando 1 minuto ($TENTATIVA/8)..."
    sleep 60
    curl -fsSL "$DIST_URL/latest.json" -o "$TMP/latest.json" || true
    VERSAO="$("$VPY" -c 'import json,sys;print(json.load(open(sys.argv[1]))["versao"])' "$TMP/latest.json")"
    SHA="$("$VPY" -c 'import json,sys;print(json.load(open(sys.argv[1]))["sha256"].lower())' "$TMP/latest.json")"
  done
  [ $BATEU = 1 ] || parar "O arquivo baixado nao confere. Espere uns minutos e rode de novo."
  mkdir -p "$DESTINO"
  printf '%s\n' "$CHAVE" | "$VPY" "$TMP/v9_cofre.py" decifrar --pacote "$TMP/$ARQ" --destino "$DESTINO" >/dev/null
  case $? in 0) ;; 4) parar "O seu acesso foi removido ou a chave foi trocada. Fale com o administrador." ;; *) parar "Nao consegui abrir o pacote do programa." ;; esac
  printf '%s\n' "$VERSAO" > "$DESTINO/VERSAO"
  rm -f "$TMP/$ARQ"
  ok "programa instalado (versao $VERSAO)."
fi
[ -f "$DESTINO/abrir_mac.py" ] || parar "Esta versao do V9 Vision ainda nao tem a parte do Mac. Avise o administrador."

# ---------- 4) ffmpeg, bibliotecas, Remotion ----------
azul 4 "Preparando ffmpeg, bibliotecas e Remotion (a parte mais demorada)"
"$DESTINO/venv/bin/python" -c 'import sys; sys.exit(sys.version_info[:2] != (3, 12))' >/dev/null 2>&1 || uv venv --clear --python 3.12 --seed "$DESTINO/venv" >/dev/null 2>&1 || parar "Nao consegui criar o ambiente Python 3.12 do programa."
AppPy="$DESTINO/venv/bin/python"
/bin/bash "$DESTINO/preparar_mac.sh" || parar "O preparo do programa falhou. Veja a mensagem acima."
[ -f "$DESTINO/remotion/node_modules/.chrome_ok" ] || aviso "O Remotion nao ficou pronto agora. O programa funciona; ele tenta de novo ao abrir."
ok "ambiente pronto."

# a chave do membro fica no Chaveiro do Mac: com ela o app le os dados do Oracle e se atualiza sem pedir login
mkdir -p "$DADOS"
if printf '%s\n' "$CHAVE" | ( cd "$DESTINO" && "$AppPy" -c 'import sys, plataforma; open(sys.argv[1], "wb").write(plataforma.proteger(sys.stdin.readline().strip().encode("ascii")))' "$DADOS/chave.dpapi" ); then
  ok "Oracle conectado: a chave ficou guardada no Chaveiro do Mac."
else
  aviso "Nao consegui guardar a chave do Oracle. O app funciona, mas a dashboard fica em modo exemplo."
fi
CHAVE=""

# ---------- 5) configuracao (.env) ----------
azul 5 "Configuracao do programa"
PROVEDOR="claude"
cd "$DESTINO" || parar "Nao consegui entrar na pasta do programa."
if [ -f ".env" ]; then
  ok "ja existe uma configuracao (.env) -- mantida como esta."
  PROVEDOR="$(grep -E '^\s*IA_PROVEDOR\s*=' .env | head -1 | cut -d= -f2 | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]')"; [ -n "$PROVEDOR" ] || PROVEDOR="claude"
  # 23/10 (auditoria): mostra a IA gravada e deixa trocar SO ela (o resto do .env fica como esta')
  case $PROVEDOR in gemini) NOME_IA="Gemini" ;; gpt) NOME_IA="GPT" ;; *) NOME_IA="Claude" ;; esac
  ok "inteligencia artificial gravada: $NOME_IA."
  TROCA="$(pergunta "      Quer trocar a IA? 1 = Claude, 2 = Gemini, 3 = GPT (Enter = manter $NOME_IA): ")"
  NOVA=""
  case $TROCA in 1) NOVA="claude" ;; 2) NOVA="gemini" ;; 3) NOVA="gpt" ;; "") ;; *) aviso "Resposta '$TROCA' nao e 1, 2 nem 3: a IA continua $NOME_IA." ;; esac
  if [ -n "$NOVA" ] && [ "$NOVA" != "$PROVEDOR" ]; then
    CHAVE_NOME=""; CHAVE_NOVA=""
    [ "$NOVA" = "gemini" ] && CHAVE_NOME="GEMINI_API_KEY" && CHAVE_NOVA="$(segredo '      Chave do Gemini (aistudio.google.com/apikey): ')"
    [ "$NOVA" = "gpt" ] && CHAVE_NOME="OPENAI_API_KEY" && CHAVE_NOVA="$(segredo '      Chave da OpenAI (platform.openai.com/api-keys): ')"
    if [ -n "$CHAVE_NOME" ] && [ -z "$CHAVE_NOVA" ] && ! grep -qE "^\s*$CHAVE_NOME\s*=\s*\S" .env; then
      aviso "Sem a chave a IA continua $NOME_IA. Rode o instalador de novo com a chave."
    else
      grep -vE '^\s*IA_PROVEDOR\s*=' .env > .env.tmp
      if [ -n "$CHAVE_NOVA" ]; then grep -vE "^\s*$CHAVE_NOME\s*=" .env.tmp > .env.tmp2; mv .env.tmp2 .env.tmp; echo "$CHAVE_NOME=$CHAVE_NOVA" >> .env.tmp; fi
      echo "IA_PROVEDOR=$NOVA" >> .env.tmp
      chmod 600 .env.tmp; mv .env.tmp .env
      ok "inteligencia artificial trocada: $NOME_IA -> $NOVA."
      PROVEDOR="$NOVA"
    fi
    CHAVE_NOVA=""
  fi
else
  echo "      Responda as perguntas. Onde diz \"Enter para pular\", pode deixar em branco e preencher depois."
  echo "      As chaves nao aparecem na tela enquanto voce digita."
  SENHA_APP=""
  until [ -n "$SENHA_APP" ] && [[ "$SENHA_APP" =~ ^[A-Za-z0-9]+$ ]]; do
    SENHA_APP="$(segredo '      Crie uma senha para abrir o programa neste Mac (so letras e numeros): ')"
  done
  PROJ="$(pergunta "      Pasta onde os videos vao ficar salvos (Enter = $HOME/ProjetosV9): ")"
  [ -n "$PROJ" ] || PROJ="$HOME/ProjetosV9"
  PROJ="${PROJ/#\~/$HOME}"
  mkdir -p "$PROJ" 2>/dev/null || aviso "Nao consegui criar a pasta $PROJ. Corrija PROJETOS_DIR no arquivo .env."
  echo ""
  echo "      Bancos de video (gratuitos): pexels.com/api e pixabay.com/api/docs"
  PEXELS="$(segredo '      Chave do Pexels  (Enter para pular): ')"
  PIXABAY="$(segredo '      Chave do Pixabay (Enter para pular): ')"
  [ -n "$PEXELS$PIXABAY" ] || aviso "Sem chave do Pexels nem do Pixabay o programa nao busca videos de estoque."
  echo ""
  echo "      Qual inteligencia artificial voce usa?"
  echo "        1 = Claude  (assinatura Pro ou Max, login pelo navegador)"
  echo "        2 = Gemini  (chave de API do Google AI Studio)"
  echo "        3 = GPT     (chave de API da OpenAI)"
  ESC=""
  until [[ "$ESC" =~ ^[123]$ ]]; do ESC="$(pergunta '      Digite 1, 2 ou 3 (Enter = 1): ')"; [ -n "$ESC" ] || ESC=1; done
  case $ESC in 1) PROVEDOR="claude" ;; 2) PROVEDOR="gemini" ;; 3) PROVEDOR="gpt" ;; esac
  GEMINI=""; OPENAI=""
  [ "$PROVEDOR" = "gemini" ] && GEMINI="$(segredo '      Chave do Gemini (aistudio.google.com/apikey): ')"
  [ "$PROVEDOR" = "gpt" ] && OPENAI="$(segredo '      Chave da OpenAI (platform.openai.com/api-keys): ')"
  SEGREDO_FLASK="$(openssl rand -hex 24)"
  {
    echo "# Configuracao do V9 Vision neste Mac. Nao envie este arquivo para ninguem."
    echo "# Nunca coloque ANTHROPIC_API_KEY aqui se voce usa a assinatura do Claude: passaria a cobrar da API paga."
    echo "SENHA=$SENHA_APP"
    echo "PROJETOS_DIR=$PROJ"
    echo "PORTA=5000"
    echo "HOST=127.0.0.1"
    echo "FLASK_SECRET=$SEGREDO_FLASK"
    echo "TETO_CENA_PADRAO=8"
    echo "PEXELS_API_KEY=$PEXELS"
    echo "PIXABAY_API_KEY=$PIXABAY"
    echo "IA_PROVEDOR=$PROVEDOR"
    [ -n "$GEMINI" ] && echo "GEMINI_API_KEY=$GEMINI"
    [ -n "$OPENAI" ] && echo "OPENAI_API_KEY=$OPENAI"
    echo "V9_DIST_URL=$DIST_URL"
  } > .env
  chmod 600 .env
  SENHA_APP=""; PEXELS=""; PIXABAY=""; GEMINI=""; OPENAI=""
  ok "configuracao gravada."
fi
grep -qE '^\s*ANTHROPIC_(API_KEY|AUTH_TOKEN)\s*=\s*\S' .env && aviso "O arquivo .env tem ANTHROPIC_API_KEY preenchida. Se voce usa a assinatura do Claude, apague essa linha."

# ---------- 6) inteligencia artificial ----------
azul 6 "Conectando a inteligencia artificial ($PROVEDOR)"
if [ "$PROVEDOR" = "claude" ]; then
  unset ANTHROPIC_API_KEY ANTHROPIC_AUTH_TOKEN
  CLAUDE="$HOME/.local/bin/claude"
  if [ -x "$CLAUDE" ]; then ok "Claude Code ja instalado."
  else
    echo "      Instalando o Claude Code oficial (claude.ai/install.sh)..."
    curl -fsSL https://claude.ai/install.sh | bash >/dev/null 2>&1
    [ -x "$CLAUDE" ] && ok "Claude Code instalado."
  fi
  if [ ! -x "$CLAUDE" ]; then aviso "Nao consegui instalar o Claude Code. Sem ele a IA do programa nao funciona. Rode o instalador de novo."
  elif "$CLAUDE" auth status >/dev/null 2>&1; then ok "Claude Code ja esta com login feito."
  else
    echo ""
    echo "      Agora o LOGIN: vai abrir o navegador. Entre com a SUA conta do Claude"
    echo "      (a que tem a assinatura Pro ou Max) e autorize. Depois volte para esta janela."
    pergunta '      Aperte Enter para abrir o login ' >/dev/null
    "$CLAUDE" auth login --claudeai < /dev/tty
    if "$CLAUDE" auth status >/dev/null 2>&1; then ok "login do Claude Code feito."
    else aviso "O login do Claude Code nao foi concluido. Rode o instalador de novo para tentar outra vez."; fi
  fi
fi

# ---------- 7) CapCut ----------
azul 7 "Conferindo o CapCut"
if [ -d "/Applications/CapCut.app" ] || [ -d "$HOME/Applications/CapCut.app" ]; then ok "CapCut instalado."
else aviso "Nao achei o CapCut. Instale pela App Store ou em capcut.com e abra uma vez antes de gerar o primeiro video."; fi

# ---------- 8) app no Launchpad + V9 Flow ----------

# 18/10 (dono: "nenhum com o ícone"): no macOS novo o app do osacompile traz um Assets.car que manda no ícone; trocar só o
# applet.icns não aparece. Apaga o Assets.car, aponta o Info.plist para o applet.icns, reassina e avisa o Launchpad.
icone_no_app() {
  local a="$1"
  rm -f "$a/Contents/Resources/Assets.car"
  /usr/libexec/PlistBuddy -c "Delete :CFBundleIconName" "$a/Contents/Info.plist" >/dev/null 2>&1 || true
  /usr/libexec/PlistBuddy -c "Set :CFBundleIconFile applet" "$a/Contents/Info.plist" >/dev/null 2>&1 \
    || /usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string applet" "$a/Contents/Info.plist" >/dev/null 2>&1 || true
  codesign --force --sign - "$a" >/dev/null 2>&1 && codesign --verify "$a" >/dev/null 2>&1 || aviso "O app $(basename "$a") pode nao abrir: a assinatura falhou. Rode este instalador de novo."
  touch "$a"
  /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$a" >/dev/null 2>&1 || true
}
azul 8 "Criando o app \"$NOME\""
# o app e' compilado pelo proprio Mac (osacompile): um .app feito a mao deu erro -10669 no M4 (Flow, 13/10)
mkdir -p "$HOME/Applications"
rm -rf "$APP"
osacompile -o "$APP" -e "do shell script \"cd '$DESTINO' && nohup '$DESTINO/venv/bin/python' abrir_mac.py > '$DESTINO/logs/abrir.log' 2>&1 &\"" \
  || parar "Nao consegui criar o app no Mac (osacompile)."
mkdir -p "$DESTINO/logs"
ICONSET="$TMP/V9Vision.iconset"; mkdir -p "$ICONSET"
if [ -f "$DESTINO/static/icone-mac.icns" ]; then   # 19/10: ícone colorido (fundo preto e verde), pronto
  cp "$DESTINO/static/icone-mac.icns" "$APP/Contents/Resources/applet.icns"
  icone_no_app "$APP"
elif "$AppPy" -c 'import sys; from PIL import Image; Image.open(sys.argv[1]).convert("RGBA").resize((512, 512), Image.LANCZOS).save(sys.argv[2])' \
     "$DESTINO/static/icone.ico" "$TMP/icone-512.png" 2>/dev/null; then
  for s in 16 32 128 256 512; do sips -z $s $s "$TMP/icone-512.png" --out "$ICONSET/icon_${s}x${s}.png" >/dev/null 2>&1; done
  iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/applet.icns" >/dev/null 2>&1 || true
  icone_no_app "$APP"
fi
touch "$APP"
ok "\"$NOME\" em Aplicativos do usuario (~/Applications) -- aparece no Launchpad e no Spotlight."
printf '%s\n' "$LOGIN" > "$DESTINO/instalado_para.txt"

# V9 Flow (incluso no Vision): igual ao Passo 10 do instalar.tpl.bat -- baixa o instalador Mac do Flow e roda aqui mesmo,
# encadeado (V9F_ENCADEADO + V9F_E_*): login, senha e termo vao daqui e ele nao pergunta de novo. A lista do Flow
# (membros.json da distribuicao dele) continua sendo a palavra final. Nunca bloqueia: falhou = aviso + linha manual.
LINHA_FLOW="curl -fsSL $FLOW_URL/instalar_mac.sh | bash"
flow_encadeado() {
  # $1 = modo (login|codigo). Codigos do instalador do Flow: 0 ok, 3 ainda nao liberado, outro = falhou
  local cod
  echo "      Instalando o V9 Flow neste Mac (mais alguns minutos)..."
  V9F_ENCADEADO=1 V9F_E_modo="$1" V9F_E_termo=ACEITO V9F_BASE_URL="$FLOW_URL"     V9F_E_login="$LOGIN" V9F_E_senha="$SENHA_FLOW" /bin/bash "$TMP/Instalar-V9Flow.sh"
  cod=$?
  if [ $cod -eq 0 ]; then ok "V9 Flow instalado: app \"V9 Flow\" no Launchpad."
  elif [ $cod -eq 3 ]; then ok "o V9 Flow ainda nao foi liberado para este Mac. Quando for, e so' rodar este instalador de novo."
  else aviso "O V9 Flow nao terminou de instalar (veja a mensagem acima). Nao afeta o V9 Vision. Para tentar de novo, cole no Terminal: $LINHA_FLOW"; fi
}
if [ -d "$HOME/Applications/V9 Flow.app" ]; then ok "V9 Flow ja instalado (ele se atualiza sozinho)."
elif [ "$MODO" != "codigo" ] && [ -z "$SENHA_FLOW" ]; then
  aviso "Nao deu para instalar o V9 Flow agora. Para instalar, cole no Terminal: $LINHA_FLOW"
elif ! curl -fsSL "$FLOW_URL/instalar_mac.sh" -o "$TMP/Instalar-V9Flow.sh" 2>/dev/null; then
  aviso "Nao consegui baixar o instalador do V9 Flow agora. Para instalar depois, cole no Terminal: $LINHA_FLOW"
elif [ "$MODO" = "codigo" ]; then
  # por codigo, quem decide e' o servidor de licencas (o mesmo Mac liberado; Joshua barrado la): o instalador do Flow
  # confere o mesmo codigo e, se ainda nao foi liberado, sai com 3 sem esperar
  flow_encadeado codigo
elif curl -fsSL "$FLOW_URL/membros.json" -o "$TMP/flow_membros.json" 2>/dev/null; then
  ID_LOGIN="$(printf '%s' "$LOGIN" | tr '[:upper:]' '[:lower:]' | xargs | tr -d '
' | shasum -a 256 | cut -d' ' -f1)"
  if "$VPY" -c 'import json,sys; sys.exit(0 if sys.argv[2] in json.load(open(sys.argv[1]))["membros"] else 1)' "$TMP/flow_membros.json" "$ID_LOGIN"; then
    flow_encadeado login
  else
    ok "o V9 Flow sera liberado para sua conta em breve. Quando for, e so' rodar este instalador de novo."
  fi
else
  aviso "Nao consegui conferir a lista do V9 Flow agora. Para instalar depois, cole no Terminal: $LINHA_FLOW"
fi
SENHA_FLOW=""


# ---------- opcional: motor Harness (DeepSeek) para o texto mecanico ----------
# Desligado por padrao (Enter = N): ~453 MB e precisa do Node.js. Nunca vai no pacote do programa. Mesmo instalado, fica
# desligado ate o dono ligar em Configuracoes > Motores de IA.
R="$(pergunta '      (Opcional) Instalar o motor Harness (DeepSeek)? ~453 MB, precisa do Node.js. (S/N, Enter = N): ')"
if [ "$R" = "s" ] || [ "$R" = "S" ]; then
  if ! "$AppPy" "$DESTINO/scripts/dsh_runtime.py" instalar; then
    aviso "O motor Harness nao foi instalado (sem Node.js: brew install node, ou https://nodejs.org). Nao afeta o programa; da para instalar depois em Configuracoes."
  fi
fi

# ---------- 9) resumo ----------
azul 9 "Resumo"
printf 'Termo de uso aceito\nlogin: %s\ndata: %s\ncomputador: %s\nversao do app: %s\nmemoria: %s GB\n' "$LOGIN" "$(date '+%Y-%m-%d %H:%M:%S')" \
  "$(scutil --get ComputerName 2>/dev/null)" "$VERSAO" "$MEM_GB" > "$DESTINO/termo_aceito.txt"
rm -rf "$TMP"
if [ ${#AVISOS[@]} -eq 0 ]; then ok "tudo certo, nenhuma pendencia."; else echo "      Instalado, com pendencias:"; for a in "${AVISOS[@]}"; do echo "       - $a"; done; fi
echo ""
echo "  Para usar: abra \"$NOME\" pelo Launchpad ou Spotlight (Cmd+Espaco, digite V9 Vision)."
echo "  Para atualizar: o programa confere sozinho cada vez que abre (ou rode este comando de novo)."
echo "  Para desinstalar: bash \"$DESTINO/desinstalar_mac.sh\""
echo ""
R="$(pergunta '  Abrir o programa agora? (S/N): ')"
if [ "$R" = "s" ] || [ "$R" = "S" ]; then open "$APP"; fi
