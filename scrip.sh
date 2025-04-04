#!/bin/bash

# Script para configurar site da Estação do Luena na porta 333
# Uso: chmod +x setup-estacao-luena.sh && sudo ./setup-estacao-luena.sh

# Cores para saída
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${YELLOW}=== Configuração do Site Estação do Luena na porta 333 ===${NC}"

# Verificar se está rodando como root
if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}Este script precisa ser executado como root (sudo).${NC}"
  exit 1
fi

# Detectar o sistema de gerenciamento de pacotes
if command -v apt &> /dev/null; then
    PKG_MANAGER="apt"
    echo -e "${GREEN}Sistema baseado em Debian/Ubuntu detectado.${NC}"
elif command -v yum &> /dev/null; then
    PKG_MANAGER="yum"
    echo -e "${GREEN}Sistema baseado em CentOS/RHEL detectado.${NC}"
else
    echo -e "${RED}Sistema não suportado. Por favor, use Ubuntu, Debian ou CentOS.${NC}"
    exit 1
fi

# Perguntar qual servidor web usar
echo -e "${YELLOW}Qual servidor web você deseja usar?${NC}"
echo "1) Apache"
echo "2) Nginx"
read -p "Escolha (1 ou 2): " WEB_SERVER_CHOICE

case $WEB_SERVER_CHOICE in
    1)
        WEB_SERVER="apache"
        echo -e "${GREEN}Apache selecionado.${NC}"
        ;;
    2)
        WEB_SERVER="nginx"
        echo -e "${GREEN}Nginx selecionado.${NC}"
        ;;
    *)
        echo -e "${RED}Opção inválida. Usando Apache como padrão.${NC}"
        WEB_SERVER="apache"
        ;;
esac

# Atualizar o sistema
echo -e "${YELLOW}Atualizando o sistema...${NC}"
if [ "$PKG_MANAGER" = "apt" ]; then
    apt update && apt upgrade -y
else
    yum update -y
fi

# Instalação do servidor web
echo -e "${YELLOW}Instalando o servidor web ${WEB_SERVER}...${NC}"
if [ "$WEB_SERVER" = "apache" ]; then
    if [ "$PKG_MANAGER" = "apt" ]; then
        apt install -y apache2
        systemctl enable apache2
        systemctl start apache2
    else
        yum install -y httpd
        systemctl enable httpd
        systemctl start httpd
    fi
else
    if [ "$PKG_MANAGER" = "apt" ]; then
        apt install -y nginx
        systemctl enable nginx
        systemctl start nginx
    else
        yum install -y nginx
        systemctl enable nginx
        systemctl start nginx
    fi
fi

# Criar diretório para o site
echo -e "${YELLOW}Criando diretório para o site...${NC}"
mkdir -p /var/www/estacao-luena
chmod -R 755 /var/www/estacao-luena

# Definir o diretório de destino
echo -e "${YELLOW}Onde estão os arquivos do site no seu sistema atual?${NC}"
echo "Pressione Enter para usar o diretório atual (.) ou digite o caminho:"
read SITE_FILES_DIR
SITE_FILES_DIR=${SITE_FILES_DIR:-"."}

if [ ! -d "$SITE_FILES_DIR" ]; then
    echo -e "${RED}Diretório $SITE_FILES_DIR não existe!${NC}"
    exit 1
fi

