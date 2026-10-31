# UART Bug Log

## B1: Pending transmit request was not reported as busy

- Symptom: consecutive writes of A1 and B2 transmitted only A1, while TX_DATA
  incorrectly read back B2.
- Detection: `uart_regression_tb`, T1.
- Root cause: the top accepted a second write before the TX FSM left IDLE;
  consecutive high tx_start cycles produced only one rising-edge request.
- Fix: combine core busy with the pending tx_start request for write protection,
  the external busy signal, and STATUS bit1.
- Lesson: busy must cover both request acceptance and execution.

## B2: Invalid-stop frames overwrote the last good receive byte

- Symptom: a valid unread 5A was replaced by C3 from a frame with a bad stop bit.
- Detection: `uart_regression_tb`, T3, checking both RX_DATA and the RX-core output.
- Root cause: the core updated ext_data_out regardless of stop-bit validity.
- Fix: update the output and pulse rx_valid only for a valid stop bit; otherwise
  preserve the output and pulse frame_error.
- Lesson: qualify data publication with the same validity decision as its event.

## B3: Unread receive data was overwritten without an overrun indication

- Symptom: two valid frames, 11 then 22, left only 22 available to software.
- Detection: `uart_regression_tb`, T2; T4 covers simultaneous read/arrival,
  T5 covers overrun set-over-clear, and T7 covers disable/re-enable recovery.
- Root cause: RX_DATA directly exposed the core output with no protected buffer.
- Fix: add an eight-bit top-level buffer, retain the old unread byte on overflow,
  and expose clear-on-STATUS-read overrun at bit4 with set priority. A simultaneous
  RX_DATA read consumes the old byte and allows replacement without overrun.
- Lesson: define buffer ownership, overflow policy, and simultaneous-event priority.

## D1: Combinational TX pin decode

- Symptom: the off-chip TX pin was driven by combinational state/data decode,
  exposing it to potential hardware glitches during state transitions.
- Detection: structural RTL review; RTL simulation does not establish physical
  glitch behavior. `uart_tx_tb` checks registered START timing and full frames;
  `uart_top_tb` and the regression check serial behavior and disable recovery.
- Root cause: multi-bit FSM transitions fed the pin without an output register.
- Fix: register TX on the system clock with synchronous reset to idle HIGH.
  The waveform follows the state/datapath by one clock; adjust the TX test's
  initial START check for this explicit latency.
- Lesson: register externally observed timing-sensitive outputs and document
  latency separately from FSM status.
