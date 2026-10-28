# Minimal OpenSSH Server on Debian Trixie

Minimal OpenSSH server with `dig`, `ping`, and `nc` based on `debian:trixie-slim` official image.

- Creates an SSH account at startup (`sshuser`, UID/GID 1000 by default).
- Uses `/home/$SSH_USER` as the home directory; supports a bind mount.
- Uses `/etc/ssh/sshd_config`; supports a read-only bind-mounted replacement.
- Generates an Ed25519 host key in `/var/lib/ssh`. Mount a volume there to persist host identity.
- Uses key-only authentication automatically if `~/.ssh/authorized_keys` contains a valid public key and has secure ownership/permissions. The login password is then locked and no password is generated.
- Otherwise generates a random 192-bit password for standalone mode; it is not logged and can be retrieved through `docker exec`.
- Runs `sshd` as PID 1, without systemd or a process supervisor.

## Standalone mode

```sh
docker run -d --name ssh-tools -p 127.0.0.1:2222:22 yurcn/openssh

docker exec ssh-tools cat /run/ssh-initial-password
ssh -p 2222 sshuser@127.0.0.1
```

## External sshd configuration + home (recommended)

Create `./home/.ssh/authorized_keys` containing your public key and ensure `./home` belongs to UID/GID `1000:1000`. Recommended permissions: `~/.ssh` mode 0700, `authorized_keys` mode 0600.

```sh
docker run -d --name ssh-tools \
  -p 127.0.0.1:2222:22 \
  -e SSH_USER=toor -e SSH_UID=1000 -e SSH_GID=1000 \
  -v "$PWD/home:/home/toor" \
  -v "$PWD/sshd_config:/etc/ssh/sshd_config:ro" \
  -v ssh-hostkeys:/var/lib/ssh \
  --restart unless-stopped \
  yurcn/openssh
```

Example `sshd_config` for key-only authentication:

```text
Port 22
HostKey /var/lib/ssh/ssh_host_ed25519_key
PermitRootLogin no
PubkeyAuthentication yes
AuthorizedKeysFile .ssh/authorized_keys .ssh/authorized_key
PasswordAuthentication no
KbdInteractiveAuthentication no
UsePAM yes
Subsystem sftp /usr/lib/openssh/sftp-server
```

If you use another complete SSH configuration, reference the generated host key at `/var/lib/ssh/ssh_host_ed25519_key`, or the compatibility symlink `/etc/ssh/ssh_host_ed25519_key`. The entrypoint validates configuration with `sshd -t` and refuses to start when invalid.

### Automatic key-only mode

At startup, the entrypoint examines `~/.ssh/authorized_keys` for at least one working and parseable public key (`ssh-keygen -l -f`). 

With a valid key file:

- `passwd -l` locks the account's password; `SSH_PASSWORD` is ignored.
- `/run/ssh-initial-password` is removed.
- The built-in `sshd_config` includes `/run/sshd/*.conf` first, so the generated `/run/sshd/00-key-only.conf` disables `PasswordAuthentication` and `KbdInteractiveAuthentication` for the built-in configuration.
- An externally mounted `sshd_config` is **never rewritten**. If it omits the `/run/sshd/*.conf` include, its SSH authentication directives remain entirely under your control. The account password is still locked.

If no usable key file exists, the entrypoint uses the standalone password behavior. **Keep `UsePAM yes` in any external configuration**: with `UsePAM no`, OpenSSH on Linux can reject even public-key logins to an account locked using `passwd -l`. When supplying an external config, ensure it enables `PubkeyAuthentication` and references your chosen authorized-key filename.

You can inspect the effective server policy with:

```sh
docker exec ssh-tools /usr/sbin/sshd -T -C user=admin,host=localhost,addr=127.0.0.1 | grep -E '^(passwordauthentication|kbdinteractiveauthentication|pubkeyauthentication|usepam|authorizedkeysfile) '
```

The entrypoint **never uses `chown -R`** on a mounted home: set `SSH_UID` and `SSH_GID` to match the existing host file ownership.

`SSH_USER` supports lowercase letters, numbers, `_`, and `-`, but must not start with a number or `-`.

