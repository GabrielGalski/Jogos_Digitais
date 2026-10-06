$ErrorActionPreference = 'Stop'
$updaterRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$updaterCompiler = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
if (-not (Test-Path -LiteralPath $updaterCompiler -PathType Leaf)) {
    $updaterCompiler = Join-Path $env:WINDIR 'Microsoft.NET\Framework\v4.0.30319\csc.exe'
}
if (-not (Test-Path -LiteralPath $updaterCompiler -PathType Leaf)) { throw 'Compilador .NET Framework não encontrado' }
$updaterOutput = Join-Path $updaterRoot 'AtualizarLDtk.exe'
$updaterSource = Join-Path $PSScriptRoot 'AtualizarLDtk.cs'
& $updaterCompiler /nologo /target:winexe /optimize+ /platform:anycpu /warnaserror+ /reference:System.Drawing.dll /reference:System.Web.Extensions.dll /reference:System.Windows.Forms.dll "/out:$updaterOutput" $updaterSource
if ($LASTEXITCODE -ne 0) { throw 'Falha ao compilar AtualizarLDtk.exe' }
Get-Item -LiteralPath $updaterOutput | Select-Object FullName, Length, LastWriteTime
