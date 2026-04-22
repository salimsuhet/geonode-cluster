# GeoNode 5.0.2 — Cluster GeoServer + HAProxy

Repositório de infraestrutura para deploy automatizado do **GeoNode 5.0.2** com cluster **GeoServer 2.27.4** e balanceamento de carga via **HAProxy + Keepalived**.

## Arquitetura

```
                        ┌─────────────────────────────────────────────┐
                        │           VIP Keepalived (HAPROXY)           │
                        │           192.168.56.50 (dev)                │
                        └─────────────┬───────────────────────────────┘
                                      │
              ┌───────────────────────┴───────────────────────┐
              │                                               │
     ┌────────▼────────┐                           ┌─────────▼───────┐
     │   HAProxy #1    │  ◄─── Keepalived ───►     │   HAProxy #2    │
     │ 192.168.56.40   │       VRRP Sync            │ 192.168.56.41   │
     └────────┬────────┘                           └────────┬────────┘
              │                                             │
              └───────────────────┬─────────────────────────┘
                                  │
              ┌───────────────────┼──────────────────────────────┐
              │                   │                              │
   ┌──────────▼──────────┐  ┌─────▼──────────────┐  ┌──────────▼──────────┐
   │  GeoServer WRITE    │  │  GeoServer READ #1  │  │  GeoServer READ #2  │
   │  192.168.56.30      │  │  192.168.56.31      │  │  192.168.56.32      │
   │  (master/JMS)       │  │  (worker/JMS)       │  │  (worker/JMS)       │
   └──────────┬──────────┘  └─────────────────────┘  └─────────────────────┘
              │ JMS Cluster Sync ──────────────────────────────────────▲──▲
              │
   ┌──────────▼──────────┐       ┌────────────────────┐
   │     GeoNode App     │       │  PostgreSQL/PostGIS │
   │  192.168.56.20      │◄─────►│  192.168.56.10     │
   └─────────────────────┘       └────────────────────┘
```

### Componentes

#### VMs do cluster

| VM | IP (Vagrant) | Papel |
|---|---|---|
| `db` | 192.168.56.10 | PostgreSQL 15 + PostGIS 3 |
| `geonode` | 192.168.56.20 | GeoNode 5.0.2 (Django + Celery) |
| `geoserver-write` | 192.168.56.30 | GeoServer 2.27.4 — Master (escrita + admin) |
| `geoserver-read-1` | 192.168.56.31 | GeoServer 2.27.4 — Worker (leitura) |
| `geoserver-read-2` | 192.168.56.32 | GeoServer 2.27.4 — Worker (leitura) |
| `haproxy-1` | 192.168.56.40 | HAProxy + Keepalived (MASTER) |
| `haproxy-2` | 192.168.56.41 | HAProxy + Keepalived (BACKUP) |

**VIP Keepalived (dev):** `192.168.56.50`

#### Ansible — estrutura em camadas

| Camada | Arquivo | Função |
|---|---|---|
| Defaults globais | `group_vars/all.yml` | Todas as variáveis lidas via `lookup('env', ...)` — se existir no `.env` usa o valor; caso contrário aplica o default definido no próprio arquivo |
| GeoServer Master | `group_vars/geoserver_write.yml` | Papel `write`: exporta NFS, sobe ActiveMQ (broker JMS), control-flow restritivo para operações de escrita |
| GeoServer Workers | `group_vars/geoserver_read.yml` | Papel `read`: monta NFS do master, modo readonly no cluster JMS, control-flow permissivo para requisições de leitura |
| Inventário dev | `inventories/vagrant/` | Autenticação com a chave insecure padrão do Vagrant, `deploy_env: vagrant` |
| Inventário produção | `inventories/production/` | Autenticação com chave SSH própria, VIP de produção separado (`HAPROXY_VIP_PROD`) |

---

## Pré-requisitos

```bash
# Desenvolvimento local (Vagrant)
vagrant >= 2.3
virtualbox >= 7.0   # ou libvirt
ansible >= 2.15

# Produção
ansible >= 2.15
python3-boto3       # se usar inventário dinâmico AWS/OpenStack
```

