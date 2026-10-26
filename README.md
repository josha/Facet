# Facet performance

Latest: `5cbd88dadcb0ff0951ac8ab558de2bb77d157734` on 2026-10-26T162411Z, measured on the CI Ubuntu runner by the paired performance shards.
Times are milliseconds per frame or operation: the median over paired rounds of each round's p50 and p95.
Retained heap is the scene's mounted retained Luau heap. Change compares the p50 of the previous main commit.

| Scene | p50 ms | p95 ms | Retained KiB | Change |
| --- | ---: | ---: | ---: | ---: |
| adaptive-navigation-images | 1.2245 | 1.7459 | 9160 | -7.9% |
| alert-present-dismiss | 3.6611 | 5.2379 | 5963 | +4.4% |
| animation-interruption | 0.0220 | 0.0260 | 4807 | -24.1% |
| async-image-burst | 0.0266 | 0.0315 | 4970 | -40.8% |
| async-image-grid | 1.7415 | 3.0703 | 6445 | -34.4% |
| collection-mutation | 0.4560 | 0.5924 | 8226 | -1.3% |
| control-motion | 0.2422 | 0.6723 | 6332 | +7.1% |
| dense-hud | 0.1114 | 0.1275 | 5259 | -24.3% |
| dense-motion | 1.0340 | 1.8862 | 7944 | -15.0% |
| hud-binding-storm | 0.1741 | 0.1886 | 4916 | -32.7% |
| lab-collection-churn | 0.2530 | 0.6109 | 9078 | -31.2% |
| lab-dense-scroll | 0.7929 | 5.4115 | 12123 | +9.5% |
| locale-textsize-change | 0.0349 | 0.0413 | 4934 | +14.7% |
| native-scroll-drag | 0.0672 | 0.0904 | 6357 | +19.8% |
| navigation-customization | 0.0376 | 0.0453 | 9146 | -17.3% |
| picker-menu-open-close | 4.5232 | 7.2134 | 6134 | -30.5% |
| picker-segmented-textsize | 0.0762 | 0.0919 | 5466 | +31.2% |
| radial-menu-open-close | 8.2964 | 15.0454 | 6049 | -36.2% |
| screen-lifecycle-churn | 15.2702 | 26.5241 | 5884 | +33.5% |
| scroll-focus-traversal | 0.2060 | 0.3896 | 5852 | -42.7% |
| settings-churn | 3.5707 | 5.5435 | 6481 | +32.0% |
| shadow-storm | 0.0006 | 0.0014 | 6401 | +19.5% |
| stylesheet-state-churn | 0.4071 | 0.6870 | 7639 | +6.1% |
| theme-swap-assets | 1.2452 | 1.5776 | 9587 | -42.0% |
| theme-swap-flat | 0.2916 | 0.3601 | 8877 | -40.5% |
| theme-swap-metrics | 1.6681 | 1.9330 | 9443 | -0.1% |
| virtual-list-scroll | 0.1329 | 0.3508 | 10205 | -27.8% |

| Microbenchmark | p50 ms | p95 ms | Change |
| --- | ---: | ---: | ---: |
| billboard-nameplate-storm | 0.1056 | 0.1379 | -37.6% |
| collection-mutation | 0.0092 | 0.0126 | +27.7% |
| collection-selection-update | 0.0017 | 0.0029 | -39.5% |
| hud-binding-storm | 0.3499 | 0.3627 | -1.3% |
| motion-declarative | 0.8779 | 1.6539 | -13.2% |
| motion-explicit | 1.3485 | 2.1380 | +5.2% |
| mount-ramp | 89.4163 | 107.6982 | -41.9% |
| mount-ramp-inherited | 149.9755 | 163.6555 | +24.6% |
| mounted-slice-update-storm | 0.1565 | 0.2209 | -27.1% |
| outline-measured-update | 2.1104 | 3.7085 | +7.1% |
| reserved-slot-record-update | 0.4799 | 1.0572 | -30.7% |
| settings-churn | 0.0162 | 0.0179 | +12.3% |
| sparse-update-under-load | 0.0014 | 0.0015 | -41.8% |
| table-mutation | 0.3887 | 0.4935 | +28.3% |
| table-resize-drag | 2.0040 | 3.6956 | -34.9% |
| table-sort-values | 1.3838 | 1.8588 | -1.9% |
| table-source-refresh | 0.1832 | 0.3598 | -2.5% |
| textinput-typing-storm | 0.2794 | 0.4964 | +25.3% |
| timer-readout-storm | 0.0914 | 1.4652 | -46.6% |
| zz-yardstick-cpu-after | 1.2940 | 1.2984 | +0.7% |
| zz-yardstick-cpu-before | 1.2871 | 1.2941 | +0.4% |

## Scene p50 over the last 5 main commits

```mermaid
xychart-beta
    title "adaptive-navigation-images (p50 ms)"
    x-axis 1 --> 5
    line [0.9159, 1.3609, 0.9193, 1.3288, 1.2245]
```

```mermaid
xychart-beta
    title "alert-present-dismiss (p50 ms)"
    x-axis 1 --> 5
    line [2.3284, 2.5432, 2.6957, 3.5058, 3.6611]
```

