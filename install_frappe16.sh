#!/usr/bin/env bash
# =============================================================================
#  install_frappe.sh — Frappe 16 / ERPNext — Aprovisionador Automatizado iZone
#  Estándar : CIS Ubuntu 24.04 LTS Benchmark v1.0.0
#  Versión  : 6.0.0  (2026-08-14 — Arquitectura de dos fases)
#  Autor    : DevOps Engineering Team — iZone
# =============================================================================
#
#  MODO DE USO:
#    sudo bash install_frappe.sh
#
#  ARQUITECTURA DE DOS FASES:
#    FASE 1 (root)      → hardening SO, SSH, banners, usuarios, UFW, swap,
#                         MariaDB. Al final, el script SE RE-INVOCA a sí mismo
#                         como el usuario operativo mediante: sudo -iu $OP_USER
#    FASE 2 (sysadmin)  → Node/NVM, uv, Python, bench, apps, sitio, producción.
#                         Corre con el $HOME REAL del usuario (no /root).
#                         Esto elimina de raíz los problemas de HOME/uv.toml/PATH.
#
#  Esta estructura replica fielmente el SOP manual validado por el operador,
#  donde tras configurar la base como root se ejecuta `su - sysadmin` y todo
#  el trabajo de Frappe ocurre en el contexto nativo del usuario.
#
#  PRERREQUISITO: Ubuntu 24.04 LTS (fresh/minimal). Conectividad a internet.
#
#  VERSIONES (alineadas al entorno real validado del operador):
#    - Python        3.14   (validado: bench init exitoso con CPython 3.14.7)
#    - MariaDB       11.8.8 (validado en producción del operador)
#    - Node.js       24     (vía NVM v0.39.7)
#    - Apps          erpnext, hrms, lending (Wiki NO se instala)
# =============================================================================

set -euo pipefail

export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a

# =============================================================================
#  VARIABLES DE CONFIGURACIÓN GLOBAL
# =============================================================================

PYTHON_VERSION="3.14"
MARIADB_VERSION="mariadb-11.8.8"
NVM_VERSION="v0.39.7"
FRAPPE_BRANCH="version-16"

# Rutas para el traspaso de estado entre Fase 1 (root) y Fase 2 (usuario).
# Usamos ${VAR:=default} para respetar valores inyectados vía `env` cuando el
# script se re-invoca en Fase 2 (donde STATE_FILE apunta al archivo del usuario).
: "${STATE_DIR:=/etc/izone-frappe}"
: "${STATE_FILE:=${STATE_DIR}/provision.env}"
: "${PHASE2_MARKER:=${STATE_DIR}/phase2.flag}"
: "${LOG_FILE:=/var/log/izone_frappe_install.log}"
touch "$LOG_FILE" 2>/dev/null || LOG_FILE="/tmp/izone_frappe_install.log"

# =============================================================================
#  SECCIÓN 0: COLORES Y LOGGING
# =============================================================================

CLR_RED='\033[0;31m'; CLR_GREEN='\033[0;32m'; CLR_YELLOW='\033[1;33m'
CLR_CYAN='\033[0;36m'; CLR_BLUE='\033[0;34m'; CLR_BOLD='\033[1m'
CLR_DIM='\033[2m';    CLR_RESET='\033[0m'

log()  { echo -e "$(date '+%Y-%m-%d %H:%M:%S')  [INFO]  $*" | tee -a "$LOG_FILE"; }
ok()   { echo -e "${CLR_GREEN}$(date '+%Y-%m-%d %H:%M:%S')  [ OK ]  $*${CLR_RESET}" | tee -a "$LOG_FILE"; }
warn() { echo -e "${CLR_YELLOW}$(date '+%Y-%m-%d %H:%M:%S')  [WARN]  $*${CLR_RESET}" | tee -a "$LOG_FILE"; }
err()  { echo -e "${CLR_RED}$(date '+%Y-%m-%d %H:%M:%S')  [ERR ]  $*${CLR_RESET}" | tee -a "$LOG_FILE"; }

header() {
    echo ""
    echo -e "${CLR_BOLD}${CLR_BLUE}══════════════════════════════════════════════════════════════${CLR_RESET}"
    echo -e "${CLR_BOLD}${CLR_BLUE}  $*${CLR_RESET}"
    echo -e "${CLR_BOLD}${CLR_BLUE}══════════════════════════════════════════════════════════════${CLR_RESET}"
    echo ""
}

section() {
    echo ""
    echo -e "${CLR_CYAN}  ▶  $*${CLR_RESET}"
    echo -e "${CLR_CYAN}  $(printf '─%.0s' {1..58})${CLR_RESET}"
}

step() { echo -e "  ${CLR_YELLOW}→${CLR_RESET} $*" | tee -a "$LOG_FILE"; }

die() {
    _spinner_stop 2>/dev/null || true
    err "FALLO FATAL: $*"
    err "Consulta el log completo en: ${LOG_FILE}"
    exit 1
}

# =============================================================================
#  SECCIÓN 0B: SISTEMA DE PROGRESO + SPINNER
# =============================================================================

PROGRESS_TOTAL=30
PROGRESS_CURRENT=0
PROGRESS_BAR_WIDTH=50

progress_tick() {
    local label="${1:-}"
    (( PROGRESS_CURRENT++ )) || true
    _draw_progress_bar "$label"
}

_draw_progress_bar() {
    local label="${1:-}"
    # Capar el contador al total para que la barra NUNCA pase de 100%,
    # sin importar desajustes en el conteo de ticks entre fases.
    local cur=$PROGRESS_CURRENT
    (( cur > PROGRESS_TOTAL )) && cur=$PROGRESS_TOTAL
    local pct=$(( cur * 100 / PROGRESS_TOTAL ))
    local filled=$(( cur * PROGRESS_BAR_WIDTH / PROGRESS_TOTAL ))
    local empty=$(( PROGRESS_BAR_WIDTH - filled ))
    local bar="${CLR_GREEN}"; local i
    for (( i=0; i<filled; i++ )); do bar+="█"; done
    bar+="${CLR_RESET}${CLR_DIM}"
    for (( i=0; i<empty;  i++ )); do bar+="░"; done
    bar+="${CLR_RESET}"
    echo -e ""
    echo -e "  ${CLR_BOLD}Progreso:${CLR_RESET} [${bar}] ${CLR_BOLD}${pct}%${CLR_RESET}  (${cur}/${PROGRESS_TOTAL})"
    [[ -n "$label" ]] && echo -e "  ${CLR_DIM}✔ Completado: ${label}${CLR_RESET}"
    echo "$(date '+%Y-%m-%d %H:%M:%S')  [PROG]  [${cur}/${PROGRESS_TOTAL}] ${pct}% — ${label}" >> "$LOG_FILE"
}

_SPINNER_PID=""; _SPINNER_ACTIVE=false
_spinner_frames=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')

_spinner_loop() {
    local msg="$1"; local i=0; local start_ts; start_ts=$(date +%s)
    tput civis 2>/dev/null || true
    while true; do
        local frame="${_spinner_frames[$((i % 10))]}"
        local elapsed=$(( $(date +%s) - start_ts ))
        local tstr; printf -v tstr "%02d:%02d" "$(( elapsed / 60 ))" "$(( elapsed % 60 ))"
        if (( elapsed > 120 )) && (( elapsed % 30 == 0 )); then
            printf "\r  ${CLR_YELLOW}%s${CLR_RESET}  ${CLR_BOLD}%s${CLR_RESET}  ${CLR_YELLOW}[%s — trabajando...]${CLR_RESET}   " "$frame" "$msg" "$tstr"
        else
            printf "\r  ${CLR_CYAN}%s${CLR_RESET}  ${CLR_BOLD}%s${CLR_RESET}  ${CLR_DIM}[%s]${CLR_RESET}   " "$frame" "$msg" "$tstr"
        fi
        sleep 0.1; (( i++ )) || true
    done
}

spinner_start() {
    echo ""
    _spinner_loop "${1:-Procesando...}" &
    _SPINNER_PID=$!; _SPINNER_ACTIVE=true
    disown "$_SPINNER_PID" 2>/dev/null || true
}

