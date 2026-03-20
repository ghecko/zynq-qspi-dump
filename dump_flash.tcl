# dump_flash.tcl
# Dumps 32MB SPI flash from Zynq-7000 via QSPI linear aperture
# Requires zynq_jlink.conf to have:
#   target create zynq.ahb mem_ap -dap zynq.dap -ap-num 0

proc check_qspi {} {
    set cfg [lindex [read_memory 0xE000D0A0 32 1] 0]
    echo [format "  LQSPI_CFG original = 0x%08x" $cfg]
    # Force safe config: linear mode + standard 0x03 READ instruction
    # (original 0x6B = Quad Read — needs dummy cycles + quad mode, causes WAIT timeout)
    mww 0xE000D0A0 0x80000003
    # Ensure controller is enabled
    mww 0xE000D014 0x00000001
    after 100
    echo [format "  LQSPI_CFG set to   = 0x%08x" [lindex [read_memory 0xE000D0A0 32 1] 0]]
    echo [format "  LQSPI_STS          = 0x%08x" [lindex [read_memory 0xE000D0A4 32 1] 0]]
}

proc dump_flash {filename} {
    set base   0xFC000000
    set size   0x2000000
    set chunk  0x10000
    set offset 0
    set errors 0

    echo "=== Zynq QSPI Flash Dump ==="

    echo "\[1/3\] Halting CPU..."
    targets zynq.cpu0
    halt

    echo "\[2/3\] Checking QSPI linear mode..."
    check_qspi

    echo "\[3/3\] Switching to AHB-AP for direct bus reads..."
    if {[catch {targets zynq.ahb} err]} {
        echo "ERROR: zynq.ahb target not found."
        echo "Add this line to zynq_jlink.conf (after zynq_7000.cfg source):"
        echo "  target create zynq.ahb mem_ap -dap zynq.dap -ap-num 0"
        return
    }

    echo "\nDumping 32MB to: $filename"
    echo "------------------------------------"

    set f [open $filename wb]

    while {$offset < $size} {
        set len $chunk
        if {[expr {$size - $offset}] < $chunk} {
            set len [expr {$size - $offset}]
        }
        set addr  [expr {$base + $offset}]
        set words [expr {$len / 4}]

        if {[catch {read_memory $addr 32 $words} data]} {
            echo [format "  ! error at 0x%08x - retrying..." $addr]
            after 300
            if {[catch {read_memory $addr 32 $words} data]} {
                echo [format "  ! retry failed at 0x%08x - padding 0xFF" $addr]
                incr errors
                set data {}
                for {set i 0} {$i < $words} {incr i} { lappend data 0xFFFFFFFF }
            }
        }

        foreach w $data { puts -nonewline $f [binary format i $w] }

        set offset [expr {$offset + $len}]
        if {[expr {$offset % 0x100000}] == 0} {
            set mb [expr {$offset / 0x100000}]
            echo [format "  %2d / 32 MB  (%d%%)" $mb [expr {$mb * 100 / 32}]]
        }
    }

    close $f

    # Hand back to CPU target
    targets zynq.cpu0

    echo "------------------------------------"
    echo "Done. Errors: $errors"
    echo "Output : $filename"
}
