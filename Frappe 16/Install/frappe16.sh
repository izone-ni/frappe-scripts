
set -Eeuo pipefail

# -----------------------------------------------------------------------------
#  COSTURA DE PRUEBAS
#  En producción BC_PREFIX está VACÍO y todas las rutas son las reales.
#  El self-test define BC_PREFIX=/tmp/sandbox para ejecutar el script completo
#  sin tocar el sistema. Es el único artificio y no altera el comportamiento.
# -----------------------------------------------------------------------------
BC_PREFIX="${BC_PREFIX:-}"
ETC="${BC_PREFIX}/etc"
VARDIR="${BC_PREFIX}/var"
HOMEBASE="${BC_PREFIX}/home"
ROOTDIR="${BC_PREFIX}/root"
USRLOCALBIN="${BC_PREFIX}/usr/local/bin"
USRBIN="${BC_PREFIX}/usr/bin"
STATE_DIR="${VARDIR}/lib/bashcore"
LOG_FILE="${VARDIR}/log/bashcore-frappe16.log"

# -----------------------------------------------------------------------------
#  CONSTANTES
# -----------------------------------------------------------------------------
TIMEZONE="America/Managua"   # valor por defecto; la pregunta 6/10 lo cambia
MARIADB_VERSION="mariadb-11.8.8"
NVM_VERSION="v0.39.7"
NODE_VERSION="24"
PYTHON_VERSION="3.14"
FRAPPE_BRANCH="version-16"
WKHTML_VERSION="0.12.6.1-2"
MIN_RAM_MB=3800
SWAP_SIZE="4G"

GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'
BLUE='\033[0;36m';  BOLD='\033[1m';   NC='\033[0m'

# -----------------------------------------------------------------------------
#  CANAL DIRECTO A LA TERMINAL  [C2]
#  Todo el stdout/stderr va al log vía tee, pero los prompts de 'read' (que no
#  terminan en newline) se quedarían en el buffer de la tubería. El descriptor 3
#  escribe siempre directo a la terminal.
# -----------------------------------------------------------------------------
# La prueba tiene que ser una APERTURA real: '[[ -w /dev/tty ]]' devuelve
# verdadero por los bits de permiso del nodo, pero el open() falla cuando el
# proceso no tiene terminal de control (cron, systemd, tubería, CI).
# ${#cadena} cuenta BYTES si el locale no es UTF-8, y los caracteres de marco
# (│ ╭ █) ocupan 3 bytes: sin esto la tarjeta se descuadra por completo.
if locale -a 2>/dev/null | grep -qiE '^C\.utf-?8$'; then
  export LC_ALL=C.UTF-8 LANG=C.UTF-8
fi
if (exec 3>/dev/tty) 2>/dev/null; then exec 3>/dev/tty; HAVE_TTY=1; else exec 3>&1; HAVE_TTY=0; fi

# Si el locale no es UTF-8, ${#cadena} cuenta BYTES y los caracteres de marco
# (│ ╭ █) ocupan 3: la tarjeta se descuadraría. En ese caso se usa un juego
# ASCII donde byte y carácter coinciden siempre.
if [[ "${LC_ALL:-${LANG:-}}" == *[Uu][Tt][Ff]* ]]; then
  BX_TL="╭"; BX_TR="╮"; BX_BL="╰"; BX_BR="╯"; BX_H="─"; BX_V="│"
  BX_FULL="█"; BX_EMPTY="░"
else
  BX_TL="+"; BX_TR="+"; BX_BL="+"; BX_BR="+"; BX_H="-"; BX_V="|"
  BX_FULL="#"; BX_EMPTY="."
fi
say() { printf "%b" "$*" >&3; }

# ---------------------------------------------------------------------------
#  Fuente de bloque para el banner de la empresa: mismo lenguaje visual que
#  el logotipo de iZone. Cada carácter son 5 filas; '#' se pinta con bloque.
# ---------------------------------------------------------------------------
declare -A FONT_BLOQUE=(
  ["A"]=" ##  |#  # |#### |#  # |#  # "
  ["B"]="###  |#  # |###  |#  # |###  "
  ["C"]=" ### |#    |#    |#    | ### "
  ["D"]="###  |#  # |#  # |#  # |###  "
  ["E"]="#### |#    |###  |#    |#### "
  ["F"]="#### |#    |###  |#    |#    "
  ["G"]=" ### |#    |# ## |#  # | ### "
  ["H"]="#  # |#  # |#### |#  # |#  # "
  ["I"]="#####|  #  |  #  |  #  |#####"
  ["J"]="  ###|   # |   # |#  # | ##  "
  ["K"]="#  # |# #  |##   |# #  |#  # "
  ["L"]="#    |#    |#    |#    |#### "
  ["M"]="#   #|## ##|# # #|#   #|#   #"
  ["N"]="#   #|##  #|# # #|#  ##|#   #"
  ["O"]=" ### |#   #|#   #|#   #| ### "
  ["P"]="###  |#  # |###  |#    |#    "
  ["Q"]=" ### |#   #|# # #|#  # | ## #"
  ["R"]="###  |#  # |###  |# #  |#  # "
  ["S"]=" ####|#    | ### |    #|#### "
  ["T"]="#####|  #  |  #  |  #  |  #  "
  ["U"]="#   #|#   #|#   #|#   #| ### "
  ["V"]="#   #|#   #|#   #| # # |  #  "
  ["W"]="#   #|#   #|# # #|## ##|#   #"
  ["X"]="#   #| # # |  #  | # # |#   #"
  ["Y"]="#   #| # # |  #  |  #  |  #  "
  ["Z"]="#####|   # |  #  | #   |#####"
  ["0"]=" ### |#  ##|# # #|##  #| ### "
  ["1"]="  #  | ##  |  #  |  #  | ### "
  ["2"]=" ### |#   #|   # |  #  |#####"
  ["3"]="#### |    #| ### |    #|#### "
  ["4"]="#  # |#  # |#####|   # |   # "
  ["5"]="#####|#    |#### |    #|#### "
  ["6"]=" ### |#    |#### |#   #| ### "
  ["7"]="#####|   # |  #  | #   | #   "
  ["8"]=" ### |#   #| ### |#   #| ### "
  ["9"]=" ### |#   #| ####|    #| ### "
  [" "]="   |   |   |   |   "
  ["-"]="     |     |#### |     |     "
  ["."]="   |   |   |   | # "
)

_glifo() { printf '%s' "${FONT_BLOQUE[$1]:-${FONT_BLOQUE[' ']}}"; }

# Banner de la empresa en letras de bloque, con el mismo estilo que iZone.
banner_empresa() {
  local nombre="${1:-}" i c fila glifo trozo
  nombre="${nombre^^}"
  (( ${#nombre} > 14 )) && nombre="${nombre:0:14}"
  say "\n"
  for fila in 1 2 3 4 5; do
    trozo=""
    for (( i=0; i<${#nombre}; i++ )); do
      c="${nombre:i:1}"
      glifo="$(_glifo "$c")"
      # extraer la fila N del glifo (campos separados por '|')
      trozo+="$(printf '%s' "$glifo" | cut -d'|' -f"$fila")"
      trozo+=" "
    done
    trozo="${trozo//#/█}"
    printf '  \033[0;36m\033[1m%s\033[0m\n' "$trozo" >&3
  done
  say "\n"
}

# Pregunta sí/no. El prompt sale por la terminal (fd 3) y la respuesta se lee
# de stdin, para que también funcione alimentando el script con un heredoc.
ask_yn() {
  local prompt="$1" def="${2:-n}" resp tries=0
  sleep 0.3   # deja que 'tee' vacíe su buffer: si no, la pregunta se adelanta
              # a los mensajes que la justifican y confunde al operador.
  while :; do
    if [[ "$def" == "y" ]]; then say "  ${prompt} [Y/n]: "; else say "  ${prompt} [y/N]: "; fi
    if ! read -r resp; then resp="$def"; fi   # EOF => valor por defecto
    resp="$(printf '%s' "${resp}" | tr '[:upper:]' '[:lower:]')"
    [[ -z "$resp" ]] && resp="$def"
    case "$resp" in
      y|yes|s|si|sí) return 0 ;;
      n|no)          return 1 ;;
      *)
        tries=$((${tries:-0}+1))
        if (( tries >= 5 )); then
          say "  Demasiadas respuestas inválidas; asumo '${def}'.\n"
          [[ "$def" == "y" ]] && return 0 || return 1
        fi
        say "  Responde 'y' (sí) o 'n' (no).\n" ;;
    esac
  done
}

phase() { echo -e "\n${BLUE}${BOLD}==============================================================${NC}"
          echo -e "${BLUE}${BOLD} $* ${NC}"
          echo -e "${BLUE}${BOLD}==============================================================${NC}"; }
ok()    { echo -e "  ${GREEN}[ OK ]${NC} $*"; }
info()  { echo -e "  ${BLUE}[INFO]${NC} $*"; }
# warn y fail salen al log Y a la pantalla: un problema nunca queda oculto.
warn()  { echo -e "  ${YELLOW}[WARN]${NC} $*"; printf '\033[2K  \033[1;33m[WARN]\033[0m %b\n' "$*" >&3; CARD_LINES=0; }
fail()  { echo -e "  ${RED}[FAIL]${NC} $*";  printf '\033[2K  \033[0;31m[FAIL]\033[0m %b\n' "$*" >&3; CARD_LINES=0; }
skip()  { echo -e "  ${YELLOW}[SKIP]${NC} $* ${YELLOW}(ya completado)${NC}"; }

# [V2][V3] Evidencia objetiva de avance. El log en silencio NO significa nada:
# yarn copia decenas de miles de archivos sin imprimir. Lo que sí demuestra
# progreso es que el árbol de frappe-bench crezca en disco.
# 'du' devuelve error si un archivo desaparece mientras recorre el árbol, y
# eso ocurre CONSTANTEMENTE durante 'yarn install'. Con pipefail activo, esa
# tubería mataría al monitor mediante el trap ERR. Nunca puede fallar.
bench_size_mb() {
  local out=""
  out="$( { du -sm "${BENCH_DIR:-/nonexistent}" 2>/dev/null || true; } | { awk '{print $1+0; exit}' || true; } )"
  [[ "$out" =~ ^[0-9]+$ ]] || out=0
  printf '%s' "$out"
}

# Causas reales de congelación dentro de un contenedor, en orden de frecuencia.
pressure_report() {
  local avail swap ooms high maxe ipct dgb
  avail=$(awk '/MemAvailable/{print int($2/1024)}' /proc/meminfo 2>/dev/null)
  swap=$(awk '/SwapTotal/{print int($2/1024)}' /proc/meminfo 2>/dev/null)
  echo "        memoria disponible: ${avail:-?}MB | swap: ${swap:-?}MB"

  # cgroup v2: prueba objetiva de estrangulamiento por límite de memoria.
  if [[ -r /sys/fs/cgroup/memory.events ]]; then
    high=$(awk '/^high /{print $2}' /sys/fs/cgroup/memory.events 2>/dev/null)
    maxe=$(awk '/^max /{print $2}'  /sys/fs/cgroup/memory.events 2>/dev/null)
    echo "        cgroup memoria: estrangulado ${high:-0} veces, tope alcanzado ${maxe:-0} veces"
  fi

  ooms=$( { dmesg 2>/dev/null || journalctl -k --no-pager 2>/dev/null; } | grep -ci 'killed process' )
  (( ${ooms:-0} > 0 )) && echo "        OOM killer: ${ooms} proceso(s) eliminados por falta de memoria"

  dgb=$(df -BG --output=avail "${BENCH_DIR:-/}" 2>/dev/null | tail -1 | tr -dc '0-9')
  ipct=$(df -i --output=ipcent "${BENCH_DIR:-/}" 2>/dev/null | tail -1 | tr -dc '0-9')
  echo "        disco libre: ${dgb:-?}GB | inodos usados: ${ipct:-?}%"

  # Los tres procesos que más CPU consumen del usuario: si están al 0%, no trabaja.
  ps -u "${NEW_USER:-root}" -o pcpu,rss,etime,comm --sort=-pcpu --no-headers 2>/dev/null \
    | sed -n '1,3p' | sed 's/^/        proc: /'
}

# [P4] Catálogo de pasos. El orden es el de ejecución y los identificadores
# deben coincidir con los que emite la fase de usuario.
PASOS_ID=(dep ssh db runtime
          node bench uv init get_erpnext get_hrms get_lending get_wiki
          site inst_erpnext inst_hrms inst_lending inst_wiki migrate build configs
          prod web)
PASOS_LABEL=("Dependencias del sistema"
             "Hardening SSH + usuario"
             "MariaDB y base de datos"
             "Entorno de ejecución"
             "Node 24 + Yarn"
             "frappe-bench (pipx)"
             "Python 3.14 (uv)"
             "bench init: núcleo de Frappe"
             "Descarga ERPNext"
             "Descarga HRMS"
             "Descarga Lending"
             "Descarga Wiki"
             "Creación del sitio"
             "Instala ERPNext"
             "Instala HRMS"
             "Instala Lending"
             "Instala Wiki"
             "Migraciones"
             "Compilación de assets"
             "Configs Nginx/Supervisor"
             "Pase a producción"
             "Nginx + Supervisor")
# Peso real de cada paso (suman 100) y duración típica en segundos: con esto
# el porcentaje avanza proporcional al trabajo y se puede estimar lo que falta.
PASOS_PESO=(3 2 5 5   4 3 3 20   5 3 3 2   4   8 5 4 3   3 8 1   4 2)
PASOS_SEGS=(120 60 180 240   180 90 120 1500   300 180 180 120   180   420 300 240 180   180 600 30   240 60)
PROGRESS_FILE="${STATE_DIR}/progress"

# Lee TODO el archivo de progreso de una sola pasada, en Bash puro: sin
# subprocesos por paso y sin tuberías (una menos que pueda dar SIGPIPE).
declare -A ESTADO_PASO=()
declare -A INICIO_PASO=()
leer_progreso() {
  local id st _ts
  ESTADO_PASO=()
  [[ -r "$PROGRESS_FILE" ]] || return 0
  while IFS='|' read -r id st _ts; do
    if [[ -n "${id:-}" ]]; then
      ESTADO_PASO["$id"]="$st"                  # la última línea gana
      [[ "$st" == "RUN" ]] && INICIO_PASO["$id"]="${_ts:-0}"
    fi
  done < "$PROGRESS_FILE"
  return 0
}
estado_de() { printf '%s' "${ESTADO_PASO[$1]:-}"; }

# Porcentaje 0-100 ponderado, interpolando el paso en curso para que la barra
# nunca se quede quieta durante un paso largo como 'bench init'.
porcentaje_global() {
  set +e; trap - ERR
  local i st acum=0 ini ahora frac
  ahora="$(date +%s)"
  for i in "${!PASOS_ID[@]}"; do
    st="${ESTADO_PASO[${PASOS_ID[$i]}]:-}"
    case "$st" in
      OK|ERR|NA) acum=$(( acum + PASOS_PESO[i] )) ;;
      RUN)
        ini="${INICIO_PASO[${PASOS_ID[$i]}]:-0}"
        if (( ini > 0 )); then
          frac=$(( (ahora - ini) * 90 / PASOS_SEGS[i] ))
          (( frac > 90 )) && frac=90
          (( frac < 0 ))  && frac=0
          acum=$(( acum + PASOS_PESO[i] * frac / 100 ))
        fi ;;
    esac
  done
  (( acum > 100 )) && acum=100
  printf '%s' "$acum"
  return 0
}

# Minutos restantes estimados: lo que falta de los pasos pendientes más lo
# que quede del actual, según sus duraciones típicas.
eta_minutos() {
  set +e; trap - ERR
  local i st segs=0 ini ahora resta
  ahora="$(date +%s)"
  for i in "${!PASOS_ID[@]}"; do
    st="${ESTADO_PASO[${PASOS_ID[$i]}]:-}"
    case "$st" in
      OK|ERR|NA) ;;
      RUN)
        ini="${INICIO_PASO[${PASOS_ID[$i]}]:-0}"
        resta=$(( PASOS_SEGS[i] - (ahora - ini) ))
        (( resta < 30 )) && resta=30
        segs=$(( segs + resta )) ;;
      *) segs=$(( segs + PASOS_SEGS[i] )) ;;
    esac
  done
  printf '%s' $(( (segs + 59) / 60 ))
  return 0
}

# --- TARJETA DE PROGRESO ÚNICA ---------------------------------------------
# Una sola barra para todo el despliegue. El detalle línea por línea vive en
# el log; en pantalla sólo fase, descripción, porcentaje y tiempo restante.
# Identifica la subtarea en curso leyendo el final del log: es la diferencia
# entre "no sé si avanza" y "está instalando dependencias JS".
subtarea_actual() {
  set +e; trap - ERR
  local ultimas
  ultimas="$( { tail -n 60 "${UP_LOG:-/dev/null}" 2>/dev/null || true; } | { tr -d '\r' || true; } )"
  case "$ultimas" in
    *"Building assets"*|*"esbuild"*)            echo "compilando assets" ;;
    *"Copying"*|*"yarn install"*|*"Linking dependencies"*)
                                                echo "instalando dependencias JS (yarn)" ;;
    *"Fetching"*|*"Resolving packages"*)        echo "resolviendo paquetes JS" ;;
    *"Installing frappe"*|*"virtualenv"*|*"Creating virtual"*|*"Resolved "*)
                                                echo "construyendo el entorno Python" ;;
    *"Cloning"*|*"Getting frappe"*|*"remote:"*|*"Receiving objects"*)
                                                echo "clonando el repositorio" ;;
    *"Installing"*)                             echo "instalando paquetes" ;;
    *) echo "" ;;
  esac
  return 0
}

