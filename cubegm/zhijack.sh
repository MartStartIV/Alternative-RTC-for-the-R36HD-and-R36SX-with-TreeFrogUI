#!/bin/sh
# zhijack.sh for r36sx/hd — GENERATED from hijack/zhijack.tpl.sh by
# build_release.sh. Unified for v1.4.0 compatibility with custom performance mods.
mkdir /tmp/zhijack.lock 2>/dev/null || exit 0
cd / || exit 1

if [ "${TF_ZHIJACK_RAM:-0}" != 1 ]; then
    cp "$0" /tmp/treefrog-zhijack.sh 2>/dev/null || exit 1
    chmod 700 /tmp/treefrog-zhijack.sh 2>/dev/null || exit 1
    rm -rf /tmp/zhijack.lock 2>/dev/null
    TF_ZHIJACK_RAM=1 exec /bin/sh /tmp/treefrog-zhijack.sh
    exit 1
fi

if [ -f /mnt/sdcard/log.txt ]; then
    LOG=/mnt/sdcard/log.txt
    mv "$LOG" "$LOG.prev" 2>/dev/null
    : > "$LOG"
    echo "=== zhijack boot [r36hd/sx] $(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null) ===" >> "$LOG"
    if [ -f /proc/meminfo ]; then
        RAM_VAL_BOOT=$(grep "MemAvailable" /proc/meminfo || grep "MemFree" /proc/meminfo)
        echo "[DIAG-BOOT] Hardware RAM disponible en frío: $(echo "$RAM_VAL_BOOT" | awk '{print $2, $3}')" >> "$LOG"
    fi
    sync
else
    LOG=/dev/null
fi

TIME_FILE_REG="/mnt/sdcard/cubegm/time_save.txt"
if [ -f "$TIME_FILE_REG" ]; then
    LAST_SAVED_CLK=$(cat "$TIME_FILE_REG" 2>/dev/null)
    date -s "$LAST_SAVED_CLK" 2>/dev/null
    echo "=== Fake-RTC: Reloj del sistema restaurado a: ($LAST_SAVED_CLK) ===" >> "$LOG"
else
    INIT_CLK_BASE="2026-09-22 12:00:00"
    echo "$INIT_CLK_BASE" > "$TIME_FILE_REG"
    date -s "$INIT_CLK_BASE" 2>/dev/null
    echo "=== Fake-RTC: Archivo no detectado. Inicializado base: ($INIT_CLK_BASE) ===" >> "$LOG"
    sync
fi

echo "NO" > /tmp/psx_executed.txt

if [ -f /mnt/sdcard/cubegm/tfupdate.sh ]; then
    cp /mnt/sdcard/cubegm/tfupdate.sh /tmp/tfupdate.sh 2>/dev/null
    if [ -f /tmp/tfupdate.sh ]; then
        sh /tmp/tfupdate.sh r36sx
        UPDATE_RC=$?
        if [ "$UPDATE_RC" = 10 ]; then
            echo "[UPDATE] Actualización offline instalada con éxito; reiniciando lanzador." >> "$LOG"
            rm -rf /tmp/zhijack.lock; exec /mnt/sdcard/cubegm/zhijack.sh; exit 1
        elif [ "$UPDATE_RC" != 0 ]; then
            echo "[UPDATE-ERROR] Error en actualización offline rc=$UPDATE_RC; continuing version actual." >> "$LOG"
        fi
    fi
fi

kill -STOP $(pidof icube) 2>/dev/null
killall rkgame 2>/dev/null
echo "[SISTEMA] icube congelado de forma segura, rkgame finalizado." >> "$LOG"

cat > /tmp/tfdevice.env <<EOF
TF_DEVICE=R36SX
TF_PANEL_W=640
TF_PANEL_H=480
TF_UI_SCALE=150
TF_ASPECT_NUM=4
TF_ASPECT_DEN=3
TF_ROTATE=0
TF_PRESENT=fbwrite
TF_DRIVER=/mnt/sdcard/cubegm/driver_r36sx.so
EOF
export TF_DEVICE=R36SX TF_PANEL_W=640 TF_PANEL_H=480 TF_UI_SCALE=150

