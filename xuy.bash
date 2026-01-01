#!/bin/bash

# ============================================
# Gentoo Install Script (Bash)
# ВНИМАНИЕ: Использовать на свой страх и риск!
# Предназначен для ознакомления с процессом.
# ============================================

set -e  # Прерывать при ошибках

# ============ НАСТРОЙКИ ============
TARGET_DISK="/dev/sda"
BOOT_PARTITION="${TARGET_DISK}1"
ROOT_PARTITION="${TARGET_DISK}2"
SWAP_PARTITION="${TARGET_DISK}3"
TIMEZONE="Europe/Moscow"
LOCALE="ru_RU.UTF-8"
HOSTNAME="gentoo-box"
ROOT_PASSWORD="change_me"  # ИЗМЕНИТЬ!

# ============ ФУНКЦИИ ============
print_step() {
    echo -e "\n\e[1;34m[*] $1\e[0m"
}

print_error() {
    echo -e "\e[1;31m[!] $1\e[0m"
}

print_success() {
    echo -e "\e[1;32m[+] $1\e[0m"
}

# ============ ПРОВЕРКА ============
if [[ $EUID -ne 0 ]]; then
    print_error "Запустите скрипт от root!"
    exit 1
fi

if [[ ! -e /mnt/gentoo ]]; then
    mkdir /mnt/gentoo
fi

# ============ РАЗДЕЛЫ ДИСКА ============
print_step "Создание разделов..."
cat << EOF | fdisk ${TARGET_DISK}
o
n
p
1

+256M
t
1
n
p
2

+20G
n
p
3

+4G
t
3
82
p
w
EOF

print_step "Форматирование разделов..."
mkfs.fat -F 32 ${BOOT_PARTITION}
mkfs.ext4 ${ROOT_PARTITION}
mkswap ${SWAP_PARTITION}
swapon ${SWAP_PARTITION}

# ============ МОНТИРОВАНИЕ ============
print_step "Монтирование разделов..."
mount ${ROOT_PARTITION} /mnt/gentoo
mkdir -p /mnt/gentoo/boot
mount ${BOOT_PARTITION} /mnt/gentoo/boot

# ============ УСТАНОВКА STAGE3 ============
print_step "Загрузка и распаковка stage3..."
cd /mnt/gentoo
STAGE3_URL="https://distfiles.gentoo.org/releases/amd64/autobuilds/latest-stage3-amd64-systemd.txt"
STAGE3_PATH=$(curl -s ${STAGE3_URL} | grep -v "^#" | awk '{print $1}')
wget "https://distfiles.gentoo.org/releases/amd64/autobuilds/${STAGE3_PATH}"
tar xpvf stage3-*.tar.xz --xattrs-include='*.*' --numeric-owner

# ============ НАСТРОЙКА ============
print_step "Настройка базовой системы..."

# mirrors
mkdir -p /mnt/gentoo/etc/portage/repos.conf
cp /mnt/gentoo/usr/share/portage/config/repos.conf /mnt/gentoo/etc/portage/repos.conf/gentoo.conf

# fstab
cat > /mnt/gentoo/etc/fstab << EOF
${ROOT_PARTITION}   /           ext4    noatime         0 1
${BOOT_PARTITION}   /boot       vfat    defaults        0 2
${SWAP_PARTITION}   none        swap    sw              0 0
EOF

# chroot подготовка
cp -L /etc/resolv.conf /mnt/gentoo/etc/

# ============ CHROOT ============
print_step "Вход в chroot-окружение..."

cat > /mnt/gentoo/chroot.sh << EOF
#!/bin/bash
set -e

# Часовой пояс
ln -sf /usr/share/zoneinfo/${TIMEZONE} /etc/localtime

# Локализация
echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen
echo "${LOCALE} UTF-8" >> /etc/locale.gen
locale-gen
eselect locale set ${LOCALE}
env-update && source /etc/profile

# Обновление Portage
emerge-webrsync
emerge --sync

# Ядро (минимальная конфигурация)
emerge -q sys-kernel/gentoo-sources sys-kernel/linux-firmware
cd /usr/src/linux
make defconfig
make -j\$(nproc) && make modules_install && make install

# Загрузчик
emerge -q sys-boot/grub
grub-install ${TARGET_DISK}
grub-mkconfig -o /boot/grub/grub.cfg

# Пароль root
echo "root:${ROOT_PASSWORD}" | chpasswd

# Имя хоста
echo "${HOSTNAME}" > /etc/hostname

# Сеть (DHCP)
emerge -q net-misc/dhcpcd
rc-update add dhcpcd default

# Завершение
emerge -q vim sudo
EOF

chmod +x /mnt/gentoo/chroot.sh
chroot /mnt/gentoo /bin/bash /chroot.sh
rm /mnt/gentoo/chroot.sh

# ============ ЗАВЕРШЕНИЕ ============
print_step "Завершение установки..."
umount -l /mnt/gentoo/boot
umount -l /mnt/gentoo
swapoff ${SWAP_PARTITION}

print_success "Установка Gentoo завершена!"
echo "Не забудьте:"
echo "1. Изменить пароль root (уже сделано в скрипте, но проверьте)"
echo "2. Настроить пользователя: useradd -m -G wheel,audio,video пользователь"
echo "3. Установить нужные пакеты: emerge -q gnome-shell firefox и т.д."
echo "4. Перезагрузиться: reboot"
