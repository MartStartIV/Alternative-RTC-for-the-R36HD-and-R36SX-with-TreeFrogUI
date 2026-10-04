#!/bin/sh
# zhijack.sh for sf3100 — GENERATED from hijack/zhijack.tpl.sh by
# build_release.sh. Do not edit on the SD; edit the template and regenerate.
#
# Reached via stock boot: rkgame (verified, untouched) -> setting.xml autorun ->
# libemu_tfhijack.so forks this script (rkgame stays alive, keeping the
# cubevol gpio -> /tmp/joy_key input pipeline up). Everything device-specific
# is HARDCODED below — no runtime device detection. /tmp/tfdevice.env is still
# written because picoarch and the standalone frontends (pcsx4all, lgpt,
# pico286) read it.
mkdir /tmp/zhijack.lock 2>/dev/null || exit 0

# Never inherit the stock launcher's SD-card working directory.  USB mode
# must unmount /mnt/sdcard before exporting its block device; a shell (or
# child launcher) whose cwd is on that filesystem makes umount fail with
# EBUSY even after the UI has exited.
cd / || exit 1

# Re-exec the launcher from RAM.  BusyBox ash keeps the file descriptor for
# the script it is interpreting; if this remains the SD copy, USB mode cannot
# unmount the card even after all child processes exit.
if [ "${TF_ZHIJACK_RAM:-0}" != 1 ]; then
    cp "$0" /tmp/treefrog-zhijack.sh 2>/dev/null || exit 1
    chmod 700 /tmp/treefrog-zhijack.sh 2>/dev/null || exit 1
    # The RAM copy must be able to reacquire the single-instance lock.
    rm -rf /tmp/zhijack.lock 2>/dev/null
    TF_ZHIJACK_RAM=1 exec /bin/sh /tmp/treefrog-zhijack.sh
    exit 1
fi

# Diagnostics are OPT-IN so we don't chew the SD card in normal use: logging is
# ON only if the user pre-created /mnt/sdcard/log.txt. Otherwise LOG=/dev/null and
# every write below is a no-op (and picoarch's own dbg_log is gated the same way,
# on log.txt existing). To debug: drop an empty log.txt on the card and reboot.
if [ -f /mnt/sdcard/log.txt ]; then
    LOG=/mnt/sdcard/log.txt
    mv "$LOG" "$LOG.prev" 2>/dev/null
    : > "$LOG"
    echo "=== zhijack boot [sf3100] $(date '+%H:%M:%S' 2>/dev/null) ===" >> "$LOG"
    sync
else
    LOG=/dev/null
fi

# ==============================================================================
# INTEGRACIÓN FAKE-RTC: RESTAURACIÓN DEL RELOJ EN INICIO DE SISTEMA
# ==============================================================================
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

# ==============================================================================
# INTEGRACIÓN FAKE-RTC: FUNCIÓN DE CONTROL Y SALVAGUARDA (SD / USB OTG)
# ==============================================================================
guardar_y_sincronizar_rtc() {
    # Guardar estampa de tiempo actual en la SD del sistema
    date "+%Y-%m-%d %H:%M:%S" 2>/dev/null > /mnt/sdcard/cubegm/time_save.txt; sync
    echo "[Fake-RTC]: Hora auto-reemplazada tras cerrar interfaz principal o juego." >> "$LOG"

    # Procesar verificación de reloj por almacenamiento externo
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
}
# ==============================================================================

if [ -f /mnt/sdcard/cubegm/tfupdate.sh ]; then
    cp /mnt/sdcard/cubegm/tfupdate.sh /tmp/tfupdate.sh 2>/dev/null
    if [ -f /tmp/tfupdate.sh ]; then
        sh /tmp/tfupdate.sh sf3100
        UPDATE_RC=$?
        if [ "$UPDATE_RC" = 10 ]; then
            echo "offline update installed; restarting launcher" >> "$LOG"
            rm -rf /tmp/zhijack.lock
            exec /mnt/sdcard/cubegm/zhijack.sh
            exit 1
        elif [ "$UPDATE_RC" != 0 ]; then
            echo "offline update failed rc=$UPDATE_RC; continuing current version" >> "$LOG"
        fi
    fi