if [ "$TF_DEVICE" = SF3000 ] && [ -f /mnt/sdcard/cubegm/driver_sf3500.so ] && \
   [ "$(head -c4 /mnt/sdcard/cubegm/driver.so 2>/dev/null)" != "$(printf '\177ELF')" ]; then
    sed -i -e 's/^TF_DEVICE=.*/TF_DEVICE=SF3500/' -e 's|^TF_DRIVER=.*|TF_DRIVER=/mnt/sdcard/cubegm/driver_sf3500.so|' /tmp/tfdevice.env
    export TF_DEVICE=SF3500
    echo "[COMPAT] SF3000 con driver cifrado detectado → Redireccionando a driver_sf3500.so" >> "$LOG"
fi
DRV_SAFE=/mnt/sdcard/cubegm/driver_r36sx27.so
DRV_FLAG=/mnt/sdcard/cubegm/driver27.flag
SIGBUS_N=0
if [ -f "$DRV_FLAG" ] && [ -f "$DRV_SAFE" ]; then
    sed -i "s|^TF_DRIVER=.*|TF_DRIVER=$DRV_SAFE|" /tmp/tfdevice.env
    echo "[DRIVER] Variante SEGURA forzada (Botas previas generaron SIGBUS)" >> "$LOG"
fi

export LD_LIBRARY_PATH=/mnt/sdcard/cubegm/lib:/mnt/sdcard/cubegm/usr/lib:$LD_LIBRARY_PATH
for g in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do [ -w "$g" ] && echo performance > "$g" 2>/dev/null; done
for c in /sys/devices/system/cpu/cpu*/cpufreq; do
    mx=$(cat "$c/cpuinfo_max_freq" 2>/dev/null)
    [ -n "$mx" ] && [ -w "$c/scaling_min_freq" ] && echo "$mx" > "$c/scaling_min_freq" 2>/dev/null
done

pidof cubevol >/dev/null 2>&1 || { [ -x /usr/bin/cubevol ] && /usr/bin/cubevol & }
sleep 0.5

TF_NOSLEEP_ADDRS="0x406d24:0xac62bb18 0x40701c:0xae02bb18 0x406b50:0xac44bb18 0x406d84:0xac62bcc8 0x407088:0xae02bcc8 0x406bb0:0xac44bcc8"
if [ -n "$TF_NOSLEEP_ADDRS" ] && grep -q '^disable_sleep=on' /mnt/sdcard/frogui/settings.txt 2>/dev/null; then
    echo 0 > /proc/sys/kernel/yama/ptrace_scope 2>/dev/null
    [ -f /mnt/sdcard/cubegm/nosleep ] && /mnt/sdcard/cubegm/nosleep -w $TF_NOSLEEP_ADDRS >/dev/null 2>&1 &
fi

PICOARCH=/mnt/sdcard/cubegm/picoarch
PICOARCH_HI=/mnt/sdcard/cubegm/picoarch_hi
FROGUI_CORE=/mnt/sdcard/cubegm/cores/frogui_libretro.so
LAUNCH=/tmp/frogui_launch.txt

rm -f /tmp/usb_checked.txt 2>/dev/null
hw_crash_check() { :; }
ITER=0

