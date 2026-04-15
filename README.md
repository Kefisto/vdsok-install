# VDSok Install

Скрипт автоматической установки операционных систем на выделенные и виртуальные серверы VDSok из rescue-системы.

## Установка

Одной командой в rescue-системе:

```bash
curl -sSL https://raw.githubusercontent.com/Kefisto/vdsok-install/master/install-vdsok.sh | bash
```

Или через git:

```bash
git clone https://github.com/Kefisto/vdsok-install.git /opt/vdsok-install && /opt/vdsok-install/vdsok-install
```

## Возможности

- Установка из интерактивного меню или полностью автоматический (batch) режим
- Поддержка Software RAID (mdadm): уровни 0, 1, 5, 6, 10
- LVM поверх RAID или обычных разделов
- Шифрование дисков (LUKS)
- UEFI и Legacy BIOS загрузка
- Файловые системы: ext2/ext3/ext4, XFS, Btrfs (с subvolumes)
- GPG-верификация образов ОС
- Post-install скрипты для кастомизации после установки
- Автоматическая настройка сети (IPv4/IPv6)
- **Установка Windows** из Linux rescue (Server 2019/2022/2025, Win10/11)

## Поддерживаемые ОС

### Linux

| Дистрибутив | Статус |
|-------------|--------|
| Debian | Официальная поддержка |
| Ubuntu | Официальная поддержка |
| Arch Linux | Официальная поддержка |
| AlmaLinux | Официальная поддержка |
| Rocky Linux | Официальная поддержка |
| CentOS Stream | Официальная поддержка |
| openSUSE | Официальная поддержка |
| RHEL | Официальная поддержка |

### Windows

| Версия | Редакция |
|--------|----------|
| Windows Server 2025 | Datacenter |
| Windows Server 2022 | Datacenter |
| Windows Server 2019 | Datacenter |
| Windows 11 | Pro / Enterprise |
| Windows 10 | Pro / Enterprise |

### Дополнительно (через post-install скрипты)
- Proxmox VE 7 (на базе Debian Bullseye)
- Proxmox VE 8 (на базе Debian Bookworm)
- Nextcloud

## Быстрый старт

### Интерактивный режим

Загрузитесь в rescue-систему и запустите:

```bash
vdsok-install
```

Откроется меню выбора ОС, после чего будет создан конфигурационный файл для редактирования.

### Автоматический режим

```bash
vdsok-install -a -i /path/to/image.tar.gz -n hostname -r yes -l 1
```

### Использование конфигурационного файла

```bash
vdsok-install -c simple-debian64-raid
```

Готовые конфиги лежат в каталоге `configs/`.

## Параметры командной строки

| Параметр | Описание |
|----------|----------|
| `-h` | Показать справку |
| `-a` | Автоматический режим (без подтверждений) |
| `-c <файл>` | Использовать конфигурационный файл для автоустановки |
| `-x <скрипт>` | Post-install скрипт (выполняется в chroot после установки) |
| `-n <имя>` | Задать hostname |
| `-r <yes\|no>` | Включить/выключить Software RAID |
| `-l <0\|1\|5\|6\|10>` | Уровень RAID |
| `-i <путь>` | Путь к образу ОС (local, ftp, http, https, nfs) |
| `-g` | Обязательная GPG-верификация образа |
| `-p <разделы>` | Определить разметку диска |
| `-v <тома>` | Определить логические тома LVM |
| `-d <диски>` | Устройства для установки (например: sda или sda,sdb) |
| `-K <путь/url>` | Установить SSH-ключи из файла или URL |
| `-t <yes\|no>` | Перенести SSH-ключи из rescue-системы |
| `-G <yes\|no>` | Сгенерировать новые SSH host keys (по умолчанию: yes) |
| `-W <ключ>` | Ключ продукта Windows (для активации вместо KMS) |

## Конфигурационный файл

Пример минимального конфига (`/autosetup`):

```bash
DRIVE1 /dev/sda
DRIVE2 /dev/sdb

SWRAID 1
SWRAIDLEVEL 1

HOSTNAME server.example.com

PART swap swap 4G
PART /boot ext3 1024M
PART / ext4 all

IMAGE /path/to/Debian-latest-amd64-base.tar.gz
```

### Пример с LVM

```bash
DRIVE1 /dev/sda
DRIVE2 /dev/sdb

SWRAID 1
SWRAIDLEVEL 1

HOSTNAME server.example.com

PART /boot ext3 1024M
PART lvm vg0 all

LV vg0 root / ext4 20G
LV vg0 swap swap swap 4G
LV vg0 home /home ext4 10G

IMAGE /path/to/Debian-latest-amd64-base.tar.gz
```

## Установка Windows

Windows устанавливается из Linux rescue-системы с помощью WIM-образов через `wimlib-imagex`.

### Быстрый старт (Windows)

```bash
vdsok-install -a -i /path/to/Windows-Server2022-Datacenter-amd64.wim -n win-server
```

Или через конфиг:

```bash
vdsok-install -c windows-server2022-datacenter
```

### Конфиг Windows

