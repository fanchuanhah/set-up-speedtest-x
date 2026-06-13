#!/bin/bash

# ============================================
# Speedtest-X 一键安装/卸载脚本 (Nginx + PHP-FPM)
# 用法: ./speedtest.sh          # 安装并启动
#       ./speedtest.sh uninstall # 完全卸载
# ============================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# ---------- 配置 ----------
PORT=33332
PROJECT_DIR="/www/wwwroot/speedtest"
LOG_FILE="/var/log/speedtest_access.log"

# ========== 端口占用检测函数 ==========
check_port() {
    local port=$1
    if command -v ss &>/dev/null; then
        if ss -tlnp | grep -q ":$port "; then
            return 0  # 端口被占用
        fi
    elif command -v netstat &>/dev/null; then
        if netstat -tlnp | grep -q ":$port "; then
            return 0  # 端口被占用
        fi
    else
        # 使用 lsof 作为备选
        if command -v lsof &>/dev/null; then
            if lsof -i :$port &>/dev/null; then
                return 0
            fi
        fi
    fi
    return 1  # 端口未被占用
}

# ========== 卸载函数 ==========
uninstall() {
    echo -e "${YELLOW}正在卸载 Speedtest-X...${NC}"

    # 停止服务
    echo -e "${YELLOW}停止相关服务...${NC}"
    if command -v rc-service &>/dev/null; then
        rc-service nginx stop 2>/dev/null || true
        rc-service php-fpm stop 2>/dev/null || true
        rc-service php-fpm82 stop 2>/dev/null || true
        rc-service php-fpm83 stop 2>/dev/null || true
    elif command -v systemctl &>/dev/null; then
        systemctl stop nginx 2>/dev/null || true
        systemctl stop php-fpm 2>/dev/null || true
        systemctl stop php*-fpm 2>/dev/null || true
    else
        service nginx stop 2>/dev/null || true
        service php-fpm stop 2>/dev/null || true
    fi

    # 删除自启动项
    echo -e "${YELLOW}删除自启动项...${NC}"
    if command -v rc-update &>/dev/null; then
        # Alpine OpenRC
        rc-update del nginx default 2>/dev/null || true
        rc-update del php-fpm default 2>/dev/null || true
        rc-update del php-fpm82 default 2>/dev/null || true
        rc-update del php-fpm83 default 2>/dev/null || true
    elif command -v systemctl &>/dev/null; then
        # Systemd
        systemctl disable nginx 2>/dev/null || true
        systemctl disable php-fpm 2>/dev/null || true
        systemctl disable php*-fpm 2>/dev/null || true
    elif command -v chkconfig &>/dev/null; then
        # CentOS 6
        chkconfig nginx off 2>/dev/null || true
        chkconfig php-fpm off 2>/dev/null || true
    elif command -v update-rc.d &>/dev/null; then
        # Debian/Ubuntu
        update-rc.d nginx remove 2>/dev/null || true
        update-rc.d php-fpm remove 2>/dev/null || true
        update-rc.d php*-fpm remove 2>/dev/null || true
    fi

    # 删除 Nginx 站点配置
    echo -e "${YELLOW}删除配置文件...${NC}"
    rm -f /etc/nginx/http.d/speedtest.conf 2>/dev/null
    rm -f /etc/nginx/conf.d/speedtest.conf 2>/dev/null
    rm -f /etc/nginx/sites-available/speedtest 2>/dev/null
    rm -f /etc/nginx/sites-enabled/speedtest 2>/dev/null

    # 重载 Nginx (如果还存在)
    if command -v nginx &>/dev/null; then
        if command -v rc-service &>/dev/null; then
            rc-service nginx reload 2>/dev/null || true
        elif command -v systemctl &>/dev/null; then
            systemctl reload nginx 2>/dev/null || true
        fi
    fi

    # 删除项目目录
    rm -rf "$PROJECT_DIR"

    # 询问是否卸载 Nginx + PHP
    read -p "是否同时卸载 Nginx 和 PHP？(y/N): " REMOVE_NGINX
    if [[ "$REMOVE_NGINX" =~ ^[Yy]$ ]]; then
        case $OS in
            alpine)
                apk del --purge nginx php php-fpm php-mbstring php-xml php-curl php-zip php-gd php-json php-openssl php-ctype 2>/dev/null
                ;;
            ubuntu|debian)
                apt-get purge -y nginx php-fpm php-cli php-mbstring php-xml php-curl php-zip php-gd php-ctype 2>/dev/null
                apt-get autoremove -y 2>/dev/null
                ;;
            centos|rhel|fedora|rocky|almalinux)
                if command -v dnf &>/dev/null; then
                    dnf remove -y nginx php-fpm php-cli php-mbstring php-xml php-curl php-zip php-gd 2>/dev/null
                else
                    yum remove -y nginx php-fpm php-cli php-mbstring php-xml php-curl php-zip php-gd 2>/dev/null
                fi
                ;;
        esac
        echo -e "${GREEN}Nginx 和 PHP 已卸载${NC}"
    fi

    # 清理日志文件
    rm -f /var/log/nginx/speedtest_access.log 2>/dev/null
    rm -f /var/log/nginx/speedtest_error.log 2>/dev/null

    echo -e "${GREEN}卸载完成！${NC}"
    exit 0
}

