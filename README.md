# frappe-scripts

Scripts de aprovisionamiento para infraestructura Frappe.

## install_frappe16.sh

Aprovisionador automatizado de **Frappe 16 / ERPNext** sobre **Ubuntu 24.04 LTS**,
con hardening de seguridad según el benchmark CIS.

### Uso

En un servidor Ubuntu 24.04 recién instalado, ejecutar como root:

```bash
wget -qO install_frappe16.sh https://github.com/izone-ni/frappe-scripts/releases/latest/download/install_frappe16.sh && sudo bash install_frappe16.sh
```

El script pedirá al inicio los datos de configuración (usuario, puerto SSH,
contraseñas, llave SSH, nombre del sitio). A partir de ahí, corre de forma
totalmente automatizada.

### Qué instala y configura

- **Base de datos:** MariaDB 11.8.8 con hardening CIS
- **Runtime:** Node.js 24, Python 3.14, Redis
- **Framework:** Frappe 16 (bench)
- **Aplicaciones:** ERPNext, HRMS, Lending (Versión 16)
- **Servidor web:** Nginx + Supervisor (modo producción)

### Hardening de seguridad aplicado

- Autenticación SSH solo por llave (sin contraseñas)
- Puerto SSH personalizado (default 44004)
- Bloqueo de login de root
- Firewall UFW (solo SSH, HTTP y HTTPS)
- Banners de acceso restringido
- Archivo swap automático si la RAM es menor a 8 GB

### Requisitos

- Ubuntu 24.04 LTS (Server o Desktop)
- Acceso root
- Conexión a internet durante la instalación
- Una llave pública SSH del operador

### Notas

- El script se ejecuta en dos fases (configuración como root, luego instalación
  como usuario operativo) de forma automática.
- Al finalizar muestra un reporte de auditoría del estado de todos los servicios.
- Duración estimada: +10 minutos según la velocidad de la red.