fi

kill -STOP $(pidof icube) 2>/dev/null
killall rkgame 2>/dev/null
echo "icube frozen, rkgame killed" >> "$LOG"

cat > /tmp/tfdevice.env <<EOF
TF_DEVICE=SF3500
TF_PANEL_W=854
TF_PANEL_H=480
TF_UI_SCALE=150
TF_ASPECT_NUM=16
TF_ASPECT_DEN=9
TF_ROTATE=90
TF_PRESENT=dispframe
TF_DRIVER=/mnt/sdcard/cubegm/driver_sf3500.so
EOF
export TF_DEVICE=SF3500 TF_PANEL_W=854 TF_PANEL_H=480 TF_UI_SCALE=150

if [ "$TF_DEVICE" = SF3000 ] && [ -f /mnt/sdcard/cubegm/driver_sf3500.so ] && \
   [ "$(head -c4 /mnt/sdcard/cubegm/driver.so 2>/dev/null)" != "$(printf '\177ELF')" ]; then
    sed -i -e 's/^TF_DEVICE=.*/TF_DEVICE=SF3500/' \
           -e 's|^TF_DRIVER=.*|TF_DRIVER=/mnt/sdcard/cubegm/driver_sf3500.so|' /tmp/tfdevice.env
    export TF_DEVICE=SF3500
    echo "SF3000 with encrypted (SF3500-class) driver detected → using driver_sf3500.so" >> "$LOG"
fi

echo "processes at boot:" >> "$LOG"; ps >> "$LOG" 2>&1; [ "$LOG" = /dev/null ] || sync

export LD_LIBRARY_PATH=/mnt/sdcard/cubegm/lib:/mnt/sdcard/cubegm/usr/lib:$LD_LIBRARY_PATH
for g in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
    [ -w "$g" ] && echo performance > "$g" 2>/dev/null
done
for c in /sys/devices/system/cpu/cpu*/cpufreq; do
    mx=$(cat "$c/cpuinfo_max_freq" 2>/dev/null)
    [ -n "$mx" ] && [ -w "$c/scaling_min_freq" ] && echo "$mx" > "$c/scaling_min_freq" 2>/dev/null
done
if [ "$LOG" != /dev/null ]; then
    echo "CPU frequency policy after performance request:" >> "$LOG"
    for c in /sys/devices/system/cpu/cpu*/cpufreq; do
        echo "$c governor=$(cat "$c/scaling_governor" 2>/dev/null) cur=$(cat "$c/scaling_cur_freq" 2>/dev/null) min=$(cat "$c/scaling_min_freq" 2>/dev/null) max=$(cat "$c/scaling_max_freq" 2>/dev/null) hwmax=$(cat "$c/cpuinfo_max_freq" 2>/dev/null)" >> "$LOG"
    done
fi

pidof cubevol >/dev/null 2>&1 || { [ -x /usr/bin/cubevol ] && /usr/bin/cubevol & }
sleep 0.5

TF_NOSLEEP_ADDRS="0x406d84:0xac62bcc8 0x407088:0xae02bcc8 0x406bb0:0xac44bcc8"
if [ -n "$TF_NOSLEEP_ADDRS" ] && grep -q '^disable_sleep=on' /mnt/sdcard/frogui/settings.txt 2>/dev/null; then
    echo 0 > /proc/sys/kernel/yama/ptrace_scope 2>/dev/null
    [ -f /mnt/sdcard/cubegm/nosleep ] && /mnt/sdcard/cubegm/nosleep -w $TF_NOSLEEP_ADDRS >/dev/null 2>&1 &
fi

PICOARCH=/mnt/sdcard/cubegm/picoarch
PICOARCH_HI=/mnt/sdcard/cubegm/picoarch_hi
FROGUI_CORE=/mnt/sdcard/cubegm/cores/frogui_libretro.so
LAUNCH=/tmp/frogui_launch.txt

