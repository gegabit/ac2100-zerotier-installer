#!/bin/sh
# =============================================================================
# Установщик ZeroTier для роутеров на прошивке Padavan
# Версия: 1.0.6
# Автор: gegabit
# Описание: Установка Entware и ZeroTier на Padavan (раздел RWFS /dev/mtd11)
# =============================================================================

echo "=== Установка ZeroTier для Padavan v1.0.6 ==="
echo ""

# Цвета
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step() { echo -e "${CYAN}[STEP]${NC} $1"; }

# -----------------------------------------------------------------------------
# Запрос ID сети ZeroTier
# -----------------------------------------------------------------------------
ask_network_id() {
    echo ""
    echo "┌─────────────────────────────────────────────────────────────┐"
    echo "│                    НАСТРОЙКА ZEROTIER                       │"
    echo "└─────────────────────────────────────────────────────────────┘"
    echo ""
    echo "Введите ID сети ZeroTier (16 HEX символов)"
    echo "Получить ID: https://my.zerotier.com"
    echo ""
    
    while true; do
        printf "${BLUE}[?]${NC} Введите ID сети: "
        read ZT_NETWORK_ID
        
        if echo "$ZT_NETWORK_ID" | grep -qE '^[a-fA-F0-9]{16}$'; then
            log_info "ID сети принят: $ZT_NETWORK_ID"
            break
        else
            log_error "Неверный формат! Нужно 16 HEX символов (0-9, a-f)"
            echo "Пример: 743993800f16d5b7"
            echo ""
        fi
    done
    
    echo ""
    echo "Будет выполнено подключение к сети: $ZT_NETWORK_ID"
    echo ""
    
    while true; do
        printf "${BLUE}[?]${NC} Продолжить установку? (y/n): "
        read confirm
        case $confirm in
            [Yy]* ) break;;
            [Nn]* ) echo "Установка отменена."; exit 0;;
            * ) echo "Пожалуйста, ответьте y или n";;
        esac
    done
}

# -----------------------------------------------------------------------------
# Монтирование /opt (раздел mtd11)
# -----------------------------------------------------------------------------
mount_opt() {
    if mount | grep -q "/opt"; then
        log_info "/opt уже смонтирован"
        return 0
    fi
    
    log_step "Монтирование /opt..."
    mkdir -p /opt
    
    # Проверяем, существует ли уже ubi0
    if [ -e /dev/ubi0 ]; then
        if mount -t ubifs ubi0 /opt 2>/dev/null; then
            log_info "/opt смонтирован успешно"
            return 0
        fi
    fi
    
    # Форматируем и создаём с нуля
    log_warn "Форматирование RWFS (первый запуск)..."
    
    # Открепляем если было приаттачено
    ubidetach -m 11 2>/dev/null
    
    # Форматируем
    ubiformat /dev/mtd11 -y
    
    # Приаттачиваем
    ubiattach -m 11
    
    # Проверяем создался ли ubi0
    if [ ! -e /dev/ubi0 ]; then
        log_error "UBI устройство не создалось!"
        exit 1
    fi
    
    # Создаём том
    ubimkvol /dev/ubi0 -N user -m
    
    # Монтируем
    if mount -t ubifs ubi0 /opt; then
        log_info "/opt создан и смонтирован успешно"
    else
        log_error "Не удалось смонтировать /opt"
        exit 1
    fi
}

# -----------------------------------------------------------------------------
# Установка Entware
# -----------------------------------------------------------------------------
install_entware() {
    if [ -f /opt/bin/opkg ]; then
        log_info "Entware уже установлен"
        return 0
    fi
    
    log_step "Установка Entware..."
    cd /tmp
    
    if command -v wget >/dev/null 2>&1; then
        wget http://bin.entware.net/mipselsf-k3.4/installer/alternative.sh
    elif command -v curl >/dev/null 2>&1; then
        curl -O http://bin.entware.net/mipselsf-k3.4/installer/alternative.sh
    else
        if busybox wget --help >/dev/null 2>&1; then
            busybox wget http://bin.entware.net/mipselsf-k3.4/installer/alternative.sh
        else
            log_error "Не найден wget или curl!"
            exit 1
        fi
    fi
    
    chmod +x alternative.sh
    sh alternative.sh
    
    if [ -f /opt/bin/opkg ]; then
        log_info "Entware установлен успешно"
    else
        log_error "Не удалось установить Entware"
        exit 1
    fi
}

# -----------------------------------------------------------------------------
# Установка ZeroTier
# -----------------------------------------------------------------------------
install_zerotier() {
    if [ -f /opt/bin/zerotier-one ]; then
        log_info "ZeroTier уже установлен"
        return 0
    fi
    
    log_step "Установка ZeroTier..."
    /opt/bin/opkg update
    /opt/bin/opkg install zerotier
    
    if [ -f /opt/bin/zerotier-one ]; then
        log_info "ZeroTier установлен успешно"
    else
        log_error "Не удалось установить ZeroTier"
        exit 1
    fi
}

