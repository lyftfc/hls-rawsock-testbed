# log_wave -recursive /
set signals {
    /sim_top/dut_inst/*
}
foreach s $signals {log_wave $s}
foreach s $signals {add_wave $s}
save_wave_config testbed
run all
quit