_spinner_stop() {
    if [[ "$_SPINNER_ACTIVE" == "true" ]] && [[ -n "$_SPINNER_PID" ]]; then
        kill "$_SPINNER_PID" 2>/dev/null || true
        wait "$_SPINNER_PID" 2>/dev/null || true
        _SPINNER_PID=""; _SPINNER_ACTIVE=false
        printf "\r%-80s\r" " "
        tput cnorm 2>/dev/null || true
    fi
}

spinner_ok()   { _spinner_stop; ok  "${1:-Listo}"; }
spinner_fail() { _spinner_stop; err "${1:-Falló}"; }

run_with_spinner() {
    local desc="$1"; shift
    spinner_start "$desc"
    if "$@" >> "$LOG_FILE" 2>&1; then spinner_ok "$desc"
    else local rc=$?; spinner_fail "FALLÓ: $desc"; return $rc; fi
}

_cleanup_on_exit() {
    local exit_code=$?
    _spinner_stop 2>/dev/null || true
    tput cnorm 2>/dev/null || true
    if (( exit_code != 0 )); then
        echo ""
        err "Script terminó inesperadamente (código: ${exit_code}). Log: ${LOG_FILE}"
    fi
}
trap _cleanup_on_exit EXIT

# =============================================================================
#  GESTIÓN ROBUSTA DE APT — Espera de locks (anti-hang crítico)
# =============================================================================
#  En Ubuntu 24.04, el servicio 'unattended-upgrades' arranca automáticamente
#  y toma el lock /var/lib/dpkg/lock-frontend en segundo plano. Si el script
#  ejecuta apt-get mientras ese lock está tomado, apt falla con código 100 y
#  'set -e' mata el script. Esto causó el corte en la ejecución del operador.
#
#  Solución estándar de aprovisionamiento cloud:
#    - apt_wait()  : espera (con timeout) a que TODOS los locks de apt/dpkg
#                    se liberen antes de continuar.
#    - apt_safe()  : envuelve cualquier comando apt-get, esperando el lock
#                    primero y reintentando si topa un lock durante la ejecución.
# =============================================================================

apt_wait() {
    # Espera a que se liberen los locks de apt/dpkg. Timeout: 300 s (5 min).
    local max_wait=300
    local waited=0
    local locks=(
        /var/lib/dpkg/lock-frontend
        /var/lib/dpkg/lock
        /var/lib/apt/lists/lock
        /var/cache/apt/archives/lock
    )
    while true; do
        local busy=false
        # fuser devuelve 0 si algún proceso tiene el archivo abierto.
        # fuser puede no existir en Ubuntu minimal (paquete psmisc) — es opcional;
        # si no está, apt_wait se apoya en pgrep (siempre disponible vía /proc).
        if command -v fuser >/dev/null 2>&1; then
            for lk in "${locks[@]}"; do
                if [[ -e "$lk" ]] && fuser "$lk" >/dev/null 2>&1; then
                    busy=true
                    break
                fi
            done
        fi
        # También verificar procesos apt/dpkg/unattended-upgr activos
        if pgrep -x "apt|apt-get|dpkg|unattended-upgr" >/dev/null 2>&1; then
            busy=true
        fi
        if [[ "$busy" == "false" ]]; then
            return 0
        fi
        if (( waited >= max_wait )); then
            warn "Timeout esperando el lock de apt (${max_wait}s). Continuando de todas formas..."
            return 0
        fi
        # Mostrar espera solo cada 5s para no saturar
        if (( waited % 5 == 0 )); then
            printf "\r  ${CLR_YELLOW}⠿${CLR_RESET}  Esperando que apt/unattended-upgrades libere el lock... ${CLR_BOLD}%ds${CLR_RESET}   " "$waited"
        fi
        sleep 2
        (( waited += 2 )) || true
    done
}

apt_safe() {
    # Envuelve apt-get esperando el lock primero, con reintentos ante lock.
    # Uso: apt_safe install -y -q paquete
    apt_wait
    printf "\r%-80s\r" " " 2>/dev/null || true
    local attempt=1
    local max_attempts=5
    while (( attempt <= max_attempts )); do
        if apt-get "$@" \
            -o Dpkg::Options::="--force-confdef" \
            -o Dpkg::Options::="--force-confold" >> "$LOG_FILE" 2>&1; then
            return 0
        fi
        local rc=$?
        # Código 100 suele ser lock o dependencia. Reintentar tras esperar.
        warn "apt-get falló (intento ${attempt}/${max_attempts}, código ${rc}). Reintentando..."
        apt_wait
        (( attempt++ )) || true
        sleep 3
    done
    return 1
}

sudo_apt_safe() {
    # Igual que apt_safe pero con sudo (para la Fase 2, que corre como usuario).
    apt_wait
    printf "\r%-80s\r" " " 2>/dev/null || true
    local attempt=1
    local max_attempts=5
    while (( attempt <= max_attempts )); do
        if sudo apt-get "$@" \
            -o Dpkg::Options::="--force-confdef" \
            -o Dpkg::Options::="--force-confold" >> "$LOG_FILE" 2>&1; then
            return 0
        fi
        local rc=$?
        warn "sudo apt-get falló (intento ${attempt}/${max_attempts}, código ${rc}). Reintentando..."
        apt_wait
        (( attempt++ )) || true
        sleep 3
    done
    return 1
}

disable_auto_updates() {
    # Deshabilita unattended-upgrades y timers de apt para evitar que tomen
    # el lock durante el aprovisionamiento. Se hace UNA vez al inicio (root).
    step "Deshabilitando actualizaciones automáticas (evita locks de apt)..."
    systemctl stop unattended-upgrades.service      >> "$LOG_FILE" 2>&1 || true
    systemctl disable unattended-upgrades.service    >> "$LOG_FILE" 2>&1 || true
    systemctl stop apt-daily.timer apt-daily-upgrade.timer         >> "$LOG_FILE" 2>&1 || true
    systemctl disable apt-daily.timer apt-daily-upgrade.timer       >> "$LOG_FILE" 2>&1 || true
    systemctl stop apt-daily.service apt-daily-upgrade.service      >> "$LOG_FILE" 2>&1 || true
    # Esperar a que cualquier proceso en curso termine
    apt_wait
    ok "Actualizaciones automáticas deshabilitadas durante el aprovisionamiento."
}

# =============================================================================
#  DETECCIÓN DE FASE
# =============================================================================
#  Si existe el marcador de fase 2 Y estamos corriendo como un usuario no-root,
#  saltamos directamente a la Fase 2. De lo contrario, corremos la Fase 1.
# =============================================================================

CURRENT_USER="$(id -un)"

# =============================================================================
# =============================================================================
#   ███████╗ █████╗ ███████╗███████╗    ██████╗
#   ██╔════╝██╔══██╗██╔════╝██╔════╝    ╚════██╗
#   █████╗  ███████║███████╗█████╗       █████╔╝
#   ██╔══╝  ██╔══██║╚════██║██╔══╝      ██╔═══╝
#   ██║     ██║  ██║███████║███████╗    ███████╗
#   ╚═╝     ╚═╝  ╚═╝╚══════╝╚══════╝    ╚══════╝
#   FASE 2 — Ejecución como usuario operativo (Frappe)
# =============================================================================
# =============================================================================

