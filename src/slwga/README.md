# SLWGA.dll

`SLWGA.dll` is a 4 KB stub implementing the one Windows function VooV's
`wemeet_platform.dll` imports: `SLIsGenuineLocal`, from the Software Licensing
API.

Wine does not provide `SLWGA.dll`, so without it the application fails to load:

```
err:module:import_dll Library SLWGA.dll (...) not found
err:module:import_dll Library wemeet_platform.dll (...) not found
```

## Source and build

[`slwga.zig`](slwga.zig) is the complete source. It is compiled for 64-bit
Windows with Zig:

```bash
zig cc -target x86_64-windows-gnu slwga.zig -o SLWGA.dll
```

The checked-in `SLWGA.dll` was built with Zig 0.16.0. The stub is MIT licensed
like the rest of this repository.
