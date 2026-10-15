#!/usr/bin/env python3
"""
V9 VISION // cofre do instalador.

Usa o MESMO formato de membros do V9 ORACLE (docs/membros.json, formato 2): cada membro tem um par
de chaves X25519; a chave privada fica trancada com a senha dele (PBKDF2 + AES-GCM) e a chave de dados
chega cifrada para a chave publica dele (ECIES: X25519 + HKDF + AES-GCM). Quem cadastra e remove membros
e' o administrador, pela pagina membros.html do Oracle. Um login valido abre a chave de dados; a chave
de dados abre o pacote do app (formato V9E1: nonce + AES-256-GCM sobre gzip), o mesmo do cofre do Oracle.

Comandos:
  abrir     --membros ARQ                     stdin: login, senha (duas linhas)  -> stdout: chave (base64)
  decifrar  --pacote ARQ --destino PASTA      stdin: chave (base64)               -> extrai o app
  publicar  --app PASTA --dist PASTA --membros ARQ [--versao V]
                                              stdin: login, senha do administrador
  guardar   --destino ARQ                     stdin: chave (base64) -> grava protegida pelo Windows (DPAPI)
Codigos de saida: 0 ok, 2 login ou senha incorretos, 3 arquivo ausente ou invalido, 4 pacote nao abre.
"""
import argparse, base64, glob, re, ctypes, gzip, hashlib, io, json, os, subprocess, sys, time, zipfile

from cryptography.exceptions import InvalidTag
from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives.asymmetric.x25519 import X25519PrivateKey, X25519PublicKey
from cryptography.hazmat.primitives.ciphers.aead import AESGCM
from cryptography.hazmat.primitives.kdf.hkdf import HKDF

try:
    sys.stdin.reconfigure(encoding="utf-8-sig", errors="strict")   # o PowerShell manda UTF-8, as vezes com BOM invisivel
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")
except Exception:
    pass

MAGIC = b"V9E1"
ITER = 600_000


# ---------------------------------------------------------------- membros (igual ao collector/cofre.py)
def id_login(login: str) -> str:
    return hashlib.sha256(login.strip().lower().encode("utf-8")).hexdigest()


def _deriva(senha: str, salt: bytes, iteracoes: int) -> bytes:
    return hashlib.pbkdf2_hmac("sha256", senha.encode("utf-8"), salt, iteracoes, 32)


def _chave_ecies(shared: bytes, eph_pub: bytes, pub: bytes) -> bytes:
    return HKDF(algorithm=hashes.SHA256(), length=32, salt=eph_pub + pub, info=b"v9-oracle-k").derive(shared)


def abre_membro(membros: dict, login: str, senha: str):
    """Devolve a chave de dados (base64) se login e senha estiverem certos, senao None."""
    ident = id_login(login)
    e = (membros.get("membros") or {}).get(ident)
    if not e or membros.get("v") != 2:
        return None
    try:
        wrap = base64.b64decode(e["priv"])
        priv = AESGCM(_deriva(senha, base64.b64decode(e["salt"]), int(membros.get("iter", ITER)))).decrypt(
            wrap[:12], wrap[12:], ident.encode())
        k = base64.b64decode(e["k"])
        eph_pub, nonce, ct = k[:32], k[32:44], k[44:]
        pub = base64.b64decode(e["pub"])
        shared = X25519PrivateKey.from_private_bytes(priv).exchange(X25519PublicKey.from_public_bytes(eph_pub))
        chave = AESGCM(_chave_ecies(shared, eph_pub, pub)).decrypt(nonce, ct, ident.encode())
        return base64.b64encode(chave).decode()
    except Exception:
        return None


# ---------------------------------------------------------------- pacote (formato V9E1)
def fecha(chave_b64: str, dados: bytes) -> bytes:
    nonce = os.urandom(12)
    return MAGIC + nonce + AESGCM(base64.b64decode(chave_b64)).encrypt(nonce, gzip.compress(dados, 6), None)