# Última línea con contenido del log, limpia y recortada. UNA pasada de awk:
# sin tuberías encadenadas que puedan fallar con el log vacío.
ultima_linea_log() {
  set +e; trap - ERR
  local l="" prog
  prog='{ gsub(/\r/,""); gsub(/\033\[[0-9;]*[a-zA-Z]/,""); if ($0 ~ /[^ \t]/) last=$0 } END { print last }'
  l="$(awk "$prog" "${UP_LOG:-/dev/null}" 2>/dev/null || true)"
  l="${l#"${l%%[![:space:]]*}"}"
  (( ${#l} > 52 )) && l="${l:0:49}..."
  printf '%s' "$l"
  return 0
}

CARD_W=62
CARD_LINES=0

# Una fila de la tarjeta. Se pasa el texto PLANO (para medir) y el estilo
# ANSI aparte: así el relleno es exacto y el borde derecho nunca se desalinea.
_row() {
  local plain="$1" estilo="${2:-}" pad
  pad=$(( CARD_W - 4 - ${#plain} ))
  (( pad < 0 )) && { plain="${plain:0:CARD_W-7}..."; pad=0; }
  printf '\033[2K\033[0;36m  %s\033[0m %b%s\033[0m%*s \033[0;36m%s\033[0m\n' \
         "$BX_V" "$estilo" "$plain" "$pad" "" "$BX_V" >&3
}
_borde() {
  local izq="$1" der="$2" i
  local linea=""
  for ((i=0; i<CARD_W-2; i++)); do linea+="$BX_H"; done
  printf '\033[2K\033[0;36m  %s%s%s\033[0m\n' "$izq" "$linea" "$der" >&3
}

render_card() {
  set +e; trap - ERR
  leer_progreso
  local pct fase="" desc="" rest i st ancho llenos barra="" mins="${1:-0}"
  pct="$(porcentaje_global)"
  rest="$(eta_minutos)"
  for i in "${!PASOS_ID[@]}"; do
    st="${ESTADO_PASO[${PASOS_ID[$i]}]:-}"
    [[ "$st" == "RUN" ]] && fase="${PASOS_LABEL[$i]}"
  done
  if [[ -z "$fase" ]]; then
    if (( pct >= 100 )); then fase="Despliegue completado"; else fase="Preparando el entorno"; fi
  fi
  desc="$(subtarea_actual 2>/dev/null || true)"
  [[ -z "$desc" ]] && desc="$(ultima_linea_log 2>/dev/null || true)"
  [[ -z "$desc" ]] && desc="trabajando"

  ancho=$(( CARD_W - 6 ))
  llenos=$(( pct * ancho / 100 ))
  for ((i=0; i<ancho; i++)); do
    if (( i < llenos )); then barra+="$BX_FULL"; else barra+="$BX_EMPTY"; fi
  done

  if (( HAVE_TTY == 1 && CARD_LINES > 0 )); then
    printf '\033[%dA' "$CARD_LINES" >&3
  fi
  CARD_LINES=0

  _borde "$BX_TL" "$BX_TR"
  # Fila 1: título a la izquierda, estimación a la derecha.
  local sep="·"; [[ "$BX_V" == "|" ]] && sep="-"
  local tit="Frappe 16 ${sep} ${fase}" der="~${rest} min" hueco
  hueco=$(( CARD_W - 4 - ${#tit} - ${#der} ))
  (( hueco < 1 )) && { tit="${tit:0:CARD_W-7-${#der}}"; hueco=1; }
  _row "${tit}$(printf '%*s' "$hueco" '')${der}" "\033[1m"
  _row "$desc" "\033[2m"
  _row "" ""
  _row "${pct}%$(printf '%*s' $(( ancho - ${#pct} - 5 )) '')100%" "\033[1m"
  _row "$barra" "\033[0;32m"
  _row "transcurrido: ${mins} min" "\033[2m"
  _borde "$BX_BL" "$BX_BR"

  # Cabecera y cierre se pintan alrededor: se reconstruye el bloque completo.
  CARD_LINES=8
  (( HAVE_TTY == 0 )) && CARD_LINES=0
  return 0
}

# Compatibilidad: el resto del script sigue llamando a estos nombres.
render_progreso() { render_card "$@"; }
barra_compacta()  { render_card 0; }

# [Z1] Publica el estado de un paso y muestra una barra compacta. La usan
# las fases que corren como root; la fase de usuario emite al mismo archivo.
avance() {
  local id="$1" est="$2"
  mkdir -p "$(dirname "$PROGRESS_FILE")" 2>/dev/null || true
  printf '%s|%s|%s\n' "$id" "$est" "$(date +%s)" >> "$PROGRESS_FILE" 2>/dev/null || true
  # No se pinta aquí: el latido repinta LA MISMA tarjeta. Si cada paso
  # dibujara la suya, aparecerían varias barras apiladas en pantalla.
  return 0
}


# Resumen de una línea para el LOG (sin códigos de control).
log_progreso() {
  local total=${#PASOS_ID[@]} hechos=0 i st actual=""
  leer_progreso
  for i in "${!PASOS_ID[@]}"; do
    st="$(estado_de "${PASOS_ID[$i]}")"
    [[ "$st" == "OK" ]] && hechos=$((hechos+1))
    [[ "$st" == "RUN" ]] && actual="${PASOS_LABEL[$i]}"
  done
  local sub; sub="$(subtarea_actual)"
  echo "  PROGRESO: ${hechos}/${total} pasos ($(( hechos * 100 / total ))%) | en curso: ${actual:-—}${sub:+ (${sub})} | ${1} min | árbol: $(bench_size_mb) MB"
}

# [A1] 'bench init' pregunta "Do you want to rollback these changes?" SÓLO
# cuando ya ha fallado (bench/commands/make.py:105). Ese prompt es el
# síntoma; el error de verdad está justo encima. Lo extraemos para no
# obligar a nadie a bucear en miles de líneas.
analizar_fallo() {
  local n
  # [S4] El prompt de sudo es inconfundible y no debería aparecer nunca.
  if grep -q "\[sudo\] password for" "$UP_LOG" 2>/dev/null; then
    fail ""
    fail "  >> Un comando pidió la contraseña de sudo y se quedó esperando."
    fail "     Ocurre en bench/utils/bench.py:340 cuando 'supervisorctl'"
    fail "     falla por permisos y bench reintenta con sudo."
    fail "     Arreglo inmediato, como root:"
    fail "       echo '${NEW_USER} ALL=(ALL) NOPASSWD: ALL' > /etc/sudoers.d/99-bashcore-install"
    fail "       chmod 440 /etc/sudoers.d/99-bashcore-install"
    fail ""
  fi
  if grep -q "rollback these changes" "$UP_LOG" 2>/dev/null; then
    fail ""
    fail "  >> 'bench init' FALLÓ y pidió confirmación para deshacer los"
    fail "     cambios. El error real es el que aparece justo antes:"
    n="$(grep -n "rollback these changes" "$UP_LOG" 2>/dev/null | sed -n '1p' | cut -d: -f1)"
    if [[ -n "${n:-}" ]]; then
      local desde=$(( n > 30 ? n - 30 : 1 ))
      sed -n "${desde},${n}p" "$UP_LOG" 2>/dev/null | sed 's/^/        /' || true
    fi
    fail ""
  fi
  # Errores frecuentes con su explicación, buscados una sola vez.
  local txt
  txt="$(tail -n 400 "$UP_LOG" 2>/dev/null | tr -d '\r')"
  case "$txt" in
    *"No module named"*)        fail "  >> Falta un módulo de Python: revisa la versión elegida." ;;
    *"Could not find a version"*|*"no matching distribution"*|*"No solution found"*)
                                fail "  >> Una dependencia no existe para Python ${PYTHON_VERSION}." 
                                fail "     Prueba con:  --python-version 3.12" ;;
    *"error: command 'gcc'"*|*"Failed building wheel"*)
                                fail "  >> Falló una compilación C: falta un -dev o no hay wheel." ;;
    *"Permission denied"*)      fail "  >> Problema de permisos en el home del usuario." ;;
    *"Connection"*"refused"*|*"Temporary failure in name resolution"*)
                                fail "  >> Problema de red/DNS dentro del contenedor." ;;
    *"No space left"*)          fail "  >> Disco lleno." ;;
    *"Killed"*)                 fail "  >> Un proceso fue eliminado (probable OOM)." ;;
  esac
}


# -----------------------------------------------------------------------------
#  GENERADORES Y SANEADORES
# -----------------------------------------------------------------------------

# [C1] Generador de contraseñas SIN SIGPIPE.
# El bug de la v1: 'tr -dc ... < /dev/urandom | head -c 20'. head cierra la
# tubería al llegar a 20 bytes, tr muere con SIGPIPE (141), pipefail lo
# propaga y set -e mata el script. Aquí leemos un bloque finito con head
# ARRIBA (sustitución de proceso) y recortamos con expansión de Bash: no hay
# ningún consumidor que cierre la tubería antes de tiempo.
gen_pass() {
  local n="${1:-20}" out
  out="$(LC_ALL=C tr -dc 'A-Za-z0-9' < <(head -c 4096 /dev/urandom))"
  if (( ${#out} < n )); then
    fail "Entropía insuficiente al generar la contraseña."
    return 1
  fi
  printf '%s' "${out:0:n}"
}

# [C4] Recorte de espacios en Bash puro. 'xargs' interpreta comillas y
# backslashes: con una llave SSH o un comentario con comillas, corrompía
# el valor o abortaba con "unmatched double quote".
trim() {
  local s="$1"
  s="${s#"${s%%[![:space:]]*}"}"   # espacios a la izquierda
  s="${s%"${s##*[![:space:]]}"}"   # espacios a la derecha
  printf '%s' "$s"
}

# -----------------------------------------------------------------------------
#  PUNTOS DE CONTROL  [C7]
#  Cada paso deja una marca. Si el script muere (red, apt, OOM), al relanzarlo
#  salta lo ya hecho. Sin esto, un fallo en la Fase 7 costaba 40 minutos.
# -----------------------------------------------------------------------------
is_done()  { [[ -f "${STATE_DIR}/$1.done" ]]; }
mark_done(){ mkdir -p "$STATE_DIR"; date -Is > "${STATE_DIR}/$1.done"; }

# -----------------------------------------------------------------------------
#  APT ROBUSTO  [C9]
#  Espera el lock de dpkg (unattended-upgrades suele tenerlo al arrancar la VM)
#  y reintenta ante errores transitorios de red o de mirror.
# -----------------------------------------------------------------------------
wait_apt_lock() {
  local waited=0
  while fuser "${VARDIR}/lib/dpkg/lock-frontend" >/dev/null 2>&1 \
     || fuser "${VARDIR}/lib/apt/lists/lock" >/dev/null 2>&1; do
    (( waited == 0 )) && info "Esperando a que se libere el lock de apt..."
    sleep 5; waited=$((waited+5))
    if (( waited > 300 )); then
      fail "El lock de apt sigue tomado tras 5 minutos."
      return 1
    fi
  done
  (( waited > 0 )) && ok "Lock liberado tras ${waited}s."
  return 0
}

apt_do() {
  local tries=0
  while :; do
    wait_apt_lock || return 1
    if DEBIAN_FRONTEND=noninteractive apt-get \
         -o Dpkg::Options::=--force-confdef \
         -o Dpkg::Options::=--force-confdef \
         -o Dpkg::Options::=--force-confold "$@" </dev/null; then
      return 0
    fi
    tries=$((tries+1))
    if (( tries >= 4 )); then
      fail "apt-get $* falló tras ${tries} intentos."
      return 1
    fi
    warn "apt-get $1 falló (intento ${tries}); reintento en 20s..."
    sleep 20
  done
}

# -----------------------------------------------------------------------------
#  TRAP GLOBAL
# -----------------------------------------------------------------------------
# shellcheck disable=SC2154  # 'rc' se asigna dentro del propio trap
trap 'rc=$?; set +e
      fail "Error (código $rc) en la línea $LINENO: ${BASH_COMMAND}"
      fail "Log: ${LOG_FILE}"
      fail "Ya completado: $(ls "${STATE_DIR}" 2>/dev/null | tr "\n" " ")"
      fail "Relanza el MISMO comando: se reanudará desde el paso que falló."
      sleep 1   # deja que tee vacíe su buffer antes de salir
      exit $rc' ERR

# =============================================================================
#  ARGUMENTOS
# =============================================================================
ACTION="install"
while (( $# > 0 )); do
  case "$1" in
    --status) ACTION="status" ;;
    --diag)   ACTION="diag"   ;;
    --python-version) shift; PYTHON_VERSION="${1:-3.14}" ;;
    --attach) ACTION="attach" ;;
    --reset)  ACTION="reset"  ;;
    -h|--help)
      cat <<AYUDA
bashcore-frappe16 v2.0

  (sin argumentos)   Instala o reanuda el despliegue.
  --status           Muestra los pasos ya completados.
  --diag             Empaqueta TODOS los logs en un .tar.gz para compartir.
  --python-version X.Y  Fuerza la versión de Python (por defecto 3.14).
  --attach           Se reengancha a la consola de la instalación en curso.
  --reset            Borra el progreso (NO desinstala nada).
  -h, --help         Esta ayuda.

Variables de entorno (pruebas):
  BC_PREFIX=/ruta    Redirige TODAS las escrituras a un sandbox.
AYUDA
      exit 0 ;;
    *) echo "Argumento desconocido: $1 (usa --help)"; exit 2 ;;
  esac
  shift
done

if [[ "$ACTION" == "status" ]]; then
  echo "Pasos completados en ${STATE_DIR}:"
  if [[ -d "$STATE_DIR" ]]; then
    for f in "$STATE_DIR"/*.done; do
      [[ -e "$f" ]] || { echo "  (ninguno)"; break; }
      printf '  %-28s %s\n' "$(basename "$f" .done)" "$(cat "$f")"
    done
  else
    echo "  (ninguno)"
  fi
  exit 0
fi

# --- [S7] Paquete de diagnóstico --------------------------------------------
if [[ "$ACTION" == "diag" ]]; then
  # Un recolector de diagnóstico que se aborta a la primera dificultad es
  # inútil: justo se usa cuando el sistema está roto. Aquí se desactivan
  # errexit Y el trap ERR (recordatorio: 'set +e' NO desactiva el trap), y
  # cada recolector es best-effort.
  set +e
  trap - ERR
  TS="$(date +%Y%m%d-%H%M%S)"
  DIAG_DIR="$(mktemp -d)"
  DIAG_OUT="${ROOTDIR}/bashcore-diagnostico-${TS}.tar.gz"
  echo "Recopilando diagnóstico..."

  # Logs del script y de la fase de usuario.
  cp "$LOG_FILE" "${DIAG_DIR}/01-bashcore.log" 2>/dev/null || true
  for h in "${HOMEBASE}"/*/bashcore-userphase.log; do
    [[ -f "$h" ]] && cp "$h" "${DIAG_DIR}/02-userphase.log"
  done

  # Estado de los pasos completados.
  { echo "== Pasos completados =="; ls -la "$STATE_DIR" 2>/dev/null; } > "${DIAG_DIR}/03-estado.txt"

  # Entorno del sistema.
  {
    echo "== Fecha ==";        date -Is
    echo; echo "== SO ==";     cat /etc/os-release 2>/dev/null
    echo; echo "== Kernel ==";  uname -a
    echo; echo "== Contenedor =="; systemd-detect-virt -c 2>/dev/null || echo "no-contenedor"
    echo; echo "== Memoria ==";  free -h 2>/dev/null
    echo; echo "== Disco ==";    df -h 2>/dev/null
    echo; echo "== Puertos ==";  ss -tlnp </dev/null 2>/dev/null || true
  } > "${DIAG_DIR}/04-sistema.txt" 2>&1

  # Servicios.
  {
    for svc in mariadb redis-server nginx supervisor ssh; do
      echo "===== ${svc} ====="
      (systemctl status "$svc" --no-pager -l </dev/null 2>&1 || true) | sed -n '1,25p' 
      echo
    done
    echo "===== supervisorctl status ====="
    supervisorctl status </dev/null 2>&1 || true
  } > "${DIAG_DIR}/05-servicios.txt" 2>&1

  # Journal de los servicios que suelen fallar.
  {
    for svc in mariadb nginx supervisor; do
      echo "===== journalctl -u ${svc} ====="
      journalctl -u "$svc" -n 60 --no-pager </dev/null 2>&1 || echo "(sin journal)"
      echo
    done
  } > "${DIAG_DIR}/06-journal.txt" 2>&1

  # Versiones de la pila.
  {
    # Una línea por herramienta SIEMPRE: si un comando no imprime nada, la
    # línea quedaría sin cerrar y el informe saldría ilegible.
    for b in bench node npm yarn uv python3 mariadb nginx supervisord wkhtmltopdf screen git; do
      if command -v "$b" >/dev/null 2>&1; then
        v="$( { "$b" --version </dev/null 2>&1 || "$b" -v </dev/null 2>&1 || echo '(no responde)'; } | sed -n '1p' )"
        printf '%-14s %s\n' "$b" "${v:-(sin salida)}"
      else
        printf '%-14s %s\n' "$b" "(ausente)"
      fi
    done
  } > "${DIAG_DIR}/07-versiones.txt" 2>&1

  # Logs internos de bench (sin archivos de configuración: contienen claves).
  for bd in "${HOMEBASE}"/*/frappe-bench; do
    [[ -d "$bd" ]] || continue
    { echo "== ${bd} =="; ls -la "$bd"; echo; echo "== apps =="; ls -la "$bd/apps" 2>/dev/null
      echo; echo "== sites =="; ls -la "$bd/sites" 2>/dev/null; } > "${DIAG_DIR}/08-bench-arbol.txt" 2>&1
    mkdir -p "${DIAG_DIR}/09-bench-logs"
    for lf in "$bd"/logs/*.log; do
      [[ -f "$lf" ]] && tail -n 200 "$lf" > "${DIAG_DIR}/09-bench-logs/$(basename "$lf")" 2>/dev/null
    done
  done

  # Configuración de Nginx y MariaDB (sin secretos).
  mkdir -p "${DIAG_DIR}/10-config"
  cp "${ETC}/mysql/mariadb.conf.d/"*.cnf "${DIAG_DIR}/10-config/" 2>/dev/null || true
  cp "${ETC}/nginx/conf.d/"*.conf        "${DIAG_DIR}/10-config/" 2>/dev/null || true
  cp "${ETC}/ssh/sshd_config.d/99-custom.conf" "${DIAG_DIR}/10-config/" 2>/dev/null || true

  # Red de seguridad: si alguna contraseña se filtró a un log, se enmascara.
  if [[ -n "${DB_ROOT_PASS:-}" ]]; then
    grep -rl "$DB_ROOT_PASS" "$DIAG_DIR" 2>/dev/null | while read -r f; do
      sed -i "s/${DB_ROOT_PASS}/***OCULTA***/g" "$f" 2>/dev/null || true
    done
  fi
  # Cualquier cosa con aspecto de credencial en los .json de sitios queda fuera.
  find "$DIAG_DIR" -name 'site_config.json' -delete 2>/dev/null || true

  if ! tar -czf "$DIAG_OUT" -C "$DIAG_DIR" . 2>/dev/null; then
    echo "No se pudo empaquetar. Los archivos quedan en: ${DIAG_DIR}"
    exit 1
  fi
  rm -rf "$DIAG_DIR"
  chmod 600 "$DIAG_OUT"
  if [[ ! -s "$DIAG_OUT" ]]; then
    echo "El paquete quedó vacío: revisa permisos en ${ROOTDIR}"
    exit 1
  fi
  echo
  echo "Paquete de diagnóstico listo:"
  echo "    ${DIAG_OUT}   ($(du -h "$DIAG_OUT" 2>/dev/null | cut -f1))"
  echo
  echo "Descárgalo con:"
  echo "    scp -P <puerto> root@<ip>:${DIAG_OUT} ."
  echo
  echo "Contiene: logs del script y de la fase de usuario, estado de los pasos,"
  echo "servicios, journal, versiones, árbol de bench y configuraciones."
  echo "Las contraseñas se enmascaran y site_config.json se excluye."
  exit 0
fi

# --- Reengancharse a la consola en curso ------------------------------------
if [[ "$ACTION" == "attach" ]]; then
  for h in "${HOMEBASE}"/*/bashcore-userphase.log; do
    if [[ -f "$h" ]]; then
      echo "Siguiendo ${h}  (Ctrl+C para salir; la instalación NO se detiene)"
      tail -n 50 -F "$h"
      exit 0
    fi
  done
  echo "No encontré ninguna instalación en curso."
  echo "Sesiones screen activas:"
  screen -ls 2>/dev/null || true
  exit 1
fi

if [[ "$ACTION" == "reset" ]]; then
  rm -rf "$STATE_DIR"
  echo "Progreso borrado. La próxima ejecución empezará desde la Fase 1."
  exit 0
fi

# =============================================================================
#  FASE 0: VERIFICACIONES PREVIAS
# =============================================================================
if [[ -z "$BC_PREFIX" && "${EUID}" -ne 0 ]]; then
  echo -e "${RED}[FAIL]${NC} Este script debe ejecutarse como root. Usa: sudo -i"
  exit 1
fi

# [C2] El log se abre AHORA, antes de cualquier otra cosa, y con permisos 0600
# porque acumula el detalle completo de la instalación.
mkdir -p "$(dirname "$LOG_FILE")" "$STATE_DIR" "$ROOTDIR"

# [F7] El estado guardado puede venir de una versión anterior del script. Los
# pasos de MariaDB de la v2/v3 escribieron 'skip-name-resolve' y dejaron la
# autenticación TCP rota: hay que reaplicarlos, no saltarlos.
STATE_VERSION=5
PREV_STATE_VERSION="$(cat "${STATE_DIR}/version" 2>/dev/null || echo 0)"
if [[ "$PREV_STATE_VERSION" != "$STATE_VERSION" ]]; then
  if [[ -f "${STATE_DIR}/fase2_config.done" || -f "${STATE_DIR}/fase1_sshd.done" ]]; then
    rm -f "${STATE_DIR}/fase2_config.done" "${STATE_DIR}/fase2_secure.done" \
          "${STATE_DIR}/fase1_sshd.done"
    echo "  Estado previo v${PREV_STATE_VERSION}: se reaplicarán los pasos de SSH y"
    echo "  MariaDB (keepalive que cortaba sesiones + autenticación TCP)."
  fi
  echo "$STATE_VERSION" > "${STATE_DIR}/version"
fi
touch "$LOG_FILE"; chmod 600 "$LOG_FILE"
# El detalle va ÚNICAMENTE al log: la pantalla queda para la tarjeta. El log
# sigue conteniendo todo, que es la fuente de verdad ante cualquier fallo.
exec >> "$LOG_FILE" 2>&1

say "
\033[0;36m\033[1m  ██╗\033[0m███████╗ ██████╗ ███╗   ██╗███████╗
\033[0;36m\033[1m  ██║\033[0m╚══███╔╝██╔═══██╗████╗  ██║██╔════╝
\033[0;36m\033[1m  ██║\033[0m  ███╔╝ ██║   ██║██╔██╗ ██║█████╗
\033[0;36m\033[1m  ██║\033[0m ███╔╝  ██║   ██║██║╚██╗██║██╔══╝
\033[0;36m\033[1m  ██║\033[0m███████╗╚██████╔╝██║ ╚████║███████╗
\033[0;36m\033[1m  ╚═╝\033[0m╚══════╝ ╚═════╝ ╚═╝  ╚═══╝╚══════╝
\033[1m       E N T E R P R I S E\033[0m
        Frappe 16 · ERPNext · HRMS · Lending · Wiki
        Ubuntu 24.04 LTS · CIS Hardening · v21.0

"
echo -e "\n### iZone bashcore-frappe16 v21.0 | Inicio: $(date -Is) | PID $$ ###"
[[ -n "$BC_PREFIX" ]] && warn "MODO PRUEBAS: todas las rutas bajo ${BC_PREFIX}"

phase "FASE 0: VERIFICACIONES PREVIAS"
ok "Ejecutando como root (EUID ${EUID})."

if [[ -r /etc/os-release ]]; then
  # shellcheck disable=SC1091
  . /etc/os-release
  if [[ "${VERSION_ID:-}" == "24.04" ]]; then
    ok "SO: ${PRETTY_NAME}"
  else
    warn "SO: ${PRETTY_NAME:-desconocido}. Validado solo en Ubuntu 24.04 LTS."
  fi
fi

ARCH="$(dpkg --print-architecture)"
[[ "$ARCH" == "amd64" || "$ARCH" == "arm64" ]] || { fail "Arquitectura sin binarios de wkhtmltopdf: $ARCH"; exit 1; }
ok "Arquitectura: ${ARCH}"

# --- [P1] Detección de virtualización: Proxmox CT (LXC) vs VM/físico ------
IS_CT=0; CT_KIND="none"; CT_UNPRIV=0
if command -v systemd-detect-virt >/dev/null 2>&1; then
  # Cuando NO hay contenedor imprime 'none' y sale con código 1: el '|| true'
  # evita que set -e aborte y que se concatene un segundo 'none'.
  CT_KIND="$(systemd-detect-virt -c 2>/dev/null || true)"
  CT_KIND="$(trim "${CT_KIND:-none}")"
fi
if [[ "$CT_KIND" == "none" || -z "$CT_KIND" ]]; then
  # Fallback sin systemd-detect-virt: la variable que inyecta LXC en PID 1.
  if grep -qa 'container=lxc' /proc/1/environ 2>/dev/null; then CT_KIND="lxc"; fi
fi
case "$CT_KIND" in
  lxc|lxc-libvirt|systemd-nspawn|docker|podman) IS_CT=1 ;;
esac

if (( IS_CT )); then
  # uid_map: si el UID 0 del contenedor no es el 0 del host, es NO privilegiado.
  if [[ -r /proc/self/uid_map ]] && ! grep -qE '^[[:space:]]*0[[:space:]]+0[[:space:]]' /proc/self/uid_map; then
    CT_UNPRIV=1
  fi
  if (( CT_UNPRIV )); then
    info "Entorno: contenedor (${CT_KIND})."
  else
    info "Entorno: contenedor (${CT_KIND})."
  fi
  info "Se aplican los ajustes propios de un entorno contenedorizado."
else
  ok "Entorno: VM o hardware físico."
fi

# --- [P9] El script depende de systemctl en todas las fases ----------------
if [[ -z "$BC_PREFIX" && ! -d /run/systemd/system ]]; then
  fail "Este servidor no arrancó con systemd como PID 1."
  fail "Usa una imagen de Ubuntu 24.04 estándar, con systemd como PID 1."
  fail "Si es un CT, revisa: pct config <VMID> y que no esté en modo 'unmanaged'."
  exit 1
fi

MEM_MB=$(awk '/MemTotal/{print int($2/1024)}' /proc/meminfo)
SWAP_MB=$(awk '/SwapTotal/{print int($2/1024)}' /proc/meminfo)
ok "RAM: ${MEM_MB}MB | Swap: ${SWAP_MB}MB"

# La compilación de assets de la v16 (esbuild + yarn) es el pico de memoria.
if (( MEM_MB < MIN_RAM_MB && SWAP_MB < 2048 )); then
  if (( IS_CT )); then
    # [P3] Dentro de un CT el swapfile no funciona: el swap lo administra el
    # host vía cgroup. Crearlo aquí falla o, peor, queda inservible.
    warn "RAM insuficiente (${MEM_MB}MB) y sin swap, y estamos en un CT."
    warn "En un contenedor el swap se define en el sistema anfitrión."
    warn "Sin eso, 'bench build' (esbuild/yarn) puede morir por OOM."
    info "Continúo y acoto NODE_OPTIONS para reducir el riesgo."
  elif is_done swap; then
    skip "Swap"
  else
    warn "Menos de 4GB de RAM sin swap: la compilación de assets puede fallar."
    info "Creando swapfile de ${SWAP_SIZE}..."
    if fallocate -l "$SWAP_SIZE" "${BC_PREFIX}/swapfile" 2>/dev/null \
       || dd if=/dev/zero of="${BC_PREFIX}/swapfile" bs=1M count=4096 status=none; then
      chmod 600 "${BC_PREFIX}/swapfile"
      mkswap "${BC_PREFIX}/swapfile" >/dev/null
      swapon "${BC_PREFIX}/swapfile"
      grep -q '^/swapfile' "${ETC}/fstab" 2>/dev/null \
        || echo '/swapfile none swap sw 0 0' >> "${ETC}/fstab"
      ok "Swap de ${SWAP_SIZE} activo y persistente."
      mark_done swap
    else
      warn "No se pudo crear el swapfile; continúo bajo tu riesgo."
    fi
  fi
fi

# [P8] Techo de heap para esbuild/yarn: sin esto Node intenta usar toda la
# RAM del host (en LXC ve la del CT vía lxcfs, pero el margen es estrecho).
if (( MEM_MB < 6000 )); then
  NODE_HEAP_MB=$(( MEM_MB * 60 / 100 ))
  (( NODE_HEAP_MB < 1024 )) && NODE_HEAP_MB=1024
  NODE_OPTS="--max-old-space-size=${NODE_HEAP_MB}"
  info "NODE_OPTIONS acotado a ${NODE_HEAP_MB}MB de heap para el build."
else
  NODE_OPTS=""
fi

DISK_FREE_GB=$(df -BG --output=avail "${BC_PREFIX}/" 2>/dev/null | tail -1 | tr -dc '0-9')
if [[ -n "$DISK_FREE_GB" ]] && (( DISK_FREE_GB < 15 )); then
  warn "Solo ${DISK_FREE_GB}GB libres. Frappe + apps + node_modules piden ~12GB."
else
  ok "Disco libre: ${DISK_FREE_GB:-?}GB"
fi

# =============================================================================
#  LAS 10 PREGUNTAS  (único tramo interactivo)
# =============================================================================
# [Z3] Las 7 preguntas viven dentro de un bucle: si la confirmación final no
# es LISTO, se repiten todas desde el principio. Los bloques no se indentan
# a propósito: los delimitadores de heredoc deben quedar en la columna 0.
while :; do

phase "PARÁMETROS DE DESPLIEGUE (10 preguntas)"
say "${YELLOW}Tras responder estas 10 preguntas el script es 100% desatendido.${NC}\n\n"

# --- 1) Nombre de la empresa -------------------------------------------------
say "${BOLD}1/10${NC} Nombre de la empresa (aparecerá en el encabezado): "
while :; do
  read -r EMPRESA
  EMPRESA="$(trim "$EMPRESA")"
  if (( ${#EMPRESA} < 2 )); then
    fail "Escribe al menos 2 caracteres."; say "     > "; continue
  fi
  if (( ${#EMPRESA} > 24 )); then
    fail "Máximo 24 caracteres (para que quepa en el encabezado)."; say "     > "; continue
  fi
  case "$EMPRESA" in
    *[\\\'\"\`\$]*) fail "Sin comillas, backslash, backtick ni \$."; say "     > "; continue ;;
  esac
  break
done
say "\n"
banner_empresa "$EMPRESA"

# --- 2) Usuario operativo ----------------------------------------------------
# En un servidor ya en uso suele existir un usuario administrativo en el grupo
# sudo. Se detecta y se ofrece como opción, para no crear otro innecesario.
SUDO_USERS="$(getent group sudo 2>/dev/null | cut -d: -f4 | tr ',' ' ' || true)"
SUDO_USERS="$(trim "${SUDO_USERS:-}")"
SUGERENCIA=""
if [[ -n "$SUDO_USERS" ]]; then
  for _u in $SUDO_USERS; do
    [[ "$_u" == "root" ]] && continue
    SUGERENCIA="$_u"; break
  done
fi
if [[ -n "$SUGERENCIA" ]]; then
  info "Usuarios con sudo detectados: ${SUDO_USERS}"
fi


while :; do
  if [[ -n "$SUGERENCIA" ]]; then
  say "${BOLD}2/10${NC} Usuario operativo (se crea si no existe; ej: sysadmin) [${BOLD}${SUGERENCIA}${NC}]: "
else
  say "${BOLD}2/10${NC} Usuario operativo (se crea si no existe; ej: sysadmin): "
fi
  read -r NEW_USER
  NEW_USER="$(trim "$NEW_USER")"
  # Enter en blanco acepta el usuario administrativo ya existente.
  [[ -z "$NEW_USER" && -n "$SUGERENCIA" ]] && NEW_USER="$SUGERENCIA"
  if [[ ! "$NEW_USER" =~ ^[a-z_][a-z0-9_-]{2,31}$ ]]; then
    fail "Inválido: minúsculas, números, '-' y '_' (3-32 caracteres)."; continue
  fi
  case "$NEW_USER" in
    root|daemon|bin|sys|www-data|mysql|nobody|systemd-*|redis|nginx)
      fail "'${NEW_USER}' es un usuario reservado del sistema."; continue ;;
  esac
  if id "$NEW_USER" &>/dev/null; then
    warn "El usuario '${NEW_USER}' ya existe: se reutilizará, no se recreará."
  fi
  break
done

# --- 3) Contraseña del usuario operativo [F4] --------------------------------
# Se pregunta explícitamente: es la clave que usarás para 'sudo'. El acceso
# SSH seguirá siendo SÓLO por llave (PasswordAuthentication no).
if id "$NEW_USER" &>/dev/null; then
  say "\n${BOLD}3/10${NC} '${NEW_USER}' YA EXISTE. Escribe SU contraseña actual (o la nueva\n"
  say "      que quieras dejarle: se aplicará al usuario existente)\n"
else
  say "\n${BOLD}3/10${NC} Contraseña para el usuario NUEVO '${NEW_USER}' (mín. 12 caracteres)\n"
fi
while :; do
  say "     Contraseña: "; read -rs OS_USER_PASS; say "\n"
  say "     Confirmar : "; read -rs OS_USER_PASS2; say "\n"
  if [[ "$OS_USER_PASS" != "$OS_USER_PASS2" ]]; then
    fail "No coinciden."; continue
  fi
  if (( ${#OS_USER_PASS} < 12 )); then
    fail "Mínimo 12 caracteres (tienes ${#OS_USER_PASS})."; continue
  fi
  # 'chpasswd' usa ':' como separador y no admite saltos de línea.
  case "$OS_USER_PASS" in
    *:*)   fail "No puede contener ':' (lo usa chpasswd como separador)."; continue ;;
    *\ *)  fail "Evita los espacios."; continue ;;
  esac
  break
done
unset OS_USER_PASS2
ok "Contraseña del usuario aceptada (${#OS_USER_PASS} caracteres)."

# --- 4) Llave pública SSH ----------------------------------------------------
say "\n${BOLD}4/10${NC} Llave pública SSH para '${NEW_USER}' (una sola línea)\n"
while :; do
  say "     > "
  read -r SSH_PUBKEY
  SSH_PUBKEY="$(trim "$SSH_PUBKEY")"
  if [[ "$SSH_PUBKEY" =~ ^(ssh-(rsa|ed25519|dss)|ecdsa-sha2-nistp[0-9]+|sk-(ssh-ed25519|ecdsa-sha2-nistp256))@?[a-z0-9.-]*[[:space:]]+[A-Za-z0-9+/=]{20,}([[:space:]].*)?$ ]]; then
    # Validación real con ssh-keygen (mejor que una regex).
    # OJO: se usa un archivo temporal, NO 'printf | ssh-keygen'. Con pipefail,
    # si el lector cierra la tubería antes de leer, printf recibe SIGPIPE y
    # una llave perfectamente válida sería rechazada. Es la misma familia de
    # error que el 'tr | head' que rompió la v1.
    if command -v ssh-keygen >/dev/null 2>&1; then
      KEY_TMP="$(mktemp)"
      printf '%s\n' "$SSH_PUBKEY" > "$KEY_TMP"
      if KEY_FP="$(ssh-keygen -l -f "$KEY_TMP" 2>/dev/null)"; then
        rm -f "$KEY_TMP"
        ok "Llave válida: ${KEY_FP}"
        break
      else
        rm -f "$KEY_TMP"
        fail "ssh-keygen rechaza la llave (¿está truncada o mal pegada?)."; continue
      fi
    fi
    break
  fi
  fail "No parece una llave pública. Debe iniciar con ssh-ed25519, ssh-rsa, ecdsa-sha2-..."
  fail "Ojo: NO pegues la llave PRIVADA ni el contenido de un archivo .pem."
done

# --- 5) Puerto SSH -----------------------------------------------------------
while :; do
  say "\n${BOLD}5/10${NC} Puerto SSH personalizado (ej: 2222): "
  read -r SSH_PORT
  SSH_PORT="$(trim "$SSH_PORT")"
  if [[ ! "$SSH_PORT" =~ ^[0-9]+$ ]] || (( SSH_PORT < 1024 || SSH_PORT > 65535 )); then
    fail "Debe ser un número entre 1024 y 65535."; continue
  fi
  # Puertos que Frappe, MariaDB y Nginx ya usan.
  case "$SSH_PORT" in
    3306|8000|9000|11000|12000|13000|6379)
      fail "El puerto ${SSH_PORT} lo usa la pila de Frappe. Elige otro."; continue ;;
  esac
  # Si el puerto ya está escuchando puede ser NUESTRO propio sshd en una
  # reanudación: rechazarlo dejaría el script en un bucle infinito.
  if ss -H -tln 2>/dev/null | grep -q ":${SSH_PORT}[[:space:]]"; then
    if grep -qs "^Port ${SSH_PORT}$" "${ETC}/ssh/sshd_config.d/99-custom.conf"; then
      info "El puerto ${SSH_PORT} ya lo sirve el sshd que configuró este script (reanudación)."
    else
      fail "El puerto ${SSH_PORT} ya está ocupado por otro servicio."; continue
    fi
  fi
  break
done

# --- 6) Password de root de MariaDB ------------------------------------------
say "\n${BOLD}6/10${NC} Contraseña para 'root' de MariaDB (mín. 12 caracteres)\n"
while :; do
  say "     Contraseña: "; read -rs DB_ROOT_PASS; say "\n"
  say "     Confirmar : "; read -rs DB_ROOT_PASS2; say "\n"
  if [[ "$DB_ROOT_PASS" != "$DB_ROOT_PASS2" ]]; then
    fail "No coinciden."; continue
  fi
  if (( ${#DB_ROOT_PASS} < 12 )); then
    fail "Mínimo 12 caracteres (tienes ${#DB_ROOT_PASS})."; continue
  fi
  # Estos metacaracteres rompen el SQL y los heredocs.
  case "$DB_ROOT_PASS" in
    *\'*|*\"*|*\\*|*\`*|*\$*|*' '*)
      fail "Sin comilla simple, comilla doble, backslash, backtick, \$ ni espacios."; continue ;;
  esac
  break
done
unset DB_ROOT_PASS2
ok "Contraseña de MariaDB aceptada (${#DB_ROOT_PASS} caracteres)."

# --- 7) Zona horaria ---------------------------------------------------------
say "\n${BOLD}7/10${NC} Zona horaria [${BOLD}America/Managua${NC}]: "
while :; do
  read -r TZ_IN
  TZ_IN="$(trim "$TZ_IN")"
  if [[ -z "$TZ_IN" ]]; then
    TIMEZONE="America/Managua"; break
  fi
  if [[ -f "/usr/share/zoneinfo/${TZ_IN}" ]]; then
    TIMEZONE="$TZ_IN"; break
  fi
  fail "No existe '/usr/share/zoneinfo/${TZ_IN}'. Ejemplos: America/Managua,"
  fail "Europe/Madrid, America/Mexico_City, UTC. (Enter = America/Managua)"
  say "     > "
done
ok "Zona horaria: ${TIMEZONE}"

# --- 8) Contraseña del Administrator de Frappe [F4] -------------------------
say "\n${BOLD}8/10${NC} Contraseña del usuario 'Administrator' de Frappe (mín. 12)\n"
while :; do
  say "     Contraseña: "; read -rs ADMIN_PASS; say "\n"
  say "     Confirmar : "; read -rs ADMIN_PASS2; say "\n"
  if [[ "$ADMIN_PASS" != "$ADMIN_PASS2" ]]; then
    fail "No coinciden."; continue
  fi
  if (( ${#ADMIN_PASS} < 12 )); then
    fail "Mínimo 12 caracteres (tienes ${#ADMIN_PASS})."; continue
  fi
  # Va como argumento de 'bench new-site --admin-password'.
  case "$ADMIN_PASS" in
    *\'*|*\"*|*\\*|*\`*|*\$*) fail "Sin comillas, backslash, backtick ni \$."; continue ;;
  esac
  break
done
unset ADMIN_PASS2
ok "Contraseña de Administrator aceptada (${#ADMIN_PASS} caracteres)."

# --- 9) Nombre del sitio -----------------------------------------------------
while :; do
  say "\n${BOLD}9/10${NC} Nombre del sitio Frappe (ej: misitio.com): "
  read -r SITE_NAME
  SITE_NAME="$(trim "$SITE_NAME")"
  SITE_NAME="${SITE_NAME,,}"                    # a minúsculas (Bash 4+)
  SITE_NAME="${SITE_NAME#http://}"              # tolera que peguen una URL
  SITE_NAME="${SITE_NAME#https://}"
  SITE_NAME="${SITE_NAME%%/*}"
  if [[ "$SITE_NAME" =~ ^[a-z0-9]([a-z0-9.-]*[a-z0-9])?$ ]] && (( ${#SITE_NAME} <= 60 )); then
    break
  fi
  fail "Inválido: minúsculas, números, puntos y guiones. Sin '_' ni espacios."
done

# --- 10) Aplicaciones a instalar ---------------------------------------------
say "\n${BOLD}10/10${NC} ¿Qué aplicaciones quieres instalar?\n"
say "      ${BOLD}1${NC}) Todas: ERPNext + HRMS + Lending + Wiki   ${BOLD}(recomendado)${NC}\n"
say "      ${BOLD}2${NC}) Las tres principales: ERPNext + HRMS + Lending\n"
say "      ${BOLD}3${NC}) Sólo ERPNext\n"
say "      ${BOLD}4${NC}) Sólo HRMS\n"
say "      ${BOLD}5${NC}) Sólo Lending\n"
say "      ${BOLD}6${NC}) Sólo Wiki\n"
say "      ${BOLD}7${NC}) Ninguna: sólo el framework Frappe\n"
while :; do
  say "      > "
  read -r APPS_OPT
  APPS_OPT="$(trim "$APPS_OPT")"
  case "$APPS_OPT" in
    1|"") APPS_SEL="erpnext hrms lending wiki" ;;
    2)    APPS_SEL="erpnext hrms lending" ;;
    3)    APPS_SEL="erpnext" ;;
    4)    APPS_SEL="hrms" ;;
    5)    APPS_SEL="lending" ;;
    6)    APPS_SEL="wiki" ;;
    7)    APPS_SEL="" ;;
    *)    fail "Elige un número del 1 al 7."; continue ;;
  esac
  break
done
# HRMS depende de ERPNext: Frappe no lo instala sin él.
case " ${APPS_SEL} " in
  *" hrms "*)
    case " ${APPS_SEL} " in
      *" erpnext "*) ;;
      *) warn "HRMS requiere ERPNext: se añade automáticamente."
         APPS_SEL="erpnext ${APPS_SEL}" ;;
    esac ;;
esac
ok "Aplicaciones: ${APPS_SEL:-(sólo el framework)}"

# --- Derivados ---------------------------------------------------------------
USER_HOME="${HOMEBASE}/${NEW_USER}"
BENCH_DIR="${USER_HOME}/frappe-bench"
CRED_FILE="${ROOTDIR}/bashcore-credenciales-${SITE_NAME}.txt"

# [C5]+[F4] Las contraseñas ahora las define el usuario, así que NO se
# guardan en disco: el archivo sólo conserva los metadatos del despliegue.
umask 077
cat > "$CRED_FILE" <<CRED
# bashcore-frappe16 :: despliegue $(date -Is)
# Las contraseñas las definiste tú y NO se almacenan aquí a propósito.
EMPRESA='${EMPRESA}'
SITE_NAME='${SITE_NAME}'
SSH_PORT='${SSH_PORT}'
NEW_USER='${NEW_USER}'
BENCH_DIR='${BENCH_DIR}'
# Usuario de la aplicación: Administrator (con la contraseña que indicaste)
CRED
chmod 600 "$CRED_FILE"
umask 022
ok "Metadatos del despliegue en ${CRED_FILE} (0600, sin contraseñas)."

# --- Resumen y confirmación única -------------------------------------------
say "
$(echo -e "${BOLD}RESUMEN DE LA OPERACIÓN${NC}")
  Empresa .............: ${EMPRESA}
  Usuario operativo ...: ${NEW_USER}
  Puerto SSH ..........: ${SSH_PORT}   (el 22 quedará CERRADO)
  Autenticación SSH ...: solo llave pública (password OFF, root OFF)
  Zona horaria ........: ${TIMEZONE}
  MariaDB .............: ${MARIADB_VERSION}, bind 127.0.0.1
  Node / Python .......: ${NODE_VERSION} / ${PYTHON_VERSION}
  Frappe ..............: ${FRAPPE_BRANCH}
  Sitio ...............: ${SITE_NAME}
  Aplicaciones ........: ${APPS_SEL:-sólo el framework}
  Bench ...............: ${BENCH_DIR}
  Contraseñas .........: definidas por ti (no se guardan en disco)
  Metadatos ...........: ${CRED_FILE}

$(echo -e "${RED}${BOLD}ADVERTENCIA CRÍTICA${NC}")
  1) SSH se moverá al puerto ${SSH_PORT}. Ábrelo en el firewall de tu
     proveedor (Security Group / Cloud Firewall) ANTES de continuar.
  2) NO cierres esta sesión hasta validar el acceso nuevo en otra terminal.
  3) El login por contraseña y el login directo de root quedan desactivados.

"
# [Z3] LISTO arranca. SALIR termina. Cualquier otra cosa repite todo.
say "Escribe ${BOLD}LISTO${NC} para iniciar, o ${BOLD}SALIR${NC} para terminar: "
read -r CONFIRM || CONFIRM="SALIR"
CONFIRM="$(trim "$CONFIRM")"
CONFIRM="${CONFIRM^^}"
case "$CONFIRM" in
  LISTO)
    ok "Confirmado. Comienza el despliegue."
    break ;;
  SALIR|EXIT|CANCELAR|Q)
    warn "Operación cancelada. No se ha modificado nada."
    exit 0 ;;
  *)
    warn "No escribiste LISTO: repetimos las 10 preguntas desde el principio."
    warn "(escribe SALIR en la confirmación si quieres terminar)"
    say "\n"
    continue ;;
esac
echo "### Confirmado. Despliegue desatendido iniciado: $(date -Is) ###"


done

# --- [F5] Dependencias: se listan las que faltan y se pide confirmación ----
# Herramientas sin las que el script no puede trabajar. Formato "comando:paquete".
DEPS=(
  "awk:mawk" "sed:sed" "grep:grep" "dpkg:dpkg" "systemctl:systemd"
  "curl:curl" "wget:wget" "git:git" "sudo:sudo" "ss:iproute2"
  "gpg:gnupg" "fuser:psmisc" "getent:libc-bin"
)
MISSING_CMDS=(); MISSING_PKGS=()
for pair in "${DEPS[@]}"; do
  dcmd="${pair%%:*}"; dpkgname="${pair##*:}"
  if ! command -v "$dcmd" >/dev/null 2>&1; then
    MISSING_CMDS+=("$dcmd")
    # Evitamos duplicados en la lista de paquetes.
    case " ${MISSING_PKGS[*]-} " in *" ${dpkgname} "*) ;; *) MISSING_PKGS+=("$dpkgname") ;; esac
  fi
done   # cierra SÓLO la detección: sin esto, la instalación y la verificación
       # de ramas se repetían una vez por cada dependencia comprobada.

avance dep RUN
if (( ${#MISSING_CMDS[@]} == 0 )); then
  ok "Dependencias básicas presentes (${#DEPS[@]} comprobadas)."
else
  # [Z2] Sin preguntas: se instalan y se informa de cada paso.
  warn "Faltan estas herramientas: ${MISSING_CMDS[*]}"
  info "Instalando automáticamente: ${MISSING_PKGS[*]}"
  if ! command -v apt-get >/dev/null 2>&1; then
    fail "No existe apt-get: este script requiere Debian/Ubuntu."
    exit 1
  fi
  info "  paso 1/2 · actualizando el índice de paquetes (apt-get update)"
  apt_do update
  info "  paso 2/2 · instalando ${#MISSING_PKGS[@]} paquete(s)"
  apt_do install -y "${MISSING_PKGS[@]}"
  STILL=()
  for dcmd in "${MISSING_CMDS[@]}"; do
    command -v "$dcmd" >/dev/null 2>&1 || STILL+=("$dcmd")
  done
  if (( ${#STILL[@]} > 0 )); then
    fail "Siguen faltando tras la instalación: ${STILL[*]}"
    fail "Revisa tus repositorios apt y relanza."
    exit 1
  fi
  ok "Dependencias instaladas y verificadas: ${MISSING_PKGS[*]}"
fi

# --- [Z4] Red y ramas: se comprueba ANTES de invertir 20 minutos -----------
info "Comprobando acceso a GitHub y existencia de las ramas..."
RAMAS_MAL=""
if command -v git >/dev/null 2>&1; then
  for rb in "frappe/frappe:${FRAPPE_BRANCH}" "frappe/erpnext:${FRAPPE_BRANCH}" \
            "frappe/hrms:${FRAPPE_BRANCH}" "frappe/lending:${FRAPPE_BRANCH}" \
            "frappe/wiki:master"; do
    repo="${rb%%:*}"; rama="${rb##*:}"
    if GIT_TERMINAL_PROMPT=0 timeout 45 git ls-remote --heads \
         "https://github.com/${repo}.git" "$rama" 2>/dev/null | grep -q .; then
      ok "  ${repo} · rama ${rama}"
    else
      warn "  ${repo} · rama ${rama}: NO responde o no existe"
      RAMAS_MAL="${RAMAS_MAL} ${repo}#${rama}"
    fi
  done
  if [[ -n "$RAMAS_MAL" ]]; then
    warn "Repositorios con problemas:${RAMAS_MAL}"
    warn "Si es el núcleo (frappe/frappe), 'bench init' fallará seguro."
    warn "Comprueba DNS y salida a internet del contenedor:"
    warn "    getent hosts github.com && curl -I https://github.com"
    case "$RAMAS_MAL" in
      *"frappe/frappe"*)
        fail "Sin acceso al repositorio del núcleo no tiene sentido continuar."
        exit 1 ;;
    esac
  fi
else
  warn "git no disponible todavía; se omite la comprobación de ramas."
fi
avance dep OK

# --- [A4] ¿Hay wheels para la versión de Python elegida? --------------------
# Sin wheel precompilado, pip/uv compilan desde fuente: minutos de gcc y
# picos de RAM. Se comprueba ANTES de empezar, consultando PyPI.
verificar_wheels() {
  local ver="$1" faltan=""
  command -v python3 >/dev/null 2>&1 || return 0
  faltan="$(python3 - "$ver" <<'PYEOF' 2>/dev/null || true
import json, sys, urllib.request
ver = sys.argv[1].replace(".", "")
tag = "cp" + ver
faltan = []
for p in ("gevent","cryptography","lxml","pillow","rapidfuzz","cffi","psutil"):
    try:
        with urllib.request.urlopen(f"https://pypi.org/pypi/{p}/json", timeout=8) as r:
            files = [f["filename"] for f in json.load(r)["urls"]]
        universal = any(f.endswith("py3-none-any.whl") or "abi3" in f for f in files)
        if not (universal or any(tag in f and f.endswith(".whl") for f in files)):
            faltan.append(p)
    except Exception:
        pass   # sin red: no bloqueamos el despliegue por esto
print(" ".join(faltan))
PYEOF
)"
  printf '%s' "$faltan"
}

info "Comprobando wheels precompilados para Python ${PYTHON_VERSION}..."
SIN_WHEEL="$(verificar_wheels "$PYTHON_VERSION")"
if [[ -z "$SIN_WHEEL" ]]; then
  ok "Los paquetes con extensiones C tienen wheel para Python ${PYTHON_VERSION}."
else
  warn "Sin wheel para Python ${PYTHON_VERSION}:${SIN_WHEEL}"
  warn "Se compilarían desde fuente: mucho tiempo de CPU y picos de RAM."
  info "Se mantiene Python ${PYTHON_VERSION} (tu guía lo exige)."
  info "Si la instalación fallara por esto, relanza con: --python-version 3.12"
  info "El script ya reintenta solo con 3.12 como tercer intento."
fi



export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a
# Con la pantalla ocupada por la tarjeta, un prompt sería invisible: se cierra
# la entrada del script completo y se neutraliza todo lo que use /dev/tty.
exec 0</dev/null
export GIT_TERMINAL_PROMPT=0 GIT_ASKPASS=/bin/true SSH_ASKPASS=/bin/true
export SUDO_ASKPASS=/bin/false PIP_NO_INPUT=1 CI=1

# Latido: repinta la tarjeta cada 3 s durante todo el despliegue, incluidas
# las fases largas de root (apt, MariaDB), para que nunca parezca detenido.
INICIO_GLOBAL="$(date +%s)"
TICKER_PID=""
ticker_on() {
  (( HAVE_TTY == 1 )) || return 0
  ( while :; do
      render_card $(( ($(date +%s) - INICIO_GLOBAL) / 60 ))
      sleep 3
    done ) &
  TICKER_PID=$!
}
ticker_off() { [[ -n "${TICKER_PID:-}" ]] && kill "$TICKER_PID" 2>/dev/null; TICKER_PID=""; }
trap 'ticker_off' EXIT
ticker_on
mkdir -p "${ETC}/needrestart/conf.d"
echo '$nrconf{restart} = "a";' > "${ETC}/needrestart/conf.d/99-bashcore.conf"

# =============================================================================
#  FASE 1: HARDENING DEL SISTEMA OPERATIVO  (CIS 1.9, 5.2)
# =============================================================================
avance ssh RUN
phase "FASE 1: HARDENING DEL SISTEMA OPERATIVO"

if is_done fase1_update; then
  skip "Actualización del sistema"
else
  info "Actualizando catálogo y parches de seguridad (CIS 1.9)..."
  apt_do update
  apt_do -y upgrade
  ok "Sistema actualizado."
  mark_done fase1_update
fi

# --- [P5] Paquetes que las plantillas LXC de Proxmox suelen NO traer -------
if is_done fase1_base; then
  skip "Paquetes base y locale"
else
  info "Instalando paquetes base (las plantillas LXC vienen mínimas)..."
  apt_do install -y sudo openssh-server ca-certificates curl wget gnupg \
                    locales tzdata lsb-release procps psmisc iproute2 less nano \
                    screen coreutils
  ok "Paquetes base presentes."

  # [P4] Locale UTF-8. Las plantillas LXC arrancan en POSIX/C y tanto bench
  # como Frappe fallan al procesar acentos, ñ o símbolos de moneda.
  info "Configurando locale UTF-8..."
  if ! locale -a 2>/dev/null | grep -qiE 'en_US\.utf-?8'; then
    if [[ -f "${ETC}/locale.gen" ]]; then
      sed -i 's/^# *en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' "${ETC}/locale.gen" || true
    else
      echo "en_US.UTF-8 UTF-8" > "${ETC}/locale.gen"
    fi
    locale-gen en_US.UTF-8 >/dev/null 2>&1 || warn "locale-gen falló; uso C.UTF-8."
  fi
  # C.UTF-8 existe siempre en Ubuntu y no necesita generación: es el respaldo.
  if command -v update-locale >/dev/null 2>&1; then
    update-locale LANG=en_US.UTF-8 LC_ALL= 2>/dev/null || update-locale LANG=C.UTF-8 2>/dev/null || true
  fi
  ok "Locale configurado: $(locale -a 2>/dev/null | grep -icE 'utf-?8' || echo 0) locales UTF-8 disponibles."
  mark_done fase1_base
fi
# El resto del script (y bench) heredan un locale sano.
export LANG="${LANG:-C.UTF-8}"

if is_done fase1_timezone; then
  skip "Zona horaria"
else
  info "Fijando zona horaria en ${TIMEZONE} (vital para logs de auditoría)..."
  # [P2] En un CT, timedatectl falla ("Failed to connect to bus" / "System has
  # not been booted with systemd"): el reloj lo controla el host. La zona
  # horaria sí es local al contenedor y se fija con el symlink + /etc/timezone.
  if timedatectl set-timezone "$TIMEZONE" 2>/dev/null; then
    ok "Zona horaria aplicada vía timedatectl."
  else
    warn "timedatectl no disponible (normal en LXC): uso el método directo."
    if [[ -f "/usr/share/zoneinfo/${TIMEZONE}" ]]; then
      ln -sf "/usr/share/zoneinfo/${TIMEZONE}" "${ETC}/localtime"
      echo "$TIMEZONE" > "${ETC}/timezone"
      ok "Zona horaria aplicada vía /etc/localtime + /etc/timezone."
    else
      warn "No existe /usr/share/zoneinfo/${TIMEZONE}; ¿falta el paquete tzdata?"
    fi
  fi
  (( IS_CT )) && info "En un contenedor, la hora la fija el sistema anfitrión."
  ok "Hora del servidor: $(date 2>/dev/null || echo '?')"
  mark_done fase1_timezone
fi

# --- 1.1 Usuario operativo: crear SÓLO si no existe [F6] ---------------------
if is_done fase1_usuario; then
  skip "Usuario operativo '${NEW_USER}'"
else
  if id "$NEW_USER" &>/dev/null; then
    info "El usuario '${NEW_USER}' YA EXISTE: no se recrea; paso a validarlo."

    # a) Home real (puede no ser /home/<usuario>).
    REAL_HOME="$(getent passwd "$NEW_USER" | cut -d: -f6 || true)"
    if [[ -n "$REAL_HOME" && "${BC_PREFIX}${REAL_HOME}" != "$USER_HOME" ]]; then
      warn "Su home es '${REAL_HOME}', no '${USER_HOME#"$BC_PREFIX"}'. Uso el real."
      USER_HOME="${BC_PREFIX}${REAL_HOME}"
      BENCH_DIR="${USER_HOME}/frappe-bench"
      ENV_FILE="${USER_HOME}/.bashcore.env"
    fi
    if [[ ! -d "$USER_HOME" ]]; then
      warn "El home '${USER_HOME}' no existe; lo creo."
      mkdir -p "$USER_HOME"
      chown "${NEW_USER}:${NEW_USER}" "$USER_HOME"
    fi
    ok "Home validado: ${USER_HOME}"

    # b) Shell utilizable: con nologin/false, 'su - usuario' fallaría.
    USER_SHELL="$(getent passwd "$NEW_USER" | cut -d: -f7 || true)"
    case "$USER_SHELL" in
      */nologin|*/false|"")
        warn "Su shell es '${USER_SHELL}': lo cambio a /bin/bash para poder usar bench."
        usermod -s /bin/bash "$NEW_USER"
        ok "Shell ajustado a /bin/bash." ;;
      *) ok "Shell válido: ${USER_SHELL}" ;;
    esac

    # c) Cuenta no bloqueada (un '!' delante del hash impide sudo).
    if passwd -S "$NEW_USER" 2>/dev/null | awk '{print $2}' | grep -q '^L'; then
      warn "La cuenta está bloqueada; se desbloquea al fijar la contraseña."
    fi
  else
    info "Creando usuario operativo '${NEW_USER}'..."
    adduser --disabled-password --gecos "" "$NEW_USER"
    ok "Usuario '${NEW_USER}' creado."
  fi

  # d) Grupo sudo: se valida y sólo se agrega si falta.
  if ! getent group sudo >/dev/null 2>&1; then
    warn "No existe el grupo 'sudo'; lo creo."
    groupadd sudo
  fi
  if id -nG "$NEW_USER" 2>/dev/null | tr ' ' '\n' | grep -qx sudo; then
    ok "'${NEW_USER}' ya pertenece al grupo sudo (no se modifica)."
  else
    info "Agregando '${NEW_USER}' al grupo sudo..."
    usermod -aG sudo "$NEW_USER"
    ok "Agregado al grupo sudo."
  fi

  # e) Contraseña: la que indicaste en la pregunta 3/10.
  if printf '%s:%s\n' "$NEW_USER" "$OS_USER_PASS" | chpasswd; then
    ok "Contraseña de '${NEW_USER}' establecida."
  else
    fail "No se pudo establecer la contraseña de '${NEW_USER}'."
    exit 1
  fi

  ok "Grupos de ${NEW_USER}: $(id -nG "$NEW_USER" 2>/dev/null || echo '?')"
  mark_done fase1_usuario