# Copiar os arquivos do site
echo -e "${YELLOW}Copiando arquivos do site...${NC}"
cp -r "$SITE_FILES_DIR"/* /var/www/estacao-luena/

# Criar diretórios adicionais necessários
mkdir -p /var/www/estacao-luena/sound

# Configurar o servidor web
echo -e "${YELLOW}Configurando o servidor web para a porta 333...${NC}"
if [ "$WEB_SERVER" = "apache" ]; then
    # Configurar Apache
    if [ "$PKG_MANAGER" = "apt" ]; then
        CONFIG_FILE="/etc/apache2/sites-available/estacao-luena.conf"
        PORTS_FILE="/etc/apache2/ports.conf"
    else
        CONFIG_FILE="/etc/httpd/conf.d/estacao-luena.conf"
        PORTS_FILE="/etc/httpd/conf/httpd.conf"
    fi
    
    # Adicionar Listen 333 ao arquivo de portas
    if ! grep -q "Listen 333" "$PORTS_FILE"; then
        echo "Listen 333" >> "$PORTS_FILE"
    fi
    
    # Criar configuração do site
    cat > "$CONFIG_FILE" << EOF
<VirtualHost *:333>
    ServerAdmin webmaster@localhost
    DocumentRoot /var/www/estacao-luena
    ErrorLog \${APACHE_LOG_DIR}/error.log
    CustomLog \${APACHE_LOG_DIR}/access.log combined
    
    <Directory /var/www/estacao-luena>
        Options Indexes FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>
</VirtualHost>
EOF
    
    # Ativar o site (apenas para sistemas Debian/Ubuntu)
    if [ "$PKG_MANAGER" = "apt" ]; then
        a2ensite estacao-luena.conf
    fi
    
    # Reiniciar Apache
    if [ "$PKG_MANAGER" = "apt" ]; then
        systemctl restart apache2
    else
        systemctl restart httpd
    fi
    
else
    # Configurar Nginx
    CONFIG_FILE="/etc/nginx/sites-available/estacao-luena"
    
    # Criar configuração do site
    cat > "$CONFIG_FILE" << EOF
server {
    listen 333;
    server_name _;
    
    root /var/www/estacao-luena;
    index index.html;
    
    location / {
        try_files \$uri \$uri/ =404;
    }
}
EOF
    
    # Criar link simbólico para ativar o site
    if [ "$PKG_MANAGER" = "apt" ]; then
        ln -sf "$CONFIG_FILE" /etc/nginx/sites-enabled/
    else
        ln -sf "$CONFIG_FILE" /etc/nginx/conf.d/
    fi
    
    # Verificar configuração e reiniciar Nginx
    nginx -t
    systemctl restart nginx
fi

# Configurar permissões
echo -e "${YELLOW}Configurando permissões...${NC}"
if [ "$WEB_SERVER" = "apache" ]; then
    if [ "$PKG_MANAGER" = "apt" ]; then
        chown -R www-data:www-data /var/www/estacao-luena
    else
        chown -R apache:apache /var/www/estacao-luena
    fi
else
    if [ "$PKG_MANAGER" = "apt" ]; then
        chown -R www-data:www-data /var/www/estacao-luena
    else
        chown -R nginx:nginx /var/www/estacao-luena
    fi
fi

# Configurar firewall
echo -e "${YELLOW}Configurando firewall...${NC}"
if command -v ufw &> /dev/null; then
    ufw allow 333/tcp
    echo -e "${GREEN}Porta 333 aberta no UFW.${NC}"
elif command -v firewall-cmd &> /dev/null; then
    firewall-cmd --permanent --add-port=333/tcp
    firewall-cmd --reload
    echo -e "${GREEN}Porta 333 aberta no firewalld.${NC}"
else
    echo -e "${YELLOW}Firewall não detectado. Verifique manualmente se a porta 333 está aberta.${NC}"
fi

# Verificar se arquivos necessários existem
echo -e "${YELLOW}Verificando arquivos necessários...${NC}"
MISSING_FILES=0

if [ ! -f "/var/www/estacao-luena/Imagens/favicon.ico" ]; then
    echo -e "${YELLOW}Aviso: favicon.ico não encontrado. Você deve adicioná-lo em /var/www/estacao-luena/Imagens/${NC}"
    MISSING_FILES=1
fi

if [ ! -f "/var/www/estacao-luena/Imagens/apple-touch-icon.png" ]; then
    echo -e "${YELLOW}Aviso: apple-touch-icon.png não encontrado. Você deve adicioná-lo em /var/www/estacao-luena/Imagens/${NC}"
    MISSING_FILES=1
fi

if [ ! -f "/var/www/estacao-luena/Imagens/mapa-luena.jpg" ]; then
    echo -e "${YELLOW}Aviso: mapa-luena.jpg não encontrado. Você deve adicioná-lo em /var/www/estacao-luena/Imagens/${NC}"
    MISSING_FILES=1
fi

if [ ! -f "/var/www/estacao-luena/sound/angola-ambient.mp3" ]; then
    echo -e "${YELLOW}Aviso: Sound/angola-ambient.mp3 não encontrado. Você deve adicioná-lo em /var/www/estacao-luena/sound/${NC}"
    MISSING_FILES=1
fi

# Obter IP do servidor
SERVER_IP=$(hostname -I | awk '{print $1}')

# Mensagem final
echo -e "\n${GREEN}=== Configuração concluída com sucesso! ===${NC}"
echo -e "${GREEN}Seu site está rodando na porta 333.${NC}"
echo -e "${GREEN}Acesse: http://$SERVER_IP:333${NC}"

if [ $MISSING_FILES -eq 1 ]; then
    echo -e "\n${YELLOW}IMPORTANTE: Alguns arquivos estão faltando. Verifique os avisos acima e adicione os arquivos necessários.${NC}"
fi

echo -e "\n${GREEN}Para atualizar o site no futuro, basta copiar os novos arquivos para a pasta /var/www/estacao-luena/${NC}"