def abre(chave_b64: str, blob: bytes) -> bytes:
    if blob[:4] != MAGIC:
        raise ValueError("arquivo nao esta no formato do pacote")
    nonce, ct = blob[4:16], blob[16:]
    try:
        return gzip.decompress(AESGCM(base64.b64decode(chave_b64)).decrypt(nonce, ct, None))
    except InvalidTag:
        raise ValueError("a chave nao abre este pacote (acesso removido ou chave trocada)")


def extrai_zip(dados: bytes, destino: str) -> int:
    """Extrai o zip recusando qualquer caminho que escape da pasta de destino."""
    destino = os.path.abspath(destino)
    n = 0
    with zipfile.ZipFile(io.BytesIO(dados)) as z:
        for info in z.infolist():
            alvo = os.path.abspath(os.path.join(destino, info.filename))
            if alvo != destino and not alvo.startswith(destino + os.sep):
                raise ValueError("pacote com caminho suspeito: " + info.filename)
        z.extractall(destino)
        n = len(z.infolist())
    return n


# ---------------------------------------------------------------- comandos
def _ler_membros(caminho):
    try:
        with open(caminho, encoding="utf-8") as f:
            m = json.load(f)
        if m.get("v") != 2:
            raise ValueError("formato de membros nao suportado")
        return m
    except (OSError, ValueError) as e:
        print(f"ERRO: nao consegui ler {caminho} ({e})", file=sys.stderr)
        return None


def _ler_credenciais():
    login = (sys.stdin.readline() or "").rstrip("\r\n")
    senha = (sys.stdin.readline() or "").rstrip("\r\n")
    return login, senha


def cmd_abrir(a):
    membros = _ler_membros(a.membros)
    if membros is None:
        return 3
    login, senha = _ler_credenciais()
    chave = abre_membro(membros, login, senha) if login and senha else None
    if not chave:
        return 2
    print(chave)
    return 0


def cmd_decifrar(a):
    chave = (sys.stdin.readline() or "").strip()
    try:
        with open(a.pacote, "rb") as f:
            blob = f.read()
    except OSError as e:
        print(f"ERRO: nao consegui ler o pacote ({e})", file=sys.stderr)
        return 3
    try:
        n = extrai_zip(abre(chave, blob), a.destino)
    except Exception as e:
        print(f"ERRO: {e}", file=sys.stderr)
        return 4
    print(f"{n} arquivo(s) extraido(s) em {a.destino}")
    return 0


class _Blob(ctypes.Structure):
    _fields_ = [("cbData", ctypes.c_uint32), ("pbData", ctypes.POINTER(ctypes.c_char))]


def proteger_dpapi(dados: bytes) -> bytes:
    """Protege com a conta do Windows do usuario: so' ele, neste computador, consegue abrir (mesma rotina do app)."""
    buf = ctypes.create_string_buffer(dados, len(dados))
    entrada, saida = _Blob(len(dados), ctypes.cast(buf, ctypes.POINTER(ctypes.c_char))), _Blob()
    if not ctypes.windll.crypt32.CryptProtectData(ctypes.byref(entrada), "V9Vision", None, None, None, 0, ctypes.byref(saida)):
        raise OSError("o Windows recusou a protecao (DPAPI)")
    try:
        return ctypes.string_at(saida.pbData, saida.cbData)
    finally:
        ctypes.windll.kernel32.LocalFree(ctypes.cast(saida.pbData, ctypes.c_void_p))


def cmd_guardar(a):
    chave = (sys.stdin.readline() or "").strip()
    try:
        base64.b64decode(chave, validate=True)
        os.makedirs(os.path.dirname(os.path.abspath(a.destino)), exist_ok=True)
        with open(a.destino, "wb") as f:
            f.write(proteger_dpapi(chave.encode("ascii")))
    except (ValueError, OSError) as e:
        print(f"ERRO: nao consegui guardar a chave ({e})", file=sys.stderr)
        return 3
    print("chave guardada")
    return 0