# ========== 检测系统 ==========
detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
    elif [ -f /etc/alpine-release ]; then
        OS="alpine"
    else
        echo -e "${RED}无法检测操作系统${NC}"
        exit 1
    fi
}

detect_os
echo -e "${GREEN}操作系统: $OS${NC}"

# ========== 如果执行卸载 ==========
[ "$1" = "uninstall" ] && uninstall

# ========== 端口检测 ==========
echo -e "${YELLOW}检测端口 $PORT 占用情况...${NC}"
if check_port $PORT; then
    echo -e "${RED}端口 $PORT 已被占用！${NC}"
    echo -e "${YELLOW}占用详情:${NC}"
    if command -v ss &>/dev/null; then
        ss -tlnp | grep ":$PORT "
    elif command -v netstat &>/dev/null; then
        netstat -tlnp | grep ":$PORT "
    elif command -v lsof &>/dev/null; then
        lsof -i :$PORT
    fi
    
    read -p "是否终止占用端口的进程并继续？(y/N): " KILL_PROCESS
    if [[ "$KILL_PROCESS" =~ ^[Yy]$ ]]; then
        # 获取占用端口的进程PID
        if command -v ss &>/dev/null; then
            PID=$(ss -tlnp | grep ":$PORT " | grep -oP 'pid=\K[0-9]+' | head -1)
        elif command -v netstat &>/dev/null; then
            PID=$(netstat -tlnp | grep ":$PORT " | awk '{print $7}' | cut -d'/' -f1)
        elif command -v lsof &>/dev/null; then
            PID=$(lsof -ti :$PORT)
        fi
        
        if [ -n "$PID" ]; then
            echo -e "${YELLOW}终止进程 PID: $PID${NC}"
            kill -9 $PID 2>/dev/null
            sleep 1
            if check_port $PORT; then
                echo -e "${RED}端口 $PORT 仍然被占用，请手动处理${NC}"
                exit 1
            else
                echo -e "${GREEN}端口 $PORT 已释放${NC}"
            fi
        else
            echo -e "${RED}无法获取进程PID，请手动处理${NC}"
            exit 1
        fi
    else
        echo -e "${RED}安装终止${NC}"
        exit 1
    fi
else
    echo -e "${GREEN}端口 $PORT 可用${NC}"
fi

# ========== 安装 Nginx 和 PHP-FPM ==========
echo -e "${GREEN}安装 Nginx 和 PHP-FPM...${NC}"