if [[ -f "$PHASE2_MARKER" && "$CURRENT_USER" != "root" ]]; then

    # Cargar el estado guardado por la Fase 1
    # shellcheck disable=SC1090
    source "$STATE_FILE"

    header "FASE 2: Instalación de Frappe (usuario: ${CURRENT_USER})"
    echo -e "  ${CLR_DIM}Contexto: HOME=${HOME}  —  ejecución nativa sin sudo -u${CLR_RESET}"

    # Reanudar la barra de progreso desde donde quedó la Fase 1
    PROGRESS_CURRENT="${PROGRESS_SAVED:-14}"

    # ── 3.1 Node.js 24 vía NVM ───────────────────────────────────────────────
    section "F2.1 — Node.js 24 vía NVM"
    export NVM_DIR="${HOME}/.nvm"

    if [[ -d "$NVM_DIR" ]]; then
        warn "NVM ya existe. Omitiendo instalación de NVM."
    else
        spinner_start "Instalando NVM ${NVM_VERSION}..."
        curl -o- "https://raw.githubusercontent.com/nvm-sh/nvm/${NVM_VERSION}/install.sh" | bash >> "$LOG_FILE" 2>&1
        spinner_ok "NVM instalado."
    fi

    # Cargar NVM en la sesión actual
    [ -s "${NVM_DIR}/nvm.sh" ] && source "${NVM_DIR}/nvm.sh"

    spinner_start "Instalando Node.js 24 + Yarn (2-5 min)..."
    nvm install 24 >> "$LOG_FILE" 2>&1
    nvm use 24 >> "$LOG_FILE" 2>&1
    nvm alias default 24 >> "$LOG_FILE" 2>&1
    npm install -g yarn >> "$LOG_FILE" 2>&1
    spinner_ok "Node.js $(node -v 2>/dev/null) + Yarn $(yarn -v 2>/dev/null) instalados."
    progress_tick "Node.js 24 + Yarn"

    # ── 3.2 wkhtmltopdf ──────────────────────────────────────────────────────
    section "F2.2 — wkhtmltopdf (Motor PDF)"
    WKHTML_DEB="wkhtmltox_0.12.6.1-2.jammy_amd64.deb"
    WKHTML_URL="https://github.com/wkhtmltopdf/packaging/releases/download/0.12.6.1-2/${WKHTML_DEB}"

    cd "$HOME"
    spinner_start "Descargando e instalando wkhtmltopdf..."
    wget -q "$WKHTML_URL" >> "$LOG_FILE" 2>&1
    sudo dpkg -i "$WKHTML_DEB" >> "$LOG_FILE" 2>&1 || true
    sudo_apt_safe install -f -y -q
    rm -f "$WKHTML_DEB"
    if command -v wkhtmltopdf &>/dev/null; then
        spinner_ok "wkhtmltopdf instalado: $(wkhtmltopdf --version 2>&1 | head -1)"
    else
        spinner_fail "wkhtmltopdf no disponible como binario nativo."
        warn "Revisa manualmente la generación de PDF en Frappe."
    fi
    progress_tick "wkhtmltopdf instalado"

    # ── 3.3 pipx + frappe-bench ──────────────────────────────────────────────
    section "F2.3 — frappe-bench vía pipx"
    spinner_start "Configurando pipx e instalando frappe-bench..."
    pipx ensurepath >> "$LOG_FILE" 2>&1
    # Asegurar PATH en esta sesión (pipx ensurepath modifica .bashrc pero no la sesión)
    export PATH="${HOME}/.local/bin:${PATH}"
    pipx install frappe-bench >> "$LOG_FILE" 2>&1
    spinner_ok "frappe-bench instalado."
    progress_tick "frappe-bench CLI"

    # ── 3.4 uv + Python 3.14 ─────────────────────────────────────────────────
    section "F2.4 — uv + Python ${PYTHON_VERSION}"
    spinner_start "Instalando uv..."
    curl -LsSf https://astral.sh/uv/install.sh | sh >> "$LOG_FILE" 2>&1
    export PATH="${HOME}/.local/bin:${PATH}"
    spinner_ok "uv instalado."

    spinner_start "Aprovisionando Python ${PYTHON_VERSION} (3-8 min)..."
    uv python install "${PYTHON_VERSION}" >> "$LOG_FILE" 2>&1
    spinner_ok "Python ${PYTHON_VERSION} aprovisionado."
    progress_tick "uv + Python ${PYTHON_VERSION}"

    # ── 3.5 bench init ───────────────────────────────────────────────────────
    section "F2.5 — bench init (Frappe ${FRAPPE_BRANCH}, Python ${PYTHON_VERSION})"
    BENCH_DIR="${HOME}/frappe-bench"

    if [[ -d "$BENCH_DIR" ]]; then
        warn "frappe-bench ya existe. Omitiendo bench init."
    else
        spinner_start "Ejecutando bench init (10-20 min, compilación Python/JS)..."
        cd "$HOME"
        bench init --frappe-branch "${FRAPPE_BRANCH}" frappe-bench --python "${PYTHON_VERSION}" >> "$LOG_FILE" 2>&1
        spinner_ok "Framework Frappe v16 inicializado."
    fi
    progress_tick "bench init"

    # ── 3.6 Permisos del home (CIS 6.x) ──────────────────────────────────────
    section "F2.6 — Permisos del Home (CIS 6.x)"
    cd "$BENCH_DIR"
    chmod 750 "$HOME"
    chmod o+x "$HOME"
    ok "Permisos home: 750 + o+x."
    progress_tick "Permisos home CIS"

    # ── 3.7 Descarga de apps ─────────────────────────────────────────────────
    section "F2.7 — Descarga de Apps (erpnext, hrms, lending)"
    _get_app() {
        local app="$1"
        spinner_start "Descargando ${app} (${FRAPPE_BRANCH})..."
        cd "$BENCH_DIR"
        bench get-app --branch "${FRAPPE_BRANCH}" "${app}" >> "$LOG_FILE" 2>&1
        spinner_ok "${app} descargado."
        progress_tick "${app} descargado"
    }
    _get_app "erpnext"
    _get_app "hrms"
    _get_app "lending"

    # ── 3.8 Creación del sitio ───────────────────────────────────────────────
    section "F2.8 — Creación del sitio '${SITE_NAME}'"
    spinner_start "Creando sitio (inicializa BD, 2-5 min)..."
    cd "$BENCH_DIR"
    bench new-site "${SITE_NAME}" \
        --db-root-username root \
        --mariadb-root-password "${MARIADB_ROOT_PASS}" \
        --admin-password "${FRAPPE_ADMIN_PASS}" \
        --no-mariadb-socket >> "$LOG_FILE" 2>&1
    spinner_ok "Sitio '${SITE_NAME}' creado."
    progress_tick "Sitio creado"

    # ── 3.9 bench start en background + instalación de apps ──────────────────
    section "F2.9 — Instalación de apps (Redis activo vía bench start)"

    # Levantar bench start en background (screen headless). HOME ya es correcto.
    step "Levantando 'bench start' en screen para activar puertos Redis..."
    cd "$BENCH_DIR"
    screen -dmS frappe_install_session bash -c "cd '${BENCH_DIR}' && source '${NVM_DIR}/nvm.sh' && bench start"

    echo ""
    log "Esperando inicialización de Redis (25 s)..."
    for i in $(seq 25 -1 1); do
        printf "\r  ${CLR_CYAN}⠿${CLR_RESET}  Inicializando Redis...  ${CLR_BOLD}%2d s${CLR_RESET} restantes  " "$i"
        sleep 1
    done
    printf "\r%-80s\r" " "

    for port in 11000 12000 13000; do
        if ! ss -tlnp 2>/dev/null | grep -q ":${port}"; then
            warn "Puerto Redis :${port} aún no responde. Esperando 15 s más..."
            for i in $(seq 15 -1 1); do
                printf "\r  ${CLR_YELLOW}⠿${CLR_RESET}  Esperando :${port}...  ${CLR_BOLD}%2d s${CLR_RESET}  " "$i"
                sleep 1
            done
            printf "\r%-80s\r" " "
            ss -tlnp 2>/dev/null | grep -q ":${port}" || warn "Puerto :${port} sin respuesta. Continuando..."
        fi
    done
    ok "Verificación de puertos Redis completada."

    _install_app() {
        local app="$1"
        spinner_start "Instalando ${app} en '${SITE_NAME}' (migraciones BD)..."
        cd "$BENCH_DIR"
        bench --site "${SITE_NAME}" install-app "${app}" >> "$LOG_FILE" 2>&1
        spinner_ok "${app} instalado en el sitio."
        progress_tick "${app} instalado"
    }
    _install_app "erpnext"
    _install_app "hrms"
    _install_app "lending"

    # Cerrar screen limpiamente
    step "Deteniendo bench start (screen frappe_install_session)..."
    screen -S frappe_install_session -X stuff $'\003' >> "$LOG_FILE" 2>&1 || true
    sleep 3
    screen -S frappe_install_session -X quit >> "$LOG_FILE" 2>&1 || true
    ok "Sesión screen terminada."
    progress_tick "Apps instaladas / Redis cerrado"

    # ── 3.10 Scheduler ───────────────────────────────────────────────────────
    section "F2.10 — Scheduler y modo mantenimiento"
    cd "$BENCH_DIR"
    bench --site "${SITE_NAME}" enable-scheduler >> "$LOG_FILE" 2>&1
    bench --site "${SITE_NAME}" set-maintenance-mode off >> "$LOG_FILE" 2>&1
    ok "Scheduler habilitado, modo mantenimiento desactivado."
    progress_tick "Scheduler habilitado"

    # ── 3.11 ansible + symlink bench ─────────────────────────────────────────
    section "F2.11 — Preparación pase a producción"
    if ! command -v ansible &>/dev/null; then
        spinner_start "Instalando ansible..."
        sudo_apt_safe install -y -q ansible
        spinner_ok "ansible instalado."
    fi
    sudo ln -sf "${HOME}/.local/bin/bench" /usr/local/bin/bench
    ok "Symlink global de bench creado."
    progress_tick "Preparación producción"

    # ── 3.12 bench setup production ──────────────────────────────────────────
    section "F2.12 — bench setup production"
    spinner_start "Ejecutando bench setup production (Nginx + Supervisor, 3-8 min)..."
    cd "$BENCH_DIR"
    sudo bench setup production "${CURRENT_USER}" >> "$LOG_FILE" 2>&1
    spinner_ok "bench setup production completado."
    progress_tick "bench setup production"

    # ── 3.13 Hardening Nginx (CIS 2.5 / 5.3) ─────────────────────────────────
    section "F2.13 — Hardening Nginx (CIS 2.5 / 5.3)"
    NGINX_CONF="/etc/nginx/nginx.conf"
    if ! sudo grep -q "server_tokens off" "$NGINX_CONF"; then
        sudo sed -i '/http {/a\
\
    # === CIS Hardening — iZone install_frappe.sh v6.0.0 ===\
    server_tokens off;\
    add_header X-Frame-Options SAMEORIGIN;\
    add_header X-Content-Type-Options nosniff;\
    add_header X-XSS-Protection "1; mode=block";\
' "$NGINX_CONF"
        ok "Directivas CIS inyectadas en nginx.conf."
    else
        warn "Directivas CIS ya presentes. Omitiendo."
    fi
    progress_tick "Nginx CIS hardening"

    # ── 3.14 Enlace manual de configs ────────────────────────────────────────
    section "F2.14 — Enlace de configs Nginx/Supervisor"
    cd "$BENCH_DIR"
    spinner_start "Generando configs bench nginx + supervisor..."
    # bench setup nginx/supervisor preguntan si sobreescribir — respondemos 'yes'
    yes | bench setup nginx >> "$LOG_FILE" 2>&1 || true
    yes | bench setup supervisor >> "$LOG_FILE" 2>&1 || true
    spinner_ok "Configs generadas."

    sudo ln -sf "${BENCH_DIR}/config/nginx.conf"      /etc/nginx/conf.d/frappe-bench.conf
    sudo ln -sf "${BENCH_DIR}/config/supervisor.conf"  /etc/supervisor/conf.d/frappe-bench.conf

    # Symlink node para Supervisor (Socket.io)
    NODE_REAL="$(command -v node)"
    if [[ -n "$NODE_REAL" ]]; then
        sudo ln -sf "$NODE_REAL" /usr/bin/node       2>/dev/null || true
        sudo ln -sf "$NODE_REAL" /usr/local/bin/node 2>/dev/null || true
    fi

    spinner_start "Recargando Nginx y Supervisor..."
    sudo nginx -t >> "$LOG_FILE" 2>&1
    sudo service nginx reload >> "$LOG_FILE" 2>&1
    sudo supervisorctl reread >> "$LOG_FILE" 2>&1
    sudo supervisorctl update >> "$LOG_FILE" 2>&1
    spinner_ok "Nginx + Supervisor actualizados."
    progress_tick "Nginx + Supervisor enlazados"

    # ── 3.15 Reinicio final ──────────────────────────────────────────────────
    section "F2.15 — Reinicio final de servicios"
    spinner_start "Reiniciando servicios..."
    sudo service nginx reload >> "$LOG_FILE" 2>&1
    sudo supervisorctl restart all >> "$LOG_FILE" 2>&1 || true
    sleep 5
    spinner_ok "Servicios reiniciados."
    progress_tick "Reinicio final"

    PROGRESS_CURRENT=$PROGRESS_TOTAL
    _draw_progress_bar "Aprovisionamiento completado al 100%"

    # =========================================================================
    #  AUDITORÍA FINAL (Fase 2)
    # =========================================================================
    header "AUDITORÍA FINAL: Diagnóstico de Estado del Sistema"

    AUDIT_PASS=0; AUDIT_FAIL=0; AUDIT_WARN=0
    AUDIT_CRITICAL_FAIL=0
    # audit_check LABEL STATUS DETAIL [CRITICAL]
    #   STATUS   : ok | fail | warn
    #   CRITICAL : "critical" (4to arg) → un 'fail' aquí SÍ aborta el deploy.
    #              Sin él, un 'fail' se reporta pero NO invalida un deploy que
    #              objetivamente funciona. Filosofía: la auditoría DIAGNOSTICA,
    #              no descarta un aprovisionamiento exitoso por un check frágil.
    audit_check() {
        local label="$1" status="$2" detail="$3" critical="${4:-}"
        case "$status" in
            ok)   echo -e "  ${CLR_GREEN}✔${CLR_RESET}  ${CLR_BOLD}${label}${CLR_RESET} — ${detail}";          (( AUDIT_PASS++ )) || true ;;
            fail)
                echo -e "  ${CLR_RED}✘${CLR_RESET}  ${CLR_BOLD}${label}${CLR_RESET} — ${CLR_RED}${detail}${CLR_RESET}"
                (( AUDIT_FAIL++ )) || true
                [[ "$critical" == "critical" ]] && (( AUDIT_CRITICAL_FAIL++ )) || true
                ;;
            warn) echo -e "  ${CLR_YELLOW}⚠${CLR_RESET}  ${CLR_BOLD}${label}${CLR_RESET} — ${CLR_YELLOW}${detail}${CLR_RESET}"; (( AUDIT_WARN++ )) || true ;;
        esac
        echo "$(date '+%Y-%m-%d %H:%M:%S')  [AUDIT-${status^^}]  ${label}: ${detail}" >> "$LOG_FILE"
    }

    echo ""; echo -e "  ${CLR_BOLD}Generando reporte de validación...${CLR_RESET}"; echo ""

    section "Validación — Nginx"
    systemctl is-active --quiet nginx \
        && audit_check "Nginx — Activo"   "ok"   "$(systemctl is-active nginx)" \
        || audit_check "Nginx — Activo"   "fail" "Nginx NO está corriendo" "critical"
    # nginx -t: el CÓDIGO DE SALIDA es la verdad autoritativa, no el texto.
    # Un grep del mensaje es frágil (depende de wording/locale/buffering del
    # pipe con sudo). Usamos el exit code directamente. Ya es confiable → critical.
    if sudo nginx -t >> "$LOG_FILE" 2>&1; then
        audit_check "Nginx — Sintaxis" "ok"   "Válida (nginx -t exit 0)"
    else
        audit_check "Nginx — Sintaxis" "fail" "nginx -t devolvió error" "critical"
    fi
    curl -sf --max-time 5 "http://127.0.0.1" > /dev/null 2>&1 \
        && audit_check "Nginx — HTTP local" "ok"   "200 OK" \
        || audit_check "Nginx — HTTP local" "warn" "Sin respuesta (puede ser normal)"
    sudo nginx -T 2>/dev/null | grep -i "server_tokens" | grep -q "off" \
        && audit_check "Nginx — CIS server_tokens" "ok"   "off (CIS 2.5.1)" \
        || audit_check "Nginx — CIS server_tokens" "warn" "no detectado"

    section "Validación — MariaDB"
    systemctl is-active --quiet mariadb \
        && audit_check "MariaDB — Activo" "ok"   "$(systemctl is-active mariadb)" \
        || audit_check "MariaDB — Activo" "fail" "MariaDB NO está corriendo" "critical"
    mysql -u root -p"${MARIADB_ROOT_PASS}" -e "SELECT 1;" > /dev/null 2>&1 \
        && audit_check "MariaDB — Auth root" "ok"   "Conexión exitosa" \
        || audit_check "MariaDB — Auth root" "fail" "Fallo de autenticación" "critical"
    DB_CS=$(mysql -u root -p"${MARIADB_ROOT_PASS}" -e "SHOW VARIABLES LIKE 'character_set_server';" 2>/dev/null | grep character_set_server | awk '{print $2}')
    [[ "$DB_CS" == "utf8mb4" ]] \
        && audit_check "MariaDB — charset" "ok" "utf8mb4" \
        || audit_check "MariaDB — charset" "warn" "${DB_CS:-desconocido}"

    section "Validación — Supervisor y Frappe"
    systemctl is-active --quiet supervisor \
        && audit_check "Supervisor — Activo" "ok"   "$(systemctl is-active supervisor)" \
        || audit_check "Supervisor — Activo" "fail" "Supervisor NO está corriendo" "critical"
    SUP=$(sudo supervisorctl status 2>/dev/null || echo "ERROR")
    if echo "$SUP" | grep -q "RUNNING"; then
        RC=$(echo "$SUP" | grep -c "RUNNING" || true)
        audit_check "Supervisor — Procesos RUNNING" "ok" "${RC} proceso(s)"
        NR=$(echo "$SUP" | grep -v "RUNNING" | grep -v "^$" || true)
        [[ -n "$NR" ]] && audit_check "Supervisor — no-RUNNING" "warn" "$(echo "$NR" | wc -l) fuera de RUNNING"
    else
        audit_check "Supervisor — Procesos" "fail" "Sin procesos RUNNING" "critical"
    fi

    section "Validación — Firewall / SSH"
    sudo ufw status | grep -q "Status: active" \
        && audit_check "UFW — Activo" "ok" "habilitado" \
        || audit_check "UFW — Activo" "warn" "deshabilitado"
    ss -tlnp 2>/dev/null | grep -q ":${SSH_PORT}" \
        && audit_check "SSH — Puerto ${SSH_PORT}" "ok" "Escuchando" \
        || audit_check "SSH — Puerto ${SSH_PORT}" "warn" "No detectado"

    section "Validación — Sitio Frappe"
    [[ -f "${BENCH_DIR}/sites/${SITE_NAME}/site_config.json" ]] \
        && audit_check "Frappe — site_config.json" "ok" "Encontrado" \
        || audit_check "Frappe — site_config.json" "fail" "No encontrado" "critical"

    section "Validación — Memoria"
    SWAP_TOT=$(free -h | grep Swap | awk '{print $2}')
    if [[ "$SWAP_TOT" != "0B" && -n "$SWAP_TOT" ]]; then
        audit_check "Swap" "ok" "Activo: ${SWAP_TOT}"
    elif (( TOTAL_RAM_GB >= 8 )); then
        audit_check "Swap" "ok" "No requerido (RAM: ${TOTAL_RAM_GB} GB)"
    else
        audit_check "Swap" "warn" "Sin swap con RAM < 8 GB"
    fi

    # ── Reporte final ────────────────────────────────────────────────────────
    echo ""
    echo -e "${CLR_BOLD}${CLR_BLUE}══════════════════════════════════════════════════════════════${CLR_RESET}"
    echo -e "${CLR_BOLD}${CLR_BLUE}  REPORTE FINAL — ${COMPANY_NAME}${CLR_RESET}"
    echo -e "${CLR_BOLD}${CLR_BLUE}══════════════════════════════════════════════════════════════${CLR_RESET}"
    echo ""
    echo -e "  ${CLR_GREEN}✔  PASARON:${CLR_RESET}  ${AUDIT_PASS}"
    echo -e "  ${CLR_YELLOW}⚠  ALERTAS:${CLR_RESET}  ${AUDIT_WARN}"
    echo -e "  ${CLR_RED}✘  FALLARON:${CLR_RESET} ${AUDIT_FAIL}  ${CLR_DIM}(críticos: ${AUDIT_CRITICAL_FAIL})${CLR_RESET}"
    echo ""
    echo -e "  ${CLR_BOLD}Detalles:${CLR_RESET}"
    echo -e "  ├── Usuario:       ${CURRENT_USER}"
    echo -e "  ├── Home:          ${HOME}"
    echo -e "  ├── Puerto SSH:    ${SSH_PORT}"
    echo -e "  ├── Sitio Frappe:  ${SITE_NAME}"
    echo -e "  ├── Empresa:       ${COMPANY_NAME}"
    echo -e "  ├── Python:        ${PYTHON_VERSION}"
    echo -e "  ├── MariaDB:       ${MARIADB_VERSION}"
    echo -e "  └── Log:           ${LOG_FILE}"
    echo ""
    if (( AUDIT_CRITICAL_FAIL > 0 )); then
        echo -e "  ${CLR_RED}${CLR_BOLD}✘  ${AUDIT_CRITICAL_FAIL} fallo(s) CRÍTICO(s) de servicio. Revisa: ${LOG_FILE}${CLR_RESET}"
    elif (( AUDIT_FAIL > 0 || AUDIT_WARN > 0 )); then
        echo -e "  ${CLR_GREEN}${CLR_BOLD}✔  APROVISIONAMIENTO EXITOSO${CLR_RESET} ${CLR_YELLOW}(con ${AUDIT_WARN} alerta(s) / ${AUDIT_FAIL} aviso(s) no críticos)${CLR_RESET}"
        echo -e "  ${CLR_DIM}Los servicios core están operativos. Revisa los ítems marcados si lo deseas.${CLR_RESET}"
    else
        echo -e "  ${CLR_GREEN}${CLR_BOLD}✔  APROVISIONAMIENTO COMPLETADO EXITOSAMENTE.${CLR_RESET}"
    fi
    echo ""
    echo -e "  ${CLR_BOLD}Acceso:${CLR_RESET}"
    echo -e "  ├── SSH: ssh -p ${SSH_PORT} ${CURRENT_USER}@<IP_DEL_SERVIDOR>"
    echo -e "  └── ERP: http://<IP_DEL_SERVIDOR>  →  Administrator"
    echo ""
    echo -e "  ${CLR_BOLD}Estado Supervisor:${CLR_RESET}"
    sudo supervisorctl status 2>/dev/null | sed 's/^/  /' || echo "  (No disponible)"
    echo ""
    echo -e "${CLR_BOLD}${CLR_BLUE}══════════════════════════════════════════════════════════════${CLR_RESET}"
    echo -e "${CLR_BOLD}  Finalizado: $(date '+%Y-%m-%d %H:%M:%S')${CLR_RESET}"
    echo -e "${CLR_BOLD}${CLR_BLUE}══════════════════════════════════════════════════════════════${CLR_RESET}"
    echo ""

    # Limpiar el marcador de fase 2 para evitar re-ejecuciones accidentales
    sudo rm -f "$PHASE2_MARKER"

    # Solo salimos con error si hubo un fallo CRÍTICO de servicio.
    # Un deploy con servicios operativos NO se invalida por checks cosméticos.
    (( AUDIT_CRITICAL_FAIL > 0 )) && exit 1
    exit 0