def _git(pasta, *args):
    r = subprocess.run(["git", "-C", pasta, *args], capture_output=True)
    if r.returncode != 0:
        raise RuntimeError((r.stderr or b"").decode("utf-8", "replace").strip() or "git falhou")
    return r.stdout


ARQUIVOS_PAIS = re.compile(r"^(BR|US|MX|DE|canais_[A-Z]{2}|virais_[A-Z]{2})\.enc$")


def conferir_dados(chave, pasta):
    """Os dados do Oracle abrem com a chave da lista de membros? Devolve (quantos conferi, nomes que nao abrem).
    Se a chave dos dados (segredo do Oracle) e a da lista de membros forem diferentes, o membro entraria com login certo
    e nao abriria nada: melhor descobrir ANTES de publicar."""
    total, falhas = 0, []
    for f in sorted(glob.glob(os.path.join(pasta, "*.enc"))):
        nome = os.path.basename(f)
        if not ARQUIVOS_PAIS.match(nome):
            continue
        total += 1
        try:
            with open(f, "rb") as fh:
                abre(chave, fh.read())
        except Exception:
            falhas.append(nome)
    return total, falhas


def _imagem_pronta(caminho, lado=1280):
    """JPEG de ate' 1280 px de largura (qualidade 82), para o banco ficar leve. Sem Pillow, manda o arquivo como esta'."""
    try:
        from PIL import Image
        with Image.open(caminho) as im:
            im = im.convert("RGB")
            if im.width > lado:
                im = im.resize((lado, round(im.height * lado / im.width)))
            b = io.BytesIO()
            im.save(b, "JPEG", quality=82, optimize=True)
            return b.getvalue()
    except Exception:
        with open(caminho, "rb") as f:
            return f.read()


def publicar_thumbs(chave, banco, dist):
    """Banco de thumbnails do administrador -> dist/thumbs/: 16 pacotes cifrados (por 1o caractere do hash da imagem) +
    nichos.v9img + indice.json. So' regrava o pacote cujo conteudo mudou (o git nao cresce a cada publicacao)."""
    exts = (".jpg", ".jpeg", ".png", ".webp")
    try:
        with open(os.path.join(banco, "_nichos.json"), encoding="utf-8") as f:
            nichos_orig = json.load(f)
    except (OSError, ValueError):
        nichos_orig = {}
    grupos, nichos = {}, {}
    for raiz, pastas, arqs in os.walk(banco):
        if os.path.relpath(raiz, banco).split(os.sep)[0] == "comunidade":
            continue                                     # o que veio da comunidade nao volta para ela
        for nome in arqs:
            if not nome.lower().endswith(exts):
                continue
            caminho = os.path.join(raiz, nome)
            rel = os.path.relpath(caminho, banco).replace(os.sep, "/")
            with open(caminho, "rb") as f:
                h = hashlib.sha1(f.read()).hexdigest()[:14]
            arq = h + ".jpg"
            grupos.setdefault(h[0], {})[arq] = caminho
            if rel in nichos_orig:
                nichos[arq] = nichos_orig[rel]
    if not grupos:
        print("Thumbnails: nenhuma imagem em " + banco)
        return 0
    pasta = os.path.join(dist, "thumbs")
    os.makedirs(pasta, exist_ok=True)
    try:
        with open(os.path.join(pasta, "indice.json"), encoding="utf-8") as f:
            antigo = json.load(f)
    except (OSError, ValueError):
        antigo = {}
    novos, pacotes = 0, {}
    for letra in sorted(grupos):
        itens = sorted(grupos[letra])
        sig = hashlib.sha256("|".join(itens).encode()).hexdigest()
        nome = f"p-{letra}.v9img"
        velho = (antigo.get("pacotes") or {}).get(nome) or {}
        if velho.get("sig") == sig and os.path.isfile(os.path.join(pasta, nome)):
            pacotes[nome] = velho
            continue
        buf = io.BytesIO()
        with zipfile.ZipFile(buf, "w", zipfile.ZIP_STORED) as z:
            for arq in itens:
                z.writestr(arq, _imagem_pronta(grupos[letra][arq]))
        blob = fecha(chave, buf.getvalue())
        with open(os.path.join(pasta, nome), "wb") as f:
            f.write(blob)
        pacotes[nome] = {"sig": sig, "sha256": hashlib.sha256(blob).hexdigest(), "n": len(itens), "kb": len(blob) // 1024}
        novos += 1
    sig_n = hashlib.sha256(json.dumps(nichos, sort_keys=True, ensure_ascii=False).encode()).hexdigest()
    velho_n = antigo.get("nichos") or {}
    if velho_n.get("sig") == sig_n and os.path.isfile(os.path.join(pasta, "nichos.v9img")):
        nichos_idx = velho_n
    else:
        blob = fecha(chave, json.dumps(nichos, ensure_ascii=False).encode("utf-8"))
        with open(os.path.join(pasta, "nichos.v9img"), "wb") as f:
            f.write(blob)
        nichos_idx = {"sig": sig_n, "sha256": hashlib.sha256(blob).hexdigest()}
    for velho_arq in glob.glob(os.path.join(pasta, "p-*.v9img")):
        if os.path.basename(velho_arq) not in pacotes:
            os.remove(velho_arq)
    total = sum(p["n"] for p in pacotes.values())
    with open(os.path.join(pasta, "indice.json"), "w", encoding="utf-8") as f:
        json.dump({"gerado_em": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()), "total": total,
                   "pacotes": pacotes, "nichos": nichos_idx}, f)
    mb = sum(p.get("kb", 0) for p in pacotes.values()) / 1024
    print(f"Thumbnails: {total} imagens em {len(pacotes)} pacotes cifrados ({mb:.0f} MB), {novos} pacote(s) regravado(s).")
    return 0


