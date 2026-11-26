# Proxy LexSnap AI (server OVH)

Aplicația nu ține nicio cheie API. Trimite documentul (fără CNP, IBAN, telefon,
email, seria buletinului și număr auto) și articolele găsite la acest proxy,
care construiește promptul și întreabă un model gratuit.

- **Groq** (implicit): plan gratuit, cererile nu sunt folosite la antrenare.
  Model implicit `llama-3.3-70b-versatile`.
- **Gemini**: plan gratuit, dar Google poate folosi datele pentru a-și
  îmbunătăți produsele. Nu e potrivit pentru documente reale.

Proxy-ul e un singur fișier executabil, fără Dart sau alte programe pe server.
Ocupă puțin (~10 MB RAM), deci merge pe serverul de 2 GB.

## 1. Cheia (o faci tu)

Intri în https://console.groq.com/keys, apeși „Create API Key” și o copiezi.
**Nu o scrie în chat.** O pui direct pe server, la pasul 3.

## 2. Compilare (de pe PC sau Mac, cu Flutter instalat)

```
dart compile exe tool/lexsnap_proxy/server.dart -o lexsnap-proxy --target-os linux --target-arch x64
scp lexsnap-proxy UTILIZATOR@SERVER:/tmp/
```

## 3. Instalare pe server

```
sudo useradd --system --no-create-home lexsnap
sudo install -m 755 /tmp/lexsnap-proxy /usr/local/bin/lexsnap-proxy
sudo mkdir -p /etc/lexsnap
sudo nano /etc/lexsnap/proxy.env          # vezi mai jos
sudo chmod 600 /etc/lexsnap/proxy.env
sudo cp lexsnap-proxy.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now lexsnap-proxy
curl -s 127.0.0.1:8787/lexsnap/sanatate     # {"ok":true}
```

`/etc/lexsnap/proxy.env`:

```
GROQ_API_KEY=cheia-de-la-groq
LEXSNAP_TOKEN=lexsnap-app-v1
# Opțional:
# LEXSNAP_MODEL=llama-3.3-70b-versatile
# LEXSNAP_MAX_MINUT=6     cereri pe minut de la același telefon
# LEXSNAP_MAX_ZI=500      cereri pe zi în total (sub limita gratuită)
```

## 4. HTTPS cu Caddy

Android nu acceptă HTTP simplu, deci punem Caddy în față (certificat gratuit
Let's Encrypt, reînnoit automat). Îți trebuie un nume de domeniu care să arate
spre server, de exemplu numele dat de OVH (`vps-xxxx.vps.ovh.net`).

```
sudo apt install -y caddy
sudo cp Caddyfile /etc/caddy/Caddyfile     # înlocuiește NUMELE-SERVERULUI
sudo systemctl reload caddy
curl -s https://NUMELE-SERVERULUI/lexsnap/sanatate
```

Porturile 80 și 443 trebuie să fie deschise în firewall.

## 5. Aplicația

În `lib/lexsnap/ai_proxy.dart`, `urlProxyAi` ia valoarea
`https://NUMELE-SERVERULUI/lexsnap`. Se poate pune și doar la build:

```
flutter build apk --dart-define=LEXSNAP_AI_URL=https://NUMELE-SERVERULUI/lexsnap
```

## Jurnal

`journalctl -u lexsnap-proxy -f` arată doar ora, numărul de articole și durata.
Textul documentelor nu e scris niciodată.
