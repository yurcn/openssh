#!/bin/sh
set -eu

: "${SSH_USER:=sshuser}"
: "${SSH_UID:=1000}"
: "${SSH_GID:=1000}"

case "$SSH_USER" in
  ''|*[!a-z0-9_-]*|[0-9-]*) echo 'Invalid SSH_USER' >&2; exit 1 ;;
esac
for value in "$SSH_UID" "$SSH_GID"; do
  case "$value" in
    ''|*[!0-9]*) echo 'SSH_UID and SSH_GID must be positive integers' >&2; exit 1 ;;
  esac
  if ! [ "$value" -gt 0 ] 2>/dev/null; then
    echo 'SSH_UID and SSH_GID must be greater than zero' >&2
    exit 1
  fi
done

home="/home/$SSH_USER"

if id -u "$SSH_USER" >/dev/null 2>&1; then
  if [ "$(id -u "$SSH_USER")" != "$SSH_UID" ] || [ "$(id -g "$SSH_USER")" != "$SSH_GID" ]; then
    echo 'Existing SSH_USER has a different UID or GID' >&2
    exit 1
  fi
else
  if ! getent group "$SSH_GID" >/dev/null 2>&1; then
    groupadd -g "$SSH_GID" "$SSH_USER"
  fi
  useradd -M -u "$SSH_UID" -g "$SSH_GID" -d "$home" -s /bin/sh "$SSH_USER"
fi

if [ ! -e "$home" ]; then
  install -d -m 0755 -o "$SSH_UID" -g "$SSH_GID" "$home"
fi
[ -d "$home" ] || { echo "Not a directory: $home" >&2; exit 1; }

secure_auth_component() {
  path="$1"
  kind="$2"

  [ ! -L "$path" ] || return 1
  if [ "$kind" = directory ]; then
    [ -d "$path" ] || return 1
    needed_owner=0100
    needed_group=0010
    needed_other=0001
  else
    [ -f "$path" ] && [ -s "$path" ] || return 1
    needed_owner=0400
    needed_group=0040
    needed_other=0004
  fi

  metadata="$(stat -c '%u:%g:%a' -- "$path" 2>/dev/null)" || return 1
  owner="${metadata%%:*}"
  metadata="${metadata#*:}"
  group="${metadata%%:*}"
  perms="${metadata#*:}"
  case "$perms" in ''|*[!0-7]*) return 1 ;; esac
  mode=$((0$perms))

  [ "$owner" = 0 ] || [ "$owner" = "$SSH_UID" ] || return 1
  [ $((mode & 0022)) -eq 0 ] || return 1

  if [ "$owner" = "$SSH_UID" ]; then
    [ $((mode & needed_owner)) -ne 0 ] || return 1
  elif [ "$group" = "$SSH_GID" ]; then
    [ $((mode & needed_group)) -ne 0 ] || return 1
  else
    [ $((mode & needed_other)) -ne 0 ] || return 1
  fi
}

key_auth=no
if secure_auth_component "$home" directory && \
   secure_auth_component "$home/.ssh" directory; then
    if secure_auth_component "$home/.ssh/authorized_keys" file && \
       ssh-keygen -l -f "$home/.ssh/authorized_keys" >/dev/null 2>&1; then
      key_auth=yes
      break
    fi
fi

mkdir -p /run/sshd
umask 077
if [ "$key_auth" = yes ]; then
  passwd -l "$SSH_USER" >/dev/null
  rm -f /run/ssh-initial-password
  printf '%s\n' 'PasswordAuthentication no' 'KbdInteractiveAuthentication no' \
    > /run/sshd/00-key-only.conf
else
  rm -f /run/sshd/00-key-only.conf

  if [ -n "${SSH_PASSWORD:-}" ]; then
    password="$SSH_PASSWORD"
    rm -f /run/ssh-initial-password
  elif [ -s /run/ssh-initial-password ]; then
    password="$(cat /run/ssh-initial-password)"
  else
    password="$(od -An -N24 -tx1 /dev/urandom | tr -d '[:space:]')"
    printf '%s\n' "$password" > /run/ssh-initial-password
  fi
  printf '%s:%s\n' "$SSH_USER" "$password" | chpasswd
  unset password
fi

if [ ! -s /var/lib/ssh/ssh_host_ed25519_key ]; then
  ssh-keygen -q -t ed25519 -N '' -f /var/lib/ssh/ssh_host_ed25519_key
fi

/usr/sbin/sshd -t -f /etc/ssh/sshd_config
exec /usr/sbin/sshd -D -e -f /etc/ssh/sshd_config