case $OS in
    alpine)
        apk add --no-cache nginx php php-fpm php-mbstring php-xml php-curl php-zip php-gd php-json php-openssl php-ctype unzip curl wget bash
        PHP_SOCKET="unix:/run/php/php-fpm.sock"
        PHP_FPM_SERVICE="php-fpm82"
        
        # 尝试检测正确的 PHP-FPM 版本
        if ! rc-service $PHP_FPM_SERVICE status 2>/dev/null | grep -q "started"; then
            PHP_FPM_SERVICE="php-fpm83"
        fi
        if ! rc-service $PHP_FPM_SERVICE status 2>/dev/null | grep -q "started"; then
            PHP_FPM_SERVICE="php-fpm"
        fi
        
        # 创建必要的目录
        mkdir -p /run/php
        mkdir -p /var/log/nginx
        chown nginx:nginx /run/php 2>/dev/null || true
        
        # 确保 nginx 用户存在
        if ! id nginx &>/dev/null; then
            adduser -D -g 'nginx' nginx 2>/dev/null || true
        fi
        ;;
    ubuntu|debian)
        export DEBIAN_FRONTEND=noninteractive
        apt-get update -y || true
        apt-get install -y --no-install-recommends \
            nginx php-fpm php-cli php-mbstring php-xml php-curl php-zip php-gd php-ctype \
            unzip curl wget
        PHP_FPM_VERSION=$(php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;' 2>/dev/null)
        if [ -z "$PHP_FPM_VERSION" ]; then
            PHP_FPM_VERSION=$(ls /etc/php/*/fpm/php-fpm.conf 2>/dev/null | head -1 | sed 's|/etc/php/\(.*\)/fpm/php-fpm.conf|\1|')
        fi
        if [ -f "/var/run/php/php${PHP_FPM_VERSION}-fpm.sock" ]; then
            PHP_SOCKET="unix:/var/run/php/php${PHP_FPM_VERSION}-fpm.sock"
        else
            PHP_SOCKET="127.0.0.1:9000"
        fi
        PHP_FPM_SERVICE="php${PHP_FPM_VERSION}-fpm"
        ;;
    centos|rhel|fedora|rocky|almalinux)
        if command -v dnf &>/dev/null; then
            dnf install -y epel-release
            dnf install -y nginx php-fpm php-cli php-mbstring php-xml php-curl php-zip php-gd unzip curl wget
        else
            yum install -y epel-release
            yum install -y nginx php-fpm php-cli php-mbstring php-xml php-curl php-zip php-gd unzip curl wget
        fi
        PHP_SOCKET="unix:/var/run/php-fpm/www.sock"
        PHP_FPM_SERVICE="php-fpm"
        ;;
esac

# 验证安装
if ! command -v nginx &>/dev/null; then
    echo -e "${RED}Nginx 安装失败${NC}"
    exit 1
fi

if ! command -v php &>/dev/null; then
    echo -e "${RED}PHP 安装失败${NC}"
    exit 1
fi

# 验证 PHP ctype 扩展
if ! php -m | grep -q "ctype"; then
    echo -e "${YELLOW}警告: PHP ctype 扩展未加载，尝试安装...${NC}"
    case $OS in
        alpine)
            apk add --no-cache php-ctype
            ;;
        ubuntu|debian)
            apt-get install -y php-ctype || apt-get install -y php${PHP_FPM_VERSION}-ctype
            ;;
    esac
fi

echo -e "${GREEN}Nginx 版本: $(nginx -v 2>&1)${NC}"
echo -e "${GREEN}PHP 版本: $(php -v | head -1)${NC}"

# ========== 下载项目 ==========
echo -e "${GREEN}下载 Speedtest-X...${NC}"
mkdir -p "$PROJECT_DIR"
TEMP_DIR=$(mktemp -d)
cd "$TEMP_DIR" || exit 1

if command -v git &>/dev/null; then
    git clone https://github.com/MortyFx/speedtest-x.git .
else
    wget -O speedtest-x.zip https://github.com/MortyFx/speedtest-x/archive/refs/heads/master.zip
    unzip -q speedtest-x.zip
    if [ -d speedtest-x-master ]; then
        mv speedtest-x-master/* . 2>/dev/null || true
        mv speedtest-x-master/.[!.]* . 2>/dev/null 2>&1 || true
        rm -rf speedtest-x-master speedtest-x.zip
    fi
fi

cp -a . "$PROJECT_DIR"/
cd /
rm -rf "$TEMP_DIR"

# 确保 results.json 可写
[ ! -f "$PROJECT_DIR/results.json" ] && echo '[]' > "$PROJECT_DIR/results.json"
chmod 666 "$PROJECT_DIR/results.json"

# 设置权限
chmod -R 755 "$PROJECT_DIR"
chown -R nginx:nginx "$PROJECT_DIR" 2>/dev/null || true

# ========== 配置 PHP-FPM ==========
if [ "$OS" = "alpine" ]; then
    # 查找 PHP-FPM 配置文件
    PHP_FPM_CONF=$(find /etc/php* -name "www.conf" 2>/dev/null | head -1)
    if [ -n "$PHP_FPM_CONF" ]; then
        # 配置 PHP-FPM 使用 Unix socket
        sed -i 's|^listen = 127.0.0.1:9000|listen = /run/php/php-fpm.sock|' "$PHP_FPM_CONF"
        sed -i 's|^listen = 9000|listen = /run/php/php-fpm.sock|' "$PHP_FPM_CONF"
        sed -i 's|^;listen.owner = nobody|listen.owner = nginx|' "$PHP_FPM_CONF"
        sed -i 's|^;listen.group = nobody|listen.group = nginx|' "$PHP_FPM_CONF"
        sed -i 's|^;listen.mode = 0660|listen.mode = 0660|' "$PHP_FPM_CONF"
        
        # 确保 socket 目录存在
        mkdir -p /run/php
        chown nginx:nginx /run/php
    fi
fi

# ========== 配置 Nginx 虚拟主机 ==========
echo -e "${GREEN}配置 Nginx...${NC}"

# 确定配置文件目录
if [ -d "/etc/nginx/http.d" ]; then
    NGINX_CONF_FILE="/etc/nginx/http.d/speedtest.conf"
elif [ -d "/etc/nginx/conf.d" ]; then
    NGINX_CONF_FILE="/etc/nginx/conf.d/speedtest.conf"
else
    NGINX_CONF_FILE="/etc/nginx/sites-available/speedtest"
    mkdir -p /etc/nginx/sites-available /etc/nginx/sites-enabled
fi

cat > "$NGINX_CONF_FILE" << EOF
server {
    listen $PORT;
    server_name _;

    root $PROJECT_DIR;
    index index.html index.htm index.php;

    access_log /var/log/nginx/speedtest_access.log;
    error_log /var/log/nginx/speedtest_error.log;

    client_max_body_size 20M;

    location / {
        try_files \$uri \$uri/ /index.php?\$args;
    }

    location ~ \.php\$ {
        try_files \$uri =404;
        fastcgi_split_path_info ^(.+\.php)(/.+)\$;
        fastcgi_pass $PHP_SOCKET;
        fastcgi_index index.php;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        include fastcgi_params;
    }

    location ~ /\.ht {
        deny all;
    }
}
EOF

# 对于 Debian/Ubuntu 创建软链接
if [ "$NGINX_CONF_FILE" = "/etc/nginx/sites-available/speedtest" ]; then
    ln -sf "$NGINX_CONF_FILE" /etc/nginx/sites-enabled/speedtest
fi

# 测试 Nginx 配置
echo -e "${YELLOW}测试 Nginx 配置...${NC}"
nginx -t 2>&1
if [ $? -ne 0 ]; then
    echo -e "${RED}Nginx 配置测试失败${NC}"
    echo -e "${YELLOW}尝试修复配置...${NC}"
    
    # 如果 socket 方式失败，尝试 TCP 方式
    sed -i 's|fastcgi_pass unix:/run/php/php-fpm.sock;|fastcgi_pass 127.0.0.1:9000;|' "$NGINX_CONF_FILE"
    nginx -t 2>&1
    if [ $? -ne 0 ]; then
        echo -e "${RED}仍然失败，请检查 PHP-FPM 配置${NC}"
        cat "$NGINX_CONF_FILE"
        exit 1
    fi
    PHP_SOCKET="127.0.0.1:9000"
    echo -e "${GREEN}已切换到 TCP 模式: $PHP_SOCKET${NC}"
fi

# ========== 启动服务 ==========
echo -e "${GREEN}启动服务...${NC}"

# 启动 PHP-FPM
if command -v rc-service &>/dev/null; then
    # Alpine OpenRC
    rc-service $PHP_FPM_SERVICE restart 2>/dev/null || {
        # 尝试通用名称
        rc-service php-fpm restart 2>/dev/null || rc-service php-fpm82 restart 2>/dev/null || rc-service php-fpm83 restart 2>/dev/null
    }
    rc-update add $PHP_FPM_SERVICE default 2>/dev/null || true
    
    # 启动 Nginx
    rc-service nginx restart
    rc-update add nginx default 2>/dev/null || true
elif command -v systemctl &>/dev/null; then
    systemctl restart $PHP_FPM_SERVICE 2>/dev/null || true
    systemctl enable $PHP_FPM_SERVICE 2>/dev/null || true
    systemctl restart nginx
    systemctl enable nginx 2>/dev/null || true
else
    service $PHP_FPM_SERVICE restart 2>/dev/null || true
    service nginx restart 2>/dev/null || true
fi

sleep 2

# 检查服务状态
echo -e "${GREEN}检查服务状态...${NC}"
if pgrep -x "nginx" > /dev/null; then
    echo -e "${GREEN}✓ Nginx 运行中${NC}"
else
    echo -e "${RED}✗ Nginx 未运行${NC}"
    echo -e "${YELLOW}查看错误: tail -20 /var/log/nginx/error.log${NC}"
fi

if pgrep -f "php-fpm" > /dev/null; then
    echo -e "${GREEN}✓ PHP-FPM 运行中${NC}"
else
    echo -e "${YELLOW}⚠ PHP-FPM 可能未运行${NC}"
fi

# ========== 最终信息 ==========
sleep 1

# 获取 IP 地址
IP=$(curl -s -m 5 4.ipw.cn 2>/dev/null || curl -s -m 5 ipinfo.io/ip 2>/dev/null || curl -s -m 5 ifconfig.me 2>/dev/null || echo "服务器IP")

# 测试本地访问
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:$PORT 2>/dev/null)
if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "403" ] || [ "$HTTP_CODE" = "301" ] || [ "$HTTP_CODE" = "302" ]; then
    STATUS="可访问 (HTTP $HTTP_CODE)"
elif [ -n "$HTTP_CODE" ] && [ "$HTTP_CODE" != "000" ]; then
    STATUS="可访问 (HTTP $HTTP_CODE)"
else
    STATUS="请检查服务状态"
fi

echo -e "${GREEN}================================${NC}"
echo -e "${GREEN}   Speedtest-X 部署成功！${NC}"
echo -e "${GREEN}================================${NC}"
echo -e "${YELLOW}访问地址:  http://${IP}:${PORT}${NC}"
echo -e "${YELLOW}项目目录:  $PROJECT_DIR${NC}"
echo -e "${YELLOW}Nginx 配置: $NGINX_CONF_FILE${NC}"
echo -e "${YELLOW}PHP-FPM:    $PHP_SOCKET${NC}"
echo -e "${YELLOW}本地状态:  $STATUS${NC}"
echo -e "  卸载:     $(basename "$0") uninstall"
echo -e "${GREEN}================================${NC}"

# 如果服务未正常运行，显示调试信息
if [ "$STATUS" = "请检查服务状态" ]; then
    echo -e "\n${YELLOW}调试信息:${NC}"
    echo -e "  1. 检查 Nginx 错误日志: tail -20 /var/log/nginx/error.log"
    echo -e "  2. 检查 PHP-FPM 状态: ps aux | grep php"
    echo -e "  3. 手动测试: curl -v http://127.0.0.1:$PORT"
    echo -e "  4. 重启服务: rc-service nginx restart && rc-service php-fpm restart"
fi

# 显示 PHP 已加载的扩展
echo -e "\n${GREEN}PHP 已加载扩展:${NC}"
php -m | grep -E "ctype|mbstring|xml|curl|zip|gd|json|openssl" | sed 's/^/  - /'

# 防火墙提醒
if command -v ufw &>/dev/null && ufw status | grep -q "active"; then
    echo -e "\n${YELLOW}⚠ 请执行: ufw allow $PORT${NC}"
elif command -v firewall-cmd &>/dev/null && firewall-cmd --state 2>/dev/null | grep -q "running"; then
    echo -e "\n${YELLOW}⚠ 请执行: firewall-cmd --add-port=${PORT}/tcp --permanent && firewall-cmd --reload${NC}"
fi
