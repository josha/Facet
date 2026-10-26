# Facet performance

Latest: `1648074f256afae06bed4821b1a87501dc54e2ed` on 2026-10-26T191705Z, measured on the CI Ubuntu runner by the paired performance shards.
Times are milliseconds per frame or operation: the median over paired rounds of each round's p50 and p95.
Retained heap is the scene's mounted retained Luau heap. Change compares the p50 of the previous main commit.

| Scene | p50 ms | p95 ms | Retained KiB | Change |
| --- | ---: | ---: | ---: | ---: |
| adaptive-navigation-images | 1.0208 | 1.4111 | 9154 | -25.0% |
| alert-present-dismiss | 2.7865 | 4.4087 | 6080 | +16.5% |
| animation-interruption | 0.0379 | 0.0451 | 4819 | -1.0% |
| async-image-burst | 0.0407 | 0.0469 | 4952 | -9.5% |
| async-image-grid | 2.7103 | 4.2275 | 7173 | -0.9% |
| collection-mutation | 0.3389 | 0.4985 | 8324 | +17.6% |
| control-motion | 0.2018 | 0.6400 | 6317 | -21.2% |
| dense-hud | 0.1522 | 0.1697 | 5255 | -22.2% |
| dense-motion | 1.5438 | 2.6571 | 5877 | -2.8% |
| hud-binding-storm | 0.2637 | 0.2847 | 4916 | -0.1% |
| lab-collection-churn | 0.4168 | 0.7612 | 9078 | +0.6% |
| lab-dense-scroll | 0.8489 | 4.4173 | 12133 | +43.2% |
| locale-textsize-change | 0.0276 | 0.0308 | 4926 | -19.9% |
| native-scroll-drag | 0.0520 | 0.0675 | 6365 | -10.6% |
| navigation-customization | 0.0482 | 0.0567 | 9142 | -27.1% |
| picker-menu-open-close | 6.8077 | 9.9458 | 6036 | +2.5% |
| picker-segmented-textsize | 0.0649 | 0.0724 | 5509 | -23.3% |
| radial-menu-open-close | 10.5207 | 18.5249 | 5748 | -19.0% |
| screen-lifecycle-churn | 13.2931 | 20.3309 | 5890 | -18.9% |
| scroll-focus-traversal | 0.3006 | 0.5103 | 5857 | -27.9% |
| settings-churn | 3.0879 | 4.7958 | 7305 | -23.2% |
| shadow-storm | 0.0005 | 0.0012 | 6438 | +54.7% |
| stylesheet-state-churn | 0.3266 | 0.6492 | 7663 | +33.3% |
| theme-swap-assets | 1.7008 | 2.2665 | 10334 | -19.8% |
| theme-swap-flat | 0.4100 | 0.5146 | 8814 | -19.9% |
| theme-swap-metrics | 1.3725 | 1.6498 | 9439 | +32.1% |
| virtual-list-scroll | 0.2004 | 0.4268 | 10236 | -4.9% |

| Microbenchmark | p50 ms | p95 ms | Change |
| --- | ---: | ---: | ---: |
| billboard-nameplate-storm | 0.1707 | 0.1986 | +0.4% |
| collection-mutation | 0.0072 | 0.0092 | -14.1% |
| collection-selection-update | 0.0027 | 0.0044 | -13.9% |
| hud-binding-storm | 0.3013 | 0.3138 | +45.8% |
| motion-declarative | 1.2643 | 2.1118 | +1.9% |
| motion-explicit | 1.0834 | 1.7351 | -16.1% |
| mount-ramp | 134.2892 | 154.4592 | -9.7% |
| mount-ramp-inherited | 128.4181 | 147.0550 | +35.5% |
| mounted-slice-update-storm | 0.2424 | 0.3061 | -1.7% |
| outline-measured-update | 1.8221 | 2.7794 | -13.4% |
| reserved-slot-record-update | 0.7069 | 1.3484 | -16.8% |
| settings-churn | 0.0108 | 0.0117 | +38.3% |
| sparse-update-under-load | 0.0024 | 0.0025 | -2.4% |
| table-mutation | 0.3272 | 0.4239 | -26.4% |
| table-resize-drag | 2.5393 | 4.7563 | -21.9% |
| table-sort-values | 1.0831 | 1.6089 | +22.8% |
| table-source-refresh | 0.3018 | 0.4796 | -3.0% |
| textinput-typing-storm | 0.2143 | 0.3984 | -20.6% |
| timer-readout-storm | 0.1343 | 2.1475 | -17.4% |
| zz-yardstick-cpu-after | 1.1470 | 1.1636 | -12.8% |
| zz-yardstick-cpu-before | 1.0552 | 1.0964 | -18.3% |

## Scene p50 over the last 7 main commits

```mermaid
xychart-beta
    title "adaptive-navigation-images (p50 ms)"
    x-axis 1 --> 7
    line [0.9159, 1.3609, 0.9193, 1.3288, 1.2245, 1.3615, 1.0208]
```

```mermaid
xychart-beta
    title "alert-present-dismiss (p50 ms)"
    x-axis 1 --> 7
    line [2.3284, 2.5432, 2.6957, 3.5058, 3.6611, 2.3918, 2.7865]
```

```mermaid
xychart-beta
    title "animation-interruption (p50 ms)"
    x-axis 1 --> 7
    line [0.0242, 0.0301, 0.0381, 0.0290, 0.0220, 0.0383, 0.0379]
```

