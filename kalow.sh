#!/bin/bash
# minimal-gentoo-runit.sh

set -e

DISK="/dev/sda"  # ИЗМЕНИТЕ ЭТО!

echo "=== Установка Gentoo с runit ==="
echo
echo "Этот скрипт выполнит:"
echo "1. Разметку диска $DISK"
echo "2. Форматирование разделов"
echo "3. Установку stage3"
echo "4. Базовую настройку с runit"
echo
read -p "Продолжить? (все данные на $DISK будут удалены!) [y/N]: " confirm

if [[ ! $confirm =~ ^[Yy]$ ]]; then
    exit 1
fi

# 1. Разметка
echo "Разметка диска..."
sgdisk -Z $DISK
sgdisk -n 1:0:+512M -t 1:ef00 $DISK
sgdisk -n 2:0:+20G -t 2:8300 $DISK
sgdisk -n 3:0:+4G -t 3:8200 $DISK
partprobe $DISK

# 2. Форматирование
echo "Форматирование..."
mkfs.fat -F 32 ${DISK}1
mkfs.ext4 ${DISK}2
mkswap ${DISK}3
swapon ${DISK}3

# 3. Монтирование
echo "Монтирование..."
mount ${DISK}2 /mnt/gentoo
mkdir -p /mnt/gentoo/boot
mount ${DISK}1 /mnt/gentoo/boot

# 4. Stage3
echo "Установка stage3..."
cd /mnt/gentoo
wget https://distfiles.gentoo.org/releases/amd64/autobuilds/latest-stage3-amd64-openrc.txt
STAGE3_FILE=$(cat latest-stage3-amd64-openrc.txt | grep -v '^#' | awk '{print $1}')
wget https://distfiles.gentoo.org/releases/amd64/autobuilds/$STAGE3_FILE
tar xpvf stage3*.tar.xz --xattrs-include='*.*' --numeric-owner

# 5. Базовая настройка
echo "Настройка..."
cp /etc/resolv.conf /mnt/gentoo/etc/

# Chroot скрипт
cat > /mnt/gentoo/root/setup.sh << 'EOF'
#!/bin/bash

# Обновление
emerge-webrsync

# USE флаги для runit
echo 'USE="runit -systemd -openrc"' >> /etc/portage/make.conf

# Установка runit
echo 'sys-process/runit' >> /etc/portage/package.accept_keywords
emerge runit

# Ядро
emerge gentoo-sources linux-firmware
cd /usr/src/linux
make defconfig
make -j$(nproc) && make modules_install && make install

# Загрузчик
emerge grub
grub-install /dev/sda
grub-mkconfig -o /boot/grub/grub.cfg

# Пароль root
echo "Установите пароль для root:"
passwd
EOF

chmod +x /mnt/gentoo/root/setup.sh

echo "Теперь выполните:"
echo "mount -t proc proc /mnt/gentoo/proc"
echo "mount --rbind /sys /mnt/gentoo/sys"
echo "mount --rbind /dev /mnt/gentoo/dev"
echo "chroot /mnt/gentoo /bin/bash"
echo
echo "В chroot выполните: /root/setup.sh"