@ECHO OFF
@REM Licensed to the Apache Software Foundation (ASF) under one or more
@REM contributor license agreements.  See the NOTICE file distributed with
@REM this work for additional information regarding copyright ownership.
@REM The ASF licenses this file to You under the Apache License, Version 2.0
@REM (the "License"); you may not use this file except in compliance with
@REM the License.  You may obtain a copy of the License at
@REM
@REM     http://www.apache.org/licenses/LICENSE-2.0
@REM
@REM Unless required by applicable law or agreed to in writing, software
@REM distributed under the License is distributed on an "AS IS" BASIS,
@REM WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
@REM See the License for the specific language governing permissions and
@REM limitations under the License.

@REM Builds Hadoop with native Windows support inside the Windows build image
@REM (dev-support/docker/Dockerfile_windows_10) and runs the native smoke test.
@REM CI runs it, and the same command reproduces a CI run locally:
@REM
@REM   docker run --rm -v <checkout>:C:\src:ro
@REM     -v <maven repository>:C:\Users\HadoopBuilder\.m2\repository
@REM     -v <output directory>:C:\out
@REM     <image> /c C:\src\dev-support\bin\win-ci-build.cmd
@REM
@REM The sources are copied to C:\h first, so the checkout stays read-only.
@REM Binaries, test reports and native build logs are copied to C:\out after
@REM the build, after the smoke test and at the end, so a run that is killed
@REM part-way still leaves what it had finished.
@REM
@REM Set WIN_CI_PHASE1B=1 to also run the Windows-specific Java tests, one
@REM Maven run per module. Each Maven exit code goes to
@REM C:\out\phase1b-<module>-rc.txt and does not change the exit code here.
@REM
@REM Exit codes: 0 success, 10 build failed, 20 smoke test failed,
@REM 90-93 environment problem.

SETLOCAL EnableExtensions DisableDelayedExpansion

@REM The prefix keeps these out of the build tools: CMake takes RC from the
@REM environment as the resource compiler, and MSBuild turns every
@REM environment variable into a property.

SET "WIN_CI_SRC=C:\src"
SET "WIN_CI_WORK=C:\h"
SET "WIN_CI_OUT=C:\out"
SET "WIN_CI_RC=0"
SET "WIN_CI_VCVARS=%ProgramFiles(x86)%\Microsoft Visual Studio\2019\BuildTools\VC\Auxiliary\Build\vcvars64.bat"

CALL :log Checking the environment
@REM The image's entry point already runs vcvars64.bat; repeating it would
@REM grow PATH past the command line limit.
IF NOT DEFINED VCINSTALLDIR CALL "%WIN_CI_VCVARS%"
> "%WIN_CI_OUT%\path.txt" ECHO %PATH%
IF /I NOT "%Platform%"=="x64" (
  ECHO ERROR: Platform is "%Platform%" instead of x64.
  SET "WIN_CI_RC=90"
  GOTO :end
)
FOR %%T IN (msbuild cmake ctest java mvn bash) DO (
  WHERE %%T >NUL 2>&1 || (
    ECHO ERROR: %%T is not on PATH.
    SET "WIN_CI_RC=91"
    GOTO :end
  )
)
CALL java -version
CALL mvn --version
CALL cmake --version

CALL :log Copying %WIN_CI_SRC% to %WIN_CI_WORK%
robocopy "%WIN_CI_SRC%" "%WIN_CI_WORK%" /E /MT:8 /R:1 /W:1 /NFL /NDL /NP /NJH
@REM robocopy exit codes below 8 mean success.
IF ERRORLEVEL 8 (
  ECHO ERROR: robocopy failed.
  SET "WIN_CI_RC=92"
  GOTO :end
)
CD /D "%WIN_CI_WORK%" || (SET "WIN_CI_RC=93" & GOTO :end)

@REM Not MAVEN_ARGS: Maven 3.9 reads that variable itself, so the arguments
@REM would be passed twice.
SET "HADOOP_MVN_ARGS=--batch-mode --no-transfer-progress -Pnative-win -Duse.platformToolsetVersion=v142 -Drequire.openssl -Drequire.test.libhadoop -Dshell-executable=C:\Git\bin\bash.exe -Dopenssl.prefix=C:\vcpkg\installed\x64-windows -Dwindows.cmake.prefix.path=C:\vcpkg\installed\x64-windows -Dwindows.cmake.toolchain.file=C:\vcpkg\scripts\buildsystems\vcpkg.cmake -Dwindows.cmake.build.type=RelWithDebInfo -Dwindows.build.hdfspp.dll=off -Dwindows.no.sasl=on -Dmaven.test.failure.ignore=false"

CALL :log Building Hadoop
CALL mvn %HADOOP_MVN_ARGS% clean install -DskipTests -Pdist,yarn-ui -Dmaven.javadoc.skip=true
IF ERRORLEVEL 1 (
  SET "WIN_CI_RC=10"
  GOTO :end
)
CALL :collect