```mermaid
xychart-beta
    title "async-image-burst (p50 ms)"
    x-axis 1 --> 7
    line [0.0288, 0.0459, 0.0389, 0.0449, 0.0266, 0.0450, 0.0407]
```

```mermaid
xychart-beta
    title "async-image-grid (p50 ms)"
    x-axis 1 --> 7
    line [1.6953, 2.7184, 1.8124, 2.6543, 1.7415, 2.7336, 2.7103]
```

```mermaid
xychart-beta
    title "collection-mutation (p50 ms)"
    x-axis 1 --> 7
    line [0.3332, 0.4681, 0.3201, 0.4622, 0.4560, 0.2881, 0.3389]
```

```mermaid
xychart-beta
    title "control-motion (p50 ms)"
    x-axis 1 --> 7
    line [0.1407, 0.1565, 0.1807, 0.2262, 0.2422, 0.2560, 0.2018]
```

```mermaid
xychart-beta
    title "dense-hud (p50 ms)"
    x-axis 1 --> 7
    line [0.1402, 0.1574, 0.1997, 0.1472, 0.1114, 0.1957, 0.1522]
```

```mermaid
xychart-beta
    title "dense-motion (p50 ms)"
    x-axis 1 --> 7
    line [1.1243, 1.3144, 1.5562, 1.2159, 1.0340, 1.5887, 1.5438]
```

```mermaid
xychart-beta
    title "hud-binding-storm (p50 ms)"
    x-axis 1 --> 7
    line [0.1858, 0.2630, 0.2187, 0.2586, 0.1741, 0.2640, 0.2637]
```

```mermaid
xychart-beta
    title "lab-collection-churn (p50 ms)"
    x-axis 1 --> 7
    line [0.2396, 0.2475, 0.3195, 0.3675, 0.2530, 0.4143, 0.4168]
```

```mermaid
xychart-beta
    title "lab-dense-scroll (p50 ms)"
    x-axis 1 --> 7
    line [0.7446, 0.8751, 0.9218, 0.7244, 0.7929, 0.5928, 0.8489]
```

```mermaid
xychart-beta
    title "locale-textsize-change (p50 ms)"
    x-axis 1 --> 7
    line [0.0152, 0.0201, 0.0267, 0.0304, 0.0349, 0.0344, 0.0276]
```

```mermaid
xychart-beta
    title "native-scroll-drag (p50 ms)"
    x-axis 1 --> 7
    line [0.0464, 0.0583, 0.0482, 0.0561, 0.0672, 0.0581, 0.0520]
```

```mermaid
xychart-beta
    title "navigation-customization (p50 ms)"
    x-axis 1 --> 7
    line [0.0348, 0.0504, 0.0668, 0.0455, 0.0376, 0.0661, 0.0482]
```

```mermaid
xychart-beta
    title "picker-menu-open-close (p50 ms)"
    x-axis 1 --> 7
    line [5.1020, 6.6154, 4.6873, 6.5076, 4.5232, 6.6400, 6.8077]
```

```mermaid
xychart-beta
    title "picker-segmented-textsize (p50 ms)"
    x-axis 1 --> 7
    line [0.0576, 0.0616, 0.0841, 0.0581, 0.0762, 0.0847, 0.0649]
```

```mermaid
xychart-beta
    title "radial-menu-open-close (p50 ms)"
    x-axis 1 --> 7
    line [9.1824, 9.6461, 9.8160, 12.9977, 8.2964, 12.9826, 10.5207]
```

```mermaid
xychart-beta
    title "screen-lifecycle-churn (p50 ms)"
    x-axis 1 --> 7
    line [11.6362, 13.3303, 15.6277, 11.4367, 15.2702, 16.3829, 13.2931]
```

```mermaid
xychart-beta
    title "scroll-focus-traversal (p50 ms)"
    x-axis 1 --> 7
    line [0.1893, 0.1954, 0.2948, 0.3595, 0.2060, 0.4169, 0.3006]
```

```mermaid
xychart-beta
    title "settings-churn (p50 ms)"
    x-axis 1 --> 7
    line [2.4831, 3.3595, 3.8546, 2.7052, 3.5707, 4.0222, 3.0879]
```

```mermaid
xychart-beta
    title "shadow-storm (p50 ms)"
    x-axis 1 --> 7
    line [0.0005, 0.0005, 0.0006, 0.0005, 0.0006, 0.0003, 0.0005]
```

```mermaid
xychart-beta
    title "stylesheet-state-churn (p50 ms)"
    x-axis 1 --> 7
    line [0.2123, 0.2752, 0.3220, 0.3838, 0.4071, 0.2450, 0.3266]
```

```mermaid
xychart-beta
    title "theme-swap-assets (p50 ms)"
    x-axis 1 --> 7
    line [1.5921, 2.1494, 1.6336, 2.1480, 1.2452, 2.1218, 1.7008]
```

```mermaid
xychart-beta
    title "theme-swap-flat (p50 ms)"
    x-axis 1 --> 7
    line [0.3449, 0.3183, 0.4072, 0.4900, 0.2916, 0.5121, 0.4100]
```

```mermaid
xychart-beta
    title "theme-swap-metrics (p50 ms)"
    x-axis 1 --> 7
    line [1.2519, 1.6733, 1.3190, 1.6705, 1.6681, 1.0387, 1.3725]
```

```mermaid
xychart-beta
    title "virtual-list-scroll (p50 ms)"
    x-axis 1 --> 7
    line [0.1263, 0.1363, 0.1356, 0.1842, 0.1329, 0.2108, 0.2004]
```
