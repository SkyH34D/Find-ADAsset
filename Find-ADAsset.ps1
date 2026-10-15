#requires -Version 5.1

[CmdletBinding()]
param (
    [Parameter(
        Mandatory = $true,
        Position = 0,
        HelpMessage = 'Direccion IPv4 o nombre del equipo'
    )]
    [ValidateNotNullOrEmpty()]
    [Alias('IP', 'ComputerName')]
    [string]$Identity
)

# ---------------------------------------------------------------------
# COMPROBACION DEL MODULO ACTIVE DIRECTORY
# ---------------------------------------------------------------------

$activeDirectoryModule = Get-Module -ListAvailable -Name ActiveDirectory

if (-not $activeDirectoryModule) {
    Write-Error "No se encuentra instalado el modulo ActiveDirectory."

    Write-Information (
        "Para instalarlo en Windows 10 u 11, abre Windows PowerShell " +
        "como administrador y ejecuta:"
    ) -InformationAction Continue

    Write-Information (
        "Add-WindowsCapability -Online " +
        "-Name Rsat.ActiveDirectory.DS-LDS.Tools~~~~0.0.1.0"
    ) -InformationAction Continue

    return
}

try {
    Import-Module ActiveDirectory -ErrorAction Stop
}
catch {
    Write-Error (
        "El modulo ActiveDirectory esta instalado, pero no se ha podido cargar. " +
        "Detalle: $($_.Exception.Message)"
    )

    return
}

if (-not (Get-Command -Name Get-ADComputer -ErrorAction SilentlyContinue)) {
    Write-Error (
        "El modulo ActiveDirectory se ha cargado, pero Get-ADComputer " +
        "no esta disponible."
    )

    return
}

$adParameters = @{
    Properties = @(
        'IPv4Address'
        'DNSHostName'
        'OperatingSystem'
        'OperatingSystemVersion'
        'LastLogonDate'
        'Description'
    )
    ErrorAction = 'Stop'
}

$computers = @()
$dnsResult = $null
$dnsAddresses = @()
$resolutionSource = $null

$identityValue = $Identity.Trim()
$parsedAddress = $null
$isIPv4 = $false

# ---------------------------------------------------------------------
# CLASIFICACION DE LA ENTRADA
# ---------------------------------------------------------------------

$canonicalIPv4Pattern = '^((0|[1-9][0-9]{0,2})[.]){3}(0|[1-9][0-9]{0,2})$'
$looksLikeIPv4 = $identityValue -match '^[0-9.]+$'

if ($identityValue -match $canonicalIPv4Pattern) {
    $parseSucceeded = [System.Net.IPAddress]::TryParse(
        $identityValue,
        [ref]$parsedAddress
    )

    if (
        $parseSucceeded -and
        $parsedAddress.AddressFamily -eq
            [System.Net.Sockets.AddressFamily]::InterNetwork
    ) {
        $isIPv4 = $true
    }
    else {
        throw "'$identityValue' no es una direccion IPv4 valida."
    }
}
elseif ($looksLikeIPv4) {
    throw "'$identityValue' parece una direccion IPv4, pero no es valida."
}

# ---------------------------------------------------------------------
# BUSQUEDA POR NOMBRE DE EQUIPO
# ---------------------------------------------------------------------

if (-not $isIPv4) {
    $normalizedComputerName = $identityValue.TrimEnd('$')
    $samAccountName = $normalizedComputerName + '$'

    Write-Information (
        "Buscando el equipo '$normalizedComputerName' directamente " +
        "en Active Directory..."
    ) -InformationAction Continue

    try {
        $computers = @(
            Get-ADComputer @adParameters -Identity $samAccountName
        )

        if ($computers.Count -gt 0) {
            $resolutionSource = 'Active Directory / ComputerName'

            Write-Information (
                "Activo localizado directamente en Active Directory."
            ) -InformationAction Continue
        }
    }
    catch [Microsoft.ActiveDirectory.Management.ADIdentityNotFoundException] {
        Write-Warning (
            "No se encontro ningun equipo llamado " +
            "'$normalizedComputerName' en Active Directory."
        )

        return
    }
}

# ---------------------------------------------------------------------
# BUSQUEDA POR DIRECCION IPv4
# ---------------------------------------------------------------------