@REM Proves that hadoop.dll loads, not just that it was built. shelltest is
@REM off so that a bats driver failure is not reported as a smoke failure.
CALL :log Phase 1: TestHdfsNativeCodeLoader
CALL mvn %HADOOP_MVN_ARGS% test -P!shelltest -pl hadoop-hdfs-project/hadoop-hdfs -Dtest=TestHdfsNativeCodeLoader -Dsurefire.failIfNoSpecifiedTests=true
IF ERRORLEVEL 1 SET "WIN_CI_RC=20"
CALL :collect

IF "%WIN_CI_PHASE1B%"=="1" CALL :phase1b

:end
CALL :collect
CALL :log Done, exit code %WIN_CI_RC%
EXIT /B %WIN_CI_RC%

@REM One Maven run per module, so a failure in one module cannot skip the
@REM others.
@REM
@REM hadoop-common excludes the methods that fail on every Windows host,
@REM including Jenkins:
@REM   TestFileUtil#testUnZip: FileUtil.unZip calls setPosixFilePermissions,
@REM     which NTFS does not support (since HADOOP-18145).
@REM   TestFileUtil#testFailFullyDeleteDirSymlinks and #testSymlinkSameFile:
@REM     POSIX-only assumptions, unlike their guarded neighbours.
@REM   TestFileUtil#testGetDU: its tearDown cannot delete a 0000 directory,
@REM     because winutils chmod -R lists children before fixing the parent.
@REM   TestNativeIO#testFstat: the S_IF* constants are only set on Unix.
@REM   TestFsShellCopy#testPutSrcFileNoPerm: HADOOP-19599.
@REM CALL expands percent signs a second time, so %%%% reaches Maven as %.
:phase1b
CALL :log Phase 1b: hadoop-common
CALL mvn %HADOOP_MVN_ARGS% test -P!shelltest -pl hadoop-common-project/hadoop-common "-Dtest=TestWinUtils,TestNativeIO,TestNativeCrc32,TestShell,TestFileUtil,TestLocalFileSystem,TestPath,TestPathData,TestFsShellCopy,TestSymlinkLocalFSFileSystem,!%%%%regex[.*TestFileUtil.class#testUnZip|testFailFullyDeleteDirSymlinks|testSymlinkSameFile|testGetDU],!%%%%regex[.*TestNativeIO.class#testFstat],!%%%%regex[.*TestFsShellCopy.class#testPutSrcFileNoPerm]" -Dsurefire.failIfNoSpecifiedTests=false
> "%WIN_CI_OUT%\phase1b-hadoop-common-rc.txt" ECHO %ERRORLEVEL%
CALL :log Phase 1b: hadoop-hdfs
CALL mvn %HADOOP_MVN_ARGS% test -P!shelltest -pl hadoop-hdfs-project/hadoop-hdfs -Dtest=TestAtomicFileOutputStream -Dsurefire.failIfNoSpecifiedTests=false
> "%WIN_CI_OUT%\phase1b-hadoop-hdfs-rc.txt" ECHO %ERRORLEVEL%
CALL :log Phase 1b: hadoop-yarn-common
CALL mvn %HADOOP_MVN_ARGS% test -P!shelltest -pl hadoop-yarn-project/hadoop-yarn/hadoop-yarn-common -Dtest=TestWindowsBasedProcessTree -Dsurefire.failIfNoSpecifiedTests=false
> "%WIN_CI_OUT%\phase1b-hadoop-yarn-common-rc.txt" ECHO %ERRORLEVEL%
EXIT /B 0

:collect
IF NOT EXIST "%WIN_CI_WORK%" EXIT /B 0
CALL :log Collecting outputs
robocopy "%WIN_CI_WORK%" "%WIN_CI_OUT%\bin" winutils.exe hadoop.dll hdfs.dll /S /XD .git node_modules /R:0 /W:0 /NFL /NDL /NP /NJH >> "%WIN_CI_OUT%\collect.log"
CALL :log robocopy of the binaries exited with %ERRORLEVEL%
robocopy "%WIN_CI_WORK%" "%WIN_CI_OUT%\reports" TEST-*.xml *-output.txt *.dumpstream hs_err*.log CMakeError.log CMakeOutput.log CMakeConfigureLog.yaml /S /XD .git node_modules /R:0 /W:0 /NFL /NDL /NP /NJH >> "%WIN_CI_OUT%\collect.log"
CALL :log robocopy of the reports exited with %ERRORLEVEL%
EXIT /B 0

:log
ECHO [%DATE% %TIME%] %*
>> "%WIN_CI_OUT%\timeline.txt" ECHO [%DATE% %TIME%] %*
EXIT /B 0
