#!/usr/bin/env bash
set -Eeuo pipefail

# internet-check.sh
# Requer: bash, curl, (opcional: dig, ping)
# Saída: resumo + exit code 0 OK / 2 FAIL

# ====== Config ======
# Quantos testes precisam passar para considerar "OK"
# (padrão: 70% dos checks)
PASS_RATIO="${PASS_RATIO:-0.70}"

# Timeout por request HTTP (segundos)
HTTP_TIMEOUT="${HTTP_TIMEOUT:-5}"

# Tentativas por request HTTP
HTTP_RETRIES="${HTTP_RETRIES:-1}"

# Teste DNS: domínio alvo para resolver
DNS_TEST_DOMAIN="${DNS_TEST_DOMAIN:-example.com}"

# DNS públicos principais
DNS_SERVERS=(
  "1.1.1.1"      # Cloudflare
  "1.0.0.1"      # Cloudflare
  "8.8.8.8"      # Google
  "8.8.4.4"      # Google
  "9.9.9.9"      # Quad9
  "149.112.112.112" # Quad9
)

# Endpoints HTTP/HTTPS estáveis (HEAD/GET leve)
HTTP_TARGETS=(
  "https://www.cloudflare.com/cdn-cgi/trace"
  "https://www.google.com/generate_204"
  "https://www.gstatic.com/generate_204"
  "https://dns.google/"
  "https://quad9.net/"
)

# Ping (opcional) para IPs bem conhecidos
PING_IPS=(
  "1.1.1.1"
  "8.8.8.8"
  "9.9.9.9"
)

# ====== Helpers ======
have() { command -v "$1" >/dev/null 2>&1; }
now() { date +"%Y-%m-%d %H:%M:%S"; }

ok()   { printf "[OK]   %s\n" "$*"; }
warn() { printf "[WARN] %s\n" "$*"; }
fail() { printf "[FAIL] %s\n" "$*"; }

pass=0
total=0

# ----- DNS test -----
dns_test() {
  local server="$1"
  total=$((total+1))

  if ! have dig; then
    warn "dig não encontrado; pulando teste DNS via $server"
    return 0
  fi

  # +time=2: timeout curto; +tries=1: 1 tentativa
  if dig @"$server" +time=2 +tries=1 "$DNS_TEST_DOMAIN" A +short >/dev/null 2>&1; then
    pass=$((pass+1))
    ok "DNS resolve via $server"
  else
    fail "DNS falhou via $server"
  fi
}

dns_test_system() {
  total=$((total+1))

  if have getent; then
    if getent ahosts "$DNS_TEST_DOMAIN" >/dev/null 2>&1; then
      pass=$((pass+1))
      ok "DNS resolve via resolver do sistema (getent)"
    else
      fail "DNS falhou via resolver do sistema (getent)"
    fi
  else
    warn "getent não encontrado; pulando teste DNS do sistema"
  fi
}

# ----- HTTP test -----
http_test() {
  local url="$1"
  total=$((total+1))

  # curl: -I (HEAD) pode falhar em alguns sites; usamos GET leve com descarte do body
  # -sS silencioso mas mostra erros, -m timeout, --retry retries (0/1)
  if curl -sS -m "$HTTP_TIMEOUT" --retry "$HTTP_RETRIES" --retry-delay 0 \
      -o /dev/null -w "%{http_code}" "$url" | grep -Eq '^(200|204|301|302)$'; then
    pass=$((pass+1))
    ok "HTTP OK: $url"
  else
    fail "HTTP falhou: $url"
  fi
}

# ----- Ping test (optional) -----
ping_test() {
  local ip="$1"
  total=$((total+1))

  if ! have ping; then
    warn "ping não encontrado; pulando ping para $ip"
    return 0
  fi

  # -c1 1 pacote; -W1 timeout 1s (Linux). Em alguns sistemas, -W é diferente.
  if ping -c 1 -W 1 "$ip" >/dev/null 2>&1; then
    pass=$((pass+1))
    ok "Ping OK: $ip"
  else
    fail "Ping falhou: $ip"
  fi
}

# ====== Exec ======
printf "== Internet Check == %s\n" "$(now)"
printf "Config: PASS_RATIO=%s, HTTP_TIMEOUT=%ss, HTTP_RETRIES=%s, DNS_DOMAIN=%s\n\n" \
  "$PASS_RATIO" "$HTTP_TIMEOUT" "$HTTP_RETRIES" "$DNS_TEST_DOMAIN"

echo "-- DNS checks --"
dns_test_system
for s in "${DNS_SERVERS[@]}"; do dns_test "$s"; done

echo "-- HTTP checks --"
for u in "${HTTP_TARGETS[@]}"; do http_test "$u"; done

echo "-- Ping checks (opcional) --"
for ip in "${PING_IPS[@]}"; do ping_test "$ip"; done

echo "-- Summary --"
printf "Passed: %d/%d\n" "$pass" "$total"

# calcula limiar: ceil(total * PASS_RATIO)
# usando awk para evitar dependências
threshold="$(awk -v t="$total" -v r="$PASS_RATIO" 'BEGIN{ printf("%d\n", (t*r)==int(t*r) ? int(t*r) : int(t*r)+1 ) }')"
printf "Threshold (min pass): %s (ratio %s)\n" "$threshold" "$PASS_RATIO"

if [ "$pass" -ge "$threshold" ]; then
  ok "Internet: OK"
  exit 0
else
  fail "Internet: PROBLEMA (abaixo do limiar)"
  exit 2
fi
