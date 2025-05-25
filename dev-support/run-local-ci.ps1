<#
1. Make sure to create a workspace directory at the root of the drive,
   like - D:\workspace. Otherwise, the build would fail owing to long
   paths limitation.
2. Please install all the necessary build dependencies and tools to your
   host Windows environment before running this. You may refer to
   <Hadoop-repo-root>\dev-support\docker\Dockerfile_windows_10
   and run the commands as per the steps specified in that file against
   your host Windows environment to setup the necessary build dependencies
   and tools for building Hadoop on Windows.
3. This script runs the full CI suite (as it would do on Jenkins) and the
   output will be located at D:\workspace\out.

Sample command invocation -
PS D:\projects\github\apache\hadoop> .\dev-support\run-local-ci.ps1 `
    -Workspace D:\workspace `
    -HadoopRepoUrl 'https://github.com/GauthamBanasandra/hadoop.git' `
    -HadoopRepoBranch 'disable-xmllint'
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory)]
    [string]
    $Workspace,

    # The URL of the Hadoop repository to checkout
    [Parameter(Mandatory = $False)]
    [string]
    $HadoopRepoUrl = 'https://github.com/apache/hadoop.git',

    # The branch of the Hadoop repository to checkout
    [Parameter(Mandatory = $False)]
    [string]
    $HadoopRepoBranch = 'trunk',

    # The URL of the Yetus repository to checkout
    [Parameter(Mandatory = $False)]
    [string]
    $YetusRepoUrl = 'https://github.com/apache/yetus.git',

    # The branch of the Yetus repository to checkout
    [Parameter(Mandatory = $False)]
    [string]
    $YetusRepoBranch = 'rel/0.14.0',
    
    # The source dir
    [Parameter(Mandatory = $False)]
    [string]
    $SourceDir = "$Workspace/hadoop",

    # The patch dir
    [Parameter(Mandatory = $False)]
    [string]
    $PatchDir = "$Workspace/out",

    # The Docker file
    [Parameter(Mandatory = $False)]
    [string]
    $DockerFile = "$SourceDir/dev-support/docker/Dockerfile_windows_10",

    # Bash
    [Parameter(Mandatory = $False)]
    [string]
    $BashExePath = 'C:\PROGRA~1\Git\bin\bash.exe'
)

function Get-LinuxPath {
    param (
        [string]
        $WindowsPath
    )
    
    # Convert to Linux path
    $linuxPath = $windowsPath -replace '\\', '/'

    $linuxPath = $linuxPath -replace '^([A-Za-z]):', '/$1' -replace '^([A-Za-z])', { $_.Value.ToLower() }

    # Output the Linux path
    $linuxPath
}

$startLocation = (Get-Location).Path

$Env:WORKSPACE = $Workspace
$Env:YETUS = 'yetus'
$Env:YETUS_VERSION = $YetusRepoBranch
$Env:SOURCEDIR = $SourceDir
$Env:PATCHDIR = $PatchDir
$Env:DOCKERFILE = $DockerFile
$Env:DOCKER_BUILDKIT = 0
$Env:IS_OPTIONAL = 0
$Env:IS_NIGHTLY_BUILD = 1
$Env:IS_WINDOWS = 1
$Env:BASH_EXECUTABLE = $BashExePath
$Env:VCPKG_INSTALLED_PACKAGES = 'D:\projects\github\microsoft\vcpkg\installed\x64-windows'
$Env:CMAKE_TOOLCHAIN_FILE = 'D:\projects\github\microsoft\vcpkg\scripts\buildsystems\vcpkg.cmake'

$yetusCheckoutDir = Join-Path `
    -Path $Workspace `
    -ChildPath $Env:YETUS
if (-not (Test-Path -Path $yetusCheckoutDir)) {
    Set-Location -Path $Workspace
    git clone $YetusRepoUrl
    Set-Location -Path $yetusCheckoutDir
    git checkout $YetusRepoBranch
}

if (-not (Test-Path -Path $SourceDir)) {
    Set-Location -Path $Workspace    
    git clone $HadoopRepoUrl
    Set-Location -Path $SourceDir
    git checkout $HadoopRepoBranch
}

Set-Location -Path $Workspace

. $BashExePath -c "$(Get-LinuxPath -WindowsPath $SourceDir\dev-support\jenkins.sh) run_ci"

Set-Location -Path $startLocation