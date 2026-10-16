# Layout

The repository follows the structure of the [article](https://benmandrew.com/articles/self-hosting-website), so each of its sections maps onto files here.

| Article section | Files |
|---|---|
| Containerised Services with Docker | `roles/proxy/templates/docker-compose.yml.j2`, `roles/gitea/templates/docker-compose.yml.j2` |
| Serving a Website with Nginx | `roles/proxy/templates/conf.d/static.conf.j2`, `roles/proxy/templates/conf.d/gitea.conf.j2` |
| Domains and DNS | `roles/certs/` |
| Repeatable Deployments with Ansible | `playbooks/site.yml`, `inventory.yml`, `ansible.cfg`, `group_vars/all/main.yml` |
| Storing Secrets | `group_vars/all/vault.yml`, `vault-pass.txt` |
| Gitea and CI/CD | `roles/gitea/` |

The Domain Name System (DNS) A records are set in Cloudflare by hand, so nothing here covers them.

## Differences from the article

The article's snippets come from a deployment built up by hand. This repository runs unattended on a fresh server, which accounts for most of the changes.

| Article | Here | Reason |
|---|---|---|
| Roles `certs`, `gitea`, `proxy` | `docker` first, then `certs`, `proxy`, `gitea` | The `docker` role installs Docker, so the playbook runs on a bare server. |
| `vars_files: group_vars/all.yml` | `group_vars/all/main.yml`, loaded automatically | Ansible reads `group_vars/` beside the inventory, so the playbook names no vars file. |
| `ansible_python_interpreter: /usr/bin/python3.12` | `interpreter_python = auto_silent` in `ansible.cfg` | That path exists on Ubuntu 24.04, and the tested target is Debian 13. |
| `--vault-pass-file vault-pass.txt` on the command line | `vault_password_file` in `ansible.cfg` | `make deploy` needs no flags. |
| Files under `/home/ben/` | `/opt/selfhost/`, set by `deployment_home` | No user account is assumed. |
| `benmandrew.com.pem` and `.key` | `origin.pem` and `origin.key` | The names do not depend on the domain. |
| `nginx:latest` | Pinned tags in `container_images` | Two deploys a week apart would otherwise run different images. |
| `files/docker-compose.yml`, `files/conf.d/` | `templates/*.j2` | The domain and paths come from variables. |
| `recreate: always` | `recreate: auto` | A second run changes nothing, which the end-to-end test checks. |
| A `post_tasks` completion message | Absent | The play recap already reports completion. |

## Roles

`playbooks/site.yml` runs four roles over the host group `myhosts`, which holds one host, `droplet`, reached as root.

**docker.** Installs Docker Engine and the Compose plugin from Docker's apt repository, and creates the shared `proxy` network. This role goes beyond the article, and it lets the playbook run on a bare server.

**certs.** Copies the vault-encrypted `origin.pem` and `origin.key` onto the server.

**proxy.** Runs the nginx container `nginx-proxy` with `static.conf` and `gitea.conf`, and copies a placeholder site. `static.conf` redirects `www` to the apex and HTTP to HTTPS with a 301, and serves pages with `try_files $uri $uri.html $uri/ =404`.

**gitea.** Runs Gitea on *SQLite* beside `act_runner`. Ansible creates the admin user, so the web installer is skipped and public registration stays off. The runner registers itself through a token shared with Gitea in `GITEA_RUNNER_REGISTRATION_TOKEN`.

## Per-request upstream resolution

`gitea.conf` holds its upstream in a variable and points nginx at Docker's embedded DNS server, `127.0.0.11`. nginx therefore resolves `gitea` on each request rather than at startup. The proxy starts, and serves the static site, whether or not the Gitea container exists yet. Each role deploys independently of the others as a result.
