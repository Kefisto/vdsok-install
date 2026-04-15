# VDSok Install — Windows Drivers

Драйверы Windows (.inf, .sys, .cat) автоматически копируются в `C:\Drivers`
при установке и подхватываются через unattend.xml (PnpCustomizationsNonWinPE).

## Быстрый старт

Из rescue-среды Linux запустите автоматический загрузчик:

```bash
bash download-drivers.sh          # скачать все драйверы
bash download-drivers.sh --network  # только сетевые
bash download-drivers.sh --virtio   # только VirtIO (для KVM)
```

## Предустановленные драйверы

```
drivers/
  └── network/
      ├── intel/          # Intel I210/I350/X710/E810 (PRO1000–PROXGB) — v31.1
      └── realtek/        # Realtek RTL8168/RTL8125/RTL8111
```

## Дополнительные (скачиваются через download-drivers.sh)

```
drivers/
  ├── network/
  │   └── virtio/         # VirtIO NetKVM (QEMU/KVM)
  ├── storage/
  │   ├── broadcom/       # Broadcom/LSI MegaRAID (inbox)
  │   └── virtio/         # VirtIO viostor/vioscsi
  ├── display/
  │   └── aspeed/         # ASPEED AST2400/2500/2600 BMC VGA
  └── chipset/
      └── intel/          # Intel Chipset INF (inbox)
```

## Ручная загрузка

| Категория | Драйвер | Ссылка |
|-----------|---------|--------|
| Сеть | Intel I210/I350/X710/E810 | https://www.intel.com/content/www/us/en/download/838943/ |
| Сеть | Realtek RTL8168/8125 | https://www.realtek.com/Download/List?cate_id=584 |
| Сеть | Broadcom NetXtreme | https://www.broadcom.com/support/download-search |
| RAID | Broadcom MegaRAID | https://www.broadcom.com/support/download-search |
| Дисплей | ASPEED AST2xxx | https://www.aspeedtech.com/support_driver/ |
| Чипсет | Intel Chipset INF | https://www.intel.com/content/www/us/en/download/19347/ |
| Виртуализация | VirtIO (KVM) | https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/stable-virtio/ |

## Формат

Каждый драйвер должен содержать:
- `.inf` — файл описания
- `.sys` — бинарный файл драйвера
- `.cat` — каталог цифровой подписи (рекомендуется)

Поддиректории внутри каталогов допускаются.
