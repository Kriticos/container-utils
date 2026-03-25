FROM debian:bookworm
LABEL maintainer="Kriticos"

ENV DEBIAN_FRONTEND=noninteractive

# -------------------------------------------------------------------
# Pacotes essenciais
# -------------------------------------------------------------------
RUN apt update && apt install -y \
    jq \
    gnupg \
    curl \
    wget \
    rsync \
    cron \
    bash \
    unzip \
    nano \
    zip \
    iproute2 \
    dnsutils \
    iputils-ping \
    procps \
    net-tools \
    iputils-tracepath \
    mtr-tiny \
    htop \
    git \
    bc \
    tzdata \
    lsb-release \
    ca-certificates \
    default-mysql-client \
    smbclient \
    && apt clean && rm -rf /var/lib/apt/lists/*

# -------------------------------------------------------------------
# Speedtest CLI (Ookla)
# -------------------------------------------------------------------
RUN curl -s https://packagecloud.io/install/repositories/ookla/speedtest-cli/script.deb.sh | bash && \
    apt install -y speedtest && \
    apt clean && rm -rf /var/lib/apt/lists/*

# -------------------------------------------------------------------
# Zabbix Sender
# -------------------------------------------------------------------
RUN wget -q https://repo.zabbix.com/zabbix/7.2/stable/debian/pool/main/z/zabbix/zabbix-sender_7.2.9-1+debian12_amd64.deb && \
    apt install -y ./zabbix-sender_7.2.9-1+debian12_amd64.deb && \
    rm zabbix-sender_7.2.9-1+debian12_amd64.deb && \
    apt clean && rm -rf /var/lib/apt/lists/*

# -------------------------------------------------------------------
# Log do cron em runtime
# -------------------------------------------------------------------
CMD ["bash", "-c", "touch /var/log/cron.log && cron && tail -f /var/log/cron.log"]