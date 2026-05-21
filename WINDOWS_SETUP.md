# Configuração do Ambiente de Desenvolvimento no Windows

Guia para configurar o WSL2, Vagrant e Ansible no Windows para utilizar os comandos `make` do repositório.

---

## Pré-requisitos

- Windows 10 (build 19041+) ou Windows 11
- Virtualização habilitada na BIOS

---

## 1. Instalar o WSL2 com Ubuntu

Abra o **PowerShell como Administrador** e execute:

```powershell
wsl --install
```

Reinicie o PC quando solicitado. Na primeira abertura do Ubuntu, crie seu usuário e senha.

---

## 2. Instalar o VirtualBox

Baixe e instale no Windows (não no WSL2):

👉 https://www.virtualbox.org/wiki/Downloads

Escolha a versão **Windows hosts**.

---

## 3. Instalar o Vagrant

Baixe e instale no Windows:

👉 https://developer.hashicorp.com/vagrant/downloads

Escolha **Windows AMD64**. Após instalar, verifique no PowerShell:

```powershell
where.exe vagrant
# C:\Program Files\Vagrant\bin\vagrant.exe
```

---

## 4. Configurar o WSL2

Abra o terminal Ubuntu e edite o `~/.bashrc`:

```bash
echo 'export VAGRANT_WSL_ENABLE_WINDOWS_ACCESS="1"' >> ~/.bashrc
echo 'export PATH="$PATH:/mnt/c/Program Files/Oracle/VirtualBox"' >> ~/.bashrc
echo 'export VAGRANT_WSL_WINDOWS_ACCESS_USER_HOME_PATH="/mnt/c/Users/SEU_USUARIO"' >> ~/.bashrc
source ~/.bashrc
```

> Substitua `SEU_USUARIO` pelo seu usuário do Windows.

---

## 5. Criar symlink do Vagrant no WSL2

Como o `make` roda em shell não-interativo, aliases não funcionam. A solução é criar um symlink:

```bash
sudo ln -s "/mnt/c/Program Files/Vagrant/bin/vagrant.exe" /usr/local/bin/vagrant
vagrant --version
```

---

## 6. Instalar Ansible e ferramentas no WSL2

```bash
# Atualiza pacotes
sudo apt update && sudo apt upgrade -y

# Dependências + Ansible via apt (fica em /usr/bin e funciona no make)
sudo apt install -y make ansible ansible-lint ruby-full

# gem dotenv (usado pelo Vagrantfile)
gem install dotenv

# Collections do projeto
ansible-galaxy collection install -r ansible/requirements.yml
```

---

## 7. Clonar o repositório no WSL2

```bash
cd ~
git clone https://github.com/salimsuhet/geonode-cluster.git
cd geonode-cluster
```

> Clonar dentro do WSL2 (`~/`) oferece melhor performance do que usar `/mnt/c/...`.

---

## Fluxo de Trabalho

Abra o Ubuntu pelo menu iniciar ou via PowerShell:

```powershell
wsl
```

Navegue até o repositório e use os comandos `make` normalmente:

```bash
cd ~/geonode-cluster

make env          # Cria o arquivo envs/.env
make vagrant-up   # Sobe todas as VMs
make deploy       # Deploy completo do cluster
make help         # Lista todos os comandos disponíveis
```

---

## Resumo das Ferramentas

| Ferramenta | Onde instalar | Motivo |
|---|---|---|
| WSL2 + Ubuntu | Windows (`wsl --install`) | Ansible não roda nativamente no Windows |
| VirtualBox | Windows (instalador) | Hypervisor para as VMs do Vagrant |
| Vagrant | Windows (instalador) | Precisa se comunicar diretamente com o VirtualBox |
| `make` | WSL2 (`apt install make`) | Executa os atalhos do Makefile |
| `ansible` + `ansible-lint` | WSL2 (`apt`) | Provisionamento das VMs (apt instala em `/usr/bin`, funciona no `make`) |
| `ruby` + `gem dotenv` | WSL2 (`apt`) | Leitura do `.env` pelo Vagrantfile |
| Symlink `vagrant` | WSL2 (`ln -s`) | Permite que o `make` encontre o executável |