if ($isIPv4) {
    $IP = $identityValue

    Write-Information (
        "Consultando DNS para $IP..."
    ) -InformationAction Continue

    try {
        $dnsResult = [System.Net.Dns]::GetHostEntry($IP)

        $dnsAddresses = @(
            $dnsResult.AddressList |
                ForEach-Object {
                    $_.IPAddressToString
                }
        )

        Write-Information (
            "DNS ha devuelto el nombre '$($dnsResult.HostName)'."
        ) -InformationAction Continue
    }
    catch {
        Write-Warning (
            "La consulta DNS ha producido un error: " +
            "$($_.Exception.Message)"
        )

        Write-Information (
            "Se continuara con la busqueda en Active Directory."
        ) -InformationAction Continue
    }

    # -----------------------------------------------------------------
    # BUSQUEDA DIRECTA EN AD UTILIZANDO EL NOMBRE DEVUELTO POR DNS
    # -----------------------------------------------------------------

    if ($dnsResult -and $dnsResult.HostName) {
        if ($dnsAddresses -contains $IP) {
            $dnsName = $dnsResult.HostName.TrimEnd('.')

            Write-Information (
                "Buscando '$dnsName' directamente en Active Directory..."
            ) -InformationAction Continue

            $computers = @(
                Get-ADComputer @adParameters -Filter {
                    DNSHostName -eq $dnsName
                }
            )

            if ($computers.Count -gt 0) {
                $resolutionSource = 'DNS -> Active Directory'

                Write-Information (
                    "Activo localizado mediante DNS y Active Directory."
                ) -InformationAction Continue
            }
            else {
                Write-Information (
                    "El nombre obtenido por DNS no aparece en Active Directory. " +
                    "Se iniciara la busqueda exhaustiva."
                ) -InformationAction Continue
            }
        }
        else {
            Write-Information (
                "DNS ha devuelto un nombre, pero la respuesta no contiene " +
                "la IP investigada. Se iniciara la busqueda exhaustiva."
            ) -InformationAction Continue
        }
    }

    # -----------------------------------------------------------------
    # FALLBACK POR IPv4Address
    # -----------------------------------------------------------------

    if ($computers.Count -eq 0) {
        Write-Information (
            "Iniciando busqueda exhaustiva por IPv4Address. " +
            "Esta operacion puede tardar..."
        ) -InformationAction Continue

        Write-Progress @{
            Id = 1
            Activity = 'Buscando activo en Active Directory'
            Status = 'Enumerando equipos y comparando IPv4Address'
        }

        try {
            $computers = @(
                Get-ADComputer @adParameters -Filter * |
                    Where-Object {
                        $_.IPv4Address -eq $IP
                    }
            )
        }
        finally {
            Write-Progress @{
                Id = 1
                Activity = 'Buscando activo en Active Directory'
                Completed = $true
            }
        }

        if ($computers.Count -gt 0) {
            $resolutionSource = 'Active Directory / IPv4Address'

            Write-Information (
                "Busqueda exhaustiva pletada: se encontraron " +
                "$($computers.Count) coincidencias."
            ) -InformationAction Continue
        }
        else {
            Write-Information (
                "Busqueda exhaustiva completada sin coincidencias."
            ) -InformationAction Continue
        }
    }
}

# ---------------------------------------------------------------------
# RESULTADO
# ---------------------------------------------------------------------

if ($computers.Count -eq 0) {
    Write-Warning (
        "No se encontraron coincidencias para '$identityValue' " +
        "con los mecanismos consultados."
    )

    return
}

if ($computers.Count -gt 1) {
    Write-Warning (
        "Se encontraron $($computers.Count) objetos de equipo. " +
        "La atribucion es ambigua."
    )
}

foreach ($computer in $computers) {
    [PSCustomObject]@{
        IPAddress              = $computer.IPv4Address
        ComputerName           = $computer.Name
        DNSHostName            = $computer.DNSHostName
        OperatingSystem        = $computer.OperatingSystem
        OperatingSystemVersion = $computer.OperatingSystemVersion
        LastLogonDate          = $computer.LastLogonDate
        Description            = $computer.Description
        DistinguishedName      = $computer.DistinguishedName
        ResolutionSource       = $resolutionSource
        DNSAddresses           = $dnsAddresses
    }
}