# copias das skills CENA e GENIU$ dentro do motor do V9 Flow embutido (motor_flow/): no membro, o estudio de avatares
# pede o texto ao scripts/conteudo.py (motor_flow/v9flow/estudio.py, _referencia)
COPIAS_DO_METODO = {"motor_flow/v9flow/conhecimento/cena.md", "motor_flow/v9flow/conhecimento/geniu.md"}
TEXTO = (".py", ".md", ".txt", ".json", ".html", ".js", ".css", ".bat", ".ps1")


def _metodo_fora_do_pacote(app, zip_bytes):
    """o zip do app com as reservas dos prompts trocadas pelo SENTINELA e os arquivos de metodo esvaziados. Confere no
    fim que nenhum texto de prompt sobrou -- se sobrar, para (melhor nao publicar do que vazar)."""
    sys.path.insert(0, os.path.join(app, "instalador"))
    import publicar_conteudo as P
    pacote, _ = P.montar_do_commit()
    entrada, saida = zipfile.ZipFile(io.BytesIO(zip_bytes)), io.BytesIO()
    n, fontes, textos = 0, [], {}
    with zipfile.ZipFile(saida, "w", zipfile.ZIP_DEFLATED) as z:
        for info in entrada.infolist():
            dados = entrada.read(info.filename)
            nome = info.filename.replace("\\", "/")
            if nome in P.conteudo.ARQUIVOS or nome in COPIAS_DO_METODO:
                dados = (P.conteudo.SENTINELA + "\n(metodo do V9: vem da nuvem com a sua licenca)\n").encode("utf-8")
                n += 1
            elif (nome.endswith(".py") and not nome.endswith("conteudo.py")
                  and (nome.count("/") <= 1 or nome.startswith("motor_flow/v9flow/"))):
                fonte = dados.decode("utf-8")
                novo = P.tirar_reservas(fonte)
                if novo != fonte:
                    n += fonte.count("conteudo.texto(") + fonte.count("conteudo.dados(")
                    dados = novo.encode("utf-8")
                fontes.append(novo if novo != fonte else fonte)
            z.writestr(info, dados)
            if nome.endswith(TEXTO):
                textos[nome] = dados.decode("utf-8", "replace")
    tudo = "\n".join(fontes)
    vazou = [k for k, v in pacote["textos"].items() if len(v) > 300 and v[:200] in tudo]
    # arquivo de metodo copiado em outro lugar do pacote (o motor do Flow embutido levava CENA e GENIU$ inteiros): conta
    # as linhas longas de cada um que aparecem num mesmo arquivo. Umas poucas em comum com as skills do assistente e'
    # normal; um terco ou mais e' copia.
    for rel, texto_arq in pacote["arquivos"].items():
        linhas = {l.strip() for l in texto_arq.splitlines() if len(l.strip()) > 60}
        if len(linhas) < 5:
            continue
        for nome, t in textos.items():
            if sum(1 for l in linhas if l in t) >= max(5, len(linhas) / 3):
                vazou.append(f"{rel} (copiado em {nome})")
    if vazou:
        raise RuntimeError("isto continuaria no pacote: " + ", ".join(vazou[:5]))
    return saida.getvalue(), n