fi

# --- 1.1b Reafirmación en CADA ejecución ------------------------------------
# La contraseña y la pertenencia a sudo NO se saltan por checkpoint: son datos
# que el operador acaba de escribir en las preguntas y deben quedar vigentes
# aunque el paso de creación del usuario ya estuviera completado.
if id "$NEW_USER" &>/dev/null; then
  if printf '%s:%s\n' "$NEW_USER" "$OS_USER_PASS" | chpasswd; then
    ok "Contraseña de '${NEW_USER}' vigente (la de la pregunta 3/10)."
  else
    warn "No se pudo fijar la contraseña de '${NEW_USER}'."
  fi
  if id -nG "$NEW_USER" 2>/dev/null | tr ' ' '\n' | grep -qx sudo; then
    ok "Pertenencia al grupo sudo validada."
  else
    warn "No estaba en el grupo sudo; lo agrego."
    usermod -aG sudo "$NEW_USER"
  fi
else
  fail "El usuario '${NEW_USER}' no existe y no pudo crearse."
  exit 1
fi

# --- 1.2 Migración de llaves SSH (antes de tocar sshd) ----------------------
if is_done fase1_llaves; then
  skip "Migración de llaves SSH"
else
  info "Instalando authorized_keys de '${NEW_USER}'..."
  install -d -m 700 -o "$NEW_USER" -g "$NEW_USER" "${USER_HOME}/.ssh"
  AUTH_KEYS="${USER_HOME}/.ssh/authorized_keys"
  touch "$AUTH_KEYS"
  # Idempotente: no duplicamos la llave si ya está.
  if ! grep -qxF "$SSH_PUBKEY" "$AUTH_KEYS" 2>/dev/null; then
    printf '%s\n' "$SSH_PUBKEY" >> "$AUTH_KEYS"
  fi
  # Heredamos las llaves de root como red de seguridad.
  if [[ -s "${ROOTDIR}/.ssh/authorized_keys" ]]; then
    cat "${ROOTDIR}/.ssh/authorized_keys" >> "$AUTH_KEYS"
    sort -u "$AUTH_KEYS" -o "$AUTH_KEYS"
    info "Llaves de root heredadas al nuevo usuario."
  fi
  chown -R "${NEW_USER}:${NEW_USER}" "${USER_HOME}/.ssh"
  chmod 700 "${USER_HOME}/.ssh"; chmod 600 "$AUTH_KEYS"
  KEY_COUNT=$(grep -c . "$AUTH_KEYS" || true)
  if (( KEY_COUNT == 0 )); then
    fail "authorized_keys quedó vacío: te quedarías fuera del servidor. Aborto."
    exit 1
  fi
  ok "authorized_keys con ${KEY_COUNT} llave(s), permisos 600."
  mark_done fase1_llaves
