#!/bin/bash
# Установка Gentoo с runit - базовый скрипт
# ВНИМАНИЕ: Используйте только если понимаете процесс установки Gentoo!

set -e

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Проверка запуска из-под root
if [[ $EUID -ne 0 ]]; then
    log_error "Этот скрипт должен запускаться с правами root"
    exit 1
fi

# Переменные
TARGET_DISK="/dev/sda"  # Измените на свой диск
BOOT_PARTITION="${TARGET_DISK}1"
ROOT_PARTITION="${TARGET_DISK}2"
SWAP_PARTITION="${TARGET_DISK}3"  # Опционально

# ========== 1. Разметка диска ==========
partition_disk() {
    log_info "Разметка диска $TARGET_DISK"
    
    # Очистка таблицы разделов
    sgdisk -Z $TARGET_DISK
    
    # Создание разделов:
    # 1. EFI (или BIOS boot) - 512M
    # 2. Root - остальное место
    # 3. Swap (опционально) - 4G
    
    # Для UEFI
    sgdisk -n 1:0:+512M -t 1:ef00 $TARGET_DISK  # EFI
    sgdisk -n 2:0:+20G -t 2:8300 $TARGET_DISK   # Root
    sgdisk -n 3:0:+4G -t 3:8200 $TARGET_DISK    # Swap
    
    # Для BIOS (альтернатива)
    # sgdisk -n 1:0:+2M -t 1:ef02 $TARGET_DISK  # BIOS boot
    # sgdisk -n 2:0:+512M -t 2:8300 $TARGET_DISK # Boot
    # sgdisk -n 3:0:+20G -t 3:8300 $TARGET_DISK  # Root
    # sgdisk -n 4:0:+4G -t 4:8200 $TARGET_DISK   # Swap
    
    partprobe $TARGET_DISK
    sleep 2
}

# ========== 2. Форматирование разделов ==========
format_partitions() {
    log_info "Форматирование разделов"
    
    # Форматирование EFI раздела
    mkfs.fat -F 32 $BOOT_PARTITION
    
    # Форматирование корневого раздела
    mkfs.ext4 $ROOT_PARTITION
    
    # Инициализация swap
    mkswap $SWAP_PARTITION
    swapon $SWAP_PARTITION
}

# ========== 3. Монтирование ==========
mount_filesystems() {
    log_info "Монтирование файловых систем"
    
    mount $ROOT_PARTITION /mnt/gentoo
    mkdir -p /mnt/gentoo/boot
    mount $BOOT_PARTITION /mnt/gentoo/boot
}