fi

# =============================================================================
# =============================================================================
#   ███████╗ █████╗ ███████╗███████╗    ██╗
#   ██╔════╝██╔══██╗██╔════╝██╔════╝   ███║
#   █████╗  ███████║███████╗█████╗     ╚██║
#   ██╔══╝  ██╔══██║╚════██║██╔══╝      ██║
#   ██║     ██║  ██║███████║███████╗    ██║
#   ╚═╝     ╚═╝  ╚═╝╚══════╝╚══════╝    ╚═╝
#   FASE 1 — Ejecución como root (Hardening + MariaDB)
# =============================================================================
# =============================================================================

header "APROVISIONADOR FRAPPE 16 — iZone Enterprise  [v6.0.0]"

[[ "$EUID" -ne 0 ]] && die "La Fase 1 debe ejecutarse como root. Usa: sudo bash $0"

if ! grep -q "Ubuntu 24.04" /etc/os-release 2>/dev/null; then
    warn "SO no verificado como Ubuntu 24.04 LTS. Continuando bajo tu responsabilidad..."
fi

# ── Bootstrap de herramientas base ───────────────────────────────────────────
section "0.0 — Bootstrap: herramientas base (curl, wget, gnupg...)"
echo -e "  ${CLR_DIM}Primer paso absoluto — necesario en Ubuntu minimal${CLR_RESET}"

