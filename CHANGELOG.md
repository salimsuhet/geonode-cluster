# Changelog

## [1.0.0] — 2026-04

### Adicionado
- Suporte a GeoNode 5.0.2 via Docker Compose
- Cluster GeoServer 2.27.4 com JMS (1 write + 2 read)
- NFS compartilhado para o data dir do GeoServer
- HAProxy com roteamento por método HTTP (write → master / GET → workers)
- Keepalived VRRP com VIP flutuante entre dois HAProxy
- Vagrantfile com leitura automática de `envs/.env`
- Inventários separados para Vagrant e produção
- `group_vars` com defaults carregados via `lookup('env', ...)`
- Makefile com atalhos para todas as operações
- Smoke tests automatizados via playbook Ansible
- Rolling restart sem downtime dos workers GeoServer