ARQUIVOS_MAC = ("plataforma.py", "abrir_mac.py", "preparar_mac.sh")


def plataformas_do_pacote(zip_bytes, pedido=None):
    """["windows"] ou ["windows", "mac"]. Mac so' entra se o pacote tem a parte do Mac (ARQUIVOS_MAC na raiz) --
    um pacote sem ela, aplicado num Mac, quebraria o app (DPAPI/ctypes.windll). --plataformas forca outra lista."""
    if pedido:
        return sorted({p.strip().lower() for p in str(pedido).split(",") if p.strip()})
    import io
    import zipfile
    with zipfile.ZipFile(io.BytesIO(zip_bytes)) as z:
        nomes = set(z.namelist())
    return ["windows", "mac"] if all(n in nomes for n in ARQUIVOS_MAC) else ["windows"]


def cmd_publicar(a):
    membros = _ler_membros(a.membros)
    if membros is None:
        return 3
    login, senha = _ler_credenciais()
    chave = abre_membro(membros, login, senha) if login and senha else None
    if not chave:
        print("ERRO: login ou senha incorretos.", file=sys.stderr)
        return 2
    if getattr(a, "dados", None):
        total, falhas = conferir_dados(chave, a.dados)
        if falhas:
            print(f"ERRO: {len(falhas)} de {total} arquivo(s) de dados do Oracle NAO abrem com a chave da lista de membros "
                  f"({', '.join(falhas[:4])}{'...' if len(falhas) > 4 else ''}).", file=sys.stderr)
            print("      A chave dos dados do Oracle e a da lista de membros estao diferentes: os membros entrariam e nao veriam nada.",
                  file=sys.stderr)
            print("      Nada foi publicado. Abra a pagina de administrador do Oracle, clique em 'Trocar a chave agora', espere a rodada "
                  "terminar, de' Pull no v9oracle e rode este arquivo de novo.", file=sys.stderr)
            return 5
        print(f"Dados do Oracle conferidos: {total} arquivo(s) abrem com a chave da lista de membros.")
    if getattr(a, "thumbs", None) and os.path.isdir(a.thumbs):
        publicar_thumbs(chave, a.thumbs, a.dist)
    try:
        zip_bytes = _git(a.app, "archive", "--format=zip", "HEAD")      # so' o que esta versionado: sem .env, venv, logs
        curto = _git(a.app, "rev-parse", "--short", "HEAD").decode().strip()
        pendente = _git(a.app, "status", "--porcelain").decode().strip()
    except (RuntimeError, OSError) as e:
        print(f"ERRO: nao consegui montar o pacote ({e})", file=sys.stderr)
        return 3
    if pendente:
        print("AVISO: ha mudancas nao commitadas na pasta do app. O pacote leva so' o ultimo commit.", file=sys.stderr)
    # FASE B do metodo na nuvem (2026-10-13): com o arquivo instalador/METODO_SO_NA_NUVEM no app, o pacote dos membros
    # vai SEM os textos dos prompts e sem os arquivos de metodo (ficam so' no Supabase, scripts/conteudo.py).
    if os.path.isfile(os.path.join(a.app, "instalador", "METODO_SO_NA_NUVEM")):
        try:
            zip_bytes, n = _metodo_fora_do_pacote(a.app, zip_bytes)
        except Exception as e:
            print(f"ERRO: nao consegui tirar o metodo do pacote ({e}). Nada foi publicado.", file=sys.stderr)
            return 6
        print(f"Metodo fora do pacote: {n} prompt(s) e arquivo(s) de metodo so' na nuvem.")
    versao = a.versao or (time.strftime("%Y.%m.%d") + "-" + curto)
    plataformas = plataformas_do_pacote(zip_bytes, getattr(a, "plataformas", None))
    print(f"Plataformas deste pacote: {', '.join(plataformas)}")
    blob = fecha(chave, zip_bytes)
    os.makedirs(a.dist, exist_ok=True)
    with open(os.path.join(a.dist, "app.v9pkg"), "wb") as f:
        f.write(blob)
    latest = {"versao": versao, "arquivo": "app.v9pkg", "sha256": hashlib.sha256(blob).hexdigest(),
              "tamanho": len(blob), "publicado_em": time.strftime("%Y-%m-%d %H:%M:%S"),
              # impressao digital da chave dos membros: o Oracle (GitHub) so' publica dados se a chave dele for a mesma
              "chave_id": hashlib.sha256(base64.b64decode(chave)).hexdigest()[:12],
              # em quais sistemas este pacote roda (unificacao Windows+Mac, 15/10): o atualizador.py de cada computador
              # recusa um pacote que nao lista o sistema dele (antes um Mac podia aplicar um pacote so' de Windows)
              "plataformas": plataformas}
    with open(os.path.join(a.dist, "latest.json"), "w", encoding="utf-8") as f:
        json.dump(latest, f, indent=1)
    with open(a.membros, "rb") as o, open(os.path.join(a.dist, "membros.json"), "wb") as d:
        d.write(o.read())
    # Mac (2026-10-13): o instalador do Terminal (curl ... | bash) e o verificador de acesso que ele baixa.
    # Fim de linha LF: com CRLF o bash do Mac quebra.
    for nome in ("instalar_mac.sh", "v9_cofre.py"):
        origem = os.path.join(a.app, "instalador", nome)
        if os.path.isfile(origem):
            with open(origem, "rb") as o, open(os.path.join(a.dist, nome), "wb") as d:
                d.write(o.read().replace(b"\r\n", b"\n"))
    print(f"Pacote {versao}: {len(blob) / 1024:.0f} KB cifrado -> {a.dist}")
    return 0


