# FPGA build script (synthesis / P&R / bitstream generation)
# Order: build_sw.ps1 -> build.ps1 -> program.ps1
#
# Calls efx_run.bat which internally runs setup.bat to configure
# the Efinity Python environment correctly.
#
# Requirements:
#   - build_sw.ps1 must be run first to distribute symbol*.bin
#   - Efinity IDE 2026.1 installed at C:\Efinity\2026.1\
#   - Efinity license at C:\Efinity\license\

$ErrorActionPreference = "Stop"

$ProjectDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $ProjectDir

$EfxRun = "C:\Efinity\2026.1\bin\efx_run.bat"

& $EfxRun at24c512c_t20.xml --prj --flow compile --timing_model C4