# -----------------------------------------------------------------------------
# Создание скриптов автозапуска
# -----------------------------------------------------------------------------
create_startup_scripts() {
    local ZT_NETWORK_ID=$1
    
    log_step "Настройка автозапуска..."
    
    # Создаём скрипт для монтирования и запуска ZeroTier
    cat > /etc/storage/zerotier_start.sh << EOF
#!/bin/sh
# ZeroTier автозапуск
ubiattach -m 11 2>/dev/null
mount -t ubifs ubi0 /opt 2>/dev/null

if [ -f /opt/bin/zerotier-one ]; then
    export PATH=/opt/bin:/opt/sbin:\$PATH
    killall zerotier-one 2>/dev/null
    sleep 2
    /opt/bin/zerotier-one -d
    sleep 10
    /opt/bin/zerotier-cli join "$ZT_NETWORK_ID" 2>/dev/null
    logger -t "Zerotier" "ZeroTier запущен, сеть: $ZT_NETWORK_ID"
fi
EOF
    
    chmod +x /etc/storage/zerotier_start.sh
    
    # Добавляем в post_wan_script.sh
    if ! grep -q "zerotier_start.sh" /etc/storage/post_wan_script.sh 2>/dev/null; then
        echo "" >> /etc/storage/post_wan_script.sh
        echo "# Запуск ZeroTier" >> /etc/storage/post_wan_script.sh
        echo "/etc/storage/zerotier_start.sh &" >> /etc/storage/post_wan_script.sh
        chmod +x /etc/storage/post_wan_script.sh
    fi
    
    log_info "Скрипт автозапуска создан"
}

# -----------------------------------------------------------------------------
# Запуск ZeroTier
# -----------------------------------------------------------------------------
start_zerotier() {
    local ZT_NETWORK_ID=$1
    
    log_step "Запуск ZeroTier..."
    
    killall zerotier-one 2>/dev/null
    sleep 2
    
    /opt/bin/zerotier-one -d
    sleep 10
    
    /opt/bin/zerotier-cli join "$ZT_NETWORK_ID"
    sleep 5
    
    ZT_INFO=$(/opt/bin/zerotier-cli info 2>/dev/null)
    ZT_NODE_ID=$(echo "$ZT_INFO" | awk '{print $3}')
    
    if [ -n "$ZT_NODE_ID" ] && [ "$ZT_NODE_ID" != "info" ]; then
        log_info "ZeroTier запущен, ID устройства: $ZT_NODE_ID"
    else
        log_warn "ZeroTier запущен"
        ZT_NODE_ID=""
    fi
}

# -----------------------------------------------------------------------------
# Сохранение конфигурации
# -----------------------------------------------------------------------------
save_config() {
    log_step "Сохранение конфигурации..."
    mtd_storage.sh save 2>/dev/null
    log_info "Конфигурация сохранена"
}

# -----------------------------------------------------------------------------
# Финальные инструкции
# -----------------------------------------------------------------------------
show_final_instructions() {
    local ZT_NETWORK_ID=$1
    local ZT_NODE_ID=$2
    
    echo ""
    echo "┌─────────────────────────────────────────────────────────────┐"
    echo "│                 УСТАНОВКА ЗАВЕРШЕНА                         │"
    echo "└─────────────────────────────────────────────────────────────┘"
    echo ""
    echo "📋 ИНФОРМАЦИЯ:"
    echo "   • ID вашей сети:     $ZT_NETWORK_ID"
    if [ -n "$ZT_NODE_ID" ]; then
        echo "   • ID устройства:     $ZT_NODE_ID"
    fi
    echo ""
    echo "🔧 ПОЛЕЗНЫЕ КОМАНДЫ:"
    echo "   • Проверить статус:  /opt/bin/zerotier-cli status"
    echo "   • Список сетей:      /opt/bin/zerotier-cli listnetworks"
    echo "   • Получить ID:       /opt/bin/zerotier-cli info"
    echo ""
    echo "➡️ СЛЕДУЮЩИЕ ШАГИ:"
    echo "   1. Зайдите на https://my.zerotier.com"
    echo "   2. Авторизуйте устройство${ZT_NODE_ID:+ с ID $ZT_NODE_ID} в сети $ZT_NETWORK_ID"
    echo "   3. Перезагрузите роутер: reboot"
    echo ""
    echo "┌─────────────────────────────────────────────────────────────┐"
    echo "│  🎉 ZeroTier успешно установлен!                           │"
    echo "└─────────────────────────────────────────────────────────────┘"
}

# -----------------------------------------------------------------------------
# Главная функция
# -----------------------------------------------------------------------------
main() {
    echo ""
    echo "╔═════════════════════════════════════════════════════════════════╗"
    echo "║     Установка Entware + ZeroTier для роутеров на Padavan        ║"
    echo "║                     Версия 1.0.6                                 ║"
    echo "╚═════════════════════════════════════════════════════════════════╝"
    echo ""
    
    ask_network_id
    mount_opt
    install_entware
    install_zerotier
    create_startup_scripts "$ZT_NETWORK_ID"
    start_zerotier "$ZT_NETWORK_ID"
    save_config
    show_final_instructions "$ZT_NETWORK_ID" "$ZT_NODE_ID"
}

# Запуск
main