---

## Início Rápido — Desenvolvimento (Vagrant)

```bash
# 1. Clone o repositório
git clone https://github.com/seu-org/geonode-cluster.git
cd geonode-cluster

# 2. Copie e edite o arquivo de variáveis
cp envs/.env.example envs/.env
$EDITOR envs/.env

# 3. Suba as VMs com Vagrant
vagrant up

# 4. Execute o playbook completo
ansible-playbook -i ansible/inventories/vagrant/hosts.yml ansible/site.yml

# Ou suba apenas uma parte
ansible-playbook -i ansible/inventories/vagrant/hosts.yml ansible/site.yml --tags database
ansible-playbook -i ansible/inventories/vagrant/hosts.yml ansible/site.yml --tags geoserver
```

---

## Deploy em Produção (VMs já provisionadas)

```bash
# 1. Copie e edite o inventário de produção
cp ansible/inventories/production/hosts.yml.example ansible/inventories/production/hosts.yml
$EDITOR ansible/inventories/production/hosts.yml

# 2. Copie e edite as variáveis
cp envs/.env.example envs/.env.production
$EDITOR envs/.env.production

# 3. Execute
ansible-playbook \
  -i ansible/inventories/production/hosts.yml \
  --extra-vars "@envs/.env.production" \
  ansible/site.yml
```

---

## Estrutura do Repositório

```
geonode-cluster/
├── Vagrantfile                          # VMs locais (desenvolvimento)
├── envs/
│   └── .env.example                     # Todas as variáveis configuráveis
├── ansible/
│   ├── ansible.cfg                      # Configuração do Ansible
│   ├── site.yml                         # Playbook principal (orquestra tudo)
│   ├── inventories/
│   │   ├── vagrant/
│   │   │   ├── hosts.yml                # Inventário gerado para Vagrant
│   │   │   └── group_vars/all.yml       # Aponta para envs/.env
│   │   └── production/
│   │       ├── hosts.yml.example        # Template de inventário de produção
│   │       └── group_vars/all.yml
│   ├── group_vars/
│   │   ├── all.yml                      # Variáveis globais + defaults
│   │   ├── geoserver.yml                # Vars do cluster GeoServer
│   │   ├── geoserver_write.yml          # Vars específicas do master
│   │   ├── geoserver_read.yml           # Vars específicas dos workers
│   │   └── haproxy.yml                  # Vars do HAProxy/Keepalived
│   ├── playbooks/
│   │   ├── database.yml
│   │   ├── geonode.yml
│   │   ├── geoserver.yml
│   │   └── haproxy.yml
│   └── roles/
│       ├── common/                      # Base: packages, users, sysctl
│       ├── docker/                      # Docker Engine + Compose
│       ├── database/                    # PostgreSQL + PostGIS
│       ├── nfs_server/                  # NFS para datadir compartilhado
│       ├── nfs_client/                  # Montagem NFS nos workers
│       ├── geoserver/                   # GeoServer (master e workers)
│       ├── geonode/                     # GeoNode app
│       ├── haproxy/                     # HAProxy
│       └── keepalived/                  # Keepalived VRRP
```

---

## Roteamento HAProxy

| Tráfego | Backend |
|---|---|
| `POST /geoserver/*` | `geoserver_write` |
| `GET /geoserver/web/*` | `geoserver_write` (admin sempre no master) |
| `GET /geoserver/*` | `geoserver_read` (round-robin) |
| `/*` (GeoNode) | `geonode_app` |

---

## Tags Ansible Disponíveis

```bash
--tags common        # Setup base de todas as VMs
--tags docker        # Instalação do Docker
--tags database      # PostgreSQL + PostGIS
--tags nfs           # Servidor e clientes NFS
--tags geoserver     # Todos os nós GeoServer
--tags geonode       # Aplicação GeoNode
--tags haproxy       # HAProxy
--tags keepalived    # Keepalived / VIP
--tags config        # Apenas reaplica configurações (sem reinstalar)
```
