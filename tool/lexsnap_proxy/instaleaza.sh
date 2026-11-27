#!/usr/bin/env bash
# Instalează proxy-ul LexSnap AI pe serverul OVH (Ubuntu), dintr-o singură
# comandă, rulată pe server:
#
#   curl -fsSLO https://raw.githubusercontent.com/luke82141-commits/portal-dosare/main/tool/lexsnap_proxy/instaleaza.sh && sudo bash instaleaza.sh
#
# Nu cu `curl ... | sudo bash`: pe Ubuntu nou (sudo-rs) scriptul nu poate
# citi cheia de la tastatură când vine printr-un pipe.
# - Nu atinge EtoroBot (serviciul `etorobot`, portul 8765): proxy-ul folosește
#   portul 8787, doar local, și utilizatorul separat `lexsnap`.
# - Cheia Groq o scrii tu când ți-o cere; nu apare pe ecran și stă doar în
#   /etc/lexsnap/proxy.env (citibil doar de root).
# - HTTPS prin Caddy, cu certificat gratuit, pe adresa 57-129-169-40.sslip.io.
# - Se poate rula din nou fără probleme (actualizează programul).
set -euo pipefail

REPO_RAW="https://raw.githubusercontent.com/luke82141-commits/portal-dosare/main/tool/lexsnap_proxy"
SHA_XZ="d3e3108671db7b843b330ae1b3e93a5fac40dd137b6e5012cc4f83d55bdb79b5"
PORT=8787

pas() { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }
ok() { printf '\033[1;32m✓ %s\033[0m\n' "$*"; }
eroare() { printf '\n\033[1;31m✗ %s\033[0m\n' "$*"; exit 1; }

[ "$(id -u)" -eq 0 ] || eroare "Rulează cu sudo (vezi comanda din instrucțiuni)."
[ -t 0 ] || eroare "Scriptul trebuie rulat așa, ca să poți lipi cheia:
  curl -fsSLO $REPO_RAW/instaleaza.sh && sudo bash instaleaza.sh"

IP="$(curl -fsS4 --max-time 10 https://api.ipify.org || true)"
[ -n "$IP" ] || IP="$(hostname -I | awk '{print $1}')"
DOMENIU="${LEXSNAP_DOMENIU:-${IP//./-}.sslip.io}"

pas "1/6 Verific că portul $PORT e liber (EtoroBot e pe 8765 și rămâne neatins)"
if ss -ltn | grep -q ":$PORT " && ! systemctl is-active --quiet lexsnap-proxy; then
  eroare "Portul $PORT e folosit de alt program. Spune-i lui Claude."
fi
ok "Portul $PORT e liber"

pas "2/6 Descarc programul"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
curl -fsSL "$REPO_RAW/dist/lexsnap-proxy-linux-x64.xz" -o "$TMP/p.xz"
echo "$SHA_XZ  $TMP/p.xz" | sha256sum -c --quiet - || eroare "Fișierul descărcat nu e cel corect."
xz -d "$TMP/p.xz"
id lexsnap >/dev/null 2>&1 || useradd --system --no-create-home --shell /usr/sbin/nologin lexsnap
install -m 755 "$TMP/p" /usr/local/bin/lexsnap-proxy
ok "Program instalat în /usr/local/bin/lexsnap-proxy"

