# wattever

A tiny macOS menu bar meter for Apple silicon.

The label shows chip usage as `-W`. While the Mac is plugged in, it also shows what the adapter is delivering as `+W`.

```
-3.4W +33.0W
```

The minus number is the SoC energy model: CPU, GPU, ANE, DRAM, display, and the rest of the chip. The plus number is live adapter input. On battery, only the minus number is shown. Click the label for the breakdown, and for the session minimum, average, and maximum.

## Run

```
make run
```

That runs the tests, builds `wattever.app`, and opens it. Quit from the menu.

Print one sample and exit:

```
make once
```

Requires macOS 14 or later. No sudo.
