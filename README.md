# self-hosting-ansible-example

This repository is the minimal working example for the article [Self-Hosting Your Own Website, from Start to Finish](https://benmandrew.com/articles/self-hosting-website). It deploys a static site and a Gitea instance with a continuous integration (CI) runner onto one server, using Ansible and Docker Compose. The layout follows the article, so each section of it maps onto files here.

## Layout

| Article section | Files |
|---|---|
| Docker Compose | `roles/proxy/templates/docker-compose.yml.j2`, `roles/gitea/templates/docker-compose.yml.j2` |
| The nginx configuration | `roles/proxy/templates/conf.d/static.conf.j2`, `roles/proxy/templates/conf.d/gitea.conf.j2` |
| Cloudflare origin certificates | `roles/certs/` |
| Ansible | `playbooks/site.yml`, `inventory.yml`, `ansible.cfg`, `group_vars/all/main.yml` |
| Ansible Vault | `group_vars/all/vault.yml`, `vault-pass.txt` |
| Gitea and Act Runner | `roles/gitea/` |

The DNS (Domain Name System) A records are set in Cloudflare by hand, so nothing here covers them.

`playbooks/site.yml` runs four roles over the host group `myhosts`, which holds one host, `droplet`, reached as root.

- `docker` installs Docker Engine and the Compose plugin from Docker's apt repository, and creates the shared `proxy` network. This role is an addition beyond the article, so the playbook runs on a bare server.
- `certs` copies the vault-encrypted `origin.pem` and `origin.key` onto the server.
- `proxy` runs the nginx container `nginx-proxy` with `static.conf` and `gitea.conf`, and copies a placeholder site. `static.conf` redirects `www` to the apex and HTTP to HTTPS with a 301, and serves pages with `try_files $uri $uri.html $uri/ =404`.
- `gitea` runs Gitea on SQLite beside `act_runner`. Ansible creates the admin user, so the web installer is skipped and public registration stays off. The runner registers itself through a token shared with Gitea in `GITEA_RUNNER_REGISTRATION_TOKEN`.

nginx resolves the Gitea upstream per request through Docker's embedded DNS server, so the proxy starts whether or not the Gitea container exists. Each role therefore deploys independently of the others.

## Requirements

The tested target is Debian 13. The `docker` role picks Docker's repository for Debian or Ubuntu from `ansible_facts.distribution`, and other distributions are untested. The machine running Ansible (the *controller*) needs `ansible-core` and the `community.docker` collection.

## Usage

**Install the collection.** Run `make install-deps`.

**Set the domain and server.** `group_vars/all/main.yml` holds `domain` and the pinned image versions. `inventory.yml` holds the server's Internet Protocol (IP) address, currently the placeholder `203.0.113.10`. Git over Secure Shell (SSH) listens on port 2222, since the server's own `sshd` keeps port 22.

**Create the secrets.** Run `make bootstrap`, which calls `scripts/bootstrap.sh`. It writes a random `vault-pass.txt`, a self-signed certificate for the domain and `*.domain`, and an encrypted `group_vars/all/vault.yml` holding the Gitea admin password and runner token. It prints the admin password, and skips any file that already exists. The repository ships none of these files.

**Swap in a real certificate.** Replace `roles/certs/files/origin.pem` and `origin.key` with a real certificate, such as a Cloudflare origin certificate, then run `ansible-vault encrypt roles/certs/files/origin.*`. Commit the encrypted certificate and `vault.yml` in your own copy. `vault-pass.txt` is gitignored and must never be committed. Losing it means nothing in the repository decrypts.

**Deploy.** Run `make deploy`, which is `ansible-playbook playbooks/site.yml`. `ansible.cfg` already points at the inventory and the vault password file. A single role deploys on its own through its tag:

```bash
ansible-playbook playbooks/site.yml --tags proxy
```

**Lint.** `make lint` runs `ansible-lint` and a playbook syntax check.

## Testing

`make test` runs `tests/e2e.sh`, which boots a fresh Debian 13 cloud image under QEMU with the Kernel-based Virtual Machine (KVM) as an ordinary user. The virtual machine (VM) uses QEMU's user-mode networking, with its ports forwarded to `127.0.0.1` only. The script deploys twice and checks that:

- the second run changes nothing;
- the site answers 200 and a missing page answers 404;
- `www` and plain HTTP both redirect;
- Gitea answers through nginx, with registration disabled;
- git over SSH answers with a banner, and the admin user can log in;
- a CI job pushed to a new repository completes successfully on the runner.

It needs `qemu-system-x86_64`, `qemu-img`, `genisoimage` and access to `/dev/kvm`. `KEEP_VM=1 make test` leaves the VM running afterwards. A full local run of `make test` took 129 seconds, most of it downloading packages and images onto the fresh VM. The same test runs in GitHub Actions through `.github/workflows/e2e.yml`, and `.github/workflows/lint.yml` runs the lint.

## What is left out

A firewall, SSH hardening, a non-root deploy user, backups, monitoring and Let's Encrypt automation are all absent on purpose. Each is something to add yourself once the basics work.

The runner mounts the Docker socket, so any workflow can act as root on the server. Keep the Gitea instance to people you trust.

The example stops at the point where a server serves a site and builds its own code, and everything past that is a decision about your own server.
