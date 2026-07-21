# =============================================================================
# QuestaSim waveform setup for UART IP Core
# Expected variable from Makefile: TOP=<testbench module name>
# =============================================================================

view wave
catch {delete wave *}

if {![info exists TOP]} {
    set TOP uart_baud_gen_tb
}

set TB sim:/$TOP
puts "wave.do: Loading waves for $TB"

add wave -divider "CLOCK / RESET"
add wave -label clk $TB/clk
add wave -label rst $TB/rst

if {$TOP == "uart_baud_gen_tb"} {
    add wave -divider "BAUD GENERATOR TB"
    add wave -label en $TB/en
    add wave -label baud_division -radix unsigned $TB/baud_division
    add wave -label baud_tick $TB/baud_tick
    add wave -label tick_count -radix unsigned $TB/tick_count

    add wave -divider "DUT INTERNAL"
    add wave -label baud_count -radix unsigned $TB/dut/baud_count
}

if {$TOP == "uart_tx_tb"} {
    add wave -divider "TX INPUTS / OUTPUTS"
    add wave -label baud_tick $TB/baud_tick
    add wave -label ext_data_in -radix hexadecimal $TB/ext_data_in
    add wave -label tx_start $TB/tx_start
    add wave -label tx $TB/tx
    add wave -label tx_busy $TB/tx_busy

    add wave -divider "TX INTERNAL"
    add wave -label state -radix unsigned $TB/dut/state
    add wave -label next_state -radix unsigned $TB/dut/next_state
    add wave -label bit_tick_cnt -radix unsigned $TB/dut/bit_tick_cnt
    add wave -label bit_cnt -radix unsigned $TB/dut/bit_cnt
    add wave -label shift_reg -radix hexadecimal $TB/dut/shift_reg
}

if {$TOP == "uart_rx_tb"} {
    add wave -divider "RX INPUTS / OUTPUTS"
    add wave -label baud_tick $TB/baud_tick
    add wave -label rx $TB/rx
    add wave -label ext_data_out -radix hexadecimal $TB/ext_data_out
    add wave -label rx_valid $TB/rx_valid
    add wave -label frame_error $TB/frame_error

    add wave -divider "RX INTERNAL"
    add wave -label state -radix unsigned $TB/dut/state
    add wave -label next_state -radix unsigned $TB/dut/next_state
    add wave -label bit_tick_cnt -radix unsigned $TB/dut/bit_tick_cnt
    add wave -label bit_cnt -radix unsigned $TB/dut/bit_cnt
    add wave -label shift_reg -radix hexadecimal $TB/dut/shift_reg
    add wave -label rx_d1 $TB/dut/rx_d1
    add wave -label rx_d2 $TB/dut/rx_d2
}

if {$TOP == "uart_top_tb"} {
    add wave -divider "REGISTER BUS"
    add wave -label address -radix unsigned $TB/address
    add wave -label write_data -radix hexadecimal $TB/write_data
    add wave -label read_data -radix hexadecimal $TB/read_data
    add wave -label we $TB/we
    add wave -label re $TB/re

    add wave -divider "UART PINS / STATUS"
    add wave -label tx $TB/tx
    add wave -label rx $TB/rx
    add wave -label tx_busy $TB/tx_busy
    add wave -label rx_valid $TB/rx_valid

    add wave -divider "TOP INTERNAL"
    add wave -label baud_division -radix unsigned $TB/dut/baud_division
    add wave -label enable $TB/dut/enable
    add wave -label tx_data -radix hexadecimal $TB/dut/tx_data
    add wave -label rx_data -radix hexadecimal $TB/dut/rx_data
    add wave -label frame_error $TB/dut/frame_error
    add wave -label rx_ready $TB/dut/rx_ready
    add wave -label frame_error_sticky $TB/dut/frame_error_sticky
    add wave -label baud_tick $TB/dut/baud_tick
    add wave -label tx_start $TB/dut/tx_start

    add wave -divider "TX CORE"
    add wave -label tx_state -radix unsigned $TB/dut/tx_core/state
    add wave -label tx_bit_tick_cnt -radix unsigned $TB/dut/tx_core/bit_tick_cnt
    add wave -label tx_bit_cnt -radix unsigned $TB/dut/tx_core/bit_cnt
    add wave -label tx_shift_reg -radix hexadecimal $TB/dut/tx_core/shift_reg

    add wave -divider "RX CORE"
    add wave -label rx_state -radix unsigned $TB/dut/rx_core/state
    add wave -label rx_bit_tick_cnt -radix unsigned $TB/dut/rx_core/bit_tick_cnt
    add wave -label rx_bit_cnt -radix unsigned $TB/dut/rx_core/bit_cnt
    add wave -label rx_shift_reg -radix hexadecimal $TB/dut/rx_core/shift_reg
}

configure wave -signalnamewidth 1
run -all
wave zoom full
