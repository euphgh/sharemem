# SHM reference component test

`gid_isolation_tb.sv` validates that equal BANK/BADDR values in gid 0 and gid 1
remain independent in the reference memory and M2V writeback map. It also
checks M2V wpid 3/4 write gid selection and VTRANS wpid 3/4 transpose data. It
does not instantiate or use DUT behavior.

Run on an EDA host with:

```bash
scripts/ubuntu/check_shm_reference_vcs.sh
```
