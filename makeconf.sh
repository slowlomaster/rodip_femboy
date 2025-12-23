#!/bin/bash
# fix-partitions.sh - исправление проблем с разделами

DISK="/dev/sda"

echo "Исправление проблем с разделами на $DISK"

# 1. Полностью очищаем диск
echo "Шаг 1: Очистка диска..."
sgdisk -Z $DISK 2>/dev/null
wipefs -a $DISK 2>/dev/null
dd if=/dev/zero of=$DISK bs=1M count=100 2>/dev/null
sync

# 2. Создаем новую GPT таблицу
echo "Шаг 2: Создание новой GPT таблицы..."
parted -s $DISK mklabel gpt

# 3. Создаем разделы с правильными вычислениями
echo "Шаг 3: Создание разделов..."

# Получаем размер диска в MB
DISK_SIZE=$(parted -s $DISK unit MB print | grep "Disk /" | awk '{print $3}' | sed 's/MB//')

# Вычисляем границы
BOOT_START=1
BOOT_END=513
ROOT_START=513
ROOT_END=$((BOOT_END + 20480))  # 20GB = 20480MB
SWAP_START=$ROOT_END
SWAP_END=$((SWAP_START + 4096))  # 4GB = 4096MB

echo "Размер диска: ${DISK_SIZE}MB"
echo "Boot: ${BOOT_START}-${BOOT_END}MB"
echo "Root: ${ROOT_START}-${ROOT_END}MB"
echo "Swap: ${SWAP_START}-${SWAP_END}MB"

# Проверяем, что все влезает
if [ $SWAP_END -gt $DISK_SIZE ]; then
    echo "Ошибка: разделы не помещаются на диск!"
    exit 1
fi

# Создаем разделы
parted -s $DISK unit MB mkpart primary fat32 ${BOOT_START} ${BOOT_END}
parted -s $DISK set 1 esp on
parted -s $DISK unit MB mkpart primary ext4 ${ROOT_START} ${ROOT_END}
parted -s $DISK unit MB mkpart primary linux-swap ${SWAP_START} ${SWAP_END}

# 4. Показываем результат
echo "Шаг 4: Результат:"
parted -s $DISK unit MB print
lsblk $DISK

echo "Готово! Теперь можно форматировать разделы."