pas "3/6 Cheia Groq"
mkdir -p /etc/lexsnap
CHEIE=""
if [ -f /etc/lexsnap/proxy.env ] && grep -q '^GROQ_API_KEY=gsk_' /etc/lexsnap/proxy.env; then
  echo "Am deja o cheie salvată. Ca s-o schimbi, lipește aici cheia NOUĂ (nu apare pe ecran)."
  echo "Ca s-o păstrezi pe cea veche, apasă doar Enter."
  printf '\033[?2004l'
  read -rsp "Cheia nouă sau Enter: " R || R=""
  echo
  R="$(printf '%s' "$R" | grep -o 'gsk_[A-Za-z0-9]*' | head -1 || true)"
  if [ ${#R} -ge 20 ]; then
    CHEIE="$R"
    ok "Cheie nouă primită (${#CHEIE} caractere, se termină cu …${CHEIE: -4})"
  else
    CHEIE="$(grep '^GROQ_API_KEY=' /etc/lexsnap/proxy.env | cut -d= -f2-)"
    ok "Păstrez cheia salvată"
  fi
  unset R
fi
while [ -z "$CHEIE" ]; do
  echo "Lipește cheia Groq (clic dreapta sau Ctrl+V), apoi apasă Enter."
  echo "ATENȚIE: cât lipești NU apare nimic pe ecran. E normal, cheia e ascunsă."
  # Terminalul Windows trimite textul lipit între coduri „bracketed paste”
  # (ESC[200~ ... ESC[201~); le oprim și, oricum, păstrăm doar cheia.
  printf '\033[?2004l'
  if ! read -rsp "Cheia: " CHEIE; then
    echo
    eroare "Nu am putut citi cheia de la tastatură. Spune-i lui Claude."
  fi
  echo
  CHEIE="$(printf '%s' "$CHEIE" | grep -o 'gsk_[A-Za-z0-9]*' | head -1 || true)"
  if [ ${#CHEIE} -lt 20 ]; then
    echo "N-am găsit o cheie care începe cu gsk_. Încearcă din nou."
    CHEIE=""
  else
    ok "Cheie primită (${#CHEIE} caractere, se termină cu …${CHEIE: -4})"
  fi
done
umask 077
printf 'GROQ_API_KEY=%s\nLEXSNAP_TOKEN=lexsnap-app-v1\nLEXSNAP_PORT=%s\n' "$CHEIE" "$PORT" > /etc/lexsnap/proxy.env
chmod 600 /etc/lexsnap/proxy.env
umask 022
unset CHEIE
ok "Cheia e salvată doar pe server"

pas "4/6 Pornesc serviciul lexsnap-proxy"
curl -fsSL "$REPO_RAW/lexsnap-proxy.service" -o /etc/systemd/system/lexsnap-proxy.service
systemctl daemon-reload
systemctl enable lexsnap-proxy >/dev/null 2>&1
systemctl restart lexsnap-proxy
sleep 2
curl -fsS "http://127.0.0.1:$PORT/lexsnap/sanatate" >/dev/null || {
  journalctl -u lexsnap-proxy -n 20 --no-pager
  eroare "Serviciul nu răspunde."
}
ok "Serviciul merge (pornește singur și după restart)"

pas "5/6 HTTPS cu Caddy pe https://$DOMENIU"
if ! command -v caddy >/dev/null; then
  # Fără ferestre ascunse (needrestart/debconf) și cu progres vizibil.
  export DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=l NEEDRESTART_SUSPEND=1
  APT=(apt-get -o DPkg::Lock::Timeout=600 -y)
  echo "Instalez Caddy (poate dura 1-2 minute; dacă serverul își face actualizările, aștept să termine)..."
  "${APT[@]}" update -q
  if ! "${APT[@]}" install -q caddy; then
    "${APT[@]}" install -q debian-keyring debian-archive-keyring apt-transport-https gnupg
    curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor --yes -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
    curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' -o /etc/apt/sources.list.d/caddy-stable.list
    "${APT[@]}" update -q
    "${APT[@]}" install -q caddy
  fi
fi
cat > /etc/caddy/lexsnap.caddy <<EOF
$DOMENIU {
	request_body {
		max_size 256KB
	}
	handle /lexsnap/* {
		reverse_proxy 127.0.0.1:$PORT
	}
	handle {
		respond 404
	}
}
EOF
# Caddyfile-ul implicit (doar pagina de bun venit) îl înlocuim; altfel doar
# adăugăm configurația noastră, fără să stricăm ce era.
if [ ! -f /etc/caddy/Caddyfile ] || ! grep -vE '^\s*(#|$)' /etc/caddy/Caddyfile | grep -vqE '^\s*(:80|root|file_server|\}|\{|:80 \{)'; then
  echo 'import lexsnap.caddy' > /etc/caddy/Caddyfile
elif ! grep -q 'import lexsnap.caddy' /etc/caddy/Caddyfile; then
  cp /etc/caddy/Caddyfile "/etc/caddy/Caddyfile.inainte-de-lexsnap"
  echo 'import lexsnap.caddy' >> /etc/caddy/Caddyfile
fi
if command -v ufw >/dev/null && ufw status | grep -q 'Status: active'; then
  ufw allow 80/tcp >/dev/null
  ufw allow 443/tcp >/dev/null
fi
caddy validate --config /etc/caddy/Caddyfile >/dev/null 2>&1 || eroare "Configurația Caddy nu e validă."
# Caddy rulează ca utilizatorul `caddy`: trebuie să-și poată citi config-ul.
chmod 644 /etc/caddy/Caddyfile /etc/caddy/lexsnap.caddy
systemctl enable caddy >/dev/null 2>&1
if ! systemctl restart caddy; then
  echo "Cine folosește porturile 80 și 443:"
  ss -ltnp '( sport = :80 or sport = :443 )' || true
  journalctl -u caddy -n 15 --no-pager || true
  eroare "Caddy nu a pornit. Trimite-i lui Claude o poză cu rândurile de mai sus."
fi
ok "Caddy pornit"

pas "6/6 Probă completă: HTTPS + Groq (poate dura până la un minut)"
RASPUNS=""
for _ in $(seq 1 12); do
  if curl -fsS --max-time 10 "https://$DOMENIU/lexsnap/sanatate" >/dev/null 2>&1; then
    RASPUNS="ok"
    break
  fi
  sleep 5
done
[ -n "$RASPUNS" ] || eroare "HTTPS nu merge încă (certificatul). Verifică în panoul OVH că porturile 80 și 443 sunt deschise."
COD="$(curl -sS -o "$TMP/r.json" -w '%{http_code}' --max-time 90 \
  -H 'Content-Type: application/json' -H 'X-LexSnap-Token: lexsnap-app-v1' \
  -d '{"document":"Proces-verbal de contravenție comunicat azi. Amendă 500 lei.","surse":[{"id":"S1","act":"OG nr. 2/2001","articol":"31","text":"(1) Împotriva procesului-verbal de constatare a contravenției și de aplicare a sancțiunii se poate face plângere în termen de 15 zile de la data înmânării sau comunicării acestuia."}]}' \
  "https://$DOMENIU/lexsnap/sugestii")"
if [ "$COD" = "200" ]; then
  ok "Groq a răspuns. Totul e gata."
  printf '\nAdresa pentru aplicație: \033[1mhttps://%s/lexsnap\033[0m\n' "$DOMENIU"
  printf 'Scrie-i lui Claude: „gata, merge”.\n'
else
  journalctl -u lexsnap-proxy -n 5 --no-pager
  eroare "Groq nu a răspuns (cod $COD). Probabil cheia e greșită: rulează comanda din nou și scrie N la cheie."
fi
