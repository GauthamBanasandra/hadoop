# Licensed to the Apache Software Foundation (ASF) under one
# or more contributor license agreements.  See the NOTICE file
# distributed with this work for additional information
# regarding copyright ownership.  The ASF licenses this file
# to you under the Apache License, Version 2.0 (the
# "License"); you may not use this file except in compliance
# with the License.  You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# The code lines below are derived from -
# https://github.com/docker-library/python/blob/105d6f34e7d70aad6f8c3e249b8208efa591916a/3.11/windows/windowsservercore-ltsc2022/Dockerfile
# See install-python.ps1 for why this is set here.
$ErrorActionPreference = 'Stop'

Write-Host ('Downloading get-pip.py ({0}) ...' -f $Env:PYTHON_GET_PIP_URL)
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Invoke-WebRequest -Uri $Env:PYTHON_GET_PIP_URL -OutFile 'get-pip.py'
Write-Host ('Verifying sha256 ({0}) ...' -f $Env:PYTHON_GET_PIP_SHA256)
if ((Get-FileHash 'get-pip.py' -Algorithm sha256).Hash -ne $Env:PYTHON_GET_PIP_SHA256) {
    Write-Host 'FAILED!'
    exit 1
}

$Env:PYTHONDONTWRITEBYTECODE = '1'

Write-Host ('Installing pip=={0} ...' -f $Env:PYTHON_PIP_VERSION)
python get-pip.py `
    --disable-pip-version-check `
    --no-cache-dir `
    --no-compile `
    --no-wheel `
('pip=={0}' -f $Env:PYTHON_PIP_VERSION) `
('setuptools=={0}' -f $Env:PYTHON_SETUPTOOLS_VERSION)
if ($LASTEXITCODE -ne 0) {
    Write-Host 'FAILED!'
    exit 1
}

Remove-Item get-pip.py -Force

Write-Host 'Verifying pip install ...'
$pipVersion = pip --version
Write-Host $pipVersion
if ($pipVersion -notlike ('pip {0} *' -f $Env:PYTHON_PIP_VERSION)) {
    Write-Host 'FAILED!'
    exit 1
}

Write-Host 'Complete.'