fi

# --- 1.3 Endurecimiento de SSHD (CIS 5.2.x) ---------------------------------
if is_done fase1_sshd; then
  skip "Hardening de SSHD"
else
  info "Escribiendo ${ETC}/ssh/sshd_config.d/99-custom.conf ..."
  mkdir -p "${ETC}/ssh/sshd_config.d"
  cat > "${ETC}/ssh/sshd_config.d/99-custom.conf" <<SSHCONF
# ==========================================================
#  Hardening SSH - CIS Ubuntu 24.04 Benchmark (5.2.x)
#  Generado por bashcore-frappe16 v2.0 el $(date -Is)
# ==========================================================

# Puerto no estándar: elimina el 99% del ruido de bots
Port ${SSH_PORT}

# (CIS 5.2.11) Sin autenticación por contraseña
PasswordAuthentication no
KbdInteractiveAuthentication no

# (CIS 5.2.10) Sin login directo de root
PermitRootLogin no

# (CIS 5.2.7) Intentos permitidos
MaxAuthTries 3

# (CIS 5.2.16) Desconexión por inactividad.
# ClientAliveCountMax 0 (como pedía la guía) cierra la sesión a los 300s en
# cuanto deja de fluir texto, aunque el cliente esté vivo: eso mataba la
# sesión durante los tramos silenciosos de 'bench init'. Con 3 sondeos la
# tolerancia sube a 15 min y se mantiene el control de inactividad.
ClientAliveInterval 300
ClientAliveCountMax 3

# (CIS 5.2.6) Sin reenvío de gráficos
X11Forwarding no

# (CIS 5.2.17) Tiempo límite para autenticarse
LoginGraceTime 30

# (CIS 5.2.12) Nunca un usuario sin clave
PermitEmptyPasswords no

# Autenticación por llave pública
PubkeyAuthentication yes
AuthenticationMethods publickey

# Reenvío TCP: la guía original indica 'yes' aunque su comentario dice
# "bloquear". CIS recomienda 'no'. Se deja en 'yes' para no romper túneles
# de administración de la base de datos; cámbialo a 'no' si no los usas.
AllowTcpForwarding yes

# Superficie mínima: solo el usuario operativo entra por SSH
AllowUsers ${NEW_USER}

# (CIS 5.2.20) Advertencia legal
Banner /etc/issue.net
SSHCONF
  chmod 600 "${ETC}/ssh/sshd_config.d/99-custom.conf"

  cat > "${ETC}/issue.net" <<'BANNER'
