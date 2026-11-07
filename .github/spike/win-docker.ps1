# Licensed to the Apache Software Foundation (ASF) under one
# or more contributor license agreements.  See the NOTICE file
# distributed with this work for additional information
# regarding copyright ownership.  The ASF licenses this file
# to you under the Apache License, Version 2.0 (the
# "License"); you may not use this file except in compliance
# with the License.  You may obtain a copy of the License at
#
#   http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing,
# software distributed under the License is distributed on an
# "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
# KIND, either express or implied.  See the License for the
# specific language governing permissions and limitations
# under the License.

# SPIKE ONLY. Starts the Docker engine on a GitHub-hosted Windows runner.
#   -DataRoot C|D  rewrite daemon.json so the image store is on that drive,
#                  then restart the engine and check that it took effect.
#                  Moving it to D: hides the images pre-pulled on C:.
#   -Restart       restart the engine without changing its configuration.
# With neither, it only starts the engine if it is not running.
# The windowsfilter sandbox already defaults to 127 GB, so it is left alone.
# Writes DOCKER_ROOT_DIR, DOCKER_INITIAL_STATUS and DOCKER_READY_SECONDS to
# GITHUB_ENV when that is set. Later calls in the same job keep the first
# call's status and timing, and write DOCKER_RESTART_READY_SECONDS instead.

param(
    [string] $DataRoot = '',
    [switch] $Restart
)

$ErrorActionPreference = 'Stop'
if ($DataRoot -and $DataRoot -notin 'C', 'D') { throw "DataRoot must be C or D, not '$DataRoot'" }

function Set-JobEnv([string] $Name, [string] $Value) {
    if ($env:GITHUB_ENV) { "$Name=$Value" >> $env:GITHUB_ENV }
}

function Invoke-WithRetry([scriptblock] $Action, [string] $What) {
    for ($attempt = 1; $attempt -le 3; $attempt++) {
        try { & $Action; return } catch {
            Write-Host "::warning title=infra::$What failed (attempt $attempt): $_"
            Start-Sleep -Seconds 10
        }
    }
    Write-Host "::error title=infra::$What failed 3 times"
    exit 1
}

$service = Get-Service -Name docker -ErrorAction SilentlyContinue
if (-not $service) {
    Write-Host '::error title=infra::The Docker service is not installed on this runner'
    exit 1
}
$firstCall = -not $env:DOCKER_READY_SECONDS
if ($firstCall) { Set-JobEnv 'DOCKER_INITIAL_STATUS' $service.Status }

# A service that is still starting has already read the old daemon.json, so
# wait for it to settle before deciding whether to restart it.
for ($i = 0; $i -lt 36 -and $service.Status -in 'StartPending', 'StopPending'; $i++) {
    Start-Sleep -Seconds 5
    $service.Refresh()
}

$expectedRoot = $null
if ($DataRoot) {
    $configDir = 'C:\ProgramData\docker\config'
    $configFile = Join-Path $configDir 'daemon.json'
    New-Item -ItemType Directory -Force -Path $configDir | Out-Null
    $config = @{}
    if (Test-Path $configFile) {
        Write-Host "Existing ${configFile}:"
        Get-Content $configFile | Write-Host
        $existing = Get-Content -Raw $configFile | ConvertFrom-Json -AsHashtable
        if ($existing) { $config = $existing }
    }
    $config.Remove('data-root')
    $expectedRoot = 'C:\ProgramData\docker'
    if ($DataRoot -eq 'D') {
        if (Test-Path 'D:\') {
            $config['data-root'] = 'D:\docker'
            $expectedRoot = 'D:\docker'
        } else {
            Write-Host '::warning title=infra::No D: drive on this runner; keeping the default data-root'
        }
    }
    $config | ConvertTo-Json -Depth 5 | Set-Content -Path $configFile -Encoding ascii
    Write-Host "New ${configFile}:"
    Get-Content $configFile | Write-Host
    $Restart = $true
}

$service.Refresh()
if ($service.Status -eq 'Running') {
    if ($Restart) { Invoke-WithRetry { Restart-Service -Name docker -Force } 'Restarting Docker' }
} else {
    Invoke-WithRetry { Start-Service -Name docker } 'Starting Docker'
}

# runner-images#13729: the engine sometimes takes minutes to answer.
$sw = [Diagnostics.Stopwatch]::StartNew()
$ready = $false
while ($sw.Elapsed.TotalMinutes -lt 5) {
    docker version --format '{{.Server.Version}}' 2>$null | Out-Null
    if ($LASTEXITCODE -eq 0) { $ready = $true; break }
    Start-Sleep -Seconds 5
}
if (-not $ready) {
    Write-Host '::error title=infra::The Docker engine did not answer within 5 minutes'
    Get-Service -Name docker | Format-List | Out-String | Write-Host
    exit 1
}
$readyName = if ($firstCall) { 'DOCKER_READY_SECONDS' } else { 'DOCKER_RESTART_READY_SECONDS' }
Set-JobEnv $readyName ([math]::Round($sw.Elapsed.TotalSeconds))

$root = (docker info --format '{{.DockerRootDir}}').Trim()
Set-JobEnv 'DOCKER_ROOT_DIR' $root
if ($expectedRoot -and $root -ne $expectedRoot) {
    Write-Host "::error title=infra::Docker root is $root, expected $expectedRoot"
    exit 1
}
docker info
exit 0
