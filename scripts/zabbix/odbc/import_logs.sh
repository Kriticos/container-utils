#!/usr/bin/env bash
set -euo pipefail

# Configuração via variáveis de ambiente (padrões opcionais)
DB_HOST="${DB_HOST:-127.0.0.1}"
DB_PORT="${DB_PORT:-3306}"
DB_USER="${DB_USER:-root}"
DB_PASS="${DB_PASS:-}"
DB_NAME="${DB_NAME:-rds_logs}"
TABLE="${TABLE:-rds_client_log}"
LOG_DIR="${LOG_DIR:-/caminho/para/hostname_logs}"

shopt -s nullglob

export MYSQL_PWD="$DB_PASS"
SMB_SHARE="${SMB_SHARE:-}"
SMB_REMOTE_FILE="${SMB_REMOTE_FILE:-}"
SMB_USER="${SMB_USER:-}"
SMB_PASS="${SMB_PASS:-}"

process_stream() {
  DEBUG_IMPORT="${DEBUG_IMPORT:-0}"
  local src_name="$1"
  local processed_lines=0
  local attempted_inserts=0
  local successful_inserts=0

  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -z "$line" ]] && continue
    processed_lines=$((processed_lines+1))

    # Esperado: [ts];display;server;client;ip;serial
    ts_bracket=$(awk -F';' '{print $1}' <<<"$line")
    display=$(awk -F';' '{print $2}' <<<"$line")
    server=$(awk -F';' '{print $3}' <<<"$line")
    client=$(awk -F';' '{print $4}' <<<"$line")
    ip=$(awk -F';' '{print $5}' <<<"$line")
    serial=$(awk -F';' '{print $6}' <<<"$line")

    # remove [ ] do timestamp e converte "dd/mm/yyyy hh:mm:ss" -> "yyyy-mm-dd hh:mm:ss"
    ts_clean="${ts_bracket#[}"
    ts_clean="${ts_clean%]}"

    # conversão por date (depende de locale; em pt_BR normalmente funciona)
    ts_iso=$(date -d "$ts_clean" "+%F %T" 2>/dev/null || true)
    if [[ -z "$ts_iso" ]]; then
      if [[ "$DEBUG_IMPORT" -eq 1 ]]; then
        echo "[DEBUG] line #${processed_lines}: timestamp parse failed: ${ts_bracket}" >&2
      fi
      continue
    fi

    # hash pra deduplicar
    hash_hex=$(printf '%s' "$line" | sha1sum | awk '{print $1}')

    # insere (ignora duplicados pelo UNIQUE)
    attempted_inserts=$((attempted_inserts+1))
    if [[ "$DEBUG_IMPORT" -eq 1 ]]; then
      echo "[DEBUG] Inserindo linha #${processed_lines} (hash=${hash_hex}) from ${src_name}" >&2
    fi

    if mysql --host="$DB_HOST" --port="$DB_PORT" --user="$DB_USER" --database="$DB_NAME" --silent --raw <<SQL; then
INSERT IGNORE INTO $TABLE
(ts, display_name, server_name, client_name, ip_address, bios_serial, source_file, raw_line, line_hash)
VALUES
(
  '$ts_iso',
  $(printf "%q" "$display" | sed "s/^/'/;s/$/'/"),
  $(printf "%q" "$server"  | sed "s/^/'/;s/$/'/"),
  $(printf "%q" "$client"  | sed "s/^/'/;s/$/'/"),
  $(printf "%q" "$ip"      | sed "s/^/'/;s/$/'/"),
  $(printf "%q" "$serial"  | sed "s/^/'/;s/$/'/"),
  $(printf "%q" "${src_name}" | sed "s/^/'/;s/$/'/"),
  $(printf "%q" "$line"    | sed "s/^/'/;s/$/'/"),
  UNHEX('$hash_hex')
);
SQL
      successful_inserts=$((successful_inserts+1))
    fi

  done

  echo "Import summary for ${src_name}: processed=${processed_lines}, attempted_inserts=${attempted_inserts}, successful_inserts=${successful_inserts}"

}

if [[ -n "$SMB_SHARE" && -n "$SMB_REMOTE_FILE" ]]; then
  if ! command -v smbclient >/dev/null 2>&1; then
    echo "smbclient não encontrado; instale smbclient no container." >&2
    exit 1
  fi
  # monta via smbclient e envia o conteúdo para process_stream
  if [[ -n "$SMB_USER" ]]; then
    smbclient "$SMB_SHARE" -U "${SMB_USER}%${SMB_PASS}" -c "get ${SMB_REMOTE_FILE} -" | process_stream "${SMB_REMOTE_FILE}"
  else
    smbclient "$SMB_SHARE" -N -c "get ${SMB_REMOTE_FILE} -" | process_stream "${SMB_REMOTE_FILE}"
  fi
else
  for f in "$LOG_DIR"/*.log; do
    process_stream "$(basename "$f")" < "$f"
  done
fi

echo "Import concluído."
