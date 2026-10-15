# Layout

The repository follows the structure of the [article](https://benmandrew.com/articles/self-hosting-website), so each of its sections maps onto files here.

| Article section | Files |
|---|---|
| Docker Compose | `roles/proxy/templates/docker-compose.yml.j2`, `roles/gitea/templates/docker-compose.yml.j2` |
| The nginx configuration | `roles/proxy/templates/conf.d/static.conf.j2`, `roles/proxy/templates/conf.d/gitea.conf.j2` |
| Cloudflare origin certificates | `roles/certs/` |
| Ansible | `playbooks/site.yml`, `inventory.yml`, `ansible.cfg`, `group_vars/all/main.yml` |
| Ansible Vault | `group_vars/all/vault.yml`, `vault-pass.txt` |
| Gitea and Act Runner | `roles/gitea/` |

The Domain Name System (DNS) A records are set in Cloudflare by hand, so nothing here covers them.

## Roles

`playbooks/site.yml` runs four roles over the host group `myhosts`, which holds one host, `droplet`, reached as root.

**docker.** Installs Docker Engine and the Compose plugin from Docker's apt repository, and creates the shared `proxy` network. This role goes beyond the article, and it lets the playbook run on a bare server.

**certs.** Copies the vault-encrypted `origin.pem` and `origin.key` onto the server.

**proxy.** Runs the nginx container `nginx-proxy` with `static.conf` and `gitea.conf`, and copies a placeholder site. `static.conf` redirects `www` to the apex and HTTP to HTTPS with a 301, and serves pages with `try_files $uri $uri.html $uri/ =404`.

**gitea.** Runs Gitea on *SQLite* beside `act_runner`. Ansible creates the admin user, so the web installer is skipped and public registration stays off. The runner registers itself through a token shared with Gitea in `GITEA_RUNNER_REGISTRATION_TOKEN`.

## Per-request upstream resolution

`gitea.conf` holds its upstream in a variable and points nginx at Docker's embedded DNS server, `127.0.0.11`. nginx therefore resolves `gitea` on each request rather than at startup. The proxy starts, and serves the static site, whether or not the Gitea container exists yet. Each role deploys independently of the others as a result.