***************************************************************************
                          ACCESO RESTRINGIDO
  Sistema de uso exclusivo para personal autorizado. Toda actividad es
  monitoreada y registrada. El acceso no autorizado será perseguido
  conforme a la legislación vigente.
***************************************************************************
BANNER
  chmod 644 "${ETC}/issue.net"
  ok "Configuración y banner escritos."

  info "Validando sintaxis (sshd -t)..."
  if ! command -v sshd >/dev/null 2>&1; then
    warn "sshd no está instalado (plantilla LXC mínima); lo instalo ahora."
    apt_do install -y openssh-server </dev/null
  fi
  # Las plantillas LXC mínimas no traen claves de host y 'sshd -t' falla con
  # "no hostkeys available". 'ssh-keygen -A' genera sólo las que falten.
  if ! ls /etc/ssh/ssh_host_*_key >/dev/null 2>&1; then
    warn "Faltan las claves de host de SSH; las genero."
    ssh-keygen -A >/dev/null 2>&1 || warn "ssh-keygen -A falló."
  fi
  # 'sshd' exige su directorio de separación de privilegios. Lo crea
  # ssh.service al arrancar (RuntimeDirectory=sshd), así que en un CT donde
  # el servicio nunca se ha iniciado no existe y 'sshd -t' aborta con
  # "Missing privilege separation directory: /run/sshd".
  if [[ ! -d /run/sshd ]]; then
    mkdir -p /run/sshd && chmod 0755 /run/sshd
    ok "Creado /run/sshd (lo exige sshd para validar la configuración)."
  fi
  # Y que persista tras reiniciar el contenedor, no sólo en esta sesión.
  if [[ ! -f "${ETC}/tmpfiles.d/sshd-run.conf" ]]; then
    mkdir -p "${ETC}/tmpfiles.d"
    echo 'd /run/sshd 0755 root root -' > "${ETC}/tmpfiles.d/sshd-run.conf"
  fi

  # Con límite de tiempo y entrada cerrada: este paso jamás puede quedarse
  # esperando, porque un bloqueo aquí ocurre ANTES de tener acceso alterno.
  SSHD_BIN="$(command -v sshd || echo /usr/sbin/sshd)"
  if timeout 60 "$SSHD_BIN" -t </dev/null; then
    ok "Sintaxis válida."
  else
    SSHD_RC=$?
    if (( SSHD_RC == 124 )); then
      fail "'sshd -t' agotó los 60 s (algo muy anómalo)."
    else
      fail "'sshd -t' falló con código ${SSHD_RC}. Detalle:"
      timeout 30 "$SSHD_BIN" -t </dev/null 2>&1 | sed 's/^/      /' || true
    fi
    fail "Aborto ANTES de reiniciar el servicio para no perder el acceso."
    fail "Revisa: ${ETC}/ssh/sshd_config.d/99-custom.conf"
    fail "Si menciona /run/sshd:  mkdir -p /run/sshd && chmod 0755 /run/sshd"
    exit 1
  fi

  # Firewall local ANTES de mover el puerto: si UFW está activo y no abrimos
  # el puerto nuevo, el reinicio nos deja fuera.
  # [P7] En un CT no privilegiado iptables suele estar vetado: ufw falla y NO
  # debe abortar el despliegue: el firewall se define en el anfitrión.
  if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -q "Status: active"; then
    if ufw allow "${SSH_PORT}/tcp" comment 'SSH bashcore' >/dev/null 2>&1 \
       && ufw allow 80/tcp >/dev/null 2>&1 && ufw allow 443/tcp >/dev/null 2>&1; then
      ok "UFW: abiertos ${SSH_PORT}, 80 y 443."
    else
      warn "UFW activo pero rechazó las reglas (típico en LXC sin capacidades de red)."
      warn "Configura el firewall en el sistema anfitrión."
    fi
  elif (( IS_CT )); then
    warn "Sin UFW activo: abre tcp/${SSH_PORT}, tcp/80 y tcp/443 en el anfitrión."
  else
    warn "UFW inactivo. Abre el puerto ${SSH_PORT} en el firewall del proveedor."
  fi

  info "Desactivando ssh.socket (en 24.04 fuerza el puerto 22)..."
  systemctl disable --now ssh.socket 2>/dev/null || info "ssh.socket no estaba activo."
  systemctl enable --now ssh.service
  systemctl restart ssh
  sleep 3

  # [C10] Red de seguridad: si el puerto nuevo no escucha, revertimos al
  # socket de Ubuntu para no quedarnos fuera del servidor.
  if ss -H -tln | grep -q ":${SSH_PORT}[[:space:]]"; then
    ok "SSH escuchando en el puerto ${SSH_PORT}."
    ok "Tu sesión actual sigue viva: las conexiones establecidas no se cortan."
  else
    fail "SSH NO escucha en ${SSH_PORT}. Restaurando el acceso por el puerto 22..."
    systemctl enable --now ssh.socket 2>/dev/null || true
    fail "Revisa: journalctl -u ssh -n 50"
    exit 1
  fi
  mark_done fase1_sshd
fi

avance ssh OK
avance db RUN

# =============================================================================
#  FASE 2: CAPA DE DATOS (MARIADB)  (CIS 2.9, 4.x, 8.1)
# =============================================================================
phase "FASE 2: CAPA DE DATOS (${MARIADB_VERSION})"

if is_done fase2_install; then
  skip "Instalación de MariaDB"
else
  info "Instalando prerequisitos del repositorio..."
  apt_do install -y curl software-properties-common apt-transport-https ca-certificates

  if ls "${ETC}/apt/sources.list.d/"mariadb* >/dev/null 2>&1; then
    info "Repositorio de MariaDB ya configurado."
  else
    info "Configurando el repositorio oficial de MariaDB..."
    curl -LsS https://r.mariadb.com/downloads/mariadb_repo_setup \
      | bash -s -- --mariadb-server-version="${MARIADB_VERSION}"
    apt_do update
    ok "Repositorio configurado."
  fi

  info "Instalando servidor, cliente y librerías de desarrollo..."
  apt_do install -y mariadb-server mariadb-client libmariadb-dev
  # libmysqlclient-dev es opcional: en algunos mirrors choca con el repo de
  # MariaDB. libmariadb-dev + pkg-config ya bastan para compilar mysqlclient.
  apt_do install -y libmysqlclient-dev 2>/dev/null \
    || warn "libmysqlclient-dev no disponible; sigo con libmariadb-dev."
  ok "MariaDB: $(mariadb --version 2>/dev/null || echo '?')"
  mark_done fase2_install
fi

if is_done fase2_config; then
  skip "Configuración de MariaDB"
else
  info "Escribiendo ${ETC}/mysql/mariadb.conf.d/frappe.cnf ..."
  mkdir -p "${ETC}/mysql/mariadb.conf.d"
  cat > "${ETC}/mysql/mariadb.conf.d/frappe.cnf" <<'DBCONF'
[mysqld]
# --- Requisitos de Frappe --------------------------------------------------
character-set-client-handshake  = FALSE
character-set-server            = utf8mb4
collation-server                = utf8mb4_unicode_ci

# Parámetros legados de InnoDB: Barracuda ya es el formato por defecto y
# estas variables fueron ELIMINADAS en MariaDB 10.3+. Sin el prefijo
# 'loose-' el servidor se niega a arrancar por "unknown variable".
loose-innodb-file-format        = barracuda
loose-innodb-file-per-table     = 1
loose-innodb-large-prefix       = 1

# --- CIS Hardening ---------------------------------------------------------
bind-address        = 127.0.0.1   # (CIS 2.9) solo conexiones locales
local-infile        = 0           # (CIS 8.1) sin carga de archivos locales
skip-symbolic-links = 1           # sin enlaces simbólicos

# NO habilitar skip-name-resolve. Si se activa, MariaDB deja de traducir
# 127.0.0.1 -> 'localhost' y entonces:
#   - 'root'@'localhost' sólo funciona por socket Unix; toda conexión TCP
#     (-h 127.0.0.1) es rechazada con "Access denied".
#   - El usuario que crea 'bench new-site' (usuario@'localhost') deja de
#     funcionar, porque Frappe se conecta por TCP: el sitio se queda sin
#     acceso a su propia base de datos.
# Fue la causa del fallo de la Fase 2 en la v2/v3.

[mysql]
default-character-set = utf8mb4
DBCONF
  chmod 644 "${ETC}/mysql/mariadb.conf.d/frappe.cnf"

  # --- [P6] Ajustes obligatorios en contenedores ---------------------------
  # Dos motivos por los que MariaDB no arranca dentro de un contenedor:
  #  a) io_setup() / AIO nativo: el CT no siempre tiene acceso a io_uring o
  #     agota aio-max-nr del host => "Can't initialize AIO subsystem".
  #  b) LimitNOFILE=infinity en la unidad systemd: dentro de LXC se traduce
  #     en un valor absurdo y mysqld aborta o consume RAM al arrancar.
  write_lxc_tuning() {
    cat > "${ETC}/mysql/mariadb.conf.d/zz-lxc.cnf" <<'LXCCNF'
[mysqld]
# ==========================================================
#  Ajustes para contenedores (Proxmox CT / LXC)
#  Generado por bashcore-frappe16
# ==========================================================
# El AIO nativo no es fiable dentro de un CT: sin esto mysqld puede no
# arrancar con "Can't initialize AIO subsystem" / io_setup EAGAIN.
innodb_use_native_aio = 0

# performance_schema consume ~400MB de RAM: en un CT es un lujo innecesario.
performance_schema = OFF

# Menos hilos de limpieza: los CT suelen tener pocos cores asignados.
innodb_read_io_threads  = 2
innodb_write_io_threads = 2
LXCCNF
    chmod 644 "${ETC}/mysql/mariadb.conf.d/zz-lxc.cnf"

    # Acotamos LimitNOFILE mediante override de systemd (no editamos la unidad).
    mkdir -p "${ETC}/systemd/system/mariadb.service.d"
    cat > "${ETC}/systemd/system/mariadb.service.d/override.conf" <<'LXCOVR'
[Service]
# 'infinity' rompe en LXC: fijamos un valor alto pero finito.
LimitNOFILE=1048576
LimitMEMLOCK=524288
LXCOVR
    systemctl daemon-reload 2>/dev/null || true
  }

  if (( IS_CT )); then
    info "Aplicando ajustes de MariaDB para contenedor (AIO, NOFILE)..."
    write_lxc_tuning
    ok "zz-lxc.cnf y override de systemd escritos."
  fi

  info "Habilitando y reiniciando el servicio..."
  systemctl enable --now mariadb 2>/dev/null || true

  # Arranque con espera activa; devuelve 0 solo si el socket responde.
  start_mariadb() {
    systemctl restart mariadb 2>/dev/null || true
    local _i
    for _i in $(seq 30); do
      if mariadb-admin ping >/dev/null 2>&1; then return 0; fi
      sleep 2
    done
    systemctl is-active --quiet mariadb && return 0
    return 1
  }

  if start_mariadb; then
    ok "MariaDB activo y respondiendo."
  else
    # Segundo intento: el fallo casi siempre es AIO, incluso en VMs con
    # aio-max-nr agotado. Aplicamos el tuning y reintentamos una vez.
    warn "MariaDB no respondió. Aplico los ajustes de contenedor y reintento..."
    write_lxc_tuning
    if start_mariadb; then
      ok "MariaDB activo tras desactivar el AIO nativo."
    else
      fail "MariaDB no arrancó. Diagnóstico:"
      journalctl -u mariadb -n 30 --no-pager 2>/dev/null | sed 's/^/      /' || true
      tail -n 20 /var/log/mysql/error.log 2>/dev/null | sed 's/^/      /' || true
      fail "En un CT revisa también: dmesg del NODO y aio-max-nr del host."
      exit 1
    fi
  fi
  mark_done fase2_config
fi

# --- 2.3 Hardening SQL no interactivo (reemplaza mysql_secure_installation) --
# [F3] MariaDB puede estar en tres estados distintos según si el script ya
# corrió antes. Los sondeamos todos en lugar de asumir uno: así el script es
# reanudable desde cualquier punto sin quedarse fuera de su propia base.
DB_MODE=""

db_try() {   # $1 = modo de conexión; 0 si conecta
  case "$1" in
    socket-pass)   mariadb -u root -p"${DB_ROOT_PASS}" -e "SELECT 1" ;;
    tcp-pass)      mariadb -u root -p"${DB_ROOT_PASS}" -h 127.0.0.1 -e "SELECT 1" ;;
    socket-nopass) mariadb -u root -e "SELECT 1" ;;
    *) return 1 ;;
  esac >/dev/null 2>&1
}

db_probe() {
  local m
  for m in socket-pass tcp-pass socket-nopass; do
    if db_try "$m"; then DB_MODE="$m"; return 0; fi
  done
  DB_MODE=""
  return 1
}

db_exec_file() {  # ejecuta un .sql con el modo ya detectado
  case "$DB_MODE" in
    socket-pass)   mariadb -u root -p"${DB_ROOT_PASS}" < "$1" ;;
    tcp-pass)      mariadb -u root -p"${DB_ROOT_PASS}" -h 127.0.0.1 < "$1" ;;
    socket-nopass) mariadb -u root < "$1" ;;
    *) return 1 ;;
  esac
}

if is_done fase2_secure && db_try socket-pass && db_try tcp-pass; then
  skip "Hardening SQL (socket y TCP ya autentican con contraseña)"
else
  if ! db_probe; then
    fail "No puedo autenticarme en MariaDB de ninguna forma:"
    fail "  - socket + contraseña   : NO"
    fail "  - TCP 127.0.0.1 + clave : NO"
    fail "  - socket sin contraseña : NO"
    fail "Si root ya tiene OTRA contraseña, relanza el script con ESA."
    fail "Rescate: systemctl stop mariadb && mariadbd-safe --skip-grant-tables"
    exit 1
  fi
  case "$DB_MODE" in
    socket-nopass) info "Conexión por unix_socket sin contraseña (instalación limpia)." ;;
    socket-pass)   info "Conexión por socket con contraseña (root ya migrado)." ;;
    tcp-pass)      info "Conexión por TCP con contraseña." ;;
  esac

  info "Aplicando hardening SQL (equivalente a mysql_secure_installation)..."
  SQL_TMP="$(mktemp)"; chmod 600 "$SQL_TMP"
  cat > "$SQL_TMP" <<SQLEOF
USE mysql;
-- (CIS 4.x) Sin usuarios anónimos
DELETE FROM global_priv WHERE User='';
-- (CIS 4.x) root sólo desde local (localhost / 127.0.0.1 / ::1)
DELETE FROM global_priv WHERE User='root' AND Host NOT IN ('localhost','127.0.0.1','::1');
-- (CIS 4.x) Fuera la base de datos de prueba
DROP DATABASE IF EXISTS test;
DELETE FROM db WHERE Db='test' OR Db='test\\_%';
-- PASO CRÍTICO: unix_socket -> mysql_native_password.
-- Frappe corre como '${NEW_USER}', no como root del SO. Sin esto MariaDB
-- rechaza la conexión aunque la contraseña sea correcta.
ALTER USER 'root'@'localhost' IDENTIFIED VIA mysql_native_password USING PASSWORD('${DB_ROOT_PASS}');

-- [F2] Frappe/bench se conectan por TCP a 127.0.0.1: declaramos las cuentas
-- literales para que la autenticación funcione con o sin resolución de nombres.
CREATE USER IF NOT EXISTS 'root'@'127.0.0.1' IDENTIFIED VIA mysql_native_password USING PASSWORD('${DB_ROOT_PASS}');
ALTER USER 'root'@'127.0.0.1' IDENTIFIED VIA mysql_native_password USING PASSWORD('${DB_ROOT_PASS}');
GRANT ALL PRIVILEGES ON *.* TO 'root'@'127.0.0.1' WITH GRANT OPTION;

CREATE USER IF NOT EXISTS 'root'@'::1' IDENTIFIED VIA mysql_native_password USING PASSWORD('${DB_ROOT_PASS}');
ALTER USER 'root'@'::1' IDENTIFIED VIA mysql_native_password USING PASSWORD('${DB_ROOT_PASS}');
GRANT ALL PRIVILEGES ON *.* TO 'root'@'::1' WITH GRANT OPTION;

FLUSH PRIVILEGES;
SQLEOF

  db_exec_file "$SQL_TMP"
  shred -u "$SQL_TMP" 2>/dev/null || rm -f "$SQL_TMP"
  ok "Hardening SQL aplicado."

  # QA en los DOS caminos: socket (administración) y TCP (lo que usa Frappe).
  info "Validando el acceso por socket con contraseña..."
  if db_try socket-pass; then
    ok "Socket + contraseña: correcto."
  else
    fail "El acceso por socket con contraseña falló tras el ALTER USER."
    exit 1
  fi

  info "Validando el acceso TCP 127.0.0.1 (el que usará Frappe)..."
  if db_try tcp-pass; then
    ok "TCP 127.0.0.1 + contraseña: correcto."
    mark_done fase2_secure
  else
    fail "El acceso TCP falló. Diagnóstico automático:"
    if grep -rn 'skip-name-resolve' "${ETC}/mysql/" 2>/dev/null | grep -vE ':\s*#'; then
      fail "  ^^ Hay 'skip-name-resolve' activo: eso rompe usuario@'localhost'"
      fail "     por TCP. Comenta esa línea y reinicia MariaDB."
    fi
    fail "  Cuentas de root registradas:"
    mariadb -u root -p"${DB_ROOT_PASS}" -e \
      "SELECT User,Host FROM mysql.global_priv WHERE User='root';" 2>/dev/null \
      | sed 's/^/      /' || true
    fail "  Comprueba también bind-address (debe ser 127.0.0.1) y el firewall local."
    exit 1
  fi
fi

avance db OK
avance runtime RUN

# =============================================================================
#  FASE 3: ENTORNO DE EJECUCIÓN (dependencias globales)
# =============================================================================
phase "FASE 3: ENTORNO DE EJECUCIÓN"

if is_done fase3_deps; then
  skip "Dependencias de sistema"
else
  info "Instalando compiladores C/C++, Redis, fuentes, Nginx y Supervisor..."
  apt_do install -y \
    git pkg-config libmariadb-dev python3-dev python3-setuptools build-essential \
    redis-server xvfb libfontconfig fontconfig xfonts-75dpi xfonts-base \
    curl wget pipx supervisor nginx cron ca-certificates
  ok "Dependencias apt instaladas."
  # [v16] NO se modifica supervisord.conf. En la v11/v13 se le añadía
  # 'chown/chmod' para que el usuario pudiera usar supervisorctl sin sudo,
  # pero Ubuntu YA trae 'chmod=0700': el duplicado provoca
  # DuplicateOptionError en configparser y 'bench setup production' aborta.
  # El sudoers NOPASSWD (más abajo) resuelve lo mismo sin tocar el archivo.
  info "supervisord.conf se deja intacto (el sudoers evita el prompt de sudo)."

  systemctl enable --now redis-server 2>/dev/null || warn "redis-server no se pudo habilitar."
  if systemctl is-active --quiet redis-server; then
    ok "Redis activo."
  else
    warn "Redis del sistema inactivo. Frappe usa sus PROPIAS instancias de Redis"
    warn "(puertos 11000/12000/13000) lanzadas por bench/supervisor, así que no"
    warn "es bloqueante, pero conviene revisarlo: journalctl -u redis-server"
  fi
  if (( IS_CT )); then
    # sysctl no es escribible desde un CT no privilegiado.
    info "Nota: el aviso de overcommit de Redis se corrige en el anfitrión."
  fi
  mark_done fase3_deps
fi

# --- wkhtmltopdf con Qt parcheado (el de los repos de Ubuntu NO sirve) ------
# [C8] El .deb de jammy sobre noble puede quedar a medias: 'apt install -f'
# es capaz de REMOVER el paquete para resolver dependencias. Verificamos que
# el binario funcione de verdad y, si no, degradamos a advertencia en lugar
# de matar el despliegue (solo se pierde la impresión de PDF).
if is_done fase3_wkhtmltopdf; then
  skip "wkhtmltopdf"
else
  WK_VER=""
  if command -v wkhtmltopdf >/dev/null 2>&1 && WK_VER="$(wkhtmltopdf --version 2>/dev/null)"; then
    :
  else
    info "Instalando wkhtmltopdf ${WKHTML_VERSION} (Qt parcheado)..."
    WK_DEB="wkhtmltox_${WKHTML_VERSION}.jammy_${ARCH}.deb"
    WK_URL="https://github.com/wkhtmltopdf/packaging/releases/download/${WKHTML_VERSION}/${WK_DEB}"
    if ( cd /tmp && wget -q "$WK_URL" ); then
      dpkg -i "/tmp/${WK_DEB}" 2>/dev/null || true   # puede fallar por deps...
      apt_do install -f -y || true                   # ...y aquí se resuelven
      rm -f "/tmp/${WK_DEB}"
      WK_VER="$(wkhtmltopdf --version 2>/dev/null || true)"
    else
      warn "No se pudo descargar wkhtmltopdf desde GitHub."
    fi
  fi
  if [[ -n "$WK_VER" ]]; then
    ok "wkhtmltopdf: ${WK_VER}"
    grep -qi "with patched qt" <<<"$WK_VER" \
      || warn "Sin 'patched qt': los PDF saldrán sin encabezados/pies."
    mark_done fase3_wkhtmltopdf
  else
    warn "wkhtmltopdf NO quedó operativo. La impresión de PDF fallará."
    warn "El resto de la instalación continúa; se puede arreglar después."
  fi
