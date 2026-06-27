$ErrorActionPreference = "Stop"

$Project = "CSK3630_UART"
$QuartusSh = "D:\intelFPGA_lite\18.1\quartus\bin64\quartus_sh.exe"
$Vlib = "D:\intelFPGA_lite\18.1\modelsim_ase\win32aloem\vlib.exe"
$Vlog = "D:\intelFPGA_lite\18.1\modelsim_ase\win32aloem\vlog.exe"
$Vsim = "D:\intelFPGA_lite\18.1\modelsim_ase\win32aloem\vsim.exe"

foreach ($Tool in @($QuartusSh, $Vlib, $Vlog, $Vsim)) {
    if (-not (Test-Path $Tool)) {
        throw "Tool not found: $Tool"
    }
}

Write-Host "== CSK3630_UART verification =="
Write-Host "Project: $Project"

if (-not (Test-Path ".\work")) {
    & $Vlib work
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}

$RtlFiles = @(
    ".\rtl\CSK3630_baud_gen.v",
    ".\rtl\CSK3630_uart_rx.v",
    ".\rtl\CSK3630_uart_tx.v",
    ".\rtl\CSK3630_uart_protocol.v",
    ".\rtl\CSK3630_seg7_595.v",
    ".\rtl\CSK3630_UART.v"
)

$TbFiles = @(
    ".\sim\tb_CSK3630_uart.v",
    ".\sim\tb_CSK3630_protocol.v",
    ".\sim\tb_CSK3630_top_loopback.v"
)

Write-Host "== ModelSim compile =="
& $Vlog -work work @RtlFiles @TbFiles
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

foreach ($Tb in @("tb_CSK3630_uart", "tb_CSK3630_protocol", "tb_CSK3630_top_loopback")) {
    Write-Host "== ModelSim run: $Tb =="
    & $Vsim -c -quiet "work.$Tb" -do "run -all; quit -f"
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}

Write-Host "== Quartus full compile =="
& $QuartusSh --flow compile $Project
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

$Sof = Get-Item ".\output_files\CSK3630_UART.sof"
Write-Host "== Verification finished =="
Write-Host ("SOF: {0}" -f $Sof.FullName)
Write-Host ("SOF time: {0}" -f $Sof.LastWriteTime)
