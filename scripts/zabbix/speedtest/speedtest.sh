#!/bin/bash

HOST="Link - Internet"
ZABBIX_SERVER="172.18.0.3"
SPEEDTEST_SERVER_ID="17484"

# Roda o speedtest e captura em JSON.
# Os flags de aceite evitam falha em execuções não interativas dentro do container.
RESULT=$(speedtest --server-id="$SPEEDTEST_SERVER_ID" --format=json --progress=no --accept-gdpr --accept-license 2>&1)
RESULT=$(printf '%s\n' "$RESULT" | awk '/^\{.*\}$/ {json=$0} END {print json}')

# Verifica erro
[ -z "$RESULT" ] && echo "Erro: speedtest não retornou dados." && exit 1

# Extrai dados
DOWNLOAD=$(echo "$RESULT" | jq '.download.bandwidth')
UPLOAD=$(echo "$RESULT" | jq '.upload.bandwidth')
LATENCY=$(echo "$RESULT" | jq '.ping.latency')
PACKET_LOSS=$(echo "$RESULT" | jq '.packetLoss // 0')
ISP=$(echo "$RESULT" | jq -r '.isp')
SERVER_NAME=$(echo "$RESULT" | jq -r '.server.name')
SERVER_ID=$(echo "$RESULT" | jq -r '.server.id')
RESULT_URL=$(echo "$RESULT" | jq -r '.result.url')

# Converte bytes → Mbps
DOWNLOAD_MBPS=$(awk "BEGIN {print $DOWNLOAD * 8 / 1000000}")
UPLOAD_MBPS=$(awk "BEGIN {print $UPLOAD * 8 / 1000000}")

echo "Download.......: $DOWNLOAD_MBPS Mbps"
echo "Upload.........: $UPLOAD_MBPS Mbps"
echo "Latência.......: $LATENCY ms"
echo "Packet Loss....: $PACKET_LOSS %"
echo "ISP............: $ISP"
echo "Servidor.......: $SERVER_NAME (id: $SERVER_ID)"
echo "URL............: $RESULT_URL"

# Envia para o Zabbix
zabbix_sender -z "$ZABBIX_SERVER" -s "$HOST" -k speedtest.download -o "$DOWNLOAD_MBPS"
zabbix_sender -z "$ZABBIX_SERVER" -s "$HOST" -k speedtest.upload -o "$UPLOAD_MBPS"
zabbix_sender -z "$ZABBIX_SERVER" -s "$HOST" -k speedtest.latency -o "$LATENCY"
zabbix_sender -z "$ZABBIX_SERVER" -s "$HOST" -k speedtest.packet_loss -o "$PACKET_LOSS"
zabbix_sender -z "$ZABBIX_SERVER" -s "$HOST" -k speedtest.isp -o "$ISP"
zabbix_sender -z "$ZABBIX_SERVER" -s "$HOST" -k speedtest.server -o "$SERVER_NAME (id: $SERVER_ID)"
zabbix_sender -z "$ZABBIX_SERVER" -s "$HOST" -k speedtest.result_url -o "$RESULT_URL"