fi

# =============================================================================
#  CAMBIO DE CONTEXTO: Fases 3.2, 4, 5 y 6 corren como el usuario operativo
#  Estrategia: sub-script + archivo .env (0600) y 'su - usuario'. Un único
#  punto de expansión de variables => cero riesgo de quoting.
# =============================================================================
avance runtime OK
phase "CAMBIO DE CONTEXTO: root -> ${NEW_USER}"

# [S2] Red de seguridad: durante la instalación, el usuario operativo no
# puede quedarse esperando una contraseña. Al terminar se sustituye por un
# permiso mínimo (sólo lo que Frappe necesita para gestionar sus servicios).
SUDOERS_INSTALL="${ETC}/sudoers.d/99-bashcore-install"
mkdir -p "${ETC}/sudoers.d"
cat > "$SUDOERS_INSTALL" <<SUDOEOF
# Temporal: creado por bashcore-frappe16 durante la instalación.
# Se sustituye por un permiso mínimo al finalizar el despliegue.
${NEW_USER} ALL=(ALL) NOPASSWD: ALL
Defaults:${NEW_USER} !requiretty
SUDOEOF
chmod 440 "$SUDOERS_INSTALL"
if command -v visudo >/dev/null 2>&1 && ! visudo -cf "$SUDOERS_INSTALL" >/dev/null 2>&1; then
  rm -f "$SUDOERS_INSTALL"
  fail "El archivo sudoers generado no es válido; se elimina por seguridad."
  exit 1
fi
ok "Permisos temporales de sudo concedidos a '${NEW_USER}' (sin contraseña)."


ENV_FILE="${USER_HOME}/.bashcore.env"
USER_SCRIPT="${USER_HOME}/bashcore-user-phase.sh"

umask 077
cat > "$ENV_FILE" <<ENVEOF
NEW_USER='${NEW_USER}'
DB_ROOT_PASS='${DB_ROOT_PASS}'
ADMIN_PASS='${ADMIN_PASS}'
SITE_NAME='${SITE_NAME}'
NVM_VERSION='${NVM_VERSION}'
NODE_VERSION='${NODE_VERSION}'
PYTHON_VERSION='${PYTHON_VERSION}'
FRAPPE_BRANCH='${FRAPPE_BRANCH}'
APPS_SEL='${APPS_SEL}'
IS_CT='${IS_CT}'
NODE_OPTS='${NODE_OPTS}'
LANG='${LANG}'
PROGRESS_FILE='${PROGRESS_FILE}'
ENVEOF
chown "${NEW_USER}:${NEW_USER}" "$ENV_FILE"
chmod 600 "$ENV_FILE"
# El archivo de progreso es compartido: root lo crea, el usuario lo amplía.
touch "$PROGRESS_FILE" 2>/dev/null || true
chown "${NEW_USER}:${NEW_USER}" "$PROGRESS_FILE" 2>/dev/null || true
chmod 664 "$PROGRESS_FILE" 2>/dev/null || true
umask 022
ok "Variables transferidas (0600, solo ${NEW_USER})."

# Heredoc CITADO: nada se expande aquí. Las variables llegan por el .env.
cat > "$USER_SCRIPT" <<'USERPHASE'
#!/usr/bin/env bash
# -----------------------------------------------------------------------------
#  bashcore v2.0 :: Fase de usuario (Fases 3.2, 4, 5 y 6)
#  Invocado como: su - <usuario> -c 'bash este_script'
# -----------------------------------------------------------------------------
set -Eeuo pipefail

GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'
BLUE='\033[0;36m';  BOLD='\033[1m';   NC='\033[0m'
phase() { echo -e "\n${BLUE}${BOLD}--------------------------------------------------------------${NC}"
          echo -e "${BLUE}${BOLD} $* ${NC}"
          echo -e "${BLUE}${BOLD}--------------------------------------------------------------${NC}"; }
ok()    { echo -e "  ${GREEN}[ OK ]${NC} $*"; }
info()  { echo -e "  ${BLUE}[INFO]${NC} $*"; }
# warn y fail salen al log Y a la pantalla: un problema nunca queda oculto.
warn()  { echo -e "  ${YELLOW}[WARN]${NC} $*"; }
fail()  { echo -e "  ${RED}[FAIL]${NC} $*"; }
skip()  { echo -e "  ${YELLOW}[SKIP]${NC} $* ${YELLOW}(ya completado)${NC}"; }

# El trap se guarda en una variable porque hay bloques (NVM, apagado de
# servicios) donde hay que quitarlo y volver a ponerlo.
# HALLAZGO VERIFICADO: 'set +e' NO desactiva el trap ERR. Aislar un bloque
# frágil exige 'trap - ERR' además de 'set +e'.
# shellcheck disable=SC2154
ERR_TRAP='rc=$?; fail "Fase de usuario abortada (código $rc) en línea $LINENO: ${BASH_COMMAND}"; exit $rc'
# shellcheck disable=SC2064  # ERR_TRAP se asignó con comillas simples: $?/$LINENO no se expanden aquí
trap "$ERR_TRAP" ERR

# shellcheck disable=SC1091
source "$HOME/.bashcore.env"

BENCH_DIR="$HOME/frappe-bench"
USTATE="$HOME/.bashcore-state"
mkdir -p "$USTATE"
is_done()   { [[ -f "${USTATE}/$1.done" ]]; }
mark_done() { date -Is > "${USTATE}/$1.done"; }

export PATH="$HOME/.local/bin:$PATH"
# [S8] Sin esto, Python bufferiza la salida en bloques de 8KB y el log parece
# congelado durante minutos aunque el proceso esté trabajando.
export PYTHONUNBUFFERED=1
export PIP_DISABLE_PIP_VERSION_CHECK=1

# [S4] Todo paso largo va con límite de tiempo: si algo se cuelga de verdad
# (red muerta, lock de git, prompt oculto esperando entrada), falla con un
# mensaje claro en lugar de dejar el despliegue esperando horas.
run_step() {
  local secs="$1" desc="$2"; shift 2
  local rc=0
  info "→ ${desc}  (límite ${secs}s)"
  local t0; t0="$(date +%s)"
  if command -v timeout >/dev/null 2>&1; then
    timeout --signal=TERM --kill-after=30 "$secs" "$@" || rc=$?
  else
    "$@" || rc=$?
  fi
  local mins=$(( ($(date +%s) - t0) / 60 ))
  if (( rc == 0 )); then
    ok "${desc}: completado en ${mins} min."
    return 0
  elif (( rc == 124 || rc == 137 )); then
    fail "${desc}: TIEMPO AGOTADO tras ${secs}s (${mins} min)."
    fail "  Revisa la red y el espacio en disco; relanza para reintentar."
    return 124
  else
    fail "${desc}: terminó con código ${rc} tras ${mins} min."
    return "$rc"
  fi
}

# Locale UTF-8: bench falla al leer archivos con acentos bajo LANG=POSIX.
export LANG="${LANG:-C.UTF-8}"
# Techo de heap de Node en equipos/CT con poca RAM (evita el OOM del build).
if [[ -n "${NODE_OPTS:-}" ]]; then
  export NODE_OPTIONS="${NODE_OPTS}"
fi
FAILED_APPS=()

# [P4] Cada paso publica su estado en un archivo que el proceso supervisor
# lee para dibujar la barra de progreso. Los identificadores deben coincidir
# con la lista PASOS del script principal (el arnés lo verifica).
# La ruta llega por el archivo de entorno: es el MISMO archivo que usa root,
# para que la barra refleje el despliegue completo y no sólo esta fase.
PROGRESS_FILE="${PROGRESS_FILE:-$HOME/.bashcore-progress}"
touch "$PROGRESS_FILE" 2>/dev/null || true
paso() {  # paso <id> <estado: RUN|OK|ERR>
  printf '%s|%s|%s\n' "$1" "$2" "$(date +%s)" >> "$PROGRESS_FILE"
}

# =============================================================
#  FASE 3.2: NODE.JS + YARN (via NVM)
# =============================================================
paso node RUN
phase "FASE 3.2: NODE ${NODE_VERSION} + YARN"

export NVM_DIR="$HOME/.nvm"
if [[ ! -s "$NVM_DIR/nvm.sh" ]]; then
  info "Instalando NVM ${NVM_VERSION}..."
  curl -o- "https://raw.githubusercontent.com/nvm-sh/nvm/${NVM_VERSION}/install.sh" | bash
else
  info "NVM ya presente."
fi

# Verificamos ANTES de sourcear: si el instalador no dejó el archivo, el
# error debe ser legible y no un fallo críptico dentro de nvm.sh.
if [[ ! -s "$NVM_DIR/nvm.sh" ]]; then
  fail "NVM no quedó instalado: falta ${NVM_DIR}/nvm.sh"
  fail "Causa típica: el firewall bloquea raw.githubusercontent.com."
  fail "Prueba: curl -I https://raw.githubusercontent.com"
  exit 1
fi

# nvm.sh no tolera 'set -u' ni 'set -e'. Y OJO: 'set +e' no basta, porque el
# trap ERR sigue disparando; hay que retirarlo y restaurarlo explícitamente.
set +eu
trap - ERR
# shellcheck disable=SC1091
. "$NVM_DIR/nvm.sh"
nvm install "${NODE_VERSION}"
nvm use "${NODE_VERSION}"
nvm alias default "${NODE_VERSION}"
NVM_RC=$?
set -eu
# shellcheck disable=SC2064  # ERR_TRAP se asignó con comillas simples: $?/$LINENO no se expanden aquí
trap "$ERR_TRAP" ERR
if ! command -v node >/dev/null 2>&1; then
  fail "Node ${NODE_VERSION} no quedó disponible (nvm devolvió ${NVM_RC})."
  fail "Diagnóstico: nvm ls  |  nvm install ${NODE_VERSION} --verbose"
  exit 1
fi

NODE_BIN="$(command -v node)"
ok "Node: $(node -v 2>/dev/null || echo '?') (${NODE_BIN})"
ok "npm : $(npm -v 2>/dev/null || echo '?')"

if ! command -v yarn >/dev/null 2>&1; then
  info "Instalando Yarn (npm genera árboles de dependencias inconsistentes)..."
  npm install -g yarn --silent
fi
ok "Yarn: $(yarn -v 2>/dev/null || echo '?')"
paso node OK

# Publicamos las rutas para que root cree los symlinks globales en la Fase 7.
printf '%s\n' "$NODE_BIN" > "$HOME/.bashcore_node_path"
printf '%s\n' "$(dirname "$NODE_BIN")" > "$HOME/.bashcore_node_dir"

# Persistencia del entorno para logins futuros.
if ! grep -q 'BASHCORE-ENV' "$HOME/.bashrc" 2>/dev/null; then
  cat >> "$HOME/.bashrc" <<'PROFILEEOF'

# --- BASHCORE-ENV (Frappe 16) ---
export PATH="$HOME/.local/bin:$PATH"
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"
# --- /BASHCORE-ENV ---
PROFILEEOF
  ok "Entorno persistido en ~/.bashrc"
fi

# =============================================================
#  FASE 4: EL CORE (pipx, bench, uv, Python)
# =============================================================
paso bench RUN
phase "FASE 4: CORE - frappe-bench, uv y Python ${PYTHON_VERSION}"

info "Configurando pipx en el PATH (cumplimiento PEP 668)..."
pipx ensurepath >/dev/null 2>&1 || true
export PATH="$HOME/.local/bin:$PATH"
hash -r

if command -v bench >/dev/null 2>&1; then
  info "frappe-bench ya instalado: $(bench --version 2>/dev/null || echo '?')"
else
  info "Instalando frappe-bench en entorno aislado..."
  pipx install frappe-bench
  hash -r
  ok "bench: $(bench --version 2>/dev/null || echo 'instalado')"
fi

paso bench OK
paso uv RUN
if ! command -v uv >/dev/null 2>&1; then
  info "Instalando uv (motor de entornos de alto rendimiento)..."
  curl -LsSf https://astral.sh/uv/install.sh | sh
  export PATH="$HOME/.local/bin:$PATH"
  hash -r
fi
ok "uv: $(uv --version 2>/dev/null || echo '?')"

info "Aprovisionando Python ${PYTHON_VERSION} (requisito de la v16)..."
uv python install "${PYTHON_VERSION}"

# Los intérpretes de uv NO quedan en el PATH: hay que resolver la ruta real
# y exponerla, o 'bench init --python' no la encuentra.
# OJO: aquí vivía el segundo SIGPIPE de la v1 ('find ... | head -n1' mataba
# el script con código 141). Ahora el pipeline está protegido.
PY_BIN="$(uv python find "${PYTHON_VERSION}" 2>/dev/null || true)"
if [[ -z "$PY_BIN" || ! -x "$PY_BIN" ]]; then
  PY_BIN="$( { find "$HOME/.local/share/uv/python" -maxdepth 3 -type f \
               -name "python${PYTHON_VERSION}" 2>/dev/null || true; } | { head -n1 || true; } )"
fi
if [[ -z "$PY_BIN" || ! -x "$PY_BIN" ]]; then
  fail "No localicé el binario de Python ${PYTHON_VERSION} provisto por uv."
  fail "Diagnóstico: uv python list"
  exit 1
fi
mkdir -p "$HOME/.local/bin"
ln -sf "$PY_BIN" "$HOME/.local/bin/python${PYTHON_VERSION}"
ok "Python: $("$PY_BIN" --version 2>&1 || echo '?') -> ${PY_BIN}"

paso uv OK

# --- 4.2 bench init ---------------------------------------------------------
# Verificación de prerequisitos ANTES de empezar: 'bench init' falla a los
# 10 minutos si falta node o yarn, y el diagnóstico queda enterrado.
# Entre intentos hay que apartar el directorio a medias: bench se niega a
# inicializar sobre un directorio que no esté vacío, así que sin esto el
# segundo intento fallaría siempre por un motivo distinto al original.
apartar_bench_roto() {
  if [[ -d "$BENCH_DIR" ]]; then
    local destino
    destino="${BENCH_DIR}.fallido-$(date +%Y%m%d-%H%M%S)"
    mv "$BENCH_DIR" "$destino" 2>/dev/null || rm -rf "$BENCH_DIR"
    info "Restos del intento anterior apartados en ${destino}"
  fi
}

verify_prereqs() {
  local missing=0 c
  for c in git node yarn bench uv; do
    if command -v "$c" >/dev/null 2>&1; then
      ok "  ${c}: $(command -v "$c")"
    else
      fail "  ${c}: NO ENCONTRADO"; missing=1
    fi
  done
  if [[ -x "$HOME/.local/bin/python${PYTHON_VERSION}" ]]; then
    ok "  python${PYTHON_VERSION}: $("$HOME/.local/bin/python${PYTHON_VERSION}" --version 2>&1 || echo '?')"
  else
    fail "  python${PYTHON_VERSION}: NO ENCONTRADO"; missing=1
  fi
  return "$missing"
}

if [[ -d "$BENCH_DIR/apps/frappe" ]]; then
  skip "bench init"
