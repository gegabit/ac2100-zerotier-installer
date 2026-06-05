#!/bin/sh
# =============================================================================
# Установщик ZeroTier для роутеров на прошивке Padavan
# Версия: 1.0.0
# Автор: deepseek and gegabit ))
# Описание: Автоматическая установка Entware и ZeroTier на Padavan (MT7621)
# =============================================================================

echo "=== Установка ZeroTier для Padavan v1.0.0 ==="
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
log_question() { echo -e "${BLUE}[?]${NC} $1"; }

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
        log_question "Введите ID сети: "
        read ZT_NETWORK_ID
        
        # Проверка формата (16 символов, только hex)
        if echo "$ZT_NETWORK_ID" | grep -qE '^[a-fA-F0-9]{16}$'; then
            log_info "ID сети принят: $ZT_NETWORK_ID"
            break
        else
            log_error "Неверный формат! ID сети должен содержать 16 HEX символов (0-9, a-f)"
            echo "Пример: 743993800f16d5b7"
            echo ""
        fi
    done
    
    echo ""
    echo "Будет выполнено подключение к сети: $ZT_NETWORK_ID"
    echo ""
    
    # Подтверждение
    while true; do
        log_question "Продолжить установку? (y/n): "
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
    RWFS_DEV=$(cat /proc/mtd | grep "RWFS" | awk -F: '{print $1}' | sed 's/mtd//')
    
    if [ -z "$RWFS_DEV" ]; then
        log_error "Раздел RWFS не найден!"
        log_error "Ваш роутер может не поддерживать установку Entware во внутреннюю память"
        exit 1
    fi
    
    log_info "Найден раздел: /dev/mtd$RWFS_DEV"
    echo "$RWFS_DEV"
}

# -----------------------------------------------------------------------------
# Монтирование /opt
# -----------------------------------------------------------------------------
mount_opt() {
    local RWFS_DEV=$1
    
    if mount | grep -q "/opt"; then
        log_info "/opt уже смонтирован"
        return 0
    fi
    
    log_step "Монтирование /opt..."
    ubiattach -p "/dev/mtd$RWFS_DEV" 2>/dev/null
    mkdir -p /opt
    
    if mount -t ubifs ubi0 /opt 2>/dev/null; then
        log_info "/opt смонтирован успешно"
    else
        log_warn "Первый запуск: форматирование RWFS..."
        ubiformat "/dev/mtd$RWFS_DEV" -y
        ubiattach -p "/dev/mtd$RWFS_DEV"
        ubimkvol /dev/ubi0 -m -N user
        mount -t ubifs ubi0 /opt
        log_info "/opt создан и смонтирован"
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
        wget -q http://bin.entware.net/mipselsf-k3.4/installer/alternative.sh
    elif command -v curl >/dev/null 2>&1; then
        curl -s -O http://bin.entware.net/mipselsf-k3.4/installer/alternative.sh
    else
        log_error "Не найден wget или curl"
        exit 1
    fi
    
    chmod +x alternative.sh
    ./alternative.sh
    
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
    
    log_step "Создание скриптов автозапуска..."
    
    # Получаем номер раздела RWFS для скриптов
    RWFS_NUM=$(cat /proc/mtd | grep "RWFS" | awk -F: '{print $1}' | sed 's/mtd//')
    
    # Скрипт для ipset_update.sh (заглушка)
    cat > /etc/storage/ipset_update.sh << 'EOF_IPSET'
#!/bin/sh
# =============================================================================
# Скрипт обновления ipset для ZeroTier (заглушка)
# =============================================================================

LOCK_FILE="/tmp/ipset_update.lock"
if [ -f "$LOCK_FILE" ]; then
    echo "[$(date)] Скрипт уже выполняется, завершаюсь." >> /tmp/ipset_update.log
    exit 0
fi
touch "$LOCK_FILE"
trap 'rm -f "$LOCK_FILE"' EXIT

IPSET_NAME="zerotier_nets"
ZT_IFACE=$(ip link show | grep -oE 'zt[a-z0-9]+' | head -1)
LOG_FILE="/tmp/ipset_update.log"

log() { 
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

log "=== Проверка ZeroTier ==="
if [ -n "$ZT_IFACE" ]; then
    log "ZeroTier интерфейс: $ZT_IFACE"
    if ! ipset list "$IPSET_NAME" >/dev/null 2>&1; then
        ipset create "$IPSET_NAME" hash:net 2>/dev/null
        log "Создан ipset $IPSET_NAME"
    fi
else
    log "ZeroTier интерфейс не найден"
fi
log "=== Готово ==="
EOF_IPSET

    # Скрипт watchdog для ZeroTier
    cat > /etc/storage/route_watchdog.sh << EOF_WATCHDOG
#!/bin/sh
# =============================================================================
# Watchdog для ZeroTier (мониторинг и восстановление)
# =============================================================================

ZT_NETWORK_ID="$ZT_NETWORK_ID"
INTERVAL=15
LOG_FILE="/tmp/route_watchdog.log"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] \$1" >> "\$LOG_FILE"
}

get_zt_interface() {
    ip link show | grep -oE 'zt[a-z0-9]+' | head -1
}

log "Watchdog ZeroTier запущен"