rm -f /tmp/usb_checked.txt 2>/dev/null
ITER=0
while true; do
    ITER=$((ITER+1))
    rm -f "$LAUNCH"
    killall rkgame 2>/dev/null
    echo "--- iter $ITER: frogui ---" >> "$LOG"
    # Keep child stdout off the SD.  USB mode must be able to unmount even
    # when diagnostics are enabled via /mnt/sdcard/log.txt.
    "$PICOARCH" "$FROGUI_CORE" "$FROGUI_CORE" >> /tmp/treefrog_ui.log 2>&1
    RC=$?
    echo "frogui exited rc=$RC" >> "$LOG"

    # PUNTO 1: Interfaz cerrada, procesamos guardado y sincronización
    guardar_y_sincronizar_rtc

    if [ -f "$LAUNCH" ]; then
        LAUNCH_KIND=$(sed -n '1p' "$LAUNCH")
        if [ "$LAUNCH_KIND" = standalone ]; then
            BIN_PATH=$(sed -n '2p' "$LAUNCH")
            ARG_PATH=$(sed -n '3p' "$LAUNCH")
            rm -f "$LAUNCH"
            sleep 0.3
            echo "--- iter $ITER: standalone [$BIN_PATH] ---" >> "$LOG"
            if [ -n "$ARG_PATH" ]; then
                "$BIN_PATH" "$ARG_PATH" >> /tmp/treefrog_ui.log 2>&1
            else
                "$BIN_PATH" >> /tmp/treefrog_ui.log 2>&1
            fi
            
            # PUNTO 2: Juego Standalone cerrado, guardamos hora antes de reiniciar ciclo
            guardar_y_sincronizar_rtc
            sleep 0.2
            continue
        fi
        CORE_PATH=$(sed -n '1p' "$LAUNCH")
        killall rkgame 2>/dev/null
        ROM_PATH=$(sed -n '2p' "$LAUNCH")
        rm -f "$LAUNCH"
        if [ -n "$CORE_PATH" ] && [ -n "$ROM_PATH" ]; then
            sleep 0.3
            BIN="$PICOARCH"
            case "$CORE_PATH" in
                *gpsp*|*pcsx*|*ps1*|*ppsspp*) [ -f "$PICOARCH_HI" ] && BIN="$PICOARCH_HI" ;;
            esac
            echo "--- iter $ITER: game [$CORE_PATH] via $BIN ---" >> "$LOG"
            echo "launcher pid=$$ exe=$(readlink /proc/$$/exe 2>/dev/null)" >> "$LOG"
            echo "bin stat: $(ls -l "$BIN" 2>/dev/null)" >> "$LOG"
            echo "core stat: $(ls -l "$CORE_PATH" 2>/dev/null)" >> "$LOG"
            echo "rom stat: $(ls -l "$ROM_PATH" 2>/dev/null)" >> "$LOG"
            echo "device env: $(tr '\n' ' ' < /tmp/tfdevice.env 2>/dev/null)" >> "$LOG"
            echo "pre-game ps:" >> "$LOG"; ps >> "$LOG" 2>&1
            # Record the exact child executable/PID; stock rkgame and the
            # TreeFrogUI child can otherwise produce indistinguishable driver
            # messages in the shared log.
            "$BIN" "$CORE_PATH" "$ROM_PATH" >> /tmp/treefrog_ui.log 2>&1 &
            GAME_PID=$!
            GAME_EXE=$(readlink "/proc/$GAME_PID/exe" 2>/dev/null)
            echo "game pid=$GAME_PID exe=$GAME_EXE" >> "$LOG"
            echo "game cmdline: $(tr '\0' ' ' < /proc/$GAME_PID/cmdline 2>/dev/null)" >> "$LOG"
            echo "game status: $(tr '\n' ' ' < /proc/$GAME_PID/status 2>/dev/null)" >> "$LOG"
            wait "$GAME_PID"
            GRC=$?
            echo "game exited rc=$GRC" >> "$LOG"
            
            # PUNTO 3: Juego Libretro (Picoarch) cerrado, guardamos hora
            guardar_y_sincronizar_rtc
        fi
    fi
    sleep 0.2
done