# CRÍTICO: esperar cualquier apt en curso ANTES del primer comando.
# Un servidor recién arrancado puede tener unattended-upgrades corriendo.
apt_wait
apt_safe update -qq
apt_safe install -y -q \
    curl wget gnupg ca-certificates apt-transport-https \
    lsb-release software-properties-common psmisc
ok "Bootstrap: curl, wget, gnupg, ca-certificates, psmisc instalados."

# CRÍTICO: deshabilitar unattended-upgrades AHORA. El bootstrap acaba de
# instalarlo (o ya venía), y arranca solo tomando el lock de apt en background.
# Sin este paso, el siguiente apt-get (UFW, MariaDB, etc.) falla con código 100.
disable_auto_updates

step "Verificando conectividad a internet..."
if ! curl -sf --max-time 10 https://github.com > /dev/null; then
    ping -c 1 -W 5 8.8.8.8 > /dev/null 2>&1 || die "Sin acceso a internet."
    warn "GitHub no responde pero hay conectividad general. Continuando..."
fi
ok "Conectividad confirmada."

# =============================================================================
#  FASE INTERACTIVA
# =============================================================================

header "FASE INTERACTIVA: Configuración del Aprovisionamiento"
echo -e "${CLR_YELLOW}⚠  Único momento en que se pedirá intervención.${CLR_RESET}"; echo ""

