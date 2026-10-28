FROM debian:trixie-slim

ENV SSH_USER=sshuser \
    SSH_UID=1000 \
    SSH_GID=1000

RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      openssh-server \
      passwd \
      bind9-dnsutils \
      iputils-ping \
      netcat-openbsd && \
    rm -rf /var/lib/apt/lists/* && \
    install -d -m 0755 /run/sshd && \
    install -d -m 0700 /var/lib/ssh && \
    rm -f /etc/ssh/ssh_host_* && \
    ln -s /var/lib/ssh/ssh_host_ed25519_key /etc/ssh/ssh_host_ed25519_key && \
    printf '%s\n' \
      'Include /run/sshd/*.conf' \
      'Port 22' \
      'HostKey /var/lib/ssh/ssh_host_ed25519_key' \
      'PermitRootLogin no' \
      'PubkeyAuthentication yes' \
      'AuthorizedKeysFile .ssh/authorized_keys' \
      'PasswordAuthentication yes' \
      'KbdInteractiveAuthentication no' \
      'UsePAM yes' \
      'Subsystem sftp /usr/lib/openssh/sftp-server' \
      > /etc/ssh/sshd_config

COPY --chmod=0755 docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh

EXPOSE 22
ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