else
  paso init RUN
  phase "FASE 4.2: bench init (${FRAPPE_BRANCH})"

  # [V5] Recursos: 'yarn install' de frappe copia decenas de miles de archivos
  # y es donde muere una instalación con poca memoria o poco disco.
  RAM_MB=$(awk '/MemTotal/{print int($2/1024)}' /proc/meminfo)
  SWP_MB=$(awk '/SwapTotal/{print int($2/1024)}' /proc/meminfo)
  DISK_GB=$(df -BG --output=avail "$HOME" 2>/dev/null | tail -1 | tr -dc '0-9')
  info "Recursos: RAM ${RAM_MB}MB + swap ${SWP_MB}MB, disco libre ${DISK_GB:-?}GB"
  if (( RAM_MB + SWP_MB < 3000 )); then
    warn "Menos de 3GB entre RAM y swap: 'yarn install' puede CONGELARSE."
    warn "Amplía memoria y swap del contenedor desde el sistema anfitrión."
  fi
  if [[ -n "${DISK_GB:-}" ]] && (( DISK_GB < 8 )); then
    fail "Sólo ${DISK_GB}GB libres: frappe + node_modules necesitan ~8GB."
    exit 1
  fi

  info "Verificando prerequisitos..."
  if ! verify_prereqs; then
    fail "Faltan prerequisitos: 'bench init' fallaría a mitad de camino."
    exit 1
  fi

  # [S5] Un 'bench init' interrumpido deja el directorio a medias, y bench se
  # niega a inicializar sobre un directorio no vacío: el reintento quedaría
  # bloqueado para siempre. Lo apartamos con fecha.
  if [[ -d "$BENCH_DIR" ]]; then
    BROKEN="${BENCH_DIR}.roto-$(date +%Y%m%d-%H%M%S)"
    warn "Existe ${BENCH_DIR} pero SIN apps/frappe: intento anterior interrumpido."
    mv "$BENCH_DIR" "$BROKEN"
    warn "Apartado en ${BROKEN} (bórralo cuando confirmes que todo va bien)."
  fi

  cd "$HOME"
  # [S6] --skip-assets si bench lo soporta: los assets se compilan UNA sola
  # vez al final (Fase 6), no aquí y otra vez después. Ahorra RAM y tiempo,
  # y es lo que evita el OOM en contenedores con poca memoria.
  # SIN --verbose: con él, yarn emite una línea por archivo copiado (~60.000)
  # y el log, la tubería y el espejo se vuelven el cuello de botella real.
  INIT_ARGS=(--frappe-branch "${FRAPPE_BRANCH}" frappe-bench
             --python "$HOME/.local/bin/python${PYTHON_VERSION}")
  if bench init --help 2>&1 | grep -q -- '--skip-assets'; then
    INIT_ARGS+=(--skip-assets)
    info "Se usará --skip-assets (los assets se compilan al final)."
  fi

  # NOTA: no existe ningún flag '--uv' en bench 5.31 (verificado en el código
  # fuente); uv se usa POR DEFECTO y se desactiva con BENCH_DISABLE_UV=1.
  # Añadir '--uv' haría fallar el comando al instante por opción desconocida.
  INIT_OK=0
  if run_step 3600 "bench init ${FRAPPE_BRANCH}" bench init "${INIT_ARGS[@]}"; then
    INIT_OK=1
  else
    # [A3] Segundo intento con el gestor clásico: si el fallo viene de uv
    # (resolución de dependencias, red, versión de Python), pip suele pasar.
    # [Z5] Intento 2: gestor clásico. Si el problema estaba en la resolución
    # de dependencias de uv, pip lo resuelve por otro camino.
    warn "Intento 1 fallido. Intento 2: BENCH_DISABLE_UV=1 (pip clásico)..."
    apartar_bench_roto
    if BENCH_DISABLE_UV=1 run_step 3600 "bench init (sin uv)" bench init "${INIT_ARGS[@]}"; then
      INIT_OK=1
      ok "Inicializado con el gestor clásico (pip)."
    else
      # [Z5] Intento 3: Python 3.12. Es la versión con más rodaje en el
      # ecosistema y con wheels para absolutamente todo.
      warn "Intento 2 fallido. Intento 3: Python 3.12 (máxima compatibilidad)..."
      apartar_bench_roto
      if uv python install 3.12 >/dev/null 2>&1; then
        PY312="$(uv python find 3.12 2>/dev/null || true)"
        if [[ -n "$PY312" && -x "$PY312" ]]; then
          ln -sf "$PY312" "$HOME/.local/bin/python3.12"
          args312=()
          for a in "${INIT_ARGS[@]}"; do
            case "$a" in
              *"/python${PYTHON_VERSION}") args312+=("$HOME/.local/bin/python3.12") ;;
              *) args312+=("$a") ;;
            esac
          done
          if run_step 3600 "bench init (Python 3.12)" bench init "${args312[@]}"; then
            INIT_OK=1
            warn "Inicializado con Python 3.12 en lugar de ${PYTHON_VERSION}."
            warn "Es una desviación de tu guía: anótalo en la documentación."
          fi
        fi
      fi
    fi
  fi

  if (( INIT_OK == 0 )); then
    fail "bench init no completó. Diagnóstico rápido:"
    fail "  Espacio libre: $(df -h "$HOME" 2>/dev/null | tail -1 || echo '?')"
    fail "  Memoria      : $(free -h 2>/dev/null | awk '/Mem:/{print $2" total, "$7" disponible"}' || echo '?')"
    [[ -d "$BENCH_DIR/logs" ]] && { fail "  Últimas líneas de los logs de bench:"; tail -n 15 "$BENCH_DIR"/logs/*.log 2>/dev/null | sed 's/^/      /'; }
    exit 1
  fi

  # Validación real: no basta con el código de salida.
  if [[ ! -d "$BENCH_DIR/apps/frappe" ]]; then
    fail "bench init terminó pero no existe ${BENCH_DIR}/apps/frappe."
    exit 1
  fi
  if [[ ! -x "$BENCH_DIR/env/bin/python" ]]; then
    fail "No se creó el entorno virtual (${BENCH_DIR}/env)."
    exit 1
  fi
  ok "Bench inicializado y verificado (apps/frappe + env/ presentes)."
  paso init OK
fi

# 750 + o+x: el bit de ejecución para 'otros' es lo que permite a www-data
# atravesar el home hasta sites/assets. Sin él, Nginx devuelve 403.
chmod 750 "$HOME"
chmod o+x "$HOME"
ok "Permisos del home: $(stat -c '%a %n' "$HOME" 2>/dev/null || echo '?')"

# =============================================================
#  FASE 5: ESTRATEGIA DE CÓDIGO ("Code First")
# =============================================================
phase "FASE 5: DESCARGA DE APLICACIONES"
cd "$BENCH_DIR"

get_app() {
  local app="$1" branch="$2"
  if [[ -d "apps/${app}" ]]; then
    skip "get-app ${app}"; paso "get_${app}" OK; return 0
  fi
  paso "get_${app}" RUN
  # Una app rota no debe tumbar el despliegue completo.
  if run_step 1800 "get-app ${app} (${branch})" bench get-app --branch "${branch}" "${app}"; then
    ok "${app} descargada."; paso "get_${app}" OK
  else
    paso "get_${app}" ERR
    warn "Falló la descarga de '${app}' (branch ${branch}); continúo."
    FAILED_APPS+=("${app}:get-app")
  fi
}

# Sólo las aplicaciones que eligió el operador en la pregunta 10/10.
APPS_SEL="${APPS_SEL:-erpnext hrms lending wiki}"
info "Aplicaciones seleccionadas: ${APPS_SEL:-(ninguna)}"
for _app in erpnext hrms lending wiki; do
  case " ${APPS_SEL} " in
    *" ${_app} "*)
      if [[ "$_app" == "wiki" ]]; then get_app wiki master
      else get_app "$_app" "${FRAPPE_BRANCH}"; fi ;;
    *)
      # NA = no aplicable: no se descarga y no penaliza el progreso.
      paso "get_${_app}" NA
      paso "inst_${_app}" NA
      info "'${_app}' no seleccionada; se omite." ;;
  esac
done

# =============================================================
#  FASE 6.1: CREACIÓN DEL SITIO
# =============================================================
paso site RUN
phase "FASE 6.1: SITIO ${SITE_NAME}"
cd "$BENCH_DIR"

if [[ -d "sites/${SITE_NAME}" ]]; then
  skip "new-site ${SITE_NAME}"
else
  # Los flags de new-site cambian entre versiones de bench. Los sondeamos
  # UNA vez y armamos la invocación correcta; la v1 reintentaba a ciegas y
  # dejaba la base de datos a medio crear.
  NS_HELP="$(bench new-site --help 2>&1 || true)"
  NS_ARGS=("${SITE_NAME}")
  if grep -q -- '--mariadb-root-password' <<<"$NS_HELP"; then
    NS_ARGS+=(--mariadb-root-password "${DB_ROOT_PASS}")
  elif grep -q -- '--db-root-password' <<<"$NS_HELP"; then
    NS_ARGS+=(--db-root-password "${DB_ROOT_PASS}")
  else
    NS_ARGS+=(--mariadb-root-password "${DB_ROOT_PASS}")
  fi
  # El prompt "Enter mysql super user [root]:" aparece porque frappe pide el
  # USUARIO de la base de datos aparte de la contraseña. Sin este flag se
  # queda esperando una respuesta que nadie va a escribir.
  if grep -q -- '--db-root-username' <<<"$NS_HELP"; then
    NS_ARGS+=(--db-root-username root)
  elif grep -q -- '--mariadb-root-username' <<<"$NS_HELP"; then
    NS_ARGS+=(--mariadb-root-username root)
  fi
  NS_ARGS+=(--admin-password "${ADMIN_PASS}")
  # Fuerza al usuario de la BD del sitio a usar contraseña en vez de socket.
  if grep -q -- '--no-mariadb-socket' <<<"$NS_HELP"; then
    NS_ARGS+=(--no-mariadb-socket)
  fi
  if ! run_step 1200 "new-site ${SITE_NAME}" bench new-site "${NS_ARGS[@]}"; then
    fail "No se pudo crear el sitio. Causa más común: credenciales de MariaDB."
    fail "Prueba a mano:  mariadb -u root -p -h 127.0.0.1 -e 'SELECT 1'"
    exit 1
  fi
  ok "Sitio '${SITE_NAME}' creado."
fi

bench use "${SITE_NAME}"
paso site OK

# =============================================================
#  FASE 6.3: EL PROBLEMA DE LAS DOS TERMINALES
#  No podemos abrir una segunda sesión SSH: levantamos 'bench start' en
#  background con setsid (grupo de procesos propio), esperamos a que Redis
#  abra el 13000 (lo que HRMS y Wiki necesitan), instalamos y matamos el
#  GRUPO completo. Un 'kill $PID' a secas dejaría honcho y los 3 redis vivos.
# =============================================================
phase "FASE 6.3: INSTALACIÓN DE APPS CON SERVICIOS TEMPORALES"

BENCH_LOG="$HOME/bashcore-bench-start.log"
BENCH_PID=""

stop_bench() {
  # Aislamiento real: 'set +e' sin 'trap - ERR' no evita que el trap dispare.
  set +e
  trap - ERR
  if [[ -n "$BENCH_PID" ]] && kill -0 "$BENCH_PID" 2>/dev/null; then
    info "Apagando el 'bench start' temporal (PGID ${BENCH_PID})..."
    kill -TERM -- "-${BENCH_PID}" 2>/dev/null || kill -TERM "$BENCH_PID" 2>/dev/null
    sleep 5
    kill -KILL -- "-${BENCH_PID}" 2>/dev/null
  fi
  # Barrido de huérfanos.
  pkill -u "$(id -u)" -f 'honcho'                 2>/dev/null
  pkill -u "$(id -u)" -f 'redis.*config/redis'    2>/dev/null
  pkill -u "$(id -u)" -f 'frappe-bench.*socketio' 2>/dev/null
  sleep 2
  ok "Servicios temporales detenidos."
  set -e
  # shellcheck disable=SC2064  # ERR_TRAP tiene comillas simples: $?/$LINENO no se expanden aquí
  trap "$ERR_TRAP" ERR
}
# Garantiza el apagado aunque una app falle a mitad de camino.
trap 'stop_bench' EXIT

info "Levantando servicios en background (Redis 11000/12000/13000)..."
cd "$BENCH_DIR"
setsid bench start > "$BENCH_LOG" 2>&1 &
BENCH_PID=$!
ok "PID/PGID ${BENCH_PID}. Log: ${BENCH_LOG}"

# Espera activa (mejor que un 'sleep 10' a ciegas).
READY=0
for i in {1..40}; do
  sleep 2
  if (echo > /dev/tcp/127.0.0.1/13000) 2>/dev/null; then
    READY=1; ok "Redis cache respondiendo tras $((i*2))s."; break
  fi
  if ! kill -0 "$BENCH_PID" 2>/dev/null; then
    fail "'bench start' murió. Últimas líneas de ${BENCH_LOG}:"
    tail -n 20 "$BENCH_LOG" || true
    exit 1
  fi
done
(( READY == 0 )) && warn "El 13000 no respondió en 80s; intento continuar."

install_app() {
  local app="$1"
  if [[ ! -d "apps/${app}" ]]; then
    warn "'${app}' no está descargada; omito."; paso "inst_${app}" ERR; return 0
  fi
  if bench --site "${SITE_NAME}" list-apps 2>/dev/null | grep -qw "${app}"; then
    skip "install-app ${app}"; paso "inst_${app}" OK; return 0
  fi
  paso "inst_${app}" RUN
  if run_step 1800 "install-app ${app}" bench --site "${SITE_NAME}" install-app "${app}"; then
    ok "${app} instalada."; paso "inst_${app}" OK
  else
    paso "inst_${app}" ERR
    warn "Falló la instalación de '${app}'."
    FAILED_APPS+=("${app}:install-app")
  fi
}

for _app in erpnext hrms lending wiki; do
  case " ${APPS_SEL} " in
    *" ${_app} "*) install_app "$_app" ;;
  esac
done

info "Aplicando migraciones pendientes..."
paso migrate RUN
run_step 1800 "bench migrate" bench --site "${SITE_NAME}" migrate && paso migrate OK || { warn "bench migrate reportó errores."; paso migrate ERR; }

# --- Preparativos de la Fase 7 que le corresponden al usuario ---------------
info "Habilitando scheduler y desactivando modo mantenimiento..."
bench --site "${SITE_NAME}" enable-scheduler         || warn "Scheduler no habilitado."
bench --site "${SITE_NAME}" set-maintenance-mode off || warn "Modo mantenimiento no cambiado."

paso build RUN
info "Compilando assets del frontend (esbuild)..."
[[ -n "${NODE_OPTIONS:-}" ]] && info "NODE_OPTIONS=${NODE_OPTIONS}"
if ! run_step 2400 "bench build (assets del frontend)" bench build; then
  warn "'bench build' falló: la UI puede quedar sin estilos."
  warn "Causa más común: falta de memoria. Amplía la RAM del sistema"
  warn "y reintenta con: cd ${BENCH_DIR} && bench build"
  paso build ERR
else
  paso build OK
fi

paso configs RUN
info "Generando configuraciones de Nginx y Supervisor..."
bench setup nginx --yes      || bench setup nginx      || warn "setup nginx con errores."
bench setup supervisor --yes || bench setup supervisor || warn "setup supervisor con errores."
ok "Configuraciones en ${BENCH_DIR}/config/"
paso configs OK

# Apagado explícito (el trap EXIT es solo la red de seguridad).
stop_bench
trap - EXIT

# [F8] Inventario real de lo que quedó instalado en el sitio: la única prueba
# válida de que la Fase 6 terminó bien es preguntárselo a Frappe.
info "Inventario de apps instaladas en ${SITE_NAME}:"
if bench --site "${SITE_NAME}" list-apps > "$HOME/.bashcore_apps" 2>/dev/null; then
  sed 's/^/      /' "$HOME/.bashcore_apps"
  for expected in frappe ${APPS_SEL}; do
    if grep -qw "$expected" "$HOME/.bashcore_apps"; then
      ok "  ${expected}: instalada"
    else
      warn "  ${expected}: NO instalada"
      case " ${FAILED_APPS[*]-} " in
        *" ${expected}:"*) ;;
        *) FAILED_APPS+=("${expected}:ausente") ;;
      esac
    fi
  done
else
  warn "No se pudo obtener el inventario de apps."
fi

if (( ${#FAILED_APPS[@]} > 0 )); then
  printf '%s\n' "${FAILED_APPS[@]}" > "$HOME/.bashcore_failed_apps"
  warn "Componentes con problemas: ${FAILED_APPS[*]}"
else
  rm -f "$HOME/.bashcore_failed_apps"
  ok "Las 5 apps (frappe, erpnext, hrms, lending, wiki) están instaladas."
fi

mark_done userphase
echo -e "\n${GREEN}${BOLD}>>> Fase de usuario completada.${NC}"
USERPHASE

chown "${NEW_USER}:${NEW_USER}" "$USER_SCRIPT"
chmod 700 "$USER_SCRIPT"
ok "Sub-script preparado: ${USER_SCRIPT}"

# --- [S2] Lanzamiento DESACOPLADO de la fase de usuario ----------------------
# El motivo: 'bench init' + 'get-app' + 'install-app' tardan 20-45 min y tienen
# tramos de varios minutos sin imprimir nada. Si el script vive en el primer
# plano de tu sesión SSH, cualquier corte (keepalive, wifi, cierre de laptop)
# se lleva la instalación a medias. Desacoplado, la instalación sobrevive.
LAUNCH_MODE="(no lanzado)"
UP_LOG="${USER_HOME}/bashcore-userphase.log"
UP_RC="${USER_HOME}/.bashcore_userphase.rc"
UP_PID="${USER_HOME}/.bashcore_userphase.pid"
WRAPPER="${USER_HOME}/bashcore-user-run.sh"
SCREEN_NAME="bashcore-frappe"

cat > "$WRAPPER" <<WRAP
#!/usr/bin/env bash
# Envoltorio de la fase de usuario.
echo \$\$ > "${UP_PID}"
rm -f "${UP_RC}"

# [P2] Nada de preguntas. Si un comando intenta pedir credenciales o una
# confirmación, debe FALLAR al instante y dejar rastro en el log, no quedarse
# esperando una tecla que nadie va a pulsar.
export GIT_TERMINAL_PROMPT=0
export GIT_ASKPASS=/bin/true
export SSH_ASKPASS=/bin/true
export GIT_CONFIG_PARAMETERS="'core.askpass='"
export DEBIAN_FRONTEND=noninteractive
export PIP_NO_INPUT=1
export PYTHONUNBUFFERED=1
export CI=1
# [A2] Terminal "tonto": ninguna librería intentará dibujar barras de
# progreso, consultar el tamaño del terminal ni emitir códigos de color.
export TERM=dumb
export NO_COLOR=1
export FORCE_COLOR=0
export COLUMNS=120
# [S3] Si algún sudo se escapara a la red de seguridad, que falle al
# instante en vez de abrir /dev/tty y quedarse esperando una tecla.
export SUDO_ASKPASS=/bin/false

# [P1][P3] Entrada cerrada (/dev/null) y salida capturada con 'script': así
# también queda registrado lo que un programa escriba directamente al
# terminal en lugar de a su salida estándar (ahí se perdían los prompts).
if command -v script >/dev/null 2>&1; then
  script -qefc "bash ${USER_SCRIPT}" /dev/null >> "${UP_LOG}" 2>&1 < /dev/null
else
  bash "${USER_SCRIPT}" >> "${UP_LOG}" 2>&1 < /dev/null
fi
echo \$? > "${UP_RC}"
WRAP
chown "${NEW_USER}:${NEW_USER}" "$WRAPPER"
chmod 700 "$WRAPPER"
touch "$UP_LOG"; chown "${NEW_USER}:${NEW_USER}" "$UP_LOG"

user_phase_running() {
  [[ -f "$UP_PID" ]] || return 1
  local pid; pid="$(cat "$UP_PID" 2>/dev/null || true)"
  [[ -n "$pid" ]] || return 1
  kill -0 "$pid" 2>/dev/null
}

launch_user_phase() {
  rm -f "$UP_RC"
  if command -v screen >/dev/null 2>&1; then
    # Sesión screen desacoplada: reenganchable con 'screen -r'.
    su - "$NEW_USER" -c "screen -dmS ${SCREEN_NAME} bash ${WRAPPER}"
    LAUNCH_MODE="screen (${SCREEN_NAME})"
    ok "Lanzado en screen '${SCREEN_NAME}' como ${NEW_USER}."
    info "Consola en vivo:  sudo -u ${NEW_USER} screen -r ${SCREEN_NAME}"
  else
    su - "$NEW_USER" -c "setsid nohup bash ${WRAPPER} >/dev/null 2>&1 &"
    LAUNCH_MODE="setsid/nohup"
    ok "Lanzado con setsid/nohup como ${NEW_USER}."
  fi
  sleep 5
}

# [S3] Supervisión con latido: distingue "trabajando en silencio" de "colgado".
monitor_user_phase() {
  local started size last_size=-1 quiet=0 elapsed pid tpid rc last_mb=0 stuck=0
  started="$(date +%s)"
  pid="$(cat "$UP_PID" 2>/dev/null || echo '?')"
  last_mb="$(bench_size_mb)"
  info "Proceso desacoplado vía ${LAUNCH_MODE} (PID ${pid}). Log: ${UP_LOG}"
  info "Comprobación independiente desde otra sesión: bash bashcore-esta-vivo.sh ${NEW_USER}"
  info "Si pierdes la conexión, la instalación CONTINÚA. Relanza este script"
  info "y se reengancha automáticamente al proceso en curso."
  echo

  # [P4] Ya no se vuelca el log en pantalla: el detalle vive en el archivo y
  # aquí se muestra únicamente el avance. Se mantiene un "espejo" silencioso
  # al log principal para que quede todo registrado en un solo sitio.
  tail -n 0 -F "$UP_LOG" >> "${LOG_FILE}.detalle" 2>/dev/null &
  tpid=$!
  say "\n"
  render_progreso 0

  local tick=0
  while :; do
    [[ -f "$UP_RC" ]] && break
    sleep 5
    tick=$((tick+1))
    elapsed=$(( ($(date +%s) - started) / 60 ))
    render_progreso "$elapsed"
    # Al log, una línea de resumen cada 2 minutos (sin códigos de control).
    (( tick % 24 == 0 )) && log_progreso "$elapsed"
    (( tick % 4 != 0 )) && continue    # el resto de comprobaciones cada 20 s
    size="$(stat -c%s "$UP_LOG" 2>/dev/null || echo 0)"
    if [[ "$size" == "$last_size" ]]; then
      quiet=$((quiet + 1))
      # Cada 3 min de silencio, medimos el DISCO: es la prueba de avance.
      if (( quiet % 36 == 0 )) && user_phase_running; then
        CARD_LINES=0   # tras escribir avisos, la tarjeta se redibuja abajo
        local cur_mb delta
        cur_mb="$(bench_size_mb)"
        delta=$(( cur_mb - last_mb ))
        if (( delta > 0 )); then
          # Silencioso pero escribiendo: exactamente lo que hace yarn install.
          ok "Trabajando en silencio: frappe-bench creció +${delta}MB (${cur_mb}MB) en $((quiet*20/60)) min. Total ${elapsed} min."
          stuck=0
        else
          stuck=$((stuck + 1))
          warn "Sin salida NI crecimiento en disco desde $((quiet*20/60)) min (total ${elapsed} min):"
          pressure_report
          # [P7] 0% de CPU + sin hijos = lectura bloqueante, no falta de recursos.
          local cpu_sum
          cpu_sum="$(ps -u "$NEW_USER" -o pcpu= --no-headers 2>/dev/null | awk '{s+=$1} END{printf "%.0f", s}')"
          if grep -q "\[sudo\] password for" "$UP_LOG" 2>/dev/null; then
            warn "        >> HAY UN PROMPT DE SUDO ESPERANDO EN LA CONSOLA."
            warn "           Desbloquéalo: sudo -u ${NEW_USER} screen -r ${SCREEN_NAME}"
            warn "           (escribe la contraseña del usuario y pulsa Enter)"
          fi
          if [[ "${cpu_sum:-0}" == "0" ]]; then
            warn "        >> 0% de CPU: el proceso NO trabaja, está BLOQUEADO."
            warn "        >> Con recursos suficientes, esto suele ser un comando"
            warn "           esperando una respuesta. El log completo está en:"
            warn "           ${UP_LOG}"
          fi
          # [V4] Nada de esperar al timeout de 60 min: 20 min sin escribir
          # un solo byte es un cuelgue real, y ya sabemos por qué suele ser.
          if (( stuck >= 7 )); then
            kill "$tpid" 2>/dev/null || true
            fail "20 minutos sin salida y sin escribir en disco: está CONGELADO."
            fail "Causa más frecuente en un CT: memoria agotada sin swap; el"
            fail "cgroup estrangula los procesos y se quedan quietos en lugar"
            fail "de morir. Revisa el informe de presión de arriba."
            fail ""
            fail "Solución habitual: ampliar memoria y swap desde el anfitrión"
            fail "y reiniciar el sistema."
            fail "Después relanza este script: reanuda y aparta el bench roto."
            fail "Generando el paquete de diagnóstico automáticamente..."
            bash "$0" --diag 2>/dev/null | tail -6 | sed 's/^/      /' || true
            return 1
          fi
        fi
        last_mb="$cur_mb"
      fi
    else
      quiet=0; stuck=0; last_size="$size"
    fi
    if ! user_phase_running && [[ ! -f "$UP_RC" ]]; then
      sleep 10
      if [[ ! -f "$UP_RC" ]]; then
        kill "$tpid" 2>/dev/null || true
        fail "El proceso de la fase de usuario desapareció sin dejar código de salida."
        fail "Últimas 30 líneas de ${UP_LOG}:"
        tail -n 30 "$UP_LOG" 2>/dev/null | sed 's/^/      /' || true
        fail "Generando el paquete de diagnóstico automáticamente..."
        bash "$0" --diag 2>/dev/null | tail -6 | sed 's/^/      /' || true
        return 1
      fi
    fi
  done

  # 'tail -F' va por detrás del archivo: si lo matamos en cuanto aparece el
  # código de salida, las últimas líneas (justo las que importan cuando algo
  # falla) nunca llegan al log principal. Le damos tiempo a alcanzar el final.
  sleep 3
  elapsed=$(( ($(date +%s) - started) / 60 ))
  render_progreso "$elapsed"
  log_progreso "$elapsed"
  kill "$tpid" 2>/dev/null || true
  wait "$tpid" 2>/dev/null || true
  rc="$(cat "$UP_RC" 2>/dev/null || echo 1)"
  # Y dejamos constancia de dónde está el log completo e íntegro.
  info "Log íntegro de la fase de usuario: ${UP_LOG} ($(wc -l < "$UP_LOG" 2>/dev/null || echo '?') líneas)"
  elapsed=$(( ($(date +%s) - started) / 60 ))
  if [[ "$rc" == "0" ]]; then
    ok "Fase de usuario completada en ${elapsed} min."
    return 0
  fi
  fail "La fase de usuario terminó con código ${rc} tras ${elapsed} min."
  analizar_fallo
  fail "Últimas 40 líneas de ${UP_LOG}:"
  tail -n 40 "$UP_LOG" 2>/dev/null | sed 's/^/      /' || true
  fail "Generando el paquete de diagnóstico automáticamente..."
  bash "$0" --diag 2>/dev/null | tail -6 | sed 's/^/      /' || true
  return 1
}

if is_done fase456; then
  skip "Fases 3.2, 4, 5 y 6 (usuario)"
elif user_phase_running; then
  # Reengancharse en lugar de lanzar un duplicado.
  warn "Ya hay una fase de usuario en curso (PID $(cat "$UP_PID")): me reengancho."
  if monitor_user_phase; then
    mark_done fase456
  else
    exit 1
  fi
else
  info "Preparando la ejecución como '${NEW_USER}'..."
  say "${YELLOW}  bench init + get-app + install-app: 20-45 min.\n"
  say "  Se ejecuta desacoplado: puedes cerrar la sesión sin romper nada.${NC}\n\n"
  launch_user_phase
  if monitor_user_phase; then
    mark_done fase456
  else
    exit 1
  fi
fi

# =============================================================================
#  FASE 7: PASE A PRODUCCIÓN Y SEGURIDAD WEB  (CIS NGINX v3.0.0)
# =============================================================================
avance prod RUN
phase "FASE 7: PASE A PRODUCCIÓN"

if is_done fase7_ansible; then
  skip "Ansible"
else
  info "Instalando Ansible..."
  apt_do install -y ansible || warn "Ansible no se instaló (no es bloqueante)."
  mark_done fase7_ansible
fi

# --- 7.1 Puentes globales ---------------------------------------------------
# pipx dejó el binario en /home/USUARIO/.local/bin/bench. Al usar sudo, Linux
# resetea el $PATH a los directorios "seguros" del sistema y no lo encuentra:
# de ahí el "command not found" con sudo y el funcionamiento sin sudo.
info "Creando enlaces simbólicos globales..."
if [[ -x "${USER_HOME}/.local/bin/bench" ]]; then
  mkdir -p "$USRLOCALBIN"
  ln -sf "${USER_HOME}/.local/bin/bench" "${USRLOCALBIN}/bench"
  ok "bench -> $(readlink -f "${USRLOCALBIN}/bench" 2>/dev/null || echo '?')"
else
  fail "No existe ${USER_HOME}/.local/bin/bench: la Fase 4 no terminó bien."
  exit 1
fi

# Supervisor necesita 'node' en un PATH global para ejecutar Socket.io.
if [[ -f "${USER_HOME}/.bashcore_node_path" ]]; then
  NODE_PATH_BIN="$(cat "${USER_HOME}/.bashcore_node_path")"
  NODE_DIR_BIN="$(cat "${USER_HOME}/.bashcore_node_dir")"
  mkdir -p "$USRBIN" "$USRLOCALBIN"
  ln -sf "$NODE_PATH_BIN" "${USRBIN}/node"
  ln -sf "$NODE_PATH_BIN" "${USRLOCALBIN}/node"
  [[ -x "${NODE_DIR_BIN}/npm"  ]] && ln -sf "${NODE_DIR_BIN}/npm"  "${USRLOCALBIN}/npm"
  [[ -x "${NODE_DIR_BIN}/yarn" ]] && ln -sf "${NODE_DIR_BIN}/yarn" "${USRLOCALBIN}/yarn"
  ok "node -> ${NODE_PATH_BIN}"
else
  warn "Sin ruta de node del usuario: Socket.io (chat, notificaciones) fallará."
fi

# --- 7.2 bench setup production --------------------------------------------
if is_done fase7_production; then
  skip "bench setup production"
else
  info "Ejecutando 'bench setup production ${NEW_USER}'..."
  cd "$BENCH_DIR"
  if bench setup production "$NEW_USER" --yes; then
    ok "Producción configurada."
  else
    warn "'bench setup production' reportó errores; refuerzo manual abajo."
  fi
  # bench corriendo como root puede dejar artefactos con dueño equivocado.
  chown -R "${NEW_USER}:${NEW_USER}" "$BENCH_DIR"
  ok "Propiedad de ${BENCH_DIR} normalizada."
  mark_done fase7_production
fi

# --- 7.3 Hardening de Nginx (CIS 2.5.1, 5.3.1, 5.3.2) ----------------------
info "Inyectando cabeceras de seguridad en Nginx..."
NGINX_MAIN="${ETC}/nginx/nginx.conf"
mkdir -p "${ETC}/nginx/conf.d"
[[ -f "$NGINX_MAIN" ]] && cp -n "$NGINX_MAIN" "${NGINX_MAIN}.bashcore.bak" 2>/dev/null || true

if [[ -f "$NGINX_MAIN" ]] && grep -qE '^\s*include\s+/etc/nginx/conf\.d/\*\.conf;' "$NGINX_MAIN"; then
  # Ruta preferida: conf.d ya se incluye DENTRO del bloque http, así que un
  # snippet propio es idempotente y sobrevive a las actualizaciones del paquete.
  cat > "${ETC}/nginx/conf.d/00-bashcore-hardening.conf" <<'NGXSEC'
# ==========================================================
#  Hardening HTTP - CIS NGINX Benchmark v3.0.0
#  Contexto: http { }  (incluido vía conf.d/*.conf)
# ==========================================================
# (CIS 2.5.1) Ocultar la versión del servidor
server_tokens off;

# (CIS 5.3.1) Anti-Clickjacking
add_header X-Frame-Options SAMEORIGIN always;

# (CIS 5.3.2) Anti-MIME sniffing
add_header X-Content-Type-Options nosniff always;

# Filtro XSS para navegadores antiguos
add_header X-XSS-Protection "1; mode=block" always;

# Control de fuga de referrers
add_header Referrer-Policy "strict-origin-when-cross-origin" always;
NGXSEC
  # La configuración que genera Frappe usa 'access_log ... main;' y el paquete
  # de nginx de Ubuntu NO define ese formato (el de nginx.org sí). Sin esto,
  # 'nginx -t' falla con: unknown log format "main".
  # Se comprueba antes: un log_format duplicado también rompe nginx.
  if grep -rqs '^\s*log_format\s\+main' "${ETC}/nginx/nginx.conf" "${ETC}/nginx/conf.d/" 2>/dev/null; then
    info "El formato de log 'main' ya está definido; no se duplica."
  else
    cat >> "${ETC}/nginx/conf.d/00-bashcore-hardening.conf" <<'NGXLOG'

# Formato que espera la configuración de Frappe (Ubuntu no lo define).
log_format main '$remote_addr - $remote_user [$time_local] "$request" '
                '$status $body_bytes_sent "$http_referer" '
                '"$http_user_agent" "$http_x_forwarded_for"';
NGXLOG
    ok "Formato de log 'main' definido (lo exige la config de Frappe)."
  fi
  ok "Snippet: ${ETC}/nginx/conf.d/00-bashcore-hardening.conf"
elif [[ -f "$NGINX_MAIN" ]]; then
  if grep -q 'BASHCORE-HARDENING' "$NGINX_MAIN"; then
    info "Cabeceras ya inyectadas en nginx.conf."
  else
    awk '
      /^[[:space:]]*http[[:space:]]*\{/ && !done {
        print
        print "\t# --- BASHCORE-HARDENING (CIS NGINX v3.0.0) ---"
        print "\tserver_tokens off;"
        print "\tadd_header X-Frame-Options SAMEORIGIN always;"
        print "\tadd_header X-Content-Type-Options nosniff always;"
        print "\tadd_header X-XSS-Protection \"1; mode=block\" always;"
        print "\t# --- /BASHCORE-HARDENING ---"
        done = 1; next
      }
      { print }
    ' "$NGINX_MAIN" > /tmp/nginx.conf.new
    mv /tmp/nginx.conf.new "$NGINX_MAIN"
    ok "Cabeceras inyectadas en nginx.conf."
  fi
else
  warn "No encontré ${NGINX_MAIN}."
fi

# --- 7.4 Symlinks de Nginx y Supervisor -------------------------------------
info "Verificando enlaces de configuración..."
if [[ -f "${BENCH_DIR}/config/nginx.conf" ]]; then
  ln -sf "${BENCH_DIR}/config/nginx.conf" "${ETC}/nginx/conf.d/frappe-bench.conf"
  ok "Nginx: frappe-bench.conf enlazado."
else
  warn "Falta ${BENCH_DIR}/config/nginx.conf"
fi

# El 'default site' de Ubuntu compite por el puerto 80.
if [[ -e "${ETC}/nginx/sites-enabled/default" ]]; then
  rm -f "${ETC}/nginx/sites-enabled/default"
  ok "Sitio 'default' de Nginx deshabilitado."
fi

# [v16] 'bench setup production' puede abortar y dejar sin generar la
# configuración de Supervisor. En ese caso se genera explícitamente como el
# usuario operativo, que es lo que hace el paso 9.3 de la guía a mano.
if [[ ! -f "${BENCH_DIR}/config/supervisor.conf" ]]; then
  warn "Falta config/supervisor.conf: lo genero explícitamente."
  su - "$NEW_USER" -c "cd '${BENCH_DIR}' && bench setup supervisor --yes" \
    >/dev/null 2>&1 || su - "$NEW_USER" -c "cd '${BENCH_DIR}' && bench setup supervisor" \
    >/dev/null 2>&1 || warn "No se pudo generar supervisor.conf."
  [[ -f "${BENCH_DIR}/config/supervisor.conf" ]] && ok "supervisor.conf generado."
fi
if [[ ! -f "${BENCH_DIR}/config/nginx.conf" ]]; then
  warn "Falta config/nginx.conf: lo genero explícitamente."
  su - "$NEW_USER" -c "cd '${BENCH_DIR}' && bench setup nginx --yes" \
    >/dev/null 2>&1 || warn "No se pudo generar nginx.conf."
  [[ -f "${BENCH_DIR}/config/nginx.conf" ]] && ok "nginx.conf generado."
fi

if [[ -f "${BENCH_DIR}/config/supervisor.conf" ]]; then
  mkdir -p "${ETC}/supervisor/conf.d"
  ln -sf "${BENCH_DIR}/config/supervisor.conf" "${ETC}/supervisor/conf.d/frappe-bench.conf"
  ok "Supervisor: frappe-bench.conf enlazado."
else
  warn "Falta ${BENCH_DIR}/config/supervisor.conf"
fi

# [P6] Despliegue local: registramos el sitio en /etc/hosts para poder
# abrirlo desde el propio servidor sin depender de un DNS ni de un dominio.
if grep -qE "^127\.0\.0\.1[[:space:]]+${SITE_NAME}$" "${ETC}/hosts" 2>/dev/null \
   || grep -qE "[[:space:]]${SITE_NAME}([[:space:]]|$)" "${ETC}/hosts" 2>/dev/null; then
  info "El sitio ya está registrado en ${ETC}/hosts."
else
  printf '127.0.0.1 %s\n' "$SITE_NAME" >> "${ETC}/hosts"
  ok "Registrado '127.0.0.1 ${SITE_NAME}' en ${ETC}/hosts (acceso local)."
fi

info "Validando la configuración de Nginx (nginx -t)..."
if nginx -t; then
  systemctl reload nginx || systemctl restart nginx
  ok "Nginx recargado."
else
  fail "Configuración de Nginx inválida. Backup: ${NGINX_MAIN}.bashcore.bak"
  fail "Corrige y ejecuta: nginx -t && systemctl reload nginx"
fi

avance prod OK
avance web RUN
info "Registrando los procesos en Supervisor..."
systemctl enable --now supervisor
supervisorctl reread || warn "supervisorctl reread con errores."
supervisorctl update || warn "supervisorctl update con errores."
sleep 8
supervisorctl status || true
avance web OK
mark_done fase7_web

# =============================================================================
#  VALIDACIÓN FINAL Y LIMPIEZA
# =============================================================================
phase "VALIDACIÓN FINAL"

# [S2] Los permisos amplios eran para la instalación. En producción, Frappe
# sólo necesita gestionar sus servicios: reducimos al mínimo imprescindible.
if [[ -f "$SUDOERS_INSTALL" ]]; then
  SUDOERS_FINAL="${ETC}/sudoers.d/99-bashcore-frappe"
  cat > "$SUDOERS_FINAL" <<SUDOFIN
# Permisos mínimos para que Frappe gestione sus propios servicios.
# Generado por bashcore-frappe16 al finalizar el despliegue.
${NEW_USER} ALL=(root) NOPASSWD: $(command -v supervisorctl 2>/dev/null || echo /usr/bin/supervisorctl) *
${NEW_USER} ALL=(root) NOPASSWD: $(command -v systemctl 2>/dev/null || echo /usr/bin/systemctl) * nginx
${NEW_USER} ALL=(root) NOPASSWD: $(command -v nginx 2>/dev/null || echo /usr/sbin/nginx)
${NEW_USER} ALL=(root) NOPASSWD: $(command -v service 2>/dev/null || echo /usr/sbin/service) nginx *
Defaults:${NEW_USER} !requiretty
SUDOFIN
  chmod 440 "$SUDOERS_FINAL"
  if command -v visudo >/dev/null 2>&1 && ! visudo -cf "$SUDOERS_FINAL" >/dev/null 2>&1; then
    rm -f "$SUDOERS_FINAL"
    warn "Los permisos finales de sudo no validaron; se conservan los amplios."
  else
    rm -f "$SUDOERS_INSTALL"
    ok "Permisos de sudo reducidos a lo mínimo (supervisorctl, systemctl, nginx)."
  fi
fi

# El .env contiene la contraseña de la base de datos: se destruye siempre.
if [[ -f "$ENV_FILE" ]]; then
  shred -u "$ENV_FILE" 2>/dev/null || rm -f "$ENV_FILE"
  ok "Archivo temporal de credenciales destruido."
fi
rm -f "${USER_HOME}/.bashcore_node_path" "${USER_HOME}/.bashcore_node_dir"
rm -f "${ETC}/needrestart/conf.d/99-bashcore.conf"

VALID_OK=0; VALID_TOTAL=0
check() {
  local desc="$1"; shift
  VALID_TOTAL=$((VALID_TOTAL+1))
  if "$@" >/dev/null 2>&1; then
    ok "${desc}"; VALID_OK=$((VALID_OK+1))
  else
    warn "${desc} -> FALLA"
  fi
}
check "MariaDB activo"        systemctl is-active --quiet mariadb
check "Redis activo"          systemctl is-active --quiet redis-server
check "Nginx activo"          systemctl is-active --quiet nginx
check "Supervisor activo"     systemctl is-active --quiet supervisor
check "SSH en puerto ${SSH_PORT}" bash -c "ss -H -tln | grep -q ':${SSH_PORT}[[:space:]]'"
check "Puerto 80 escuchando"  bash -c "ss -H -tln | grep -q ':80[[:space:]]'"
check "Directorio del sitio"  test -d "${BENCH_DIR}/sites/${SITE_NAME}"
check "Login a MariaDB"       mariadb -u root -p"${DB_ROOT_PASS}" -h 127.0.0.1 -e "SELECT 1"

HTTP_CODE="$(curl -s -o /dev/null -w '%{http_code}' -H "Host: ${SITE_NAME}" http://127.0.0.1/ 2>/dev/null || echo '000')"
VALID_TOTAL=$((VALID_TOTAL+1))
if [[ "$HTTP_CODE" =~ ^(200|302|303)$ ]]; then
  ok "El sitio responde por HTTP (${HTTP_CODE})"; VALID_OK=$((VALID_OK+1))
else
  warn "El sitio devolvió ${HTTP_CODE}. Revisa: supervisorctl status y ${BENCH_DIR}/logs/"
fi

info "Cabeceras de seguridad en la respuesta:"
curl -sI -H "Host: ${SITE_NAME}" http://127.0.0.1/ 2>/dev/null \
  | grep -iE 'x-frame-options|x-content-type-options|x-xss-protection|^server:' \
  | sed 's/^/    /' || warn "No se pudieron leer las cabeceras."

FAILED_LIST=""
if [[ -f "${USER_HOME}/.bashcore_failed_apps" ]]; then
  FAILED_LIST="$(tr '\n' ' ' < "${USER_HOME}/.bashcore_failed_apps")"
fi

# Completamos el archivo de credenciales.
{
  echo "# --- Resumen del despliegue $(date -Is) ---"
  echo "# Acceso SSH .....: ssh -p ${SSH_PORT} ${NEW_USER}@<IP>"
  echo "# URL ............: http://${SITE_NAME}/"
  echo "# Usuario app ....: Administrator"
  echo "# Bench ..........: ${BENCH_DIR}"
  echo "# Validación .....: ${VALID_OK}/${VALID_TOTAL} comprobaciones OK"
} >> "$CRED_FILE"
chmod 600 "$CRED_FILE"

mark_done completo

# =============================================================================
#  RESUMEN  ([C5] las contraseñas salen SOLO a la terminal, nunca al log)
# =============================================================================
SERVER_IP="$(hostname -I 2>/dev/null | awk '{print $1}')"

echo -e "\n${GREEN}${BOLD}=============================================================="
echo -e "  DESPLIEGUE DE FRAPPE 16 FINALIZADO  (${VALID_OK}/${VALID_TOTAL} validaciones OK)"
echo -e "==============================================================${NC}"
echo "  Metadatos en: ${CRED_FILE}  (las contraseñas no se escriben en disco)"

say "
$(echo -e "${BOLD}ACCESO AL SERVIDOR${NC}")
  ssh -p ${SSH_PORT} ${NEW_USER}@${SERVER_IP}
  Contraseña de '${NEW_USER}': la que indicaste en la pregunta 3/10

$(echo -e "${BOLD}ACCESO A LA APLICACIÓN (local, sin dominio ni SSL)${NC}")
  Desde el servidor : http://${SITE_NAME}/   (ya está en /etc/hosts)
  Desde tu PC       : añade esta línea al hosts de tu equipo y abre la URL
                        ${SERVER_IP}  ${SITE_NAME}
                      Windows: C:\\Windows\\System32\\drivers\\etc\\hosts
                      Linux/macOS: /etc/hosts
  Comprobar ahora   : curl -I -H "Host: ${SITE_NAME}" http://${SERVER_IP}/
  Usuario  : Administrator
  Password : la que indicaste en la pregunta 8/10

$(echo -e "${BOLD}ARCHIVOS CLAVE${NC}")
  Metadatos    : ${CRED_FILE}   (0600, sin contraseñas)
  Log completo : ${LOG_FILE}    (0600)
  Progreso     : ${STATE_DIR}
  Bench        : ${BENCH_DIR}
  Apps del sitio: $( [[ -f "${USER_HOME}/.bashcore_apps" ]] && tr '\n' ' ' < "${USER_HOME}/.bashcore_apps" || echo '(no disponible)' )

$(echo -e "${BOLD}COMANDOS ÚTILES${NC}")
  bash $0 --status          # pasos completados
  bash $0 --attach          # seguir la instalación en vivo
  bash $0 --diag            # empaquetar logs si algo falla
  sudo -u ${NEW_USER} screen -r ${SCREEN_NAME}   # consola de la instalación
  supervisorctl status
  sudo -u ${NEW_USER} bash -lc 'cd ${BENCH_DIR} && bench --site ${SITE_NAME} list-apps'
  tail -f ${BENCH_DIR}/logs/worker.error.log

$(echo -e "${YELLOW}${BOLD}PENDIENTES RECOMENDADOS${NC}")
  1) Valida el acceso SSH en OTRA terminal ANTES de cerrar esta sesión.
  2) Apunta el DNS de ${SITE_NAME} a ${SERVER_IP}.
  3) Despliegue LOCAL: sin HTTPS ni certificados (no hace falta dominio).
  4) fail2ban:  sudo apt install fail2ban  (jail sshd puerto ${SSH_PORT})
  5) Backups:   bench --site ${SITE_NAME} backup --with-files  (+ cron)
  6) Guarda tus contraseñas en un gestor: el script no las almacena.

"
[[ -n "$FAILED_LIST" ]] && warn "Requieren atención manual: ${FAILED_LIST}"

echo -e "${GREEN}Fin: $(date -Is)${NC}\n"
sleep 1   # deja que tee vacíe el buffer
