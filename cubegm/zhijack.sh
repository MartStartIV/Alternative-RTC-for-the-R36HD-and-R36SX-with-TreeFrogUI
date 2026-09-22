#!/bin/sh
# zhijack.sh for r36sx/hd — GENERATED from hijack/zhijack.tpl.sh by
# build_release.sh. Unified for v1.4.0 compatibility with custom performance mods.
#
# Alternative RTC solution implemented by MartStartIV
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
    echo "=== zhijack boot [r36hd/sx] $(date '+%H:%M:%S' 2>/dev/null) ===" >> "$LOG"
    
    # [MEJORA REGISTRO - PRESERVADO] Mostrar la RAM disponible justo antes de iniciar la interfaz
    if [ -f /proc/meminfo ]; then
        RAM_VAL_BOOT=$(grep "MemAvailable" /proc/meminfo || grep "MemFree" /proc/meminfo)
        RAM_NUM_BOOT=$(echo "$RAM_VAL_BOOT" | awk '{print $2, $3}')
        echo "Hardware RAM disponible en frío (Pre-Boot) es de: $RAM_NUM_BOOT" >> "$LOG"
    fi
    
    sync
else
    LOG=/dev/null
fi

# =========================================================================
# [NUEVA SUB-RUTINA NATIVA INTEGRADA FAKE-RTC - LECTURA EN FRÍO]
# =========================================================================
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
# =========================================================================

# Flag virtual en RAM para evaluar el retorno prioritario de pcsx4all
echo "NO" > /tmp/psx_executed.txt

# Offline updates: users drop the official update.zip into the SD-card root.
# Run a /tmp copy so the updater can atomically replace its own
# installed file. Status 10 means success: restart through the newly installed
# device launcher. Failures keep both the current installation and update ZIP.
if [ -f /mnt/sdcard/cubegm/tfupdate.sh ]; then
    cp /mnt/sdcard/cubegm/tfupdate.sh /tmp/tfupdate.sh 2>/dev/null
    if [ -f /tmp/tfupdate.sh ]; then
        sh /tmp/tfupdate.sh r36sx
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

# Freeze icube (the respawner), THEN kill rkgame. Devices that boot through
# icube (R36SX, SF3000, GB350) respawn any killed rkgame, and the fresh
# instance redraws the stock menu over our frames (flicker/ghosting); a merely
# frozen rkgame (SIGSTOP) glitched the display too. Frozen icube = no respawn;
# dead rkgame = nothing reacting to SELECT+START (its stock exit-game hotkey).
# On rkgame-direct devices (SF3500/HD/SF3100) there is no icube: STOP no-ops.
kill -STOP $(pidof icube) 2>/dev/null
killall rkgame 2>/dev/null
echo "icube frozen, rkgame killed" >> "$LOG"

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

# Some "SF3000"-branded units are really SF3500-class hardware (the "v3" / HDMI
# variant): same 854x480 panel geometry, but the SF3500 audio+display driver. The
# reliable tell is the stock driver.so format: classic SF3000 ships a PLAIN ELF
# driver, SF3500-class ships an ENCRYPTED one. If we're booting as SF3000 but the
# stock driver is encrypted, switch to driver_sf3500.so. Otherwise the classic
# SF3000 driver's audio (AUDDEC/I2SO) init fails on this hardware and picoarch
# SIGSEGVs on the NULL sound handle (+0x270) → black-screen boot loop.
if [ "$TF_DEVICE" = SF3000 ] && [ -f /mnt/sdcard/cubegm/driver_sf3500.so ] && \
   [ "$(head -c4 /mnt/sdcard/cubegm/driver.so 2>/dev/null)" != "$(printf '\177ELF')" ]; then
    sed -i -e 's/^TF_DEVICE=.*/TF_DEVICE=SF3500/' \
           -e 's|^TF_DRIVER=.*|TF_DRIVER=/mnt/sdcard/cubegm/driver_sf3500.so|' /tmp/tfdevice.env
    export TF_DEVICE=SF3500
    echo "SF3000 with encrypted (SF3500-class) driver detected → using driver_sf3500.so" >> "$LOG"
