# Frappe-setup
**Scripts de aprovisionamiento universal para infraestructura Frappe.**

![Frappe Versions](https://img.shields.io/badge/Frappe-v13%20|%20v14%20|%20v15%20|%20v16-blue?style=for-the-badge&logo=frappe)
![OS Compatibility](https://img.shields.io/badge/Ubuntu-18.04%20|%2024.04%20|%2026.04-E95420?style=for-the-badge&logo=ubuntu)
![Bash](https://img.shields.io/badge/Script-Bash-4EAA25?style=for-the-badge&logo=gnu-bash)
![License](https://img.shields.io/badge/License-MIT-yellow?style=for-the-badge)

**Frappe-setup** es un aprovisionador automatizado escrito en Bash que te permite instalar, configurar y desplegar cualquier versión del framework Frappe (desde la versión 13 hasta la 16) de forma interactiva y segura. 

Destaca por su compatibilidad nativa para instalar **Frappe 16 sobre Ubuntu 26.04 LTS**, aplicando desde el primer momento un endurecimiento de seguridad (hardening) basado en los estándares CIS.

---

## Uso Rápido

En un servidor Ubuntu recién instalado, accede como `root` y ejecuta el script principal. Puedes descargar y lanzar el instalador en un solo paso:

```bash
wget -qO frappe-setup.sh https://github.com/izone-ni/frappe-scripts/releases/latest/download/frappe-setup.sh && sudo bash frappe-setup.sh
