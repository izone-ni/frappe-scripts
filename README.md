# Frappe-setup
**Instalador automatizado de Frappe 15 y 16 / ERPNext, con hardening CIS.**

![Frappe Versions](https://img.shields.io/badge/Frappe-v15%20|%20v16-blue?style=for-the-badge&logo=frappe)
![OS Compatibility](https://img.shields.io/badge/Ubuntu-22.04%20|%2024.04%20|%2026.04-E95420?style=for-the-badge&logo=ubuntu)
![Arch](https://img.shields.io/badge/Arch-amd64%20|%20arm64-555?style=for-the-badge)
![Bash](https://img.shields.io/badge/Script-Bash-4EAA25?style=for-the-badge&logo=gnu-bash)

`frappe-setup.sh` instala Frappe en un servidor Ubuntu limpio: MariaDB, Redis,
Node, Python, bench, el sitio, las aplicaciones elegidas (ERPNext, HRMS,
Lending, Wiki) y el pase a producción con Nginx y Supervisor. Además endurece el
sistema según CIS. Hace 10 preguntas al principio; el resto es desatendido.

---

## Contenido

1. [Requisitos](#requisitos)
2. [Instalación](#instalación)
3. [Después de instalar: cómo entrar al servidor](#después-de-instalar-cómo-entrar-al-servidor)
4. [Atajos de bench](#atajos-de-bench)
5. [Otras opciones del script](#otras-opciones-del-script)
6. [Si algo falla](#si-algo-falla)

---

## Requisitos

| | |
|---|---|
| **Sistema** | Ubuntu Server recién instalado. Frappe 16: Ubuntu 24.04 (probado), 26.04 o Debian 13 (con aviso). Frappe 15: Ubuntu 22.04 o 24.04 (probados), 26.04, Debian 12 o 13 (con aviso). |
| **Arquitectura** | amd64, o arm64 (por ejemplo Raspberry Pi 5 con Ubuntu Server 26.04) |
| **Memoria** | 4 GB de RAM como mínimo. Con menos, el script añade swap. |
| **Disco** | Unos 12 GB libres |
| **Permisos** | Ser `root`, o un usuario con `sudo` |
| **Llave SSH** | Tu llave **pública** SSH, en una sola línea (`ssh-ed25519 AAAA… tu@equipo`). La pide la pregunta 4 y, después de instalar, será la única forma de entrar por SSH. |

Si no tienes llave, créala **en tu equipo** (no en el servidor) y copia la
pública:

```bash
ssh-keygen -t ed25519
cat ~/.ssh/id_ed25519.pub
```

---

## Instalación

La instalación necesita privilegios de administrador: instala paquetes, crea
usuarios y cambia la configuración de SSH. Puedes lanzarla como `root` o desde
cualquier usuario que tenga `sudo`.

### Opción A: como root

Si entras al servidor directamente como `root`, o te conviertes en root con
`sudo -i`:

```bash
sudo -i     # sólo si no estás ya como root
wget -qO frappe-setup.sh https://github.com/izone-ni/frappe-scripts/releases/latest/download/frappe-setup.sh
bash frappe-setup.sh
```

### Opción B: desde cualquier usuario con sudo

Es lo habitual en un VPS o en la nube, donde entras como `ubuntu` u otro
usuario administrador:

```bash
wget -qO frappe-setup.sh https://github.com/izone-ni/frappe-scripts/releases/latest/download/frappe-setup.sh
sudo bash frappe-setup.sh
```

`sudo` te pide la contraseña de tu usuario. Si responde que no estás en el
archivo *sudoers*, tu usuario no tiene permisos de administrador: pide a quien
administre el servidor que lo añada al grupo `sudo`, o usa la opción A.

> **Ojo:** el usuario con el que entras **no** tiene por qué ser el que tendrá
> Frappe. Eso lo eliges en la pregunta 2 (el *usuario operativo*): puede ser el
> tuyo o uno nuevo, que el script crea.

### Qué pasa al ejecutarlo

1. Aparece el menú principal. Elige **1) Instalar** y la versión de Frappe
   (15 o 16).
2. Responde las 10 preguntas:

   | # | Pregunta |
   |---|---|
   | 1 | Nombre de la empresa (sale en el banner de acceso) |
   | 2 | Usuario operativo: el dueño de Frappe. Si no existe, se crea. |
   | 3 | Contraseña de ese usuario, para `sudo` (mínimo 12 caracteres) |
   | 4 | Tu llave pública SSH (puedes añadir varias) |
   | 5 | Puerto SSH nuevo |
   | 6 | Contraseña de `root` en MariaDB (mínimo 12 caracteres) |
   | 7 | Zona horaria (por defecto `America/Managua`) |
   | 8 | Contraseña de `Administrator` en Frappe (mínimo 12 caracteres) |
   | 9 | Nombre del sitio, por ejemplo `izone.frappe.software` |
   | 10 | Aplicaciones: ERPNext, HRMS, Lending, Wiki |

   Al final escribe `LISTO` para confirmar, o cualquier otra cosa para repetir
   las preguntas.

3. Empieza la instalación desatendida. Suele tardar entre 30 y 60 minutos:
   sólo `bench init` y la instalación de las apps llevan de 20 a 45. Una tarjeta de
   progreso muestra la fase actual y el tiempo estimado.

4. Al terminar verás un resumen con la URL del sitio, el usuario, el puerto SSH
   y las comprobaciones de la validación final.

**Las contraseñas no se guardan en ningún archivo.** Anótalas en tu gestor de
contraseñas antes de empezar.

### Si se corta la conexión durante la instalación

La parte larga corre dentro de `screen`, así que **la instalación sigue** aunque
se cierre tu sesión SSH. Para volver a verla, entra de nuevo y ejecuta como
root:

```bash
bash frappe-setup.sh --attach
```

Si la instalación se detuvo por un error, corrige la causa y lanza **el mismo
comando** de antes: continúa desde el paso que falló, sin repetir lo ya hecho.

---

## Después de instalar: cómo entrar al servidor

El hardening cambia SSH. A partir de aquí:

- SSH escucha en el **puerto que elegiste** en la pregunta 5, no en el 22.
- Sólo se entra **con llave**: las contraseñas por SSH quedan desactivadas.
- **`root` ya no puede entrar por SSH.** Se entra con el usuario operativo y,
  desde ahí, se pasa a root con `sudo`.

> **Antes de cerrar la sesión de la instalación**, abre **otra** terminal y
> comprueba que puedes entrar con el comando de abajo. Si falla, todavía tienes
> la sesión original abierta para corregirlo.

**Entrar como el usuario operativo** (el de Frappe):

```bash
ssh -p <puerto> <usuario>@<ip-del-servidor>
```

**Pasar a root** desde esa sesión. `sudo` pide la contraseña de la pregunta 3:

```bash
sudo -i
```

**Pasar al usuario operativo** desde root:

```bash
su - <usuario>
```

**Abrir el sitio:** `http://<nombre-del-sitio>/`, con el usuario
`Administrator` y la contraseña de la pregunta 8. Si el nombre del sitio no
tiene DNS, añade al archivo *hosts* de tu equipo la línea
`<ip-del-servidor>  <nombre-del-sitio>`:

- Windows: `C:\Windows\System32\drivers\etc\hosts`
- Linux y macOS: `/etc/hosts`

---

## Atajos de bench

Con los atajos escribes `migrate` en lugar de
`cd ~/frappe-bench && bench --site izone.frappe.software migrate`. Funcionan
desde cualquier carpeta y usan el sitio activo. `bench` sigue funcionando
exactamente igual: los atajos sólo añaden nombres nuevos.

### Instalarlos

Los atajos se instalan en el **usuario dueño del bench** (el usuario operativo),
porque es quien trabaja con Frappe. Si ya están instalados, no se duplica nada.

**En una instalación nueva** no hay que hacer nada: se añaden solos al final.

**En un servidor ya instalado**, elige una de estas dos formas.

#### Como root (recomendado)

```bash
sudo -i
wget -qO frappe-setup.sh https://github.com/izone-ni/frappe-scripts/releases/latest/download/frappe-setup.sh
bash frappe-setup.sh --atajos
```

También puedes ejecutar `bash frappe-setup.sh` y elegir **5) Atajos** en el
menú. El script encuentra el bench y escribe los atajos en el usuario dueño.

#### Como el usuario dueño del bench, sin root

El usuario necesita su propia copia del script, porque no puede leer la que
está en `/root`:

```bash
cd ~
wget -qO frappe-setup.sh https://github.com/izone-ni/frappe-scripts/releases/latest/download/frappe-setup.sh
bash frappe-setup.sh --atajos
```

Si lo ejecuta un usuario que no es el dueño del bench, el script se niega y
dice cuál es el dueño.

#### Activarlos

Los atajos se activan en la siguiente sesión del usuario. Para tenerlos al
momento, **como el usuario operativo**:

```bash
source ~/.bashrc
atajos          # muestra la lista completa
```

Como `root` no existen: viven en el `~/.bashrc` del usuario operativo. Para
usarlos, entra con ese usuario (`ssh -p <puerto> <usuario>@<ip>` o `su - <usuario>`).

### Los principales

| Escribes | Se ejecuta |
|---|---|
| `migrate` | `bench --site <sitio> migrate` |
| `build [app]` | `bench build [--app <app>]` |
| `restart` | `bench restart` |
| `clear-cache` | `clear-cache` y `clear-website-cache` del sitio |
| `console` | Consola de Python del sitio |
| `fdb` | Consola de MariaDB del sitio |
| `install-app <app>` | `bench --site <sitio> install-app <app>` |
| `add-app <enlace> [rama]` | `bench get-app --branch <rama> <enlace>` |
| `backup` | `bench --site <sitio> backup --with-files` |
| `maint on\|off` | Modo mantenimiento |
| `deploy` | Mantenimiento on → migrate → build → caché → restart → mantenimiento off |
| `logs [web\|worker\|scheduler\|socketio]` | Sigue el log de errores de ese proceso |
| `estado` | `supervisorctl status` y diagnóstico de workers |
| `sitio [nombre]` | Muestra o cambia el sitio activo |
| `bcd` | `cd` a la carpeta del bench |
| `llaves` | Crea llaves SSH para repositorios privados de GitHub |

### Todos los demás comandos

Cada uno de los 133 comandos de bench y Frappe se escribe con su mismo nombre:

```bash
set-admin-password NuevaClave        # bench --site <sitio> set-admin-password NuevaClave
add-user correo@empresa.com          # bench --site <sitio> add-user correo@empresa.com
run-patch frappe.patches.v16_0.x     # bench --site <sitio> run-patch …
new-site prueba.local                # bench new-site prueba.local
setup nginx --yes                    # bench setup nginx --yes
```

- **Otro sitio para una sola orden:** escríbelo primero, por ejemplo
  `migrate otro.local` o `set-admin-password otro.local Clave`. El sitio activo
  no cambia.
- **Buscar:** `atajos user` lista los comandos que contienen *user* y lo que
  ejecuta cada uno.
- **Confirmación:** los comandos que borran datos o cambian producción
  (`drop-site`, `reinstall`, `restore`, `uninstall-app`, `update`,
  `setup production`…) piden escribir el nombre del sitio, o `si`, antes de
  ejecutarse. Cualquier otra respuesta cancela.
- **Nombres ocupados:** `rm`, `find`, `install`, `init` y `pip` siguen siendo
  los programas del sistema. El comando de bench se escribe con `b` delante:
  `b find .`, `b pip list`. Para `mariadb` y `watch` se usan `fdb` y `fwatch`.

### Descargar apps de repositorios privados

`llaves` crea una llave SSH por cada cuenta o repositorio de GitHub, cada una
con su contraseña, y añade su bloque a `~/.ssh/config`:

```
Host github-izone-core
    HostName github.com
    User git
    IdentityFile ~/.ssh/id_ed25519_core
    IdentitiesOnly yes
```

Pega la llave pública que imprime en GitHub (*Settings → Deploy keys* del
repositorio) y descarga la app con el alias:

```bash
add-app github-izone-core:izone/mi_app version-15
install-app mi_app
```

---

## Otras opciones del script

Todas se ejecutan como root (`sudo -i` y luego `bash frappe-setup.sh …`):

| Opción | Para qué |
|---|---|
| *(sin opciones)* | Menú: instalar, diagnosticar, reparar, desinstalar o atajos |
| `--status` | Muestra los pasos de la instalación ya completados |
| `--attach` | Vuelve a la consola de una instalación en curso |
| `--reparar` | El sitio no vuelve tras reiniciar el servidor: habilita los servicios y el arranque. No reinstala nada. |
| `--diag` | Empaqueta los logs en un `.tar.gz` para compartir, con las contraseñas ocultas |
| `--atajos` | Instala o actualiza los atajos de bench |
| `--reset` | Olvida el progreso guardado. No desinstala nada. |
| `--python-version X.Y` | Fuerza una versión de Python |
| `--help` | Ayuda |

**Desinstalar** todo lo que instaló el script: `bash frappe-setup.sh`, opción
**4) Desinstalar**, y escribe `DESINSTALAR` para confirmar. SSH vuelve al puerto
22. El usuario operativo y su carpeta sólo se borran si lo confirmas aparte.

---

## Si algo falla

| Problema | Qué hacer |
|---|---|
| Se cortó la conexión durante la instalación | Entra de nuevo y ejecuta `bash frappe-setup.sh --attach` |
| La instalación se detuvo con un error | Lanza el mismo comando otra vez: continúa desde el paso que falló |
| El sitio no responde tras reiniciar el servidor | `bash frappe-setup.sh --reparar` |
| No puedo entrar por SSH después de instalar | Usa el puerto nuevo (`ssh -p <puerto>`), el usuario operativo y tu llave. `root` ya no entra por SSH. |
| `migrate: command not found` | Los atajos no están cargados: entra como el usuario operativo y ejecuta `source ~/.bashrc`. Si sigue igual, ejecuta como root `bash frappe-setup.sh --atajos`. |
| Necesito ayuda con un error | `bash frappe-setup.sh --diag` y comparte el `.tar.gz` que genera en `/root` |

El log completo de la instalación está en `/var/log/bashcore-frappe16.log`.
