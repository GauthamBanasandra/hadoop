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
    $BashExePath = 'C:\PROGRA~1\Git\bin\bash.exe',

    # The path to the Maven repository
    [Parameter(Mandatory = $False)]
    [string]
    $MavenRepoPath = "$Env:USERPROFILE\.m2",

    # Use Docker for the build
    [Parameter(Mandatory = $False)]
    [switch]
    $UseDocker
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

if ($UseDocker) {
    if (-not (Test-Path -Path $PatchDir)) {
        mkdir $PatchDir
    }

    docker build --label org.apache.yetus="" `
        --label org.apache.yetus.testpatch.project=hadoop `
        --tag hadoop-windows-10-builder `
        -f $DockerFile $SourceDir\dev-support\docker

    Write-Host 'Running the Docker container to execute the CI build...'

    # Log all variables used in the docker run command
    Write-Host "Docker run variables:"
    Write-Host "  Workspace: $Workspace"
    Write-Host "  MavenRepoPath: $MavenRepoPath"
    Write-Host "  Env:YETUS: $($Env:YETUS)"
    Write-Host "  HadoopRepoBranch: $HadoopRepoBranch"
    Write-Host "  Env:IS_NIGHTLY_BUILD: $($Env:IS_NIGHTLY_BUILD)"
    Write-Host "  Env:IS_WINDOWS: $($Env:IS_WINDOWS)"
    Write-Host "  Env:USERPROFILE: $($Env:USERPROFILE)"

    docker run --rm -v $Workspace\out:C:\out `
        -v $Workspace\hadoop:C:\src `
        -v $Workspace\yetus:C:\yetus `
        -v $MavenRepoPath`:$Env:USERPROFILE\.m2 `
        -e WORKSPACE=/c -e YETUS=$Env:YETUS `
        -e GIT_COMMIT=HEAD `
        -e GIT_BRANCH=$HadoopRepoBranch `
        -e IS_OPTIONAL=0 -e SOURCEDIR=/c/hadoop -e PATCHDIR=/c/out `
        -e IS_NIGHTLY_BUILD=$Env:IS_NIGHTLY_BUILD -e IS_WINDOWS=$Env:IS_WINDOWS `
        -e BASH_EXECUTABLE=/c/Git/bin/bash.exe `
        -e VCPKG_INSTALLED_PACKAGES=/c/vcpkg/installed/x64-windows `
        -e CMAKE_TOOLCHAIN_FILE=/c/vcpkg/scripts/buildsystems/vcpkg.cmake `
        hadoop-windows-10-builder '/c' 'xcopy' '/s' '/e' '/h' '/y' '/i' '/q' 'C:\src' 'C:\hadoop' '&&' 'C:\Git\bin\bash.exe' '-c' '"echo hello"' # '"/c/src/dev-support/jenkins.sh" "run_ci"'
}
else {
    $Env:BASH_EXECUTABLE = $BashExePath
    $Env:VCPKG_INSTALLED_PACKAGES = 'D:\projects\github\microsoft\vcpkg\installed\x64-windows'
    $Env:CMAKE_TOOLCHAIN_FILE = 'D:\projects\github\microsoft\vcpkg\scripts\buildsystems\vcpkg.cmake'

    Set-Location -Path $Workspace

    . $BashExePath -c "$(Get-LinuxPath -WindowsPath $SourceDir\dev-support\jenkins.sh) run_ci"
}


Set-Location -Path $startLocation