def main():
    ap = argparse.ArgumentParser(description="Cofre do instalador V9 Vision")
    sub = ap.add_subparsers(dest="cmd", required=True)
    p = sub.add_parser("abrir"); p.add_argument("--membros", required=True); p.set_defaults(f=cmd_abrir)
    p = sub.add_parser("decifrar"); p.add_argument("--pacote", required=True); p.add_argument("--destino", required=True)
    p.set_defaults(f=cmd_decifrar)
    p = sub.add_parser("publicar"); p.add_argument("--app", required=True); p.add_argument("--dist", required=True)
    p.add_argument("--membros", required=True); p.add_argument("--versao")
    p.add_argument("--plataformas", help="ex.: windows,mac (padrao: descobre pelo pacote)")
    p.add_argument("--dados", help="pasta com os .enc do Oracle: confere se abrem com a chave antes de publicar")
    p.add_argument("--thumbs", help="pasta do banco de thumbnails (_thumbnails\\banco): publica cifrado em thumbs/")
    p.set_defaults(f=cmd_publicar)
    p = sub.add_parser("guardar"); p.add_argument("--destino", required=True); p.set_defaults(f=cmd_guardar)
    a = ap.parse_args()
    return a.f(a)


if __name__ == "__main__":
    sys.exit(main())
