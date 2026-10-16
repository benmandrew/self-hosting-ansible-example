# Setup

## Requirements

The tested target is Debian 13. The `docker` role picks Docker's repository for Debian or Ubuntu from `ansible_facts.distribution`, and other distributions are untested. The machine running Ansible (the *controller*) needs `ansible-core` and the `community.docker` collection, which `make install-deps` installs from `requirements.yml`.

## Domain and server

`group_vars/all/main.yml` holds `domain` and the pinned image versions. Gitea is served at `git.<domain>`, and `www` redirects to the apex. `inventory.yml` holds the server's Internet Protocol (IP) address, shipped as the placeholder `203.0.113.10`. Git over Secure Shell (SSH) listens on port 2222, since the server's own `sshd` keeps port 22.

## Secrets

`make bootstrap` runs `scripts/bootstrap.sh`, which writes three things:

- a random `vault-pass.txt`, readable only by its owner;
- a self-signed certificate in `roles/certs/files/origin.pem` and `origin.key`, valid for the domain and `*.domain`, vault-encrypted;
- an encrypted `group_vars/all/vault.yml` holding the Gitea admin password and the runner token.

The script prints the admin password, and `ansible-vault view group_vars/all/vault.yml` shows it again later. It skips any file that already exists, so re-running it is safe. The repository ships none of these files.

## A real certificate

The self-signed certificate is a placeholder. Replace `roles/certs/files/origin.pem` and `origin.key` with a real one, such as a Cloudflare origin certificate, before pointing DNS at the server. Then encrypt both:

```bash
ansible-vault encrypt roles/certs/files/origin.*
```

This repository gitignores the certificate and `vault.yml`, so its own test secrets never reach it. In your own copy, delete those two lines from `.gitignore` and commit the encrypted files.

## vault-pass.txt

`vault-pass.txt` is gitignored and must never be committed. `ansible.cfg` already points at it and at the inventory, so `make deploy` needs no flags. Losing it means nothing in the repository decrypts, so keep a copy somewhere safe.

## Partial deploys

`make deploy` runs `ansible-playbook playbooks/site.yml`. Each role carries a tag of its own name (`docker`, `certs`, `proxy`, `gitea`), so a single role deploys alone:

```bash
ansible-playbook playbooks/site.yml --tags proxy
```

## Lint

`make lint` runs `ansible-lint` and a playbook syntax check. `.github/workflows/lint.yml` runs the same target on every push and pull request, after generating throwaway secrets with `bootstrap.sh`.
