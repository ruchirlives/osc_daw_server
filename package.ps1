<#
.SYNOPSIS
Builds the OSCDawServer installer with Inno Setup.

.DESCRIPTION
This script compiles the parent-level `OSCDawServer_packager.iss` Inno Setup script.
You can provide a custom Inno Setup compiler path; otherwise it probes the default installation
locations and the PATH in that order.

.PARAMETER InnoSetupPath
Path to the `ISCC.exe` compiler. Optional.

.PARAMETER MSBuildPath
Path to `MSBuild.exe`. Optional.

.PARAMETER SkipBuild
Compile the installer from the existing Release binaries without rebuilding first.
#>
param (
    [Parameter()]
    [string]$InnoSetupPath,

    [Parameter()]
    [string]$MSBuildPath,

    [Parameter()]
    [switch]$SkipBuild
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

function Resolve-MSBuildPath {
    param (
        [string]$Override
    )

    if ($Override) {
        if (-not (Test-Path $Override)) {
            throw "Provided MSBuild path '$Override' does not exist."
        }

        return (Get-Item $Override).FullName
    }

    $vsWhere = Join-Path ${Env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
    if (Test-Path $vsWhere) {
        $installationPath = & $vsWhere -latest -products * -requires Microsoft.Component.MSBuild -property installationPath
        if ($installationPath) {
            $candidate = Join-Path $installationPath 'MSBuild\Current\Bin\MSBuild.exe'
            if (Test-Path $candidate) {
                return (Get-Item $candidate).FullName
            }
        }
    }

    $command = Get-Command 'MSBuild.exe' -ErrorAction SilentlyContinue
    if ($command) {
        return $command.Path
    }

    throw "Unable to locate 'MSBuild.exe'. Install Visual Studio Build Tools, use '-MSBuildPath', or use '-SkipBuild'."
}

function Invoke-ReleaseBuild {
    param (
        [string]$MSBuildExe,
        [string]$SolutionPath,
        [string]$Target = 'Build'
    )

    Write-Host "Building: $SolutionPath" -ForegroundColor Cyan

    & $MSBuildExe $SolutionPath `
        /t:$Target `
        /p:Configuration=Release `
        /p:Platform=x64 `
        /m

    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0) {
        throw "MSBuild.exe exited with code $exitCode while building '$SolutionPath'."
    }
}

function Normalize-Version {
    param (
        [string]$Version
    )

    if (-not $Version) {
        return ''
    }

    $parts = $Version.Split('.') | ForEach-Object { [int]$_ }
    while ($parts.Count -gt 1 -and $parts[$parts.Count - 1] -eq 0) {
        $parts = $parts[0..($parts.Count - 2)]
    }

    return ($parts -join '.')
}

function Assert-PackagedVersion {
    param (
        [string]$JucerPath,
        [string]$ExePath
    )

    if (-not (Test-Path $ExePath)) {
        throw "Expected Release executable at '$ExePath' but it was missing."
    }

    [xml]$jucer = Get-Content -Path $JucerPath
    $expectedVersion = Normalize-Version -Version $jucer.JUCERPROJECT.version
    $actualVersion = Normalize-Version -Version (Get-Item $ExePath).VersionInfo.ProductVersion

    if ($expectedVersion -and $actualVersion -and $expectedVersion -ne $actualVersion) {
        throw "The installer would package version $actualVersion, but '$JucerPath' is version $expectedVersion. Rebuild the Release app or use the matching project version."
    }
}

try {
    $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
    $serverSolution = Join-Path $scriptDir 'Builds\VisualStudio2022\OSCDawServer.sln'
    $clientSolution = Join-Path $scriptDir '..\OSC_Client\Builds\VisualStudio2022\OSC_Client.sln'
    $jucerPath = Join-Path $scriptDir 'OSCDawServer.jucer'
    $releaseExe = Join-Path $scriptDir 'Builds\VisualStudio2022\x64\Release\App\DAWSERVER.exe'
    $issCandidate = Join-Path $scriptDir '..\OSCDawServer_packager.iss'

    if (-not (Test-Path $issCandidate)) {
        throw "Expected Inno Setup script at ..\\OSCDawServer_packager.iss but it was missing."
    }

    if (-not $SkipBuild) {
        $resolvedMSBuildPath = Resolve-MSBuildPath -Override $MSBuildPath
        Write-Host "Using MSBuild: $resolvedMSBuildPath" -ForegroundColor Cyan
        Invoke-ReleaseBuild -MSBuildExe $resolvedMSBuildPath -SolutionPath $serverSolution
        Invoke-ReleaseBuild -MSBuildExe $resolvedMSBuildPath -SolutionPath $clientSolution
    }

    Assert-PackagedVersion -JucerPath $jucerPath -ExePath $releaseExe

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