```bash
DRIVE1 /dev/sda
DRIVE2 /dev/sdb

SWRAID 1
SWRAIDLEVEL 1

HOSTNAME win-server.example.com

IMAGE /path/to/Windows-Server2022-Datacenter-amd64.wim
```

Разметка диска для Windows фиксированная:
- **UEFI**: EFI (100MB FAT32) + MSR (16MB) + C: (NTFS, всё место)
- **Legacy BIOS**: System Reserved (350MB NTFS) + C: (NTFS, всё место)

### Что настраивается автоматически

- Статический IP (берётся из rescue-системы)
- Пароль Administrator (из rescue-системы)
- RDP включён + порт 3389 открыт в файрволе
- ICMP (ping) разрешён
- KMS-активация (`kms.vdsok.com`)
- Часовой пояс: MSK (Russian Standard Time)
- Windows Update отключён
- Дисковое зеркалирование через diskpart (если SWRAID=1)

### Зависимости в rescue-системе

Необходимые пакеты (устанавливаются автоматически при их отсутствии):
- `wimtools` — работа с WIM-образами
- `ntfs-3g` — запись на NTFS
- `chntpw` — offline-правка реестра Windows
- `parted` — разметка дисков

### Драйверы

В репозиторий уже включены драйверы сетевых карт:
- **Intel** I210/I350/X710/E810 (PRO1000–PROXGB) — v31.1
- **Realtek** RTL8168/RTL8125/RTL8111

Для скачивания дополнительных драйверов (ASPEED, VirtIO, и др.):

```bash
bash download-drivers.sh          # все драйверы
bash download-drivers.sh --network  # только сетевые
bash download-drivers.sh --virtio   # VirtIO для KVM
```

Драйверы автоматически копируются в `C:\Drivers` и подхватываются при первом запуске.

## KMS-сервер (активация Windows)

VDSok использует собственный KMS-сервер (`kms.vdsok.com`) на базе [vlmcsd](https://github.com/Wind4/vlmcsd) для автоматической активации Windows.

### Быстрое развёртывание KMS

На отдельном VPS (Ubuntu/Debian/CentOS):

```bash
curl -sSL https://raw.githubusercontent.com/Kefisto/vdsok-install/master/kms/deploy.sh | bash
```

Или вручную:

```bash
git clone https://github.com/Kefisto/vdsok-install.git
cd vdsok-install/kms
sudo bash deploy.sh
```

Скрипт автоматически:
- Установит Docker (если отсутствует)
- Соберёт и запустит vlmcsd в контейнере
- Откроет порт 1688/tcp в firewall
- Проверит работоспособность

### DNS

Создайте A-запись `kms.vdsok.com` → IP вашего KMS-сервера.

### Проверка с Windows

```powershell
slmgr /skms kms.vdsok.com
slmgr /ato
```

### Управление

```bash
cd /opt/vdsok-kms
docker compose logs -f        # логи
docker compose restart         # перезапуск
docker compose down            # остановка
docker compose up -d --build   # пересборка
```

## Структура проекта

```
├── vdsok-install              # Главная точка входа
├── vdsok-install.in_screen    # Обёртка для запуска в screen
├── install.sh                 # Основной конвейер установки
├── setup.sh                   # Интерактивное меню
├── autosetup.sh               # Автоматический режим
├── config.sh                  # Глобальная конфигурация
├── functions.sh               # Ядро: разметка, RAID, LVM, распаковка
├── get_options.sh             # Парсинг CLI-аргументов
│
├── debian.sh                  # Дистрибутивные модули Linux
├── ubuntu.sh
├── centos.sh
├── almalinux.sh
├── rockylinux.sh
├── rhel.sh
├── suse.sh
├── archlinux.sh
├── windows.sh                 # Дистрибутивный модуль Windows
│
├── *.functions.sh             # Библиотеки функций
│   ├── windows.functions      #   Windows: WIM, NTFS, реестр, KMS
│   ├── network_config         #   Настройка сети
│   ├── swraid                 #   Software RAID
│   ├── chroot / systemd_nspawn#   Выполнение команд в целевой ОС
│   ├── passwd                 #   Управление паролями
│   ├── report                 #   Телеметрия установки
│   └── ...                    #   и другие
│
├── windows_unattend.xml.template  # Шаблон unattend.xml для Windows
├── configs/                   # Готовые конфигурации (Linux + Windows)
├── download-drivers.sh        # Загрузчик драйверов для rescue-среды
├── drivers/                   # Драйверы Windows (сеть, хранилище, видео)
├── kms/                       # KMS-сервер (vlmcsd в Docker)
│   ├── docker-compose.yml     #   Docker Compose конфигурация
│   ├── Dockerfile             #   Сборка vlmcsd из исходников
│   └── deploy.sh              #   Скрипт быстрого развёртывания
├── gpg/                       # GPG-ключи для верификации образов
├── post-install/              # Post-install скрипты (Proxmox, Nextcloud, Windows)
└── util/                      # Утилиты (хэширование паролей и др.)
```

## Файлы после установки

После успешной установки на целевой системе создаются:

- `/vdsok-install.conf` — использованная конфигурация (без паролей)
- `/vdsok-install.debug` — лог установки для диагностики

## Лицензия

Свободное использование и модификация. Подробности в файле [LICENSE](LICENSE).
