# =============================================================================
# Makefile — GeoNode Cluster
# Atalhos para as operações mais comuns
# =============================================================================

SHELL := /bin/bash
.DEFAULT_GOAL := help

ENV_FILE        ?= $(CURDIR)/envs/.env
VARS_FILE       := /tmp/ansible_vars.yml
VAGRANT_INV     := $(CURDIR)/ansible/inventories/vagrant/hosts.yml
PRODUCTION_INV  := $(CURDIR)/ansible/inventories/production/hosts.yml
ANSIBLE_EXTRA   := --extra-vars "@$(VARS_FILE)"

# Detecta inventário de acordo com DEPLOY_MODE no .env
ifneq (,$(wildcard $(ENV_FILE)))
  DEPLOY_MODE := $(shell grep -E '^DEPLOY_MODE=' $(ENV_FILE) | cut -d= -f2 | tr -d ' ')
endif
DEPLOY_MODE ?= vagrant

ifeq ($(DEPLOY_MODE),vagrant)
  INVENTORY := $(VAGRANT_INV)
else
  INVENTORY := $(PRODUCTION_INV)
endif

ANSIBLE := ansible-playbook -i $(INVENTORY) $(ANSIBLE_EXTRA)

# Converte .env (CHAVE=VALOR) → YAML para o Ansible
$(VARS_FILE): $(ENV_FILE)
	@grep -v "^#" $(ENV_FILE) | grep -v "^$$" | \
	  sed 's/^\([^=]*\)=\(.*\)$$/\1: "\2"/' > $(VARS_FILE)

# =============================================================================
.PHONY: help
help: ## Exibe esta ajuda
	@awk 'BEGIN {FS = ":.*##"; printf "\n\033[1mGeoNode Cluster — Comandos disponíveis\033[0m\n\n"} \
	  /^[a-zA-Z_-]+:.*?##/ { printf "  \033[36m%-28s\033[0m %s\n", $$1, $$2 }' $(MAKEFILE_LIST)
	@echo ""

# =============================================================================
# Ambiente
# =============================================================================
.PHONY: env
env: ## Copia .env.example → envs/.env (apenas se não existir)
	@[ -f $(ENV_FILE) ] && echo "$(ENV_FILE) já existe." || \
	  (cp envs/.env.example $(ENV_FILE) && echo "✔ $(ENV_FILE) criado. Edite antes de continuar.")

.PHONY: deps
deps: ## Instala dependências Ansible (collections) e gem dotenv
	@echo "→ Instalando Ansible collections..."
	ansible-galaxy collection install -r ansible/requirements.yml
	@echo "→ Instalando gem dotenv (para Vagrantfile)..."
	gem install dotenv 2>/dev/null || true
	@echo "✔ Dependências instaladas."

# =============================================================================
# Vagrant (desenvolvimento)
# =============================================================================
.PHONY: vagrant-up
vagrant-up: env ## Sobe todas as VMs Vagrant
	vagrant up

.PHONY: vagrant-up-db
vagrant-up-db: ## Sobe apenas a VM de banco
	vagrant up db

.PHONY: vagrant-up-geoserver
vagrant-up-geoserver: ## Sobe VMs GeoServer (write + reads)
	vagrant up geoserver-write geoserver-read-1 geoserver-read-2

.PHONY: vagrant-halt
vagrant-halt: ## Para todas as VMs Vagrant
	vagrant halt

.PHONY: vagrant-destroy
vagrant-destroy: ## Destroi todas as VMs Vagrant (irreversível!)
	vagrant destroy -f

.PHONY: vagrant-status
vagrant-status: ## Status das VMs Vagrant
	vagrant status

.PHONY: vagrant-ssh
vagrant-ssh: ## SSH na VM (uso: make vagrant-ssh VM=geonode)
	vagrant ssh $(VM)

# =============================================================================
# Deploy completo
# =============================================================================
.PHONY: deploy
deploy: $(VARS_FILE) ## Deploy completo do cluster (all playbooks)
	$(ANSIBLE) $(CURDIR)/ansible/site.yml

.PHONY: deploy-check
deploy-check: $(VARS_FILE) ## Dry-run do deploy completo
	$(ANSIBLE) $(CURDIR)/ansible/site.yml --check --diff

# =============================================================================
# Deploy por componente
# =============================================================================
.PHONY: deploy-common
deploy-common: $(VARS_FILE) ## Setup base em todas as VMs
	$(ANSIBLE) $(CURDIR)/ansible/site.yml --tags common

.PHONY: deploy-docker
deploy-docker: $(VARS_FILE) ## Instala Docker em todos os nós
	$(ANSIBLE) $(CURDIR)/ansible/site.yml --tags docker

.PHONY: deploy-db
deploy-db: $(VARS_FILE) ## Provisiona PostgreSQL + PostGIS
	$(ANSIBLE) $(CURDIR)/ansible/site.yml --tags database

.PHONY: deploy-nfs
deploy-nfs: $(VARS_FILE) ## Configura NFS server (write) e clientes (reads)
	$(ANSIBLE) $(CURDIR)/ansible/site.yml --tags nfs

.PHONY: deploy-geoserver
deploy-geoserver: $(VARS_FILE) ## Deploy de todos os nós GeoServer
	$(ANSIBLE) $(CURDIR)/ansible/site.yml --tags geoserver

.PHONY: deploy-geoserver-write
deploy-geoserver-write: $(VARS_FILE) ## Deploy apenas do nó write
	$(ANSIBLE) $(CURDIR)/ansible/site.yml --tags geoserver_write

.PHONY: deploy-geoserver-read
deploy-geoserver-read: $(VARS_FILE) ## Deploy dos workers de leitura
	$(ANSIBLE) $(CURDIR)/ansible/site.yml --tags geoserver_read

.PHONY: deploy-geonode
deploy-geonode: $(VARS_FILE) ## Deploy da aplicação GeoNode
	$(ANSIBLE) $(CURDIR)/ansible/site.yml --tags geonode

.PHONY: deploy-haproxy
deploy-haproxy: $(VARS_FILE) ## Deploy do HAProxy
	$(ANSIBLE) $(CURDIR)/ansible/site.yml --tags haproxy

.PHONY: deploy-keepalived
deploy-keepalived: $(VARS_FILE) ## Deploy do Keepalived (VIP)
	$(ANSIBLE) $(CURDIR)/ansible/site.yml --tags keepalived

# =============================================================================
# Reconfiguração (sem reinstalar serviços)
# =============================================================================
.PHONY: reconfigure
reconfigure: $(VARS_FILE) ## Reaplica apenas arquivos de configuração
	$(ANSIBLE) $(CURDIR)/ansible/site.yml --tags config

.PHONY: reconfigure-haproxy
reconfigure-haproxy: $(VARS_FILE) ## Reaplica config do HAProxy
	$(ANSIBLE) $(CURDIR)/ansible/site.yml --tags haproxy,config

.PHONY: reconfigure-geoserver
reconfigure-geoserver: $(VARS_FILE) ## Reaplica config de todos os GeoServers
	$(ANSIBLE) $(CURDIR)/ansible/site.yml --tags geoserver,config

# =============================================================================
# Operações em produção
# =============================================================================
.PHONY: ping
ping: $(VARS_FILE) ## Testa conectividade Ansible com todos os hosts
	ansible -i $(INVENTORY) $(ANSIBLE_EXTRA) all -m ping

.PHONY: facts
facts: $(VARS_FILE) ## Coleta facts de todos os hosts
	ansible -i $(INVENTORY) $(ANSIBLE_EXTRA) all -m gather_facts --tree /tmp/ansible-facts

.PHONY: check-haproxy
check-haproxy: ## Verifica saúde do HAProxy via stats API
	@for ip in $(shell grep -E 'ansible_host:' $(INVENTORY) | grep haproxy | awk '{print $$2}'); do \
	  echo "→ HAProxy $$ip:$(shell grep HAPROXY_STATS_PORT $(ENV_FILE) | cut -d= -f2)/stats"; \
	  curl -sf -u "$(shell grep HAPROXY_STATS_USER $(ENV_FILE) | cut -d= -f2):$(shell grep HAPROXY_STATS_PASSWORD $(ENV_FILE) | cut -d= -f2)" \
	    "http://$$ip:$(shell grep HAPROXY_STATS_PORT $(ENV_FILE) | cut -d= -f2)/stats" | grep -c "pxname" || echo "  ✗ Falhou"; \
	done