fi

# R36SX driver self-selection. Some kernels (v2.7-class, but firmware traits   
# vary WITHIN 2.6/2.7, so no offline identification works) make the full v2.6  
# driver SIGBUS in hcge_open. Measure instead of guessing: run the full driver;
# if frogui dies with SIGBUS twice, switch permanently (marker file on SD) to  
# driver_r36sx27.so, the variant with the crashing 2D engine stubbed out.      
DRV_SAFE=/mnt/sdcard/cubegm/driver_r36sx27.so
DRV_FLAG=/mnt/sdcard/cubegm/driver27.flag
SIGBUS_N=0
if [ -f "$DRV_FLAG" ] && [ -f "$DRV_SAFE" ]; then
    sed -i "s|^TF_DRIVER=.*|TF_DRIVER=$DRV_SAFE|" /tmp/tfdevice.env
    echo "driver: SAFE variant (previous boots hit SIGBUS)" >> "$LOG"
fi
echo "processes at boot:" >> "$LOG"; ps >> "$LOG" 2>&1; [ "$LOG" = /dev/null ] || sync

export LD_LIBRARY_PATH=/mnt/sdcard/cubegm/lib:/mnt/sdcard/cubegm/usr/lib:$LD_LIBRARY_PATH
# CPU [MEJORA PERFORMANCE - PRESERVADO]: force max-performance governor (helps every emulator).
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
# Input: cubevol (reads gpio -> /tmp/joy_key shm) must be up; picoarch reads the shm.
pidof cubevol >/dev/null 2>&1 || { [ -x /usr/bin/cubevol ] && /usr/bin/cubevol & }
sleep 0.5
# Optional: disable the power-button sleep (FrogUI Settings -> "Disable Sleep",
# default off, applies after restart). Live-patch every cubevol instance in RAM
# so the on-disk binary stays byte-identical -> passes SF3500 boot verification.
# The watcher also handles a genuine daemon crash/respawn.
# [DIRECCIONES ACTUALIZADAS V1.4.0]: Se incluye el mapeo expandido de memoria oficial.
TF_NOSLEEP_ADDRS="0x406d24:0xac62bb18 0x40701c:0xae02bb18 0x406b50:0xac44bb18 0x406d84:0xac62bcc8 0x407088:0xae02bcc8 0x406bb0:0xac44bcc8"
if [ -n "$TF_NOSLEEP_ADDRS" ] && grep -q '^disable_sleep=on' /mnt/sdcard/frogui/settings.txt 2>/dev/null; then
    echo 0 > /proc/sys/kernel/yama/ptrace_scope 2>/dev/null
    [ -f /mnt/sdcard/cubegm/nosleep ] && /mnt/sdcard/cubegm/nosleep -w $TF_NOSLEEP_ADDRS >/dev/null 2>&1 &
fi

PICOARCH=/mnt/sdcard/cubegm/picoarch
PICOARCH_HI=/mnt/sdcard/cubegm/picoarch_hi
FROGUI_CORE=/mnt/sdcard/cubegm/cores/frogui_libretro.so
LAUNCH=/tmp/frogui_launch.txt

# [MODIFICACIÓN DE SEGURIDAD MODS - PRESERVADO]: Se anula por completo la función hw_crash_check.
hw_crash_check() { :; }

