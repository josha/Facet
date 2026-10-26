# Facet performance

Latest: `d1d129087326548a1a32e0abf13c4eb091b6856c` on 2026-10-26T134515Z, measured on the CI Ubuntu runner by the paired performance shards.
Times are milliseconds per frame or operation: the median over paired rounds of each round's p50 and p95.
Retained heap is the scene's mounted retained Luau heap. Change compares the p50 of the previous main commit.

| Scene | p50 ms | p95 ms | Retained KiB | Change |
| --- | ---: | ---: | ---: | ---: |
| adaptive-navigation-images | 1.3288 | 1.6531 | 9159 | +44.5% |
| alert-present-dismiss | 3.5058 | 5.2280 | 6571 | +30.1% |
| animation-interruption | 0.0290 | 0.0340 | 4815 | -24.0% |
| async-image-burst | 0.0449 | 0.0528 | 4979 | +15.6% |
| async-image-grid | 2.6543 | 4.0103 | 7094 | +46.4% |
| collection-mutation | 0.4622 | 0.6087 | 8240 | +44.4% |
| control-motion | 0.2262 | 0.6450 | 6326 | +25.2% |
| dense-hud | 0.1472 | 0.1619 | 5259 | -26.3% |
| dense-motion | 1.2159 | 2.1382 | 8171 | -21.9% |
| hud-binding-storm | 0.2586 | 0.2817 | 4920 | +18.3% |
| lab-collection-churn | 0.3675 | 0.7697 | 9074 | +15.0% |
| lab-dense-scroll | 0.7244 | 4.1040 | 12132 | -21.4% |
| locale-textsize-change | 0.0304 | 0.0345 | 4926 | +13.9% |
| native-scroll-drag | 0.0561 | 0.0708 | 6364 | +16.4% |
| navigation-customization | 0.0455 | 0.0532 | 9141 | -31.9% |
| picker-menu-open-close | 6.5076 | 9.5107 | 6117 | +38.8% |
| picker-segmented-textsize | 0.0581 | 0.0689 | 5454 | -30.9% |
| radial-menu-open-close | 12.9977 | 20.2105 | 6007 | +32.4% |
| screen-lifecycle-churn | 11.4367 | 20.6838 | 5903 | -26.8% |
| scroll-focus-traversal | 0.3595 | 0.5744 | 5853 | +21.9% |
| settings-churn | 2.7052 | 4.1003 | 6490 | -29.8% |
| shadow-storm | 0.0005 | 0.0015 | 6406 | -15.6% |
| stylesheet-state-churn | 0.3838 | 0.7474 | 7643 | +19.2% |
| theme-swap-assets | 2.1480 | 2.5963 | 9574 | +31.5% |
| theme-swap-flat | 0.4900 | 0.6355 | 8810 | +20.3% |
| theme-swap-metrics | 1.6705 | 1.9073 | 9450 | +26.6% |
| virtual-list-scroll | 0.1842 | 0.4587 | 10141 | +35.8% |

| Microbenchmark | p50 ms | p95 ms | Change |
| --- | ---: | ---: | ---: |
| billboard-nameplate-storm | 0.1691 | 0.1964 | +15.4% |
| collection-mutation | 0.0072 | 0.0098 | -13.8% |
| collection-selection-update | 0.0028 | 0.0040 | +8.1% |
| hud-binding-storm | 0.3546 | 0.3686 | +20.4% |
| motion-declarative | 1.0114 | 1.5895 | -19.8% |
| motion-explicit | 1.2814 | 2.1089 | +24.4% |
| mount-ramp | 153.7911 | 173.2050 | +32.8% |
| mount-ramp-inherited | 120.3640 | 138.4097 | -24.2% |
| mounted-slice-update-storm | 0.2148 | 0.2233 | +4.6% |
| outline-measured-update | 1.9697 | 3.1719 | +23.9% |
| reserved-slot-record-update | 0.6928 | 1.9982 | -20.1% |
| settings-churn | 0.0144 | 0.0155 | +36.7% |
| sparse-update-under-load | 0.0024 | 0.0025 | +17.9% |
| table-mutation | 0.3031 | 0.4022 | -31.2% |
| table-resize-drag | 3.0784 | 4.9367 | +25.2% |
| table-sort-values | 1.4113 | 2.2446 | +35.7% |
| table-source-refresh | 0.1880 | 0.5177 | -29.4% |
| textinput-typing-storm | 0.2230 | 0.3906 | +2.1% |
| timer-readout-storm | 0.1711 | 2.7081 | +25.4% |
| zz-yardstick-cpu-after | 1.2855 | 1.2913 | +3.9% |
| zz-yardstick-cpu-before | 1.2817 | 1.2914 | +10.3% |

## Scene p50 over the last 4 main commits

```mermaid
xychart-beta
    title "adaptive-navigation-images (p50 ms)"
    x-axis 1 --> 4
    line [0.9159, 1.3609, 0.9193, 1.3288]
```