```mermaid
xychart-beta
    title "animation-interruption (p50 ms)"
    x-axis 1 --> 5
    line [0.0242, 0.0301, 0.0381, 0.0290, 0.0220]
```

```mermaid
xychart-beta
    title "async-image-burst (p50 ms)"
    x-axis 1 --> 5
    line [0.0288, 0.0459, 0.0389, 0.0449, 0.0266]
```

```mermaid
xychart-beta
    title "async-image-grid (p50 ms)"
    x-axis 1 --> 5
    line [1.6953, 2.7184, 1.8124, 2.6543, 1.7415]
```

```mermaid
xychart-beta
    title "collection-mutation (p50 ms)"
    x-axis 1 --> 5
    line [0.3332, 0.4681, 0.3201, 0.4622, 0.4560]
```

```mermaid
xychart-beta
    title "control-motion (p50 ms)"
    x-axis 1 --> 5
    line [0.1407, 0.1565, 0.1807, 0.2262, 0.2422]
```

```mermaid
xychart-beta
    title "dense-hud (p50 ms)"
    x-axis 1 --> 5
    line [0.1402, 0.1574, 0.1997, 0.1472, 0.1114]
```

```mermaid
xychart-beta
    title "dense-motion (p50 ms)"
    x-axis 1 --> 5
    line [1.1243, 1.3144, 1.5562, 1.2159, 1.0340]
```

```mermaid
xychart-beta
    title "hud-binding-storm (p50 ms)"
    x-axis 1 --> 5
    line [0.1858, 0.2630, 0.2187, 0.2586, 0.1741]
```

```mermaid
xychart-beta
    title "lab-collection-churn (p50 ms)"
    x-axis 1 --> 5
    line [0.2396, 0.2475, 0.3195, 0.3675, 0.2530]
```

```mermaid
xychart-beta
    title "lab-dense-scroll (p50 ms)"
    x-axis 1 --> 5
    line [0.7446, 0.8751, 0.9218, 0.7244, 0.7929]
```

```mermaid
xychart-beta
    title "locale-textsize-change (p50 ms)"
    x-axis 1 --> 5
    line [0.0152, 0.0201, 0.0267, 0.0304, 0.0349]
```

```mermaid
xychart-beta
    title "native-scroll-drag (p50 ms)"
    x-axis 1 --> 5
    line [0.0464, 0.0583, 0.0482, 0.0561, 0.0672]
```

```mermaid
xychart-beta
    title "navigation-customization (p50 ms)"
    x-axis 1 --> 5
    line [0.0348, 0.0504, 0.0668, 0.0455, 0.0376]
```

```mermaid
xychart-beta
    title "picker-menu-open-close (p50 ms)"
    x-axis 1 --> 5
    line [5.1020, 6.6154, 4.6873, 6.5076, 4.5232]
```

```mermaid
xychart-beta
    title "picker-segmented-textsize (p50 ms)"
    x-axis 1 --> 5
    line [0.0576, 0.0616, 0.0841, 0.0581, 0.0762]
```

```mermaid
xychart-beta
    title "radial-menu-open-close (p50 ms)"
    x-axis 1 --> 5
    line [9.1824, 9.6461, 9.8160, 12.9977, 8.2964]
```

```mermaid
xychart-beta
    title "screen-lifecycle-churn (p50 ms)"
    x-axis 1 --> 5
    line [11.6362, 13.3303, 15.6277, 11.4367, 15.2702]
```

```mermaid
xychart-beta
    title "scroll-focus-traversal (p50 ms)"
    x-axis 1 --> 5
    line [0.1893, 0.1954, 0.2948, 0.3595, 0.2060]
```

```mermaid
xychart-beta
    title "settings-churn (p50 ms)"
    x-axis 1 --> 5
    line [2.4831, 3.3595, 3.8546, 2.7052, 3.5707]
```

```mermaid
xychart-beta
    title "shadow-storm (p50 ms)"
    x-axis 1 --> 5
    line [0.0005, 0.0005, 0.0006, 0.0005, 0.0006]
```

```mermaid
xychart-beta
    title "stylesheet-state-churn (p50 ms)"
    x-axis 1 --> 5
    line [0.2123, 0.2752, 0.3220, 0.3838, 0.4071]
```

```mermaid
xychart-beta
    title "theme-swap-assets (p50 ms)"
    x-axis 1 --> 5
    line [1.5921, 2.1494, 1.6336, 2.1480, 1.2452]
```

```mermaid
xychart-beta
    title "theme-swap-flat (p50 ms)"
    x-axis 1 --> 5
    line [0.3449, 0.3183, 0.4072, 0.4900, 0.2916]
```

```mermaid
xychart-beta
    title "theme-swap-metrics (p50 ms)"
    x-axis 1 --> 5
    line [1.2519, 1.6733, 1.3190, 1.6705, 1.6681]
```

```mermaid
xychart-beta
    title "virtual-list-scroll (p50 ms)"
    x-axis 1 --> 5
    line [0.1263, 0.1363, 0.1356, 0.1842, 0.1329]
```
