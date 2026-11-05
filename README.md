# Facet performance

Latest: `c099a93b0906e504ced4f054e697941ff9cafec4` on 2026-11-05T205607Z, measured on the CI Ubuntu runner by the paired performance shards.
Times are milliseconds per frame or operation: the median over paired rounds of each round's p50 and p95.
Retained heap is the scene's mounted retained Luau heap. Change compares the p50 of the previous main commit.

| Scene | p50 ms | p95 ms | Retained KiB | Change |
| --- | ---: | ---: | ---: | ---: |
| adaptive-navigation-images | 1.1465 | 1.2213 | 3922 | -2.2% |
| alert-present-dismiss | 2.9589 | 4.2918 | 9390 | +0.2% |
| animation-interruption | 0.0306 | 0.0339 | 372 | +92.7% |
| async-image-burst | 0.0388 | 0.0472 | 480 | +101.8% |
| async-image-grid | 2.2419 | 3.6427 | 2727 | +62.7% |
| collection-mutation | 0.3400 | 0.3723 | 2977 | +1.2% |
| control-motion | 0.1801 | 0.5627 | 1751 | -0.5% |
| dense-hud | 0.1379 | 0.1487 | 751 | +82.6% |
| dense-motion | 0.9128 | 1.2650 | 1620 | +65.1% |
| hud-binding-storm | 0.2142 | 0.2358 | 475 | +68.4% |
| lab-collection-churn | 0.3706 | 0.5296 | 4891 | +80.4% |
| lab-dense-scroll | 0.1552 | 0.2429 | 5916 | -0.5% |
| locale-textsize-change | 0.0296 | 0.0324 | 530 | +0.7% |
| native-scroll-drag | 0.0355 | 0.0508 | 1911 | -0.2% |
| navigation-customization | 0.0412 | 0.0480 | 3756 | +38.9% |
| picker-menu-open-close | 5.4017 | 8.3897 | 15932 | +58.8% |
| picker-segmented-textsize | 0.0669 | 0.0775 | 910 | +1.1% |
| radial-menu-open-close | 2.7809 | 3.7230 | 6665 | +49.6% |
| screen-lifecycle-churn | 13.3474 | 20.1715 | 26930 | -2.4% |
| scroll-focus-traversal | 0.3674 | 0.5680 | 1252 | +85.5% |
| settings-churn | 3.6307 | 5.3019 | 9278 | -0.3% |
| shadow-storm | 0.0005 | 0.0006 | 1957 | -0.0% |
| stylesheet-state-churn | 0.3378 | 0.3765 | 2589 | +1.6% |
| theme-swap-assets | 1.4603 | 1.8177 | 7059 | +56.6% |
| theme-swap-flat | 0.4068 | 0.4555 | 4462 | +70.2% |
| theme-swap-metrics | 1.3991 | 1.6666 | 6109 | +1.1% |
| virtual-list-scroll | 0.1330 | 0.1862 | 4270 | +60.1% |

| Microbenchmark | p50 ms | p95 ms | Change |
| --- | ---: | ---: | ---: |
| billboard-nameplate-storm | 0.1542 | 0.1686 | +82.7% |
| collection-mutation | 0.0084 | 0.0113 | +0.2% |
| collection-selection-update | 0.0026 | 0.0032 | +107.9% |
| hud-binding-storm | 0.3108 | 0.3262 | +0.0% |
| motion-declarative | 0.8385 | 1.1569 | +77.7% |
| motion-explicit | 0.8089 | 1.1230 | -2.7% |
| mount-ramp | 171.3478 | 192.8599 | +60.2% |
| mount-ramp-inherited | 167.9753 | 181.9892 | -1.1% |
| mounted-slice-update-storm | 0.2117 | 0.2255 | +77.6% |
| outline-measured-update | 1.2825 | 1.6429 | -1.8% |
| reserved-slot-record-update | 0.5893 | 0.6084 | +81.6% |
| settings-churn | 0.0162 | 0.0183 | -4.6% |
| sparse-update-under-load | 0.0024 | 0.0025 | +86.6% |
| table-mutation | 0.2859 | 0.3400 | +0.6% |
| table-resize-drag | 1.2830 | 1.6779 | +50.9% |
| table-sort-values | 1.0383 | 1.2746 | -0.8% |
| table-source-refresh | 0.2114 | 0.4108 | +81.7% |
| textinput-typing-storm | 0.2306 | 0.3684 | -2.2% |
| timer-readout-storm | 0.1507 | 0.6895 | +75.3% |
| zz-yardstick-cpu-after | 1.3237 | 1.3405 | +1.6% |
| zz-yardstick-cpu-before | 1.3143 | 1.3255 | +1.5% |