```mermaid
xychart-beta
    title "alert-present-dismiss (p50 ms)"
    x-axis 1 --> 4
    line [2.3284, 2.5432, 2.6957, 3.5058]
```

```mermaid
xychart-beta
    title "animation-interruption (p50 ms)"
    x-axis 1 --> 4
    line [0.0242, 0.0301, 0.0381, 0.0290]
```

```mermaid
xychart-beta
    title "async-image-burst (p50 ms)"
    x-axis 1 --> 4
    line [0.0288, 0.0459, 0.0389, 0.0449]
```

```mermaid
xychart-beta
    title "async-image-grid (p50 ms)"
    x-axis 1 --> 4
    line [1.6953, 2.7184, 1.8124, 2.6543]
```

```mermaid
xychart-beta
    title "collection-mutation (p50 ms)"
    x-axis 1 --> 4
    line [0.3332, 0.4681, 0.3201, 0.4622]
```

```mermaid
xychart-beta
    title "control-motion (p50 ms)"
    x-axis 1 --> 4
    line [0.1407, 0.1565, 0.1807, 0.2262]
```

```mermaid
xychart-beta
    title "dense-hud (p50 ms)"
    x-axis 1 --> 4
    line [0.1402, 0.1574, 0.1997, 0.1472]
```

```mermaid
xychart-beta
    title "dense-motion (p50 ms)"
    x-axis 1 --> 4
    line [1.1243, 1.3144, 1.5562, 1.2159]
```

```mermaid
xychart-beta
    title "hud-binding-storm (p50 ms)"
    x-axis 1 --> 4
    line [0.1858, 0.2630, 0.2187, 0.2586]
```

```mermaid
xychart-beta
    title "lab-collection-churn (p50 ms)"
    x-axis 1 --> 4
    line [0.2396, 0.2475, 0.3195, 0.3675]
```

```mermaid
xychart-beta
    title "lab-dense-scroll (p50 ms)"
    x-axis 1 --> 4
    line [0.7446, 0.8751, 0.9218, 0.7244]
```

```mermaid
xychart-beta
    title "locale-textsize-change (p50 ms)"
    x-axis 1 --> 4
    line [0.0152, 0.0201, 0.0267, 0.0304]
```

```mermaid
xychart-beta
    title "native-scroll-drag (p50 ms)"
    x-axis 1 --> 4
    line [0.0464, 0.0583, 0.0482, 0.0561]
```

```mermaid
xychart-beta
    title "navigation-customization (p50 ms)"
    x-axis 1 --> 4
    line [0.0348, 0.0504, 0.0668, 0.0455]
```

```mermaid
xychart-beta
    title "picker-menu-open-close (p50 ms)"
    x-axis 1 --> 4
    line [5.1020, 6.6154, 4.6873, 6.5076]
```

```mermaid
xychart-beta
    title "picker-segmented-textsize (p50 ms)"
    x-axis 1 --> 4
    line [0.0576, 0.0616, 0.0841, 0.0581]
```

```mermaid
xychart-beta
    title "radial-menu-open-close (p50 ms)"
    x-axis 1 --> 4
    line [9.1824, 9.6461, 9.8160, 12.9977]
```

```mermaid
xychart-beta
    title "screen-lifecycle-churn (p50 ms)"
    x-axis 1 --> 4
    line [11.6362, 13.3303, 15.6277, 11.4367]
```

```mermaid
xychart-beta
    title "scroll-focus-traversal (p50 ms)"
    x-axis 1 --> 4
    line [0.1893, 0.1954, 0.2948, 0.3595]
```

```mermaid
xychart-beta
    title "settings-churn (p50 ms)"
    x-axis 1 --> 4
    line [2.4831, 3.3595, 3.8546, 2.7052]
```

```mermaid
xychart-beta
    title "shadow-storm (p50 ms)"
    x-axis 1 --> 4
    line [0.0005, 0.0005, 0.0006, 0.0005]
```

```mermaid
xychart-beta
    title "stylesheet-state-churn (p50 ms)"
    x-axis 1 --> 4
    line [0.2123, 0.2752, 0.3220, 0.3838]
```

```mermaid
xychart-beta
    title "theme-swap-assets (p50 ms)"
    x-axis 1 --> 4
    line [1.5921, 2.1494, 1.6336, 2.1480]
```

```mermaid
xychart-beta
    title "theme-swap-flat (p50 ms)"
    x-axis 1 --> 4
    line [0.3449, 0.3183, 0.4072, 0.4900]
```

```mermaid
xychart-beta
    title "theme-swap-metrics (p50 ms)"
    x-axis 1 --> 4
    line [1.2519, 1.6733, 1.3190, 1.6705]
```

```mermaid
xychart-beta
    title "virtual-list-scroll (p50 ms)"
    x-axis 1 --> 4
    line [0.1263, 0.1363, 0.1356, 0.1842]
```