# ========== 4. Установка stage3 ==========
install_stage3() {
    log_info "Загрузка и установка stage3"
    
    cd /mnt/gentoo
    
    # Определяем последний stage3
    LATEST_STAGE3=$(curl -s https://distfiles.gentoo.org/releases/amd64/autobuilds/latest-stage3-amd64.txt | grep -v '#' | awk '{print $1}')
    STAGE3_URL="https://distfiles.gentoo.org/releases/amd64/autobuilds/${LATEST_STAGE3}"
    
    # Загрузка
    wget $STAGE3_URL
    
    # Распаковка
    tar xpvf stage3-*.tar.xz --xattrs-include='*.*' --numeric-owner
    
    log_info "Stage3 установлен"
}

# ========== 5. Настройка make.conf ==========
configure_makeconf() {
    log_info "Настройка make.conf"
    
    cat >> /mnt/gentoo/etc/portage/make.conf << EOF
# Флаги компиляции
COMMON_FLAGS="-march=native -O2 -pipe"
CFLAGS="\${COMMON_FLAGS}"
CXXFLAGS="\${COMMON_FLAGS}"
FCFLAGS="\${COMMON_FLAGS}"
FFLAGS="\${COMMON_FLAGS}"

# USE флаги для runit
USE="runit -systemd -openrc elogind"

# Параллельная сборка
MAKEOPTS="-j$(nproc)"

# Локализация
L10N="ru en"
LINGUAS="ru en"

# Переменные Portage
GENTOO_MIRRORS="https://mirror.yandex.ru/gentoo-distfiles/ http://mirror.leaseweb.com/gentoo/ https://gentoo.osuosl.org/"
EOF
}

# ========== 6. Настройка chroot окружения ==========
setup_chroot() {
    log_info "Настройка chroot окружения"
    
    # Копирование DNS
    cp --dereference /etc/resolv.conf /mnt/gentoo/etc/
    
    # Монтирование необходимых файловых систем
    mount --types proc /proc /mnt/gentoo/proc
    mount --rbind /sys /mnt/gentoo/sys
    mount --make-rslave /mnt/gentoo/sys
    mount --rbind /dev /mnt/gentoo/dev
    mount --make-rslave /mnt/gentoo/dev
    
    # Альтернатива для современных систем
    mount --bind /run /mnt/gentoo/run
    mount --make-slave /mnt/gentoo/run
}

# ========== 7. Chroot и настройка системы ==========
chroot_setup() {
    log_info "Вход в chroot окружение"
    
    cat << 'EOF' | chroot /mnt/gentoo /bin/bash
set -e

# Цвета
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

log_info() {
    echo -e "${GREEN}[CHROOT INFO]${NC} $1"
}

# 7.1. Обновление Portage tree
log_info "Обновление Portage tree"
emerge-webrsync

# 7.2. Выбор профиля (минимальный с systemd, позже заменим на runit)
log_info "Выбор профиля"
eselect profile set default/linux/amd64/17.1

# 7.3. Обновление мира
log_info "Обновление мира"
emerge --ask --update --deep --newuse @world

# 7.4. Настройка локали
log_info "Настройка локали"
echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen
echo "ru_RU.UTF-8 UTF-8" >> /etc/locale.gen
locale-gen
eselect locale set en_US.utf8

# 7.5. Установка ядра
log_info "Установка ядра"
emerge --ask sys-kernel/gentoo-sources sys-kernel/linux-firmware

# 7.6. Настройка ядра (используем genkernel для простоты)
log_info "Настройка ядра с genkernel"
emerge --ask sys-kernel/genkernel
genkernel all

# 7.7. Установка runit
log_info "Установка runit"
echo 'sys-process/runit' >> /etc/portage/package.accept_keywords
emerge --ask sys-process/runit

# 7.8. Настройка fstab
log_info "Настройка fstab"
cat > /etc/fstab << FSTAB_EOF
# <fs>                  <mountpoint>    <type>    <opts>              <dump/pass>
$(blkid -o value -s UUID /dev/sda2)   /               ext4      noatime            0 1
$(blkid -o value -s UUID /dev/sda1)   /boot           vfat      defaults           0 2
$(blkid -o value -s UUID /dev/sda3)   none            swap      sw                 0 0
FSTAB_EOF

# 7.9. Настройка хоста и сети
log_info "Настройка хоста"
echo "gentoo-runit" > /etc/hostname

# Установка сетевых утилит
emerge --ask net-misc/dhcpcd net-misc/networkmanager

# 7.10. Настройка времени
log_info "Настройка времени"
echo "Europe/Moscow" > /etc/timezone
emerge --config sys-libs/timezone-data

# 7.11. Установка необходимых пакетов
log_info "Установка базовых пакетов"
emerge --ask app-admin/sudo sys-apps/pciutils sys-apps/usbutils app-editors/vim sys-process/htop

# 7.12. Настройка пароля root
log_info "Установка пароля root"
passwd

# 7.13. Создание пользователя
log_info "Создание пользователя"
useradd -m -G wheel,users -s /bin/bash user
passwd user

# 7.14. Настройка sudo
echo "%wheel ALL=(ALL) ALL" >> /etc/sudoers

# 7.15. Настройка загрузчика (для UEFI)
log_info "Установка загрузчика (GRUB)"
emerge --ask sys-boot/grub
grub-install --target=x86_64-efi --efi-directory=/boot
grub-mkconfig -o /boot/grub/grub.cfg

# 7.16. Включение сервисов runit
log_info "Настройка сервисов runit"
ln -s /etc/sv/dhcpcd /etc/runit/runsvdir/default/
ln -s /etc/sv/sshd /etc/runit/runsvdir/default/

# Для NetworkManager вместо dhcpcd
# ln -s /etc/sv/NetworkManager /etc/runit/runsvdir/default/

log_info "Базовая установка в chroot завершена!"
EOF
}

# ========== 8. Финальные шаги ==========
final_steps() {
    log_info "Завершение установки"
    
    # Размонтирование
    umount -l /mnt/gentoo/dev{/shm,/pts,}
    umount -R /mnt/gentoo
    
    log_info "Установка завершена!"
    log_warn "Не забудьте:"
    echo "1. Настроить /etc/runit/runsvdir/default/ под свои нужды"
    echo "2. Добавить необходимые сервисы в /etc/runit/runsvdir/default/"
    echo "3. Проверить настройки ядра если нужно"
    echo "4. Перезагрузиться в новую систему"
}

# ========== Главная функция ==========
main() {
    log_info "Начинается установка Gentoo с runit"
    
    # ВАЖНО: Раскомментируйте нужные шаги
    # partition_disk
    # format_partitions
    # mount_filesystems
    # install_stage3
    # configure_makeconf
    # setup_chroot
    # chroot_setup
    # final_steps
    
    log_warn "Этот скрипт требует ручной настройки!"
    echo "1. Отредактируйте переменные (диск, разделы)"
    echo "2. Раскомментируйте нужные шаги в main()"
    echo "3. Запустите скрипт"
}

# Дополнительный скрипт для настройки runit после установки
create_runit_setup_script() {
    cat > /mnt/gentoo/root/setup_runit.sh << 'RUNIT_EOF'
#!/bin/bash
# Скрипт настройки runit после установки

# 1. Установка дополнительных пакетов
emerge --ask app-admin/runit-scripts sys-process/runit-service-manager

# 2. Создание необходимых директорий
mkdir -p /etc/runit/runsvdir/{default,previous}

# 3. Базовые сервисы которые должны быть запущены
SERVICES="agetty-tty1 agetty-tty2 agetty-tty3 cron dhcpcd syslog-ng"

for svc in $SERVICES; do
    if [ -d /etc/sv/$svc ]; then
        ln -s /etc/sv/$svc /etc/runit/runsvdir/default/
    fi
done

# 4. Создание своего сервиса (пример)
mkdir -p /etc/sv/myservice/{log,env}
cat > /etc/sv/myservice/run << 'EOF'
#!/bin/sh
exec 2>&1
exec /usr/local/bin/myapp
EOF
chmod +x /etc/sv/myservice/run

# 5. Настройка getty для консолей
cat > /etc/sv/agetty-tty1/run << 'EOF'
#!/bin/sh
exec /sbin/agetty -8 38400 tty1 linux
EOF

# 6. Активация сервисов
for svc in $(ls /etc/sv/); do
    if [ ! -L /etc/runit/runsvdir/default/$svc ]; then
        echo "Активировать $svc? (y/N)"
        read answer
        if [ "$answer" = "y" ]; then
            ln -s /etc/sv/$svc /etc/runit/runsvdir/default/
        fi
    fi
done

echo "Настройка runit завершена"
echo "После перезагрузки система будет использовать runit"
RUNIT_EOF
    
    chmod +x /mnt/gentoo/root/setup_runit.sh
}

# Запуск
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main
fi