ITER=0
while true; do
    ITER=$((ITER+1))
    rm -f "$LAUNCH"
    
    # [TRAZA AL PRINCIPIO] Verificar estado inicial de la iteración
    echo "[DEBUG] === Iniciando ciclo iteración: $ITER ===" >> "$LOG"
    
    # [MODIFICACIÓN DE SEGURIDAD MODS - PRESERVADO]: Eliminación proactiva e inmediata de banderas accidentales.
    rm -f /mnt/sdcard/cubegm/driver27.flag /mnt/sdcard/cubegm/force_sw.flag 2>/dev/null

    # =========================================================================
    # [BLOQUE DE CONTROL DE RAM UBICADO AL INICIO DEL CICLO - ADAPTADO A LÍMITE 5]
    # =========================================================================
    [ ! -f /tmp/app_count.txt ] && echo "0" > /tmp/app_count.txt
    
    APP_COUNTER=$(cat /tmp/app_count.txt 2>/dev/null || echo 0)
    APP_COUNTER=$((APP_COUNTER+1))
    echo "$APP_COUNTER" > /tmp/app_count.txt
    
    # Comprobamos si venimos de lanzar pcsx4all
    WAS_PSX=$(cat /tmp/psx_executed.txt 2>/dev/null || echo "NO")
    echo "Retorno o inicio detectado. Iteración de interfaz: $ITER. Contador de RAM: $APP_COUNTER / 5" >> "$LOG"
    echo "Se está ejecutando pcsx4all en el último retorno: $WAS_PSX" >> "$LOG"

    # Capturamos la memoria libre real antes de evaluar la limpieza
    if [ -f /proc/meminfo ] && [ "$LOG" != /dev/null ]; then
        RAM_VAL=$(grep "MemAvailable" /proc/meminfo || grep "MemFree" /proc/meminfo)
        RAM_NUM=$(echo "$RAM_VAL" | awk '{print $2, $3}')
        echo "Hardware RAM disponible antes de evaluar limpieza: $RAM_NUM" >> "$LOG"
    fi

    # Límite ajustado de manera limpia a 5 ejecuciones consecutivas o purga inmediata por PS1
    if [ "$APP_COUNTER" -ge 5 ] || [ "$WAS_PSX" = "SI" ]; then
        if [ "$WAS_PSX" = "SI" ]; then
            echo "Retorno prioritario detectado desde pcsx4all. Aplicando refresco agresivo..." >> "$LOG"
        else
            echo "Límite alcanzado ($APP_COUNTER). Aplicando refresco de recursos de memoria..." >> "$LOG"
        fi
        sync
        echo 3 > /proc/sys/vm/drop_caches
        rm -f /tmp/app_count.txt
        echo "Contador y caché de RAM reiniciados exitosamente." >> "$LOG"
        
        # [TU MEJORA REGISTRO - PRESERVADO] Captura la RAM libre inmediatamente después de limpiar la caché
        if [ -f /proc/meminfo ] && [ "$LOG" != /dev/null ]; then
            RAM_VAL_POST=$(grep "MemAvailable" /proc/meminfo || grep "MemFree" /proc/meminfo)
            RAM_NUM_POST=$(echo "$RAM_VAL_POST" | awk '{print $2, $3}')
            echo "Hardware RAM disponible justo en este momento (Post-Limpieza): $RAM_NUM_POST" >> "$LOG"
        fi
    fi
    
    # Reiniciar estado para ciclos comunes
    echo "NO" > /tmp/psx_executed.txt
    # =========================================================================
    echo "--- iter $ITER: frogui ---" >> "$LOG"
    echo "[DEBUG] Lanzando interfaz FrogUI principal..." >> "$LOG"
    # [COMPATIBILIDAD V1.4.0 OBLIGATORIA]: Redirección segura a memoria RAM para evitar bloqueo de la SD en Modo USB.
    "$PICOARCH" "$FROGUI_CORE" "$FROGUI_CORE" >> /tmp/treefrog_ui.log 2>&1
    RC=$?
    echo "frogui exited rc=$RC" >> "$LOG"
    hw_crash_check "$RC"
    
    # =========================================================================
    # [FAKE-RTC NATIVO - GUARDADO INTERFAZ]
    # =========================================================================
    date "+%Y-%m-%d %H:%M:%S" 2>/dev/null > /mnt/sdcard/cubegm/time_save.txt
    sync
    echo "[Fake-RTC]: Hora auto-reemplazada tras cerrar interfaz principal." >> "$LOG"
    # =========================================================================
    
    # [TRAZA INTERMEDIA] Verificar si la interfaz cerró con error o de forma limpia
    if [ "$RC" != 0 ]; then
        echo "[ALERTA] FrogUI cerró de forma imprevista con código de error rc=$RC" >> "$LOG"
    fi
    # [MODIFICACIÓN DE SEGURIDAD MODS - PRESERVADO]: Se desactivan las líneas reactivas del error 138 (SIGBUS).
    if [ "$RC" = 138 ] && [ ! -f "$DRV_FLAG" ] && [ -f "$DRV_SAFE" ]; then
        SIGBUS_N=$((SIGBUS_N+1))
        if [ "$SIGBUS_N" -ge 2 ]; then
            echo "driver: 2x SIGBUS detectado - Ejecución forzada continua protegida" >> "$LOG"
            sync
        fi
    fi

    # [TRAZA DIAGNÓSTICA PRE-LANZAMIENTO]
    echo "[DEBUG] Comprobando existencia de comando de juego en: $LAUNCH" >> "$LOG"

    if [ -f "$LAUNCH" ]; then
        LAUNCH_KIND=$(sed -n '1p' "$LAUNCH")
        echo "[DEBUG] Tipo de lanzamiento detectado en archivo: LAUNCH_KIND=$LAUNCH_KIND" >> "$LOG"
        
        # =========================================================================
        # [RUTA STANDALONE ADAPTADA - ADAPTACIÓN EN PARALELO DEL DESARROLLADOR]
        # =========================================================================
        if [ "$LAUNCH_KIND" = standalone ]; then
            BIN_PATH=$(sed -n '2p' "$LAUNCH")
            ARG_PATH=$(sed -n '3p' "$LAUNCH")
            rm -f "$LAUNCH"
            sleep 0.3
            
            echo "--- iter $ITER: standalone [$BIN_PATH] ---" >> "$LOG"
            echo "[DEBUG] DatosStandalone - Executable: $BIN_PATH | Rom: $ARG_PATH" >> "$LOG"
            
            # Si el ejecutable es el emulador de PS1, activamos bandera y centinela
            if echo "$BIN_PATH" | grep -qE "pcsx|ps1|pcsx4all|PS1|PSX"; then
                echo "SI" > /tmp/psx_executed.txt
                echo "Activando centinela de escape para PS1 Standalone..." >> "$LOG"
                (
                    echo "[DEBUG-Centinela] Hilo de pánico inicializado con éxito." >> "$LOG"
                    sleep 2
                    while pidof "${BIN_PATH##*/}" >/dev/null 2>&1; do
                        KEYS=$(hexdump -vn 4 -e '1/4 "%08x "' /tmp/joy_key 2>/dev/null)
                        if echo "$KEYS" | grep -qE "0000030f|00000f03|00003c03"; then
                            echo "[ALERTA] Botón de pánico presionado. Liquidando emulador Standalone..." >> "$LOG"
                            killall -9 "${BIN_PATH##*/}" 2>/dev/null
                            killall -9 pcsx4all 2>/dev/null
                            break
                        fi
                        usleep 400000 2>/dev/null || sleep 1
                    done
                    echo "[DEBUG-Centinela] Hilo de pánico cerrado." >> "$LOG"
                ) &
                WATCHDOG_PID=$!
            fi

            echo "[DEBUG] Ejecutando comando binario Standalone en segundo plano..." >> "$LOG"
            if [ -n "$ARG_PATH" ]; then
                "$BIN_PATH" "$ARG_PATH" >> /tmp/treefrog_ui.log 2>&1 &
            else
                "$BIN_PATH" >> /tmp/treefrog_ui.log 2>&1 &
            fi
            GAME_PID=$!
            
            echo "game pid=$GAME_PID exe=$BIN_PATH" >> "$LOG"
            echo "pre-game ps:" >> "$LOG"; ps >> "$LOG" 2>&1
            
            echo "[DEBUG] Esperando (wait) liberación de proceso Standalone PID: $GAME_PID" >> "$LOG"
            wait "$GAME_PID"
            GRC=$?
            
            echo "[DEBUG] Proceso Standalone liberado de memoria. Retorno rc=$GRC" >> "$LOG"
            [ -n "$WATCHDOG_PID" ] && kill "$WATCHDOG_PID" 2>/dev/null
            echo "game exited rc=$GRC" >> "$LOG"
            hw_crash_check "$GRC"
            
            # =========================================================================
            # [FAKE-RTC NATIVO - GUARDADO POST STANDALONE]
            # =========================================================================
            date "+%Y-%m-%d %H:%M:%S" 2>/dev/null > /mnt/sdcard/cubegm/time_save.txt
            sync
            echo "[Fake-RTC]: Hora auto-reemplazada tras cerrar emulador independiente." >> "$LOG"
            # =========================================================================
            
            sleep 0.2
            continue
        fi
        # =========================================================================

        # ---------------------------------------------------------------------
        # RUTA LIBRETRO ORIGINAL (TU SEMÁNTICA COMPLETA DE ANTES PARA CORES JUEGOS)
        # ---------------------------------------------------------------------
        CORE_PATH=$(sed -n '1p' "$LAUNCH")
        ROM_PATH=$(sed -n '2p' "$LAUNCH")
        rm -f "$LAUNCH"
        if [ -n "$CORE_PATH" ] && [ -n "$ROM_PATH" ]; then
            sleep 0.3
            BIN="$PICOARCH"
            
            # [MEJORA DE ALTO RENDIMIENTO MODS - PRESERVADO] Mantiene soporte HI y emuladores pesados (con ppsspp oficial v1.4.0)
            case "$CORE_PATH" in
                *gpsp*|*pcsx*|*ps1*|*ppsspp*|*ffmpeg*|*video*) [ -f "$PICOARCH_HI" ] && BIN="$PICOARCH_HI" ;;
            esac
            
            echo "--- iter $ITER: game [$CORE_PATH] via $BIN ---" >> "$LOG"
            echo "launcher pid=$$ exe=$(readlink /proc/$$/exe 2>/dev/null)" >> "$LOG"
            echo "bin stat: $(ls -l "$BIN" 2>/dev/null)" >> "$LOG"
            echo "core stat: $(ls -l "$CORE_PATH" 2>/dev/null)" >> "$LOG"
            echo "rom stat: $(ls -l "$ROM_PATH" 2>/dev/null)" >> "$LOG"
            echo "device env: $(tr '\n' ' ' < /tmp/tfdevice.env 2>/dev/null)" >> "$LOG"
            echo "pre-game ps:" >> "$LOG"; ps >> "$LOG" 2>&1
            
            echo "[DEBUG] Lanzando Core Libretro ($BIN) en segundo plano..." >> "$LOG"
            "$BIN" "$CORE_PATH" "$ROM_PATH" >> /tmp/treefrog_ui.log 2>&1 &
            GAME_PID=$!
            GAME_EXE=$(readlink "/proc/$GAME_PID/exe" 2>/dev/null)
            echo "game pid=$GAME_PID exe=$GAME_EXE" >> "$LOG"
            echo "game cmdline: $(tr '\0' ' ' < /proc/$GAME_PID/cmdline 2>/dev/null)" >> "$LOG"
            echo "game status: $(tr '\n' ' ' < /proc/$GAME_PID/status 2>/dev/null)" >> "$LOG"
            
            echo "[DEBUG] Esperando (wait) liberación de Core Libretro PID: $GAME_PID" >> "$LOG"
            wait "$GAME_PID"
            GRC=$?
            echo "[DEBUG] Proceso Libretro liberado de memoria. Retorno rc=$GRC" >> "$LOG"
            echo "game exited rc=$GRC" >> "$LOG"
            hw_crash_check "$GRC"
            
            # =========================================================================
            # [FAKE-RTC NATIVO - GUARDADO POST LIBRETRO]
            # =========================================================================
            date "+%Y-%m-%d %H:%M:%S" 2>/dev/null > /mnt/sdcard/cubegm/time_save.txt
            sync
            echo "[Fake-RTC]: Hora auto-reemplazada tras cerrar core de juego común." >> "$LOG"
            # =========================================================================
        fi
    else
        echo "[DEBUG] Archivo $LAUNCH no encontrado en este ciclo. No hay juego por cargar." >> "$LOG"
    fi

    sleep 0.2
done
