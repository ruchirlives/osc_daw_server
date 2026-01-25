<#
.SYNOPSIS
Builds the OSCDawServer installer with Inno Setup.

.DESCRIPTION
This script compiles the parent-level `OSCDawServer_packager.iss` Inno Setup script.
You can provide a custom Inno Setup compiler path; otherwise it probes the default installation
locations and the PATH in that order.

.PARAMETER InnoSetupPath
Path to the `ISCC.exe` compiler. Optional.
#>
param (
    [Parameter()]
    [string]$InnoSetupPath
)

function Resolve-InnoPath {
    param (
        [string]$Override
    )

    if ($Override) {
        if (-not (Test-Path $Override)) {
            throw "Provided Inno Setup path '$Override' does not exist."
        }

        return (Get-Item $Override).FullName
    }

    $candidates = @()
    if (${Env:ProgramFiles(x86)}) {
        $candidates += Join-Path ${Env:ProgramFiles(x86)} 'Inno Setup 6\ISCC.exe'
    }
    if (${Env:ProgramFiles}) {
        $candidates += Join-Path ${Env:ProgramFiles} 'Inno Setup 6\ISCC.exe'
    }

    foreach ($candidate in $candidates) {
        if (Test-Path $candidate) {
            return (Get-Item $candidate).FullName
        }
    }

    $command = Get-Command 'ISCC.exe' -ErrorAction SilentlyContinue
    if ($command) {
        return $command.Path
    }

    throw "Unable to locate 'ISCC.exe'. Install Inno Setup or use '-InnoSetupPath'."
}

try {
    $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
    $issCandidate = Join-Path $scriptDir '..\OSCDawServer_packager.iss'

    if (-not (Test-Path $issCandidate)) {
        throw "Expected Inno Setup script at ..\\OSCDawServer_packager.iss but it was missing."
    }

    $issPath = (Get-Item $issCandidate).FullName
    $compilerPath = Resolve-InnoPath -Override $InnoSetupPath

    Write-Host "Using Inno Setup compiler: $compilerPath" -ForegroundColor Cyan
    Write-Host "Compiling: $issPath" -ForegroundColor Cyan

    & $compilerPath $issPath
    $exitCode = $LASTEXITCODE

    if ($exitCode -ne 0) {
        throw "ISCC.exe exited with code $exitCode."
    }

    Write-Host 'Installer build complete.' -ForegroundColor Green
} catch {
    Write-Error $_.Exception.Message
    exit 1
}