.PHONY: check-geoserver
check-geoserver: ## Verifica saúde de cada nó GeoServer
	@echo "→ GeoServer Write ($(shell grep IP_GEOSERVER_WRITE $(ENV_FILE) | cut -d= -f2))"
	@curl -sf "http://$(shell grep IP_GEOSERVER_WRITE $(ENV_FILE) | cut -d= -f2):$(shell grep GEOSERVER_PORT $(ENV_FILE) | cut -d= -f2)/geoserver/web/" && echo "  ✔ OK" || echo "  ✗ Falhou"
	@echo "→ GeoServer Read-1 ($(shell grep IP_GEOSERVER_READ_1 $(ENV_FILE) | cut -d= -f2))"
	@curl -sf "http://$(shell grep IP_GEOSERVER_READ_1 $(ENV_FILE) | cut -d= -f2):$(shell grep GEOSERVER_PORT $(ENV_FILE) | cut -d= -f2)/geoserver/web/" && echo "  ✔ OK" || echo "  ✗ Falhou"
	@echo "→ GeoServer Read-2 ($(shell grep IP_GEOSERVER_READ_2 $(ENV_FILE) | cut -d= -f2))"
	@curl -sf "http://$(shell grep IP_GEOSERVER_READ_2 $(ENV_FILE) | cut -d= -f2):$(shell grep GEOSERVER_PORT $(ENV_FILE) | cut -d= -f2)/geoserver/web/" && echo "  ✔ OK" || echo "  ✗ Falhou"

.PHONY: check-vip
check-vip: ## Verifica se o VIP Keepalived está respondendo
	@VIP=$(shell grep HAPROXY_VIP $(ENV_FILE) | grep -v PROD | cut -d= -f2); \
	  echo "→ VIP $$VIP:80"; \
	  curl -sf --max-time 5 "http://$$VIP/" -o /dev/null && echo "  ✔ OK" || echo "  ✗ VIP inacessível"

# =============================================================================
# Logs
# =============================================================================
.PHONY: logs-geonode
logs-geonode: $(VARS_FILE) ## Exibe logs do GeoNode (tail -f)
	ansible -i $(INVENTORY) $(ANSIBLE_EXTRA) geonode -m command \
	  -a "docker compose -f /opt/geonode/docker-compose.yml logs -f --tail=100"

.PHONY: logs-geoserver-write
logs-geoserver-write: $(VARS_FILE) ## Exibe logs do GeoServer Write
	ansible -i $(INVENTORY) $(ANSIBLE_EXTRA) geoserver_write -m command \
	  -a "docker compose -f /opt/geoserver/docker-compose.yml logs -f --tail=100"

.PHONY: logs-haproxy
logs-haproxy: $(VARS_FILE) ## Exibe logs do HAProxy
	ansible -i $(INVENTORY) $(ANSIBLE_EXTRA) haproxy -m command \
	  -a "journalctl -u haproxy -f --lines=50"

# =============================================================================
# Utilitários
# =============================================================================
.PHONY: lint
lint: ## Valida playbooks Ansible (ansible-lint)
	ansible-lint $(CURDIR)/ansible/site.yml || true

.PHONY: graph
graph: $(VARS_FILE) ## Gera grafo de dependências do playbook
	ansible-playbook -i $(INVENTORY) $(CURDIR)/ansible/site.yml --list-tasks

.PHONY: inventory
inventory: ## Exibe inventário atual formatado
	ansible-inventory -i $(INVENTORY) --graph

.PHONY: clean
clean: ## Remove arquivos temporários e caches
	find . -name "*.retry" -delete
	find . -name "__pycache__" -type d -exec rm -rf {} + 2>/dev/null || true
	rm -rf /tmp/ansible-facts /tmp/ansible-ssh-*
	@echo "✔ Limpeza concluída."