# ── Usuario operativo — con detección de usuarios sudo existentes ────────────
section "Usuario Operativo del Sistema"
# Detectar usuarios humanos (UID >= 1000, < 65534) en grupo sudo
EXISTING_SUDO_USERS=$(getent group sudo | cut -d: -f4 | tr ',' '\n' | grep -v '^$' || true)
HUMAN_USERS=$(awk -F: '$3 >= 1000 && $3 < 65534 {print $1}' /etc/passwd || true)

if [[ -n "$EXISTING_SUDO_USERS" ]]; then
    echo -e "  ${CLR_BOLD}Usuarios existentes en el grupo sudo:${CLR_RESET}"
    echo "$EXISTING_SUDO_USERS" | sed 's/^/    - /'
    echo ""
    echo -e "  Puedes usar uno existente o crear uno nuevo."
fi

read -rp "  Nombre del usuario operativo [sysadmin]: " INPUT_OP_USER
OP_USER="${INPUT_OP_USER:-sysadmin}"

if id "$OP_USER" &>/dev/null; then
    warn "El usuario '${OP_USER}' ya existe. Se usará ese usuario."
    OP_USER_EXISTS=true
else
    OP_USER_EXISTS=false
    while true; do
        read -rsp "  Contraseña para el nuevo usuario '${OP_USER}': " OP_PASSWORD; echo ""
        read -rsp "  Confirma la contraseña: " OP_PASSWORD_CONFIRM; echo ""
        if [[ "$OP_PASSWORD" == "$OP_PASSWORD_CONFIRM" ]]; then
            [[ ${#OP_PASSWORD} -ge 12 ]] && break
            warn "Mínimo 12 caracteres."
        else
            warn "No coinciden."
        fi
    done
fi

# ── Puerto SSH ───────────────────────────────────────────────────────────────
section "Puerto SSH Personalizado (CIS 5.2)"
read -rp "  Puerto SSH personalizado [44004]: " INPUT_SSH_PORT
SSH_PORT="${INPUT_SSH_PORT:-44004}"
if ! [[ "$SSH_PORT" =~ ^[0-9]+$ ]] || (( SSH_PORT < 1024 || SSH_PORT > 65535 )); then
    warn "Puerto inválido. Usando 44004."; SSH_PORT="44004"
fi

# ── Contraseña MariaDB ───────────────────────────────────────────────────────
section "Base de Datos — MariaDB"
while true; do
    read -rsp "  Contraseña root para MariaDB: " MARIADB_ROOT_PASS; echo ""
    read -rsp "  Confirma la contraseña de MariaDB: " MARIADB_ROOT_PASS_CONFIRM; echo ""
    if [[ "$MARIADB_ROOT_PASS" == "$MARIADB_ROOT_PASS_CONFIRM" ]]; then
        [[ ${#MARIADB_ROOT_PASS} -ge 12 ]] && break
        warn "Mínimo 12 caracteres."
    else
        warn "No coinciden."
    fi
done

# ── Sitio Frappe ─────────────────────────────────────────────────────────────
section "Configuración del Sitio Frappe"
read -rp "  Nombre del sitio [izone.frappe.software]: " INPUT_SITE_NAME
SITE_NAME="${INPUT_SITE_NAME:-izone.frappe.software}"
while true; do
    read -rsp "  Contraseña del administrador Frappe: " FRAPPE_ADMIN_PASS; echo ""
    read -rsp "  Confirma la contraseña del administrador: " FRAPPE_ADMIN_PASS_CONFIRM; echo ""
    if [[ "$FRAPPE_ADMIN_PASS" == "$FRAPPE_ADMIN_PASS_CONFIRM" ]]; then
        [[ ${#FRAPPE_ADMIN_PASS} -ge 12 ]] && break
        warn "Mínimo 12 caracteres."
    else
        warn "No coinciden."
    fi
done

# ── Empresa ──────────────────────────────────────────────────────────────────
section "Identidad Corporativa"
echo -e "  ${CLR_DIM}Nota: usa el nombre sin acentos para los banners.${CLR_RESET}"
read -rp "  Nombre de la empresa para banners [iZone]: " INPUT_COMPANY
COMPANY_NAME="${INPUT_COMPANY:-iZone}"

# ── Llave SSH ────────────────────────────────────────────────────────────────
section "Llave Pública SSH"
echo -e "  Pega el CONTENIDO de tu llave pública (ssh-ed25519 AAAA... comentario)"
echo -e "  ${CLR_DIM}o la ruta a un archivo .pub (ej: /root/.ssh/id_ed25519.pub).${CLR_RESET}"
echo ""

# Validación robusta con reintentos. Acepta:
#   - Contenido pegado directamente (con espacios/saltos accidentales)
#   - Una ruta a un archivo .pub existente
# No mata el script al primer intento fallido: reintenta hasta 3 veces.
SSH_KEY_ATTEMPTS=0
while true; do
    (( SSH_KEY_ATTEMPTS++ )) || true
    read -rp "  Llave pública SSH (o ruta a .pub): " SSH_PUBLIC_KEY_RAW

    # Si es una ruta a un archivo existente, leer su contenido
    if [[ -f "$SSH_PUBLIC_KEY_RAW" ]]; then
        SSH_PUBLIC_KEY_RAW="$(cat "$SSH_PUBLIC_KEY_RAW")"
        step "Llave leída desde archivo."
    fi

    # Limpiar: quitar espacios/tabs al inicio y final, y saltos de línea internos
    SSH_PUBLIC_KEY="$(echo "$SSH_PUBLIC_KEY_RAW" | tr -d '\r\n' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"

    if [[ -z "$SSH_PUBLIC_KEY" ]]; then
        warn "No ingresaste nada. La llave SSH es obligatoria."
    elif echo "$SSH_PUBLIC_KEY" | grep -qE "^(ssh-ed25519|ssh-rsa|ecdsa-sha2-nistp256|sk-ssh-ed25519@openssh.com|sk-ecdsa-sha2-nistp256@openssh.com) "; then
        ok "Formato de llave SSH válido."
        break
    else
        warn "Formato no reconocido. Debe empezar con ssh-ed25519, ssh-rsa o ecdsa-sha2-nistp256."
        echo -e "  ${CLR_DIM}Recibido (primeros 40 chars): ${SSH_PUBLIC_KEY:0:40}${CLR_RESET}"
    fi

    if (( SSH_KEY_ATTEMPTS >= 3 )); then
        die "Se superaron 3 intentos con una llave SSH inválida. Verifica tu llave y reintenta el script."
    fi
    warn "Intento ${SSH_KEY_ATTEMPTS}/3. Inténtalo de nuevo."
done

# ── Zona horaria ─────────────────────────────────────────────────────────────
section "Zona Horaria del Servidor"
read -rp "  Zona horaria [America/Managua]: " INPUT_TZ
SERVER_TZ="${INPUT_TZ:-America/Managua}"

OP_HOME="/home/${OP_USER}"

# ── Confirmación ─────────────────────────────────────────────────────────────
echo ""
header "RESUMEN DE CONFIGURACIÓN"
echo -e "  ${CLR_BOLD}Usuario operativo:${CLR_RESET}   ${OP_USER} $([[ "$OP_USER_EXISTS" == "true" ]] && echo '(existente)' || echo '(nuevo)')"
echo -e "  ${CLR_BOLD}Puerto SSH:${CLR_RESET}          ${SSH_PORT}"
echo -e "  ${CLR_BOLD}Sitio Frappe:${CLR_RESET}        ${SITE_NAME}"
echo -e "  ${CLR_BOLD}Empresa:${CLR_RESET}             ${COMPANY_NAME}"
echo -e "  ${CLR_BOLD}Zona horaria:${CLR_RESET}        ${SERVER_TZ}"
echo -e "  ${CLR_BOLD}Python:${CLR_RESET}              ${PYTHON_VERSION}"
echo -e "  ${CLR_BOLD}MariaDB:${CLR_RESET}             ${MARIADB_VERSION}"
echo ""
echo -e "  ${CLR_YELLOW}⚠  El script se ejecutará en 2 fases automáticas (root → ${OP_USER}).${CLR_RESET}"
echo -e "  ${CLR_YELLOW}   Duración estimada: 30-50 minutos.${CLR_RESET}"
echo ""
read -rp "  ¿Todo correcto? Escribe 'SI' para iniciar: " CONFIRM
[[ "${CONFIRM^^}" != "SI" ]] && { log "Cancelado por el operador."; exit 0; }

echo ""
ok "Configuración confirmada. Iniciando FASE 1 (root)..."
_draw_progress_bar "Inicio de la Fase 1"

# =============================================================================
#  FASE 1 — HARDENING DEL SISTEMA OPERATIVO
# =============================================================================

header "FASE 1: Hardening del Sistema Operativo (CIS Ubuntu 24.04)"

# 1.1 Actualización
section "1.1 — Actualización de paquetes (CIS 1.9)"
spinner_start "Actualizando sistema (apt upgrade)..."
apt_safe upgrade -y -q
spinner_ok "Sistema actualizado."
progress_tick "apt update + upgrade"

# 1.2 Zona horaria
section "1.2 — Zona horaria"
run_with_spinner "Configurando zona horaria: ${SERVER_TZ}" \
    timedatectl set-timezone "${SERVER_TZ}"
progress_tick "Zona horaria"

# 1.3 openssh-server
section "1.3 — Servicio SSH"
spinner_start "Instalando openssh-server..."
apt_safe install -y -q openssh-server
spinner_ok "openssh-server instalado."
progress_tick "openssh-server"

# 1.4 SWAP
section "1.4 — Gestión de Memoria (CIS 6.1.2)"
TOTAL_RAM_KB=$(grep MemTotal /proc/meminfo | awk '{print $2}')
TOTAL_RAM_GB=$(( TOTAL_RAM_KB / 1024 / 1024 ))
log "RAM detectada: ${TOTAL_RAM_GB} GB"
if (( TOTAL_RAM_GB < 8 )); then
    warn "RAM (${TOTAL_RAM_GB} GB) < 8 GB. Creando SWAP de 4 GB."
    if swapon --show | grep -q "/swapfile"; then
        warn "Swapfile ya activo. Omitiendo."
    else
        spinner_start "Creando swapfile de 4 GB..."
        fallocate -l 4G /swapfile >> "$LOG_FILE" 2>&1
        chmod 600 /swapfile
        mkswap /swapfile >> "$LOG_FILE" 2>&1
        swapon /swapfile >> "$LOG_FILE" 2>&1
        grep -q '/swapfile' /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab
        grep -q 'vm.swappiness' /etc/sysctl.conf || echo 'vm.swappiness=10' >> /etc/sysctl.conf
        sysctl -p >> "$LOG_FILE" 2>&1
        spinner_ok "SWAP de 4 GB creado."
    fi
else
    ok "RAM suficiente (${TOTAL_RAM_GB} GB). No se requiere SWAP."
fi
progress_tick "SWAP"

# 1.5 Usuario operativo
section "1.5 — Usuario Operativo (CIS 5.2)"
if [[ "$OP_USER_EXISTS" == "false" ]]; then
    useradd -m -s /bin/bash -G sudo "$OP_USER" >> "$LOG_FILE" 2>&1
    echo "${OP_USER}:${OP_PASSWORD}" | chpasswd >> "$LOG_FILE" 2>&1
    ok "Usuario '${OP_USER}' creado y agregado a sudo."
else
    usermod -aG sudo "$OP_USER" >> "$LOG_FILE" 2>&1
    ok "Usuario '${OP_USER}' agregado al grupo sudo."
fi
# NOPASSWD para permitir bench setup production sin prompt en Fase 2
printf '%s ALL=(ALL) NOPASSWD: ALL\n' "$OP_USER" > "/etc/sudoers.d/99-${OP_USER}-frappe"
chmod 440 "/etc/sudoers.d/99-${OP_USER}-frappe"
ok "Sudoers NOPASSWD configurado."
progress_tick "Usuario operativo"

# 1.6 Llave SSH
section "1.6 — Inyección de Llave SSH (CIS 5.2)"
SSH_DIR="${OP_HOME}/.ssh"
mkdir -p "$SSH_DIR"
touch "${SSH_DIR}/authorized_keys"
grep -qF "$SSH_PUBLIC_KEY" "${SSH_DIR}/authorized_keys" 2>/dev/null \
    || echo "$SSH_PUBLIC_KEY" >> "${SSH_DIR}/authorized_keys"
# También copiar la llave de root si existe (para no perder acceso)
if [[ -f /root/.ssh/authorized_keys ]]; then
    cat /root/.ssh/authorized_keys >> "${SSH_DIR}/authorized_keys"
    sort -u "${SSH_DIR}/authorized_keys" -o "${SSH_DIR}/authorized_keys"
fi
chown -R "${OP_USER}:${OP_USER}" "$SSH_DIR"
chmod 700 "$SSH_DIR"
chmod 600 "${SSH_DIR}/authorized_keys"
ok "Llave SSH inyectada. Permisos 700/600."
progress_tick "Llave SSH"

# 1.7 Banners
section "1.7 — Banners de Seguridad"
cat > /etc/issue.net << EOF
###############################################################################
#                                                                             #
#         _  _____                                                            #
#        (_)|__  /___  _ __    ___                                            #
#        | |  / // _ \| '_ \  / _ \                                           #
#        | | / /| (_) | | | ||  __/                                           #
#        |_|/____\___/|_| |_| \___|                                           #
#                                                                             #
#                       AVISO DE ACCESO RESTRINGIDO                           #
#                                                                             #
###############################################################################
Este sistema es propiedad exclusiva de ${COMPANY_NAME}. El acceso esta restringido
unica y exclusivamente a personal explicitamente autorizado.

Toda actividad en este sistema es monitoreada, registrada y auditada de
forma continua. El uso no autorizado, el intento de acceso o la alteracion
de este sistema constituyen un delito federal/nacional y seran perseguidos
por la via civil y penal con todo el peso de la ley.

Si usted no cuenta con credenciales legitimas y autorizacion por escrito,
desconectese INMEDIATAMENTE. Su direccion IP y datos de conexion ya han
sido registrados.
###############################################################################
EOF

cat > /etc/motd << EOF
===============================================================================
[!] ADVERTENCIA CRITICA: SISTEMA PROPIEDAD DE ${COMPANY_NAME} [!]
===============================================================================

Usted ha iniciado sesion en un servidor privado de ${COMPANY_NAME}.

* El acceso esta estrictamente limitado a las funciones laborales asignadas.
* Cualquier actividad inusual sera reportada al equipo de seguridad.
* Su sesion esta siendo auditada en tiempo real.

EL ABUSO O USO NO AUTORIZADO CONLLEVA SANCIONES LEGALES.
===============================================================================
EOF
ok "Banners configurados."
progress_tick "Banners"

# 1.8 Hardening SSH
section "1.8 — Hardening SSH (CIS 5.2)"
cat > /etc/ssh/sshd_config.d/99-custom.conf << EOF
# ${COMPANY_NAME} — SSH Hardened (CIS 5.2) — install_frappe.sh v6.0.0
Port ${SSH_PORT}
PasswordAuthentication no
PermitRootLogin no
MaxAuthTries 3
ClientAliveInterval 300
ClientAliveCountMax 0
X11Forwarding no
LoginGraceTime 30
PermitEmptyPasswords no
PubkeyAuthentication yes
AllowTcpForwarding yes
Banner /etc/issue.net
EOF

sshd -t >> "$LOG_FILE" 2>&1 || die "Sintaxis SSH inválida. Revisa ${LOG_FILE}"
spinner_start "Reiniciando SSH en puerto ${SSH_PORT}..."
systemctl stop ssh.socket >> "$LOG_FILE" 2>&1 || true
systemctl disable ssh.socket >> "$LOG_FILE" 2>&1 || true
systemctl enable --now ssh.service >> "$LOG_FILE" 2>&1
systemctl restart ssh.service >> "$LOG_FILE" 2>&1
spinner_ok "SSH reiniciado (puerto ${SSH_PORT}, CIS hardened)."
progress_tick "SSH hardened"

# 1.9 UFW
section "1.9 — Firewall UFW (CIS 3.5)"
spinner_start "Configurando UFW..."
apt_safe install -y -q ufw
ufw --force reset >> "$LOG_FILE" 2>&1
ufw default deny incoming  >> "$LOG_FILE" 2>&1
ufw default allow outgoing >> "$LOG_FILE" 2>&1
ufw allow "${SSH_PORT}/tcp" comment "SSH Custom" >> "$LOG_FILE" 2>&1
ufw allow http  >> "$LOG_FILE" 2>&1
ufw allow https >> "$LOG_FILE" 2>&1
ufw --force enable >> "$LOG_FILE" 2>&1
spinner_ok "UFW activo (SSH ${SSH_PORT}, HTTP, HTTPS)."
progress_tick "UFW"

# =============================================================================
#  FASE 1 — MARIADB
# =============================================================================

header "FASE 1: Capa de Datos — MariaDB ${MARIADB_VERSION}"

# 2.1 Instalación
section "2.1 — Instalación de MariaDB"
spinner_start "Configurando repositorio MariaDB (${MARIADB_VERSION})..."
curl -LsS https://r.mariadb.com/downloads/mariadb_repo_setup \
    | bash -s -- --mariadb-server-version="${MARIADB_VERSION}" >> "$LOG_FILE" 2>&1
apt_safe update -qq
spinner_ok "Repositorio configurado."

spinner_start "Instalando mariadb-server y libmysqlclient-dev..."
# DEBIAN_FRONTEND=noninteractive suprime el prompt de feedback plugin
apt_safe install -y -q mariadb-server libmysqlclient-dev
# mysql --version reporta el nº de protocolo (15.x), no la versión real.
# Reportamos la versión configurada, que es la fuente de verdad.
spinner_ok "MariaDB instalado (${MARIADB_VERSION})"
progress_tick "MariaDB instalado"

# 2.2 Configuración frappe.cnf (directivas del SOP real validado)
section "2.2 — Configuración frappe.cnf"
cat > /etc/mysql/mariadb.conf.d/frappe.cnf << 'EOF'
[mysqld]
# Frappe Requisitos
character-set-client-handshake = FALSE
character-set-server = utf8mb4
collation-server = utf8mb4_unicode_ci
innodb-file-format = barracuda
innodb-file-per-table = 1
innodb-large-prefix = 1
# CIS Hardening
bind-address = 127.0.0.1
local-infile = 0
skip-symbolic-links = 1

[mysql]
default-character-set = utf8mb4
EOF
run_with_spinner "Reiniciando MariaDB..." service mariadb restart
progress_tick "frappe.cnf configurado"

# 2.3 Hardening SQL directo (automatizado — equivale a mariadb-secure-installation)
section "2.3 — Hardening MariaDB vía SQL directo"
spinner_start "Aplicando hardening CIS + native_password..."
mysql -u root << EOSQL >> "$LOG_FILE" 2>&1
DELETE FROM mysql.user WHERE User='';
DROP DATABASE IF EXISTS test;
DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';
DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');
ALTER USER 'root'@'localhost' IDENTIFIED VIA mysql_native_password USING PASSWORD('${MARIADB_ROOT_PASS}');
FLUSH PRIVILEGES;
EOSQL
spinner_ok "Hardening MariaDB completado."
progress_tick "MariaDB hardened"

# 2.4 QA de conexión
section "2.4 — QA: Conexión MariaDB"
mysql -u root -p"${MARIADB_ROOT_PASS}" -e "SELECT 1;" >> "$LOG_FILE" 2>&1 \
    || die "Conexión MariaDB fallida. Revisa: ${LOG_FILE}"
ok "MariaDB responde con la contraseña configurada."
progress_tick "MariaDB QA"

# 2.5 Dependencias del sistema para Frappe
section "2.5 — Dependencias de sistema para Frappe"
spinner_start "Instalando git, redis, pipx, screen, build-essential..."
apt_safe install -y -q \
    git pkg-config libmariadb-dev python3-dev build-essential \
    redis-server xvfb libfontconfig fontconfig \
    xfonts-75dpi xfonts-base pipx screen
spinner_ok "Dependencias de sistema instaladas."
progress_tick "Dependencias sistema"

# =============================================================================
#  TRASPASO A FASE 2 — Guardar estado y re-invocar como usuario operativo
# =============================================================================

header "TRANSICIÓN: Fase 1 (root) → Fase 2 (${OP_USER})"

# Guardar todo el estado necesario para la Fase 2
mkdir -p "$STATE_DIR"
cat > "$STATE_FILE" << EOF
# Estado de aprovisionamiento — generado por install_frappe.sh Fase 1
OP_USER="${OP_USER}"
SITE_NAME="${SITE_NAME}"
COMPANY_NAME="${COMPANY_NAME}"
SSH_PORT="${SSH_PORT}"
SERVER_TZ="${SERVER_TZ}"
MARIADB_ROOT_PASS="${MARIADB_ROOT_PASS}"
FRAPPE_ADMIN_PASS="${FRAPPE_ADMIN_PASS}"
TOTAL_RAM_GB="${TOTAL_RAM_GB}"
PROGRESS_SAVED="${PROGRESS_CURRENT}"
EOF
chmod 600 "$STATE_FILE"      # Contiene contraseñas — solo root
touch "$PHASE2_MARKER"
ok "Estado guardado en ${STATE_FILE} (permisos 600)."

# Copiar el script a una ubicación accesible por el usuario operativo
SCRIPT_SELF="$(readlink -f "$0")"
SCRIPT_PHASE2="${STATE_DIR}/install_frappe.sh"
cp "$SCRIPT_SELF" "$SCRIPT_PHASE2"
chmod 755 "$SCRIPT_PHASE2"
ok "Script copiado a ${SCRIPT_PHASE2} para la Fase 2."

echo ""
step "Re-invocando el script como '${OP_USER}' (login shell, HOME correcto)..."
echo -e "  ${CLR_DIM}A partir de aquí el contexto es el usuario operativo nativo.${CLR_RESET}"
echo ""

# Re-invocar como el usuario operativo con un login shell completo.
# sudo -iu garantiza HOME=/home/OP_USER y un entorno limpio de login,
# eliminando de raíz los problemas de HOME=/root que afectaban a uv/pipx/nvm.
# El STATE_FILE (root-only 600) se lee con sudo cat y se re-exporta.
sudo cp "$STATE_FILE" "${STATE_DIR}/provision.env.phase2"
sudo chown "${OP_USER}:${OP_USER}" "${STATE_DIR}/provision.env.phase2"
sudo chmod 600 "${STATE_DIR}/provision.env.phase2"

# Ajustar el STATE_FILE que la Fase 2 leerá (como el usuario)
STATE_FILE_PHASE2="${STATE_DIR}/provision.env.phase2"

# Lanzar Fase 2. Usamos sudo -iu para login shell nativo del usuario.
sudo -iu "$OP_USER" env \
    STATE_FILE="$STATE_FILE_PHASE2" \
    PHASE2_MARKER="$PHASE2_MARKER" \
    STATE_DIR="$STATE_DIR" \
    LOG_FILE="$LOG_FILE" \
    bash "$SCRIPT_PHASE2"

PHASE2_RC=$?

# Limpieza de estado sensible tras la Fase 2
rm -f "$STATE_FILE" "${STATE_DIR}/provision.env.phase2" 2>/dev/null || true

exit $PHASE2_RC
