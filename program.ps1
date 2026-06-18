# FPGA write script
# Order: build_sw.ps1 -> build.ps1 -> program.ps1
#
# Uses ftdi_pgm.bat to write outflow/*.hex to T20 SPI Flash (Active Serial mode)
#
# Requirements:
#   - build.ps1 must be run first to generate the bitstream (.hex)
#   - T20 board connected via USB with Efinity USB driver installed
#   - Efinity IDE 2026.1 installed at C:\Efinity\2026.1\

$ErrorActionPreference = "Stop"

$ProjectDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $ProjectDir

$HexFile = Join-Path $ProjectDir "outflow\at24c512c_t20.hex"
$FtdiPgm = "C:\Efinity\2026.1\pgm\bin\ftdi_pgm.bat"

if (-not (Test-Path $HexFile)) {
    Write-Host "ERROR: HEX file not found: $HexFile"
    Write-Host "Please run build.ps1 first."
    exit 1
}

Write-Host "Programming: $HexFile"
& $FtdiPgm $HexFile -m active
