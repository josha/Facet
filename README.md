# Facet performance

Latest: `1b698e4c19085b3cf63150ebe804d79e7e318564` on 2026-10-26T185124Z, measured on the CI Ubuntu runner by the paired performance shards.
Times are milliseconds per frame or operation: the median over paired rounds of each round's p50 and p95.
Retained heap is the scene's mounted retained Luau heap. Change compares the p50 of the previous main commit.

| Scene | p50 ms | p95 ms | Retained KiB | Change |
| --- | ---: | ---: | ---: | ---: |
| adaptive-navigation-images | 1.3615 | 1.7822 | 9157 | +11.2% |
| alert-present-dismiss | 2.3918 | 3.8426 | 6820 | -34.7% |
| animation-interruption | 0.0383 | 0.0453 | 4814 | +74.3% |
| async-image-burst | 0.0450 | 0.0524 | 4978 | +69.1% |
| async-image-grid | 2.7336 | 4.2576 | 6615 | +57.0% |
| collection-mutation | 0.2881 | 0.4255 | 8202 | -36.8% |
| control-motion | 0.2560 | 0.7485 | 6326 | +5.7% |
| dense-hud | 0.1957 | 0.2172 | 5252 | +75.7% |
| dense-motion | 1.5887 | 2.5445 | 5876 | +53.6% |
| hud-binding-storm | 0.2640 | 0.2859 | 4917 | +51.7% |
| lab-collection-churn | 0.4143 | 0.7524 | 9084 | +63.8% |
| lab-dense-scroll | 0.5928 | 3.6507 | 12163 | -25.2% |
| locale-textsize-change | 0.0344 | 0.0444 | 4933 | -1.3% |
| native-scroll-drag | 0.0581 | 0.0794 | 6365 | -13.5% |
| navigation-customization | 0.0661 | 0.0787 | 9149 | +75.6% |
| picker-menu-open-close | 6.6400 | 9.2420 | 5365 | +46.8% |
| picker-segmented-textsize | 0.0847 | 0.1054 | 5458 | +11.1% |
| radial-menu-open-close | 12.9826 | 21.2947 | 6188 | +56.5% |
| screen-lifecycle-churn | 16.3829 | 28.0692 | 6052 | +7.3% |
| scroll-focus-traversal | 0.4169 | 0.5955 | 5863 | +102.4% |
| settings-churn | 4.0222 | 5.9284 | 6921 | +12.6% |
| shadow-storm | 0.0003 | 0.0011 | 6448 | -46.5% |
| stylesheet-state-churn | 0.2450 | 0.4867 | 7647 | -39.8% |
| theme-swap-assets | 2.1218 | 2.5461 | 9572 | +70.4% |
| theme-swap-flat | 0.5121 | 0.6092 | 8814 | +75.6% |
| theme-swap-metrics | 1.0387 | 1.2719 | 9449 | -37.7% |
| virtual-list-scroll | 0.2108 | 0.4592 | 10204 | +58.6% |

| Microbenchmark | p50 ms | p95 ms | Change |
| --- | ---: | ---: | ---: |
| billboard-nameplate-storm | 0.1701 | 0.1983 | +61.0% |
| collection-mutation | 0.0083 | 0.0108 | -10.0% |
| collection-selection-update | 0.0031 | 0.0048 | +82.5% |
| hud-binding-storm | 0.2067 | 0.2148 | -40.9% |
| motion-declarative | 1.2404 | 2.0335 | +41.3% |
| motion-explicit | 1.2917 | 2.0728 | -4.2% |
| mount-ramp | 148.6554 | 167.2170 | +66.3% |
| mount-ramp-inherited | 94.8015 | 111.1359 | -36.8% |
| mounted-slice-update-storm | 0.2466 | 0.3133 | +57.6% |
| outline-measured-update | 2.1033 | 3.5710 | -0.3% |
| reserved-slot-record-update | 0.8498 | 1.3829 | +77.1% |
| settings-churn | 0.0078 | 0.0087 | -51.8% |
| sparse-update-under-load | 0.0024 | 0.0026 | +76.2% |
| table-mutation | 0.4446 | 0.5721 | +14.4% |
| table-resize-drag | 3.2496 | 5.2873 | +62.2% |
| table-sort-values | 0.8819 | 1.4399 | -36.3% |
| table-source-refresh | 0.3111 | 0.4572 | +69.8% |
| textinput-typing-storm | 0.2700 | 0.4722 | -3.3% |
| timer-readout-storm | 0.1625 | 2.4448 | +77.9% |
| zz-yardstick-cpu-after | 1.3153 | 1.3426 | +1.6% |
| zz-yardstick-cpu-before | 1.2909 | 1.2996 | +0.3% |

## Scene p50 over the last 6 main commits

```mermaid
xychart-beta
    title "adaptive-navigation-images (p50 ms)"
    x-axis 1 --> 6
    line [0.9159, 1.3609, 0.9193, 1.3288, 1.2245, 1.3615]
```

```mermaid
xychart-beta
    title "alert-present-dismiss (p50 ms)"
    x-axis 1 --> 6
    line [2.3284, 2.5432, 2.6957, 3.5058, 3.6611, 2.3918]
```

```mermaid
xychart-beta
    title "animation-interruption (p50 ms)"
    x-axis 1 --> 6
    line [0.0242, 0.0301, 0.0381, 0.0290, 0.0220, 0.0383]
```