while true; do
    ITER=$((ITER+1))
    rm -f "$LAUNCH"
    rm -f /mnt/sdcard/cubegm/driver27.flag /mnt/sdcard/cubegm/force_sw.flag 2>/dev/null
    echo "[CICLO] === Iniciando iteración de interfaz nº: $ITER ===" >> "$LOG"

    # --- SUB-RUTINA INTEGRADA FAKE-RTC POR USB OTG ---
    USB_PATH="${TFUPDATE_USB_ROOT:-/media/hdd}"
    USB_TIME_FILE="$USB_PATH/time_save.txt"

    if [ -f "$USB_TIME_FILE" ]; then
        if [ ! -f /tmp/usb_checked.txt ]; then
            USB_CLK_DATA=$(cat "$USB_TIME_FILE" 2>/dev/null)
            SYS_SECONDS=$(date +%s 2>/dev/null || echo 0)
            USB_SECONDS=$(date -d "$USB_CLK_DATA" +%s 2>/dev/null || echo 0)
            echo "[Fake-RTC USB] Pendrive montado detectado. Consola: $SYS_SECONDS seg | USB: $USB_SECONDS seg ($USB_CLK_DATA)" >> "$LOG"

            if [ "$USB_SECONDS" -gt "$SYS_SECONDS" ]; then
                date -s "$USB_CLK_DATA" 2>/dev/null
                echo "$USB_CLK_DATA" > /mnt/sdcard/cubegm/time_save.txt
                echo "[Fake-RTC USB] ¡Reloj del sistema actualizado con éxito a: ($USB_CLK_DATA)!" >> "$LOG"
                sync
            else
                echo "[Fake-RTC USB] Reloj omitido: El sistema tiene una hora igual o más reciente." >> "$LOG"
            fi
            echo "LEIDO" > /tmp/usb_checked.txt
        fi
    else
        rm -f /tmp/usb_checked.txt 2>/dev/null
    fi

    # --- REFRESCO Y PURGA DE MEMORIA RAM (CON TRAZAS FIJAS EN LOG) ---
    [ ! -f /tmp/app_count.txt ] && echo "0" > /tmp/app_count.txt
    APP_COUNTER=$(($(cat /tmp/app_count.txt 2>/dev/null || echo 0)+1))
    echo "$APP_COUNTER" > /tmp/app_count.txt
    WAS_PSX=$(cat /tmp/psx_executed.txt 2>/dev/null || echo "NO")
    
    # Imprimir siempre el estado actual del contador y de la RAM disponible antes de evaluar
    if [ "$LOG" != /dev/null ] && [ -f /proc/meminfo ]; then
        RAM_VAL_NOW=$(grep -E "MemAvailable|MemFree" /proc/meminfo | head -n1)
        echo "[DIAG-RAM] Iteración: $ITER | Contador RAM: $APP_COUNTER / 5 | PSX_Flag: $WAS_PSX | Hardware RAM: $(echo "$RAM_VAL_NOW" | awk '{print $2, $3}')" >> "$LOG"
    fi

    if [ "$APP_COUNTER" -ge 5 ] || [ "$WAS_PSX" = "SI" ]; then
        echo "[DIAG-RAM] Límite o retorno prioritario alcanzado. Forzando purga de drop_caches..." >> "$LOG"
        sync; echo 3 > /proc/sys/vm/drop_caches
        rm -f /tmp/app_count.txt
        if [ "$LOG" != /dev/null ] && [ -f /proc/meminfo ]; then
            RAM_VAL_POST=$(grep -E "MemAvailable|MemFree" /proc/meminfo | head -n1)
            echo "[DIAG-RAM] Recursos liberados con éxito. RAM Post-Purga: $(echo "$RAM_VAL_POST" | awk '{print $2, $3}')" >> "$LOG"
        fi
    fi
    echo "NO" > /tmp/psx_executed.txt

    # --- LANZAMIENTO INTERFAZ FROGUI ---
    echo "[EJECUCIÓN] Iniciando entorno de interfaz FrogUI..." >> "$LOG"
    "$PICOARCH" "$FROGUI_CORE" "$FROGUI_CORE" >> /tmp/treefrog_ui.log 2>&1
    RC=$?
    echo "[RETORNO] Interfaz FrogUI cerrada con código de salida (Return Code) rc=$RC" >> "$LOG"
    
    date "+%Y-%m-%d %H:%M:%S" 2>/dev/null > /mnt/sdcard/cubegm/time_save.txt; sync
    echo "[Fake-RTC]: Hora auto-reemplazada tras cerrar interfaz principal." >> "$LOG"
    if [ "$RC" != 0 ]; then
        echo "[ALERTA-CRASH] FrogUI terminó de forma inesperada o fallida con código rc=$RC" >> "$LOG"
    fi
    if [ "$RC" = 138 ] && [ ! -f "$DRV_FLAG" ] && [ -f "$DRV_SAFE" ]; then
        SIGBUS_N=$((SIGBUS_N+1))
        echo "[CRITICAL] FrogUI arrojó un error SIGBUS ($SIGBUS_N/2)" >> "$LOG"
    fi

    echo "[DEBUG] Comprobando existencia de comando de juego en: $LAUNCH" >> "$LOG"

    if [ -f "$LAUNCH" ]; then
        LAUNCH_KIND=$(sed -n '1p' "$LAUNCH")
        echo "[LAUNCHER] Comando de juego interceptado con éxito. Tipo detectado: $LAUNCH_KIND" >> "$LOG"
        
        if [ "$LAUNCH_KIND" = standalone ]; then
            BIN_PATH=$(sed -n '2p' "$LAUNCH")
            ARG_PATH=$(sed -n '3p' "$LAUNCH")
            rm -f "$LAUNCH"; sleep 0.3
            echo "[STANDALONE] Iniciando binario independiente. Ruta ejecutable: [$BIN_PATH]" >> "$LOG"
            echo "[STANDALONE] Argumento/Rom enviado al binario: [$ARG_PATH]" >> "$LOG"
            
            if echo "$BIN_PATH" | grep -qE "pcsx|ps1|pcsx4all|PS1|PSX"; then
                echo "SI" > /tmp/psx_executed.txt
                echo "[CENTINELA] Emulador PS1 detectado. Desplegando hilo guardián de botones..." >> "$LOG"
                (
                    while pidof "${BIN_PATH##*/}" >/dev/null 2>&1; do
                        if hexdump -vn 4 -e '1/4 "%08x "' /tmp/joy_key 2>/dev/null | grep -qE "0000030f|00000f03|00003c03"; then
                            echo "[CENTINELA-ALERTA] Combinación de escape presionada. Liquidando procesos standalone..." >> "$LOG"
                            killall -9 "${BIN_PATH##*/}" pcsx4all 2>/dev/null; break
                        fi
                        usleep 400000 2>/dev/null || sleep 1
                    done
                ) &
                WATCHDOG_PID=$!
            fi

            if [ -n "$ARG_PATH" ]; then "$BIN_PATH" "$ARG_PATH" >> /tmp/treefrog_ui.log 2>&1 & else "$BIN_PATH" >> /tmp/treefrog_ui.log 2>&1 & fi
            GAME_PID=$!
            wait "$GAME_PID"
            GRC=$?
            [ -n "$WATCHDOG_PID" ] && kill "$WATCHDOG_PID" 2>/dev/null
            echo "[RETORNO-STANDALONE] Proceso independiente finalizado. Código de salida rc=$GRC" >> "$LOG"
            
            date "+%Y-%m-%d %H:%M:%S" 2>/dev/null > /mnt/sdcard/cubegm/time_save.txt; sync
            sleep 0.2; continue
        fi

        CORE_PATH=$(sed -n '1p' "$LAUNCH")
        ROM_PATH=$(sed -n '2p' "$LAUNCH")
        rm -f "$LAUNCH"
        if [ -n "$CORE_PATH" ] && [ -n "$ROM_PATH" ]; then
            sleep 0.3; BIN="$PICOARCH"
            case "$CORE_PATH" in
                *gpsp*|*pcsx*|*ps1*|*ppsspp*|*ffmpeg*|*video*) [ -f "$PICOARCH_HI" ] && BIN="$PICOARCH_HI" ;;
            esac
            
            echo "[LIBRETRO] Lanzando Core via frontend picoarch. Lanzador: [$BIN]" >> "$LOG"
            echo "[LIBRETRO] Core seleccionado: [${CORE_PATH##*/}] | Ruta completa: $CORE_PATH" >> "$LOG"
            echo "[LIBRETRO] Juego/Rom cargado: [${ROM_PATH##*/}]" >> "$LOG"
            
            if [ "$LOG" != /dev/null ] && [ -f /proc/meminfo ]; then
                echo "[DIAG-RAM] Memoria RAM libre antes de entrar al juego: $(grep -E "MemAvailable|MemFree" /proc/meminfo | head -n1 | awk '{print $2, $3}')" >> "$LOG"
            fi

            "$BIN" "$CORE_PATH" "$ROM_PATH" >> /tmp/treefrog_ui.log 2>&1 &
            wait $!
            GRC=$?
            
            echo "[RETORNO-LIBRETRO] Juego cerrado de forma segura. Código de salida de emulación rc=$GRC" >> "$LOG"
            if [ "$GRC" != 0 ] && [ "$GRC" != 137 ]; then
                echo "[ALERTA-EMU] El emulador cerró con un código de error inesperado rc=$GRC. Revisa compatibilidad de la ROM o del Core." >> "$LOG"
            fi
            
            date "+%Y-%m-%d %H:%M:%S" 2>/dev/null > /mnt/sdcard/cubegm/time_save.txt; sync
        fi
    else
        echo "[SISTEMA] Ciclo de interfaz completado de forma pasiva (No se solicitó carga de juegos)." >> "$LOG"
    fi
    sleep 0.2
done