## Scene p50 over the last 3 main commits

```mermaid
xychart-beta
    title "adaptive-navigation-images (p50 ms)"
    x-axis 1 --> 3
    line [0.8330, 1.1721, 1.1465]
```

```mermaid
xychart-beta
    title "alert-present-dismiss (p50 ms)"
    x-axis 1 --> 3
    line [2.9632, 2.9538, 2.9589]
```

```mermaid
xychart-beta
    title "animation-interruption (p50 ms)"
    x-axis 1 --> 3
    line [0.0236, 0.0159, 0.0306]
```

```mermaid
xychart-beta
    title "async-image-burst (p50 ms)"
    x-axis 1 --> 3
    line [0.0357, 0.0192, 0.0388]
```

```mermaid
xychart-beta
    title "async-image-grid (p50 ms)"
    x-axis 1 --> 3
    line [1.4898, 1.3778, 2.2419]
```

```mermaid
xychart-beta
    title "collection-mutation (p50 ms)"
    x-axis 1 --> 3
    line [0.3063, 0.3360, 0.3400]
```

```mermaid
xychart-beta
    title "control-motion (p50 ms)"
    x-axis 1 --> 3
    line [0.1272, 0.1810, 0.1801]
```

```mermaid
xychart-beta
    title "dense-hud (p50 ms)"
    x-axis 1 --> 3
    line [0.1428, 0.0755, 0.1379]
```

```mermaid
xychart-beta
    title "dense-motion (p50 ms)"
    x-axis 1 --> 3
    line [0.7269, 0.5529, 0.9128]
```

```mermaid
xychart-beta
    title "hud-binding-storm (p50 ms)"
    x-axis 1 --> 3
    line [0.1859, 0.1272, 0.2142]
```

```mermaid
xychart-beta
    title "lab-collection-churn (p50 ms)"
    x-axis 1 --> 3
    line [0.2870, 0.2054, 0.3706]
```

```mermaid
xychart-beta
    title "lab-dense-scroll (p50 ms)"
    x-axis 1 --> 3
    line [0.1688, 0.1559, 0.1552]
```

```mermaid
xychart-beta
    title "locale-textsize-change (p50 ms)"
    x-axis 1 --> 3
    line [0.0212, 0.0294, 0.0296]
```

```mermaid
xychart-beta
    title "native-scroll-drag (p50 ms)"
    x-axis 1 --> 3
    line [0.0313, 0.0356, 0.0355]
```

```mermaid
xychart-beta
    title "navigation-customization (p50 ms)"
    x-axis 1 --> 3
    line [0.0505, 0.0296, 0.0412]
```

```mermaid
xychart-beta
    title "picker-menu-open-close (p50 ms)"
    x-axis 1 --> 3
    line [4.0174, 3.4024, 5.4017]
```

```mermaid
xychart-beta
    title "picker-segmented-textsize (p50 ms)"
    x-axis 1 --> 3
    line [0.0429, 0.0662, 0.0669]
```

```mermaid
xychart-beta
    title "radial-menu-open-close (p50 ms)"
    x-axis 1 --> 3
    line [3.1112, 1.8589, 2.7809]
```

```mermaid
xychart-beta
    title "screen-lifecycle-churn (p50 ms)"
    x-axis 1 --> 3
    line [10.3266, 13.6779, 13.3474]
```

```mermaid
xychart-beta
    title "scroll-focus-traversal (p50 ms)"
    x-axis 1 --> 3
    line [0.3840, 0.1980, 0.3674]
```

```mermaid
xychart-beta
    title "settings-churn (p50 ms)"
    x-axis 1 --> 3
    line [2.5856, 3.6434, 3.6307]
```

```mermaid
xychart-beta
    title "shadow-storm (p50 ms)"
    x-axis 1 --> 3
    line [0.0005, 0.0005, 0.0005]
```

```mermaid
xychart-beta
    title "stylesheet-state-churn (p50 ms)"
    x-axis 1 --> 3
    line [0.3080, 0.3324, 0.3378]
```

```mermaid
xychart-beta
    title "theme-swap-assets (p50 ms)"
    x-axis 1 --> 3
    line [1.5349, 0.9322, 1.4603]
```

```mermaid
xychart-beta
    title "theme-swap-flat (p50 ms)"
    x-axis 1 --> 3
    line [0.3972, 0.2391, 0.4068]
```

```mermaid
xychart-beta
    title "theme-swap-metrics (p50 ms)"
    x-axis 1 --> 3
    line [1.3783, 1.3845, 1.3991]
```

```mermaid
xychart-beta
    title "virtual-list-scroll (p50 ms)"
    x-axis 1 --> 3
    line [0.0907, 0.0831, 0.1330]
```
