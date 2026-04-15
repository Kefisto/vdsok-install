# VDSok Install — Windows Drivers

Поместите драйверы Windows (.inf, .sys, .cat) в соответствующие подкаталоги.
Они будут автоматически скопированы в `C:\Drivers` при установке Windows
и подхвачены через unattend.xml (PnpCustomizationsNonWinPE).

## Структура

```
drivers/
  ├── network/     # Сетевые адаптеры (Intel I210/I350, Realtek, Broadcom)
  ├── storage/     # Контроллеры дисков (LSI, Adaptec, Intel RST)
  ├── display/     # Видеоадаптеры (Aspeed AST2xxx для серверных BMC/IPMI)
  └── chipset/     # Чипсеты (Intel chipset INF)
```

## Где взять драйверы

### Серверные сетевые карты (обязательно)
- **Intel I210/I350/X710**: https://www.intel.com/content/www/us/en/download/18293/
- **Broadcom NetXtreme**: https://www.broadcom.com/support/download-search
- **Realtek**: https://www.realtek.com/Download

### Серверные RAID-контроллеры
- **LSI MegaRAID**: https://www.broadcom.com/support/download-search
- **Adaptec**: https://www.microchip.com/design-centers/storage

### Серверные видеоадаптеры (BMC)
- **Aspeed AST2400/2500/2600**: обычно входят в Windows Server inbox-драйверы

## Формат

Каждый драйвер должен содержать как минимум:
- `.inf` — файл описания
- `.sys` — бинарный файл драйвера
- `.cat` — каталог цифровой подписи (опционально, но рекомендуется)

Поддиректории внутри каталогов допускаются.
