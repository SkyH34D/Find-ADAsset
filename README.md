# Find-ADAsset

![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B-blue.svg?logo=powershell)
![Active Directory](https://img.shields.io/badge/Active%20Directory-RSAT-0078D4.svg?logo=windows)
![License](https://img.shields.io/badge/License-MIT-green.svg)
![Purpose](https://img.shields.io/badge/Focus-DFIR%20%2F%20SOC-red.svg)

Herramienta ligera en PowerShell diseñada para acelerar el triage y la atribución de activos en investigaciones de ciberseguridad (SOC/DFIR). A partir de una IP IPv4 o un Hostname, resuelve el equipo asociado cruzando información de **DNS** y **Active Directory**.

---

## ⚡ Característica Clave: Flujo de Resolución

El script decide automáticamente la ruta de búsqueda más eficiente según el tipo de entrada:

```text
[ Entrada: IP / Hostname ]
       │
       ├──► Hostname ──► Búsqueda directa por SamAccountName en AD
       │
       └──► IPv4
             │
             ├── 1. Consulta DNS Inversa (PTR / A)
             │      └── Éxito ──► Búsqueda directa por DNSHostName en AD
             │
             └── 2. Fallback (Si DNS falla / inconsistente)
                    └── Búsqueda exhaustiva por atributo IPv4Address en AD
```

---

## 🛠️ Requisitos Previos

* **OS:** Windows con **Windows PowerShell 5.1** o superior.
* **Módulo RSAT ActiveDirectory:** Requiere `Get-ADComputer`.

Si el módulo no está disponible, instálalo desde una consola de PowerShell elevada:

```powershell
Add-WindowsCapability -Online -Name Rsat.ActiveDirectory.DS-LDS.Tools~~~~0.0.1.0
```

---

## 🚀 Uso y Ejemplos

### Búsqueda por dirección IPv4
```powershell
.\Find-ADAsset.ps1 192.168.100.131
```

### Búsqueda por Hostname
```powershell
.\Find-ADAsset.ps1 ESCORPION2
```

### Ejemplo de Salida (Objeto PSCustomObject)

```text
IPAddress              : 192.168.100.131
ComputerName           : ESCORPION2
DNSHostName            : EsCORpiON2.corp.local
OperatingSystem        : Windows 11 Pro
OperatingSystemVersion : 10.0 (26100)
LastLogonDate          : 12/10/2026 10:37:06
Description            : Workstation - IT Dept
DistinguishedName      : CN=ESCORPION2,OU=Workstations,DC=corp,DC=local
ResolutionSource       : Active Directory / IPv4Address
DNSAddresses           : {192.168.100.131}
```

---

## 📊 Integración en Pipeline (PowerShell Objects)

Al retornar objetos nativos y no texto plano, permite encadenar comandos fácilmente:

```powershell
# Filtrar campos específicos
.\Find-ADAsset.ps1 192.168.100.131 | Select-Object ComputerName, OperatingSystem, ResolutionSource

# Exportar a CSV para informes de incidentes
.\Find-ADAsset.ps1 192.168.100.131 | Export-Csv -Path .\incident_asset.csv -NoTypeInformation
```

---

## ⚠️ Consideraciones de Triage

* **`ResolutionSource`**: Indica exactamente de dónde proviene la atribución (`DNS -> Active Directory`, `Active Directory / IPv4Address` o `Active Directory / ComputerName`).
* **`LastLogonDate`**: Pertenece a la autenticación del *objeto de equipo* en el dominio, no al inicio de sesión interactivo de un usuario.
* **Trazabilidad DHCP**: Los atributos de AD reflejan el estado registrado actual; no sustituyen los logs históricos de asignación DHCP.

---

## 🗺️ Roadmap

- [x] Resolución vía DNS + Fallback AD por IP.
- [x] Búsqueda por Hostname.
- [ ] Consulta de usuario interactivo / logged-on actual (WMI/WinRM).
- [ ] Enriquecimiento con fuentes adicionales (Logs DHCP / FW / EDR).

## 🖌️ Nota del autor
*Pórtense bien 🙏*
