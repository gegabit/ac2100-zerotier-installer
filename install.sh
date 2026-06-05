#!/bin/sh
# =============================================================================
# Установщик ZeroTier для роутеров на прошивке Padavan
# Версия: 1.0.4
# Автор: deepseek and gegabit
# Описание: Установка Entware и ZeroTier на Padavan (MT7621)
# =============================================================================

echo "==== Установка ZeroTier для Padavan v1.0.4 ===="
echo ""

# -----------------------------------------------------------------------------
# Функции для цветного вывода
# -----------------------------------------------------------------------------
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
    echo "Введите ID сети ZeroTier (формат: 16 символов, цифры и буквы)"
    echo "Получить ID можно в вашем аккаунте на https://my.zerotier.com"
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
# Определение раздела RWFS
# -----------------------------------------------------------------------------
get_rwfs_partition() {
    log_step "Поиск раздела RWFS..."
    RWFS_LINE=$(cat /proc/mtd | grep "RWFS")
    
    if [ -z "$RWFS_LINE" ]; then
        log_error "Раздел RWFS не найден!"
        exit 1
    fi
    
    RWFS_DEV=$(echo "$RWFS_LINE" | awk -F: '{print $1}' | sed 's/mtd//')
    log_info "Найден раздел: /dev/mtd$RWFS_DEV"
    echo "$RWFS_DEV"
}

# -----------------------------------------------------------------------------
# Монтирование /opt (исправленная версия)
# -----------------------------------------------------------------------------
mount_opt() {
    local RWFS_DEV=$1
    
    if mount | grep -q "/opt"; then
        log_info "/opt уже смонтирован"
        return 0
    fi
    
    log_step "Монтирование /opt..."
    mkdir -p /opt
    
    # Проверяем, существует ли уже ubi0
    if [ -e /dev/ubi0 ]; then
        # Пробуем смонтировать существующий
        if mount -t ubifs ubi0 /opt 2>/dev/null; then
            log_info "/opt смонтирован успешно"
            return 0
        fi
    fi
    
    # Форматируем и создаём с нуля
    log_warn "Форматирование RWFS (первый запуск)..."
    
    # Открепляем если было приаттачено
    ubidetach -m "$RWFS_DEV" 2>/dev/null
    
    # Форматируем
    ubiformat "/dev/mtd$RWFS_DEV" -y
    
    # Приаттачиваем
    ubiattach -m "$RWFS_DEV"
    
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
# Установка Entware (с проверкой наличия wget/curl)
# -----------------------------------------------------------------------------
install_entware() {
    if [ -f /opt/bin/opkg ]; then
        log_info "Entware уже установлен"
        return 0
    fi
    
    log_step "Установка Entware..."
    cd /tmp
    
    # Пробуем скачать разными способами
    if command -v wget >/dev/null 2>&1; then
        wget http://bin.entware.net/mipselsf-k3.4/installer/alternative.sh
    elif command -v curl >/dev/null 2>&1; then
        curl -O http://bin.entware.net/mipselsf-k3.4/installer/alternative.sh
    else
        # Если нет wget и curl, используем встроенный busybox wget
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
# Создание скрипта автозапуска
# -----------------------------------------------------------------------------
create_startup_scripts() {
    local ZT_NETWORK_ID=$1
    local RWFS_DEV=$2
    
    log_step "Настройка автозапуска..."
    
    cat > /etc/storage/started_script.sh << EOF
#!/bin/sh
# ZeroTier автозапуск

# Монтирование Entware
ubiattach -m $RWFS_DEV 2>/dev/null
mount -t ubifs ubi0 /opt 2>/dev/null

# Запуск ZeroTier
if [ -f /opt/bin/zerotier-one ]; then
    export PATH=/opt/bin:/opt/sbin:\$PATH
    killall zerotier-one 2>/dev/null
    sleep 2
    /opt/bin/zerotier-one -d
    sleep 10
    /opt/bin/zerotier-cli join "$ZT_NETWORK_ID" 2>/dev/null
fi
EOF

    chmod +x /etc/storage/started_script.sh
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
    echo "   2. Авторизуйте устройство в сети $ZT_NETWORK_ID"
    echo "   3. Перезагрузите роутер для проверки: reboot"
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
    echo "║                     Версия 1.0.4                                 ║"
    echo "╚═════════════════════════════════════════════════════════════════╝"
    echo ""
    
    ask_network_id
    
    RWFS_DEV=$(get_rwfs_partition)
    mount_opt "$RWFS_DEV"
    install_entware
    install_zerotier
    create_startup_scripts "$ZT_NETWORK_ID" "$RWFS_DEV"
    start_zerotier "$ZT_NETWORK_ID"
    save_config
    show_final_instructions "$ZT_NETWORK_ID" "$ZT_NODE_ID"
}

# Запуск
main
