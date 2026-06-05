#!/bin/sh
# =============================================================================
# Установщик ZeroTier для роутеров на прошивке Padavan
# Версия: 1.0.1
# Автор: deepseek and gegabit
# Описание: Автоматическая установка Entware и ZeroTier на Padavan (MT7621)
# =============================================================================

# --- ФИКС ДЛЯ ЧТЕНИЯ ВВОДА ПРИ ЗАПУСКЕ ЧЕРЕЗ ПАЙП ---
# Перенаправляем stdin с терминала, если скрипт запущен через curl ... | sh
if [ ! -t 0 ]; then
    exec </dev/tty
fi
# ----------------------------------------------------

echo "=== Установка ZeroTier для Padavan v1.0.1 ==="
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
        printf "${BLUE}[?]${NC} Введите ID сети: "
        read ZT_NETWORK_ID
        
        # Проверка формата (16 символов, только hex)
        if echo "$ZT_NETWORK_ID" | grep -qE '^[a-fA-F0-9]{16}$'; then
            log_info "ID сети принят: $ZT_NETWORK_ID"
            break
        else
            log_error "Неверный формат! ID сети должен содержать 16 HEX символов (0-9, a-f)"
            echo "Пример: 743993888f16d5b7"
            echo ""
        fi
    done
    
    echo ""
    echo "Будет выполнено подключение к сети: $ZT_NETWORK_ID"
    echo ""
    
    # Подтверждение
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
# Создание скриптов автозапуска (остаётся без изменений, слишком большой для вывода)
# -----------------------------------------------------------------------------
# ... (весь остальной код скрипта без изменений) ...

# -----------------------------------------------------------------------------
# Главная функция
# -----------------------------------------------------------------------------
main() {
    echo ""
    echo "╔═════════════════════════════════════════════════════════════════╗"
    echo "║     Установка Entware + ZeroTier для роутеров на Padavan        ║"
    echo "║                     Версия 1.0.1                                 ║"
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