```mermaid
xychart-beta
    title "async-image-burst (p50 ms)"
    x-axis 1 --> 6
    line [0.0288, 0.0459, 0.0389, 0.0449, 0.0266, 0.0450]
```

```mermaid
xychart-beta
    title "async-image-grid (p50 ms)"
    x-axis 1 --> 6
    line [1.6953, 2.7184, 1.8124, 2.6543, 1.7415, 2.7336]
```

```mermaid
xychart-beta
    title "collection-mutation (p50 ms)"
    x-axis 1 --> 6
    line [0.3332, 0.4681, 0.3201, 0.4622, 0.4560, 0.2881]
```

```mermaid
xychart-beta
    title "control-motion (p50 ms)"
    x-axis 1 --> 6
    line [0.1407, 0.1565, 0.1807, 0.2262, 0.2422, 0.2560]
```

```mermaid
xychart-beta
    title "dense-hud (p50 ms)"
    x-axis 1 --> 6
    line [0.1402, 0.1574, 0.1997, 0.1472, 0.1114, 0.1957]
```

```mermaid
xychart-beta
    title "dense-motion (p50 ms)"
    x-axis 1 --> 6
    line [1.1243, 1.3144, 1.5562, 1.2159, 1.0340, 1.5887]
```

```mermaid
xychart-beta
    title "hud-binding-storm (p50 ms)"
    x-axis 1 --> 6
    line [0.1858, 0.2630, 0.2187, 0.2586, 0.1741, 0.2640]
```

```mermaid
xychart-beta
    title "lab-collection-churn (p50 ms)"
    x-axis 1 --> 6
    line [0.2396, 0.2475, 0.3195, 0.3675, 0.2530, 0.4143]
```

```mermaid
xychart-beta
    title "lab-dense-scroll (p50 ms)"
    x-axis 1 --> 6
    line [0.7446, 0.8751, 0.9218, 0.7244, 0.7929, 0.5928]
```

```mermaid
xychart-beta
    title "locale-textsize-change (p50 ms)"
    x-axis 1 --> 6
    line [0.0152, 0.0201, 0.0267, 0.0304, 0.0349, 0.0344]
```

```mermaid
xychart-beta
    title "native-scroll-drag (p50 ms)"
    x-axis 1 --> 6
    line [0.0464, 0.0583, 0.0482, 0.0561, 0.0672, 0.0581]
```

```mermaid
xychart-beta
    title "navigation-customization (p50 ms)"
    x-axis 1 --> 6
    line [0.0348, 0.0504, 0.0668, 0.0455, 0.0376, 0.0661]
```

```mermaid
xychart-beta
    title "picker-menu-open-close (p50 ms)"
    x-axis 1 --> 6
    line [5.1020, 6.6154, 4.6873, 6.5076, 4.5232, 6.6400]
```

```mermaid
xychart-beta
    title "picker-segmented-textsize (p50 ms)"
    x-axis 1 --> 6
    line [0.0576, 0.0616, 0.0841, 0.0581, 0.0762, 0.0847]
```

```mermaid
xychart-beta
    title "radial-menu-open-close (p50 ms)"
    x-axis 1 --> 6
    line [9.1824, 9.6461, 9.8160, 12.9977, 8.2964, 12.9826]
```

```mermaid
xychart-beta
    title "screen-lifecycle-churn (p50 ms)"
    x-axis 1 --> 6
    line [11.6362, 13.3303, 15.6277, 11.4367, 15.2702, 16.3829]
```

```mermaid
xychart-beta
    title "scroll-focus-traversal (p50 ms)"
    x-axis 1 --> 6
    line [0.1893, 0.1954, 0.2948, 0.3595, 0.2060, 0.4169]
```

```mermaid
xychart-beta
    title "settings-churn (p50 ms)"
    x-axis 1 --> 6
    line [2.4831, 3.3595, 3.8546, 2.7052, 3.5707, 4.0222]
```

```mermaid
xychart-beta
    title "shadow-storm (p50 ms)"
    x-axis 1 --> 6
    line [0.0005, 0.0005, 0.0006, 0.0005, 0.0006, 0.0003]
```

```mermaid
xychart-beta
    title "stylesheet-state-churn (p50 ms)"
    x-axis 1 --> 6
    line [0.2123, 0.2752, 0.3220, 0.3838, 0.4071, 0.2450]
```

```mermaid
xychart-beta
    title "theme-swap-assets (p50 ms)"
    x-axis 1 --> 6
    line [1.5921, 2.1494, 1.6336, 2.1480, 1.2452, 2.1218]
```

```mermaid
xychart-beta
    title "theme-swap-flat (p50 ms)"
    x-axis 1 --> 6
    line [0.3449, 0.3183, 0.4072, 0.4900, 0.2916, 0.5121]
```

```mermaid
xychart-beta
    title "theme-swap-metrics (p50 ms)"
    x-axis 1 --> 6
    line [1.2519, 1.6733, 1.3190, 1.6705, 1.6681, 1.0387]
```

```mermaid
xychart-beta
    title "virtual-list-scroll (p50 ms)"
    x-axis 1 --> 6
    line [0.1263, 0.1363, 0.1356, 0.1842, 0.1329, 0.2108]
```