while true; do
    ZT_IF=\$(get_zt_interface)
    
    if [ -n "\$ZT_IF" ]; then
        # Проверяем процесс
        if ! pgrep -f "zerotier-one" > /dev/null; then
            log "ZeroTier не запущен! Запускаю..."
            /opt/bin/zerotier-one -d
            sleep 5
        fi
        
        # Проверяем подключение к сети
        if ! /opt/bin/zerotier-cli listnetworks 2>/dev/null | grep -q "\$ZT_NETWORK_ID.*OK"; then
            log "Подключаюсь к сети \$ZT_NETWORK_ID..."
            /opt/bin/zerotier-cli join "\$ZT_NETWORK_ID"
            sleep 5
        fi
        
        # Настройка маршрутизации
        echo 1 > /proc/sys/net/ipv4/ip_forward
        
        iptables -t nat -D POSTROUTING -o br0 -j MASQUERADE 2>/dev/null
        iptables -t nat -A POSTROUTING -o br0 -j MASQUERADE
        
        iptables -D FORWARD -i "\$ZT_IF" -j ACCEPT 2>/dev/null
        iptables -D FORWARD -o "\$ZT_IF" -j ACCEPT 2>/dev/null
        iptables -A FORWARD -i "\$ZT_IF" -j ACCEPT
        iptables -A FORWARD -o "\$ZT_IF" -j ACCEPT
    else
        if pgrep -f "zerotier-one" > /dev/null; then
            log "Интерфейс пропал, перезапускаю ZeroTier..."
            killall zerotier-one
            sleep 2
            /opt/bin/zerotier-one -d
        fi
    fi
    
    sleep \$INTERVAL
done
EOF_WATCHDOG

    # Скрипт автозапуска started_script.sh
    cat >> /etc/storage/started_script.sh << EOF_STARTED
#!/bin/sh
# --- ZeroTier автозапуск ---

# Монтирование Entware
ubiattach -p /dev/mtd$RWFS_NUM 2>/dev/null
mount -t ubifs ubi0 /opt 2>/dev/null

# Добавляем PATH
export PATH=/opt/bin:/opt/sbin:\$PATH

# Запуск ZeroTier
if [ -f /opt/bin/zerotier-one ]; then
    killall zerotier-one 2>/dev/null
    sleep 2
    /opt/bin/zerotier-one -d
    sleep 10
    /opt/bin/zerotier-cli join "$ZT_NETWORK_ID" 2>/dev/null
fi

# Запуск вспомогательных скриптов
( sleep 60 && /etc/storage/ipset_update.sh ) &
( sleep 90 && /etc/storage/route_watchdog.sh & ) &
EOF_STARTED

    chmod +x /etc/storage/ipset_update.sh
    chmod +x /etc/storage/route_watchdog.sh
    chmod +x /etc/storage/started_script.sh
    
    log_info "Скрипты автозапуска созданы"
}

# -----------------------------------------------------------------------------
# Запуск ZeroTier
# -----------------------------------------------------------------------------
start_zerotier() {
    local ZT_NETWORK_ID=$1
    
    log_step "Запуск ZeroTier..."
    
    # Останавливаем старые процессы
    killall zerotier-one 2>/dev/null
    sleep 2
    
    # Запускаем демон
    /opt/bin/zerotier-one -d
    sleep 10
    
    # Подключаемся к сети
    /opt/bin/zerotier-cli join "$ZT_NETWORK_ID"
    sleep 5
    
    # Получаем ID устройства
    ZT_NODE_ID=$(/opt/bin/zerotier-cli info 2>/dev/null | awk '{print $2}')
    
    if [ -n "$ZT_NODE_ID" ]; then
        log_info "ZeroTier запущен, ID устройства: $ZT_NODE_ID"
    else
        log_warn "ZeroTier запущен, но не удалось получить ID"
    fi
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
    echo "   • ID устройства:     ${ZT_NODE_ID:-(получите командой ниже)}"
    echo "   • IP в ZeroTier:     будет получен после авторизации"
    echo ""
    echo "🔧 ПОЛЕЗНЫЕ КОМАНДЫ:"
    echo "   • Проверить статус:  /opt/bin/zerotier-cli status"
    echo "   • Список сетей:      /opt/bin/zerotier-cli listnetworks"
    echo "   • Получить ID:       /opt/bin/zerotier-cli info"
    echo ""
    echo "➡️ СЛЕДУЮЩИЕ ШАГИ:"
    echo "   1. Зайдите на https://my.zerotier.com"
    echo "   2. Авторизуйте устройство в сети $ZT_NETWORK_ID"
    if [ -n "$ZT_NODE_ID" ]; then
        echo "      (найдите устройство с ID: $ZT_NODE_ID)"
    fi
    echo "   3. Через 1 минуту проверьте подключение:"
    echo "      /opt/bin/zerotier-cli listnetworks"
    echo "   4. Перезагрузите роутер для проверки автозапуска: reboot"
    echo ""
    echo "⚠️ ВАЖНО: Если после перезагрузки ZeroTier не работает,"
    echo "   проверьте, что в веб-интерфейсе в разделе"
    echo "   'Скрипты → Выполнить после запуска' есть строка:"
    echo "   /etc/storage/started_script.sh"
    echo ""
    echo "┌─────────────────────────────────────────────────────────────┐"
    echo "│  🎉 Поздравляем! ZeroTier успешно установлен!              │"
    echo "└─────────────────────────────────────────────────────────────┘"
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
# Главная функция
# -----------------------------------------------------------------------------
main() {
    echo ""
    echo "╔═════════════════════════════════════════════════════════════════╗"
    echo "║     Установка Entware + ZeroTier для роутеров на Padavan        ║"
    echo "║                     Версия 1.0.0                                 ║"
    echo "╚═════════════════════════════════════════════════════════════════╝"
    echo ""
    
    # Запрашиваем ID сети
    ask_network_id
    
    # Установка
    RWFS_NUM=$(get_rwfs_partition)
    mount_opt "$RWFS_NUM"
    install_entware
    install_zerotier
    create_startup_scripts "$ZT_NETWORK_ID"
    start_zerotier "$ZT_NETWORK_ID"
    save_config
    show_final_instructions "$ZT_NETWORK_ID" "$ZT_NODE_ID"
}

# Запуск
main
