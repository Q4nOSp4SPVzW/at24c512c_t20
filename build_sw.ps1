# Firmware build script
# Order: build_sw.ps1 -> build.ps1 -> program.ps1
#
# Steps:
#   1. Compile firmware with RISC-V GCC (sw/main.c + sw/crt0.S)
#   2. Convert ELF to BIN
#   3. Generate ROM symbol files (symbol*.bin) via binGen.py
#   4. Distribute symbol*.bin to ip/soc/ and project root
#
# Requirements:
#   - Efinity RISC-V IDE 2026.1 at C:\Efinity\efinity-riscv-ide-2026.1\
#   - Efinity IDE 2026.1 at C:\Efinity\2026.1\

$ErrorActionPreference = "Stop"

$ProjectDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $ProjectDir

# Toolchain paths (edit here if installed elsewhere)
$Toolchain = "C:\Efinity\efinity-riscv-ide-2026.1\toolchain\bin"
$Gcc      = Join-Path $Toolchain "riscv-none-elf-gcc.exe"
$Objcopy  = Join-Path $Toolchain "riscv-none-elf-objcopy.exe"
$Size     = Join-Path $Toolchain "riscv-none-elf-size.exe"
$BinGen   = "C:\Efinity\2026.1\ipm\ip\efx_soc\efx_soc\embedded_sw\tool\binGen.py"
$Python   = "C:\Efinity\2026.1\python311\bin\python.exe"

$BuildDir = Join-Path $ProjectDir "sw\build"
$RomDir   = Join-Path $BuildDir "rom"
New-Item -ItemType Directory -Force -Path $BuildDir | Out-Null

# --- Step 1: Compile ---
$IncBsp   = Join-Path $ProjectDir "embedded_sw\soc\bsp\efinix\EfxSapphireSoc\include"
$IncDrv   = Join-Path $ProjectDir "embedded_sw\soc\software\standalone\driver"

$GccArgs = @(
    "-march=rv32im_zicsr_zifencei",
    "-mabi=ilp32",
    "-Os",
    "-ffreestanding",
    "-fno-builtin",
    "-nostdlib",
    "-nostartfiles",
    "-msmall-data-limit=0",
    "-I", $IncBsp,
    "-I", $IncDrv,
    "-Wl,--gc-sections",
    "-Wl,-T,sw/linker.ld",
    "-Wl,-Map,sw/build/at24c512c.map",
    "sw/crt0.S",
    "sw/main.c",
    "-o",
    "sw/build/at24c512c.elf"
)
& $Gcc @GccArgs
& $Size sw/build/at24c512c.elf

# --- Step 2: ELF to BIN ---
& $Objcopy -O binary sw/build/at24c512c.elf sw/build/at24c512c.bin

# --- Step 3: Generate ROM symbol files ---
# Use Efinity's python3.bat wrapper so Python finds its standard library correctly
$Python3Bat = "C:\Efinity\2026.1\bin\python3.bat"

Push-Location $BuildDir
try {
    & $Python3Bat $BinGen -b at24c512c.bin -f 0 -s 8192
}
finally {
    Pop-Location
}

# --- Step 4: Distribute symbol*.bin ---
$Destinations = @(
    (Join-Path $ProjectDir "ip\soc"),
    (Join-Path $ProjectDir "ip\soc\source\hardware\netlist"),
    $ProjectDir
)

foreach ($dest in $Destinations) {
    New-Item -ItemType Directory -Force -Path $dest | Out-Null
    Copy-Item -Force (Join-Path $RomDir "EfxSapphireSoc.v_toplevel_system_ramA_logic_ram_symbol*.bin") $dest
}
