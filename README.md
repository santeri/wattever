# wattever

A tiny macOS menu bar meter for Apple silicon.

The label shows whole-machine use as `-W`. While the Mac is plugged in, it also shows what the adapter is delivering as `+W`.

```
-11.0W +12.0W
```

The minus number is system load. With a full battery it sits next to the plus number, because the adapter is only running the Mac. While charging, the gap is power going into the battery. On battery, only the minus number is shown.

The menu keeps a 10 minute history of that load, and says how long the battery has until it is empty or full. On a full battery that line reads `full`. Under the history, the chip is broken out: CPU, GPU, ANE, DRAM, display, and the rest. That part is smaller than the whole machine, because the screen backlight and the board sit outside it.

## Run

```
make run
```

That runs the tests, builds `wattever.app`, and opens it. Quit from the menu.

Print one sample and exit:

```
make once
```

Requires macOS 14 or later.

## Chip counters

The menu-bar total comes from the battery. The rows under it come from the Energy Model. On macOS 27 those counters stay frozen unless Apple's `powermetrics` is sampling. Install a helper once:

```
make enable
```

That asks for sudo and installs a setuid root program at `/usr/local/libexec/wattever-powermetrics`. wattever starts it on the next tick. The helper runs only `/usr/bin/powermetrics` with a fixed command, and it stops when wattever quits.

Without the helper, CPU comes from power histograms and DRAM from the SMC. GPU still has its own counter. Display, ANE, and the rest read zero. The menu says `make enable for exact chip power` until the helper is installed.
