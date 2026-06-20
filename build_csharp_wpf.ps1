param(
    [string]$Output = "dist\AT24C512C_GUI_CSharp.exe"
)

$ErrorActionPreference = "Stop"

$csc = Join-Path $env:WINDIR "Microsoft.NET\Framework64\v4.0.30319\csc.exe"
$framework = Join-Path $env:WINDIR "Microsoft.NET\Framework64\v4.0.30319"
$wpf = Join-Path $framework "WPF"

if (-not (Test-Path $csc)) {
    throw "C# compiler not found: $csc"
}

New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Output) | Out-Null

& $csc /nologo /target:winexe /platform:x64 /optimize+ `
    /out:$Output `
    csharp_wpf\AT24C512C_GUI.cs `
    /reference:"$wpf\PresentationCore.dll" `
    /reference:"$wpf\PresentationFramework.dll" `
    /reference:"$wpf\WindowsBase.dll" `
    /reference:"$framework\System.Xaml.dll"

if ($LASTEXITCODE -ne 0) {
    throw "C# build failed with exit code $LASTEXITCODE"
}

Write-Host "Built $Output"
