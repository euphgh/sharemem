# SHM reference component test

`gid_isolation_tb.sv` validates that equal BANK/BADDR values in gid 0 and gid 1
remain independent in the reference memory and M2V writeback map. It also
checks M2V wpid 3/4 write gid selection and VTRANS wpid 3/4 transpose data. It
checks that inactive, masked, topology-unused, out-of-length, and M2V-unused X/Z
payload is filtered before offset decode or data consumption. It does not
instantiate or use DUT behavior.

The test package supplies a component-only byte-memory stand-in with the API
used by production `shm_reference`. The stand-in is not included by the
production environment, and lets this component test run without loading a
licensed Synopsys VIP package.

Run on an EDA host with:

```bash
scripts/ubuntu/check_shm_reference_vcs.sh
```
