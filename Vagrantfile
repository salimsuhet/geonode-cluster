# frozen_string_literal: true

# =============================================================================
# Vagrantfile — GeoNode Cluster (Desenvolvimento Local)
# Lê variáveis do arquivo envs/.env automaticamente
# =============================================================================

require 'yaml'

# Carrega envs/.env com parser puro Ruby (sem dependência de gems)
def load_env_file(path)
  return unless File.exist?(path)
  File.foreach(path) do |line|
    line = line.strip
    next if line.empty? || line.start_with?('#')
    next unless line.include?('=')
    key, value = line.split('=', 2)
    key   = key.strip
    value = (value || '').strip
    value = value.gsub(/\A['"]|['"]\z/, '')
    ENV[key] ||= value
  end
end

env_file = File.join(File.dirname(__FILE__), 'envs', '.env')
load_env_file(env_file)

def env(key, default = nil)
  ENV.fetch(key, default)
end

BOX        = env('VAGRANT_BOX',            'ubuntu/jammy64')
NET_PREFIX = env('VAGRANT_NETWORK_PREFIX', '192.168.56')
VIP        = env('HAPROXY_VIP',            "#{NET_PREFIX}.50")

IP = {
  db:               env('IP_DB',               "#{NET_PREFIX}.10"),
  geonode:          env('IP_GEONODE',           "#{NET_PREFIX}.20"),
  geoserver_write:  env('IP_GEOSERVER_WRITE',   "#{NET_PREFIX}.30"),
  geoserver_read_1: env('IP_GEOSERVER_READ_1',  "#{NET_PREFIX}.31"),
  geoserver_read_2: env('IP_GEOSERVER_READ_2',  "#{NET_PREFIX}.32"),
  haproxy_1:        env('IP_HAPROXY_1',         "#{NET_PREFIX}.40"),
  haproxy_2:        env('IP_HAPROXY_2',         "#{NET_PREFIX}.41"),
}.freeze

RESOURCES = {
  db:              { cpu: env('VM_DB_CPU',        2).to_i, mem: env('VM_DB_MEM',        2048).to_i },
  geonode:         { cpu: env('VM_GEONODE_CPU',   2).to_i, mem: env('VM_GEONODE_MEM',   4096).to_i },
  geoserver_write: { cpu: env('VM_GEOSERVER_CPU', 4).to_i, mem: env('VM_GEOSERVER_MEM', 4096).to_i },
  geoserver_read:  { cpu: env('VM_GEOSERVER_CPU', 4).to_i, mem: env('VM_GEOSERVER_MEM', 4096).to_i },
  haproxy:         { cpu: env('VM_HAPROXY_CPU',   1).to_i, mem: env('VM_HAPROXY_MEM',    512).to_i },
}.freeze

# =============================================================================
Vagrant.configure('2') do |config|
  config.vm.box             = BOX
  config.vm.box_check_update = false

  # ── Correções para Windows + VirtualBox ────────────────────────────────────
  # Timeout ampliado: primeira importação da box no Windows pode demorar muito
  config.vm.boot_timeout = 600

  # Communicator explícito evita fallback silencioso no Windows
  config.vm.communicator = 'ssh'

  # Mantém chave insecure (padrão Vagrant) — facilita Ansible em dev
  config.ssh.insert_key = false

  # Desabilita atualização automática do vagrant-vbguest se o plugin existir
  config.vbguest.auto_update = false if Vagrant.has_plugin?('vagrant-vbguest')

  # ==========================================================================
  # Provisionamento base (roda em todas as VMs após o boot)
  # ==========================================================================
  config.vm.provision 'base', type: 'shell', inline: <<~SHELL
    set -e
    apt-get update -qq
    apt-get install -y -qq python3 python3-pip
    ln -sf /usr/bin/python3 /usr/bin/python 2>/dev/null || true
  SHELL

  # ==========================================================================
  # DB
  # ==========================================================================
  config.vm.define 'db' do |m|
    m.vm.hostname = 'db'
    m.vm.network 'private_network', ip: IP[:db]
    vm_provider(m, 'db', RESOURCES[:db])
    add_hosts(m, IP)
  end

  # ==========================================================================
  # GeoNode
  # ==========================================================================
  config.vm.define 'geonode' do |m|
    m.vm.hostname = 'geonode'
    m.vm.network 'private_network', ip: IP[:geonode]
    vm_provider(m, 'geonode', RESOURCES[:geonode])
    add_hosts(m, IP)
  end

  # ==========================================================================
  # GeoServer Write (Master)
  # ==========================================================================
  config.vm.define 'geoserver-write' do |m|
    m.vm.hostname = 'geoserver-write'
    m.vm.network 'private_network', ip: IP[:geoserver_write]
    vm_provider(m, 'geoserver-write', RESOURCES[:geoserver_write])
    add_hosts(m, IP)
    m.vm.provision 'nfs-export', type: 'shell', inline: <<~SHELL
      apt-get install -y -qq nfs-kernel-server
      mkdir -p /opt/geoserver_data
      chown -R nobody:nogroup /opt/geoserver_data
    SHELL
  end

  # ==========================================================================
  # GeoServer Read 1
  # ==========================================================================
  config.vm.define 'geoserver-read-1' do |m|
    m.vm.hostname = 'geoserver-read-1'
    m.vm.network 'private_network', ip: IP[:geoserver_read_1]
    vm_provider(m, 'geoserver-read-1', RESOURCES[:geoserver_read])
    add_hosts(m, IP)
  end

  # ==========================================================================
  # GeoServer Read 2
  # ==========================================================================
  config.vm.define 'geoserver-read-2' do |m|
    m.vm.hostname = 'geoserver-read-2'
    m.vm.network 'private_network', ip: IP[:geoserver_read_2]
    vm_provider(m, 'geoserver-read-2', RESOURCES[:geoserver_read])
    add_hosts(m, IP)
  end

  # ==========================================================================
  # HAProxy 1 (Keepalived MASTER)
  # ==========================================================================
  config.vm.define 'haproxy-1' do |m|
    m.vm.hostname = 'haproxy-1'
    m.vm.network 'private_network', ip: IP[:haproxy_1]
    m.vm.network 'private_network', ip: VIP, auto_config: false
    vm_provider(m, 'haproxy-1', RESOURCES[:haproxy])
    add_hosts(m, IP)
  end

  # ==========================================================================
  # HAProxy 2 (Keepalived BACKUP)
  # ==========================================================================
  config.vm.define 'haproxy-2' do |m|
    m.vm.hostname = 'haproxy-2'
    m.vm.network 'private_network', ip: IP[:haproxy_2]
    vm_provider(m, 'haproxy-2', RESOURCES[:haproxy])
    add_hosts(m, IP)
  end

end

# =============================================================================
# Helpers
# =============================================================================

def vm_provider(machine, name, res)
  machine.vm.provider 'virtualbox' do |vb|
    vb.name   = name
    vb.cpus   = res[:cpu]
    vb.memory = res[:mem]
    vb.gui    = false

    # Resolução DNS pelo host — necessário para apt funcionar no Windows
    vb.customize ['modifyvm', :id, '--natdnshostresolver1', 'on']
    vb.customize ['modifyvm', :id, '--natdnsproxy1',        'on']

    # Desabilita USB — causa travamento de boot no Windows + VirtualBox
    vb.customize ['modifyvm', :id, '--usb',     'off']
    vb.customize ['modifyvm', :id, '--usbehci', 'off']
    vb.customize ['modifyvm', :id, '--usbxhci', 'off']

    # Remove dispositivo de áudio (evita warnings e possível hang)
    vb.customize ['modifyvm', :id, '--audio', 'none']

    # Limita uso de CPU do host (evita que as VMs travem o Windows)
    vb.customize ['modifyvm', :id, '--cpuexecutioncap', '80']

    # Sincronização de relógio precisa (evita drift nas VMs)
    vb.customize ['guestproperty', 'set', :id,
                  '/VirtualBox/GuestAdd/VBoxService/--timesync-interval', '10000']
    vb.customize ['guestproperty', 'set', :id,
                  '/VirtualBox/GuestAdd/VBoxService/--timesync-min-adjust', '100']
  end

  # Suporte libvirt (Linux)
  machine.vm.provider 'libvirt' do |lv|
    lv.cpus   = res[:cpu]
    lv.memory = res[:mem]
  end
end

def add_hosts(machine, ips)
  hosts_entries = ips.map { |name, ip| "#{ip} #{name.to_s.tr('_', '-')}" }.join("\n")
  machine.vm.provision 'hosts', type: 'shell', run: 'always', inline: <<~SHELL
    grep -v "# geonode-cluster" /etc/hosts > /tmp/hosts_clean
    mv /tmp/hosts_clean /etc/hosts
    cat >> /etc/hosts << 'EOF'
#{hosts_entries}
    # geonode-cluster
EOF
  SHELL
end
