# Facet performance

Latest: `e6f3589d9ab928fd980c3acaa86b985eb9fc2d0e` on 2026-11-06T011636Z, measured on the CI Ubuntu runner by the paired performance shards.
Times are milliseconds per frame or operation: the median over paired rounds of each round's p50 and p95.
Retained heap is the scene's mounted retained Luau heap. Change compares the p50 of the previous main commit.

| Scene | p50 ms | p95 ms | Retained KiB | Change |
| --- | ---: | ---: | ---: | ---: |
| adaptive-navigation-images | 0.7309 | 0.8287 | 3948 | -37.7% |
| alert-present-dismiss | 3.0157 | 4.4636 | 9403 | +42.0% |
| animation-interruption | 0.0309 | 0.0339 | 383 | +14.3% |
| async-image-burst | 0.0379 | 0.0449 | 499 | +26.6% |
| async-image-grid | 2.1310 | 3.3076 | 2722 | +0.5% |
| collection-mutation | 0.3128 | 0.3463 | 2980 | +32.0% |
| control-motion | 0.1085 | 0.3714 | 1748 | -39.7% |
| dense-hud | 0.1342 | 0.1454 | 747 | +23.5% |
| dense-motion | 0.8911 | 1.1323 | 1623 | +9.1% |
| hud-binding-storm | 0.2091 | 0.2236 | 470 | +0.7% |
| lab-collection-churn | 0.3462 | 0.4868 | 4912 | +6.0% |
| lab-dense-scroll | 0.1724 | 0.2273 | 5940 | +50.7% |
| locale-textsize-change | 0.0141 | 0.0158 | 533 | -52.9% |
| native-scroll-drag | 0.0226 | 0.0398 | 1906 | -37.1% |
| navigation-customization | 0.0409 | 0.0474 | 3790 | +29.7% |
| picker-menu-open-close | 5.1493 | 7.5513 | 15972 | -3.8% |
| picker-segmented-textsize | 0.0367 | 0.0409 | 921 | -44.6% |
| radial-menu-open-close | 2.7740 | 3.8272 | 6669 | +24.6% |
| screen-lifecycle-churn | 9.1106 | 14.9006 | 27088 | -36.0% |
| scroll-focus-traversal | 0.3612 | 0.5358 | 1239 | +27.1% |
| settings-churn | 2.3185 | 3.6561 | 9361 | -36.6% |
| shadow-storm | 0.0005 | 0.0006 | 1961 | +14.1% |
| stylesheet-state-churn | 0.3057 | 0.3559 | 2584 | +24.6% |
| theme-swap-assets | 1.4492 | 1.8165 | 7081 | +27.4% |
| theme-swap-flat | 0.3948 | 0.4393 | 4477 | +26.6% |
| theme-swap-metrics | 1.3071 | 1.6341 | 6123 | +23.3% |
| virtual-list-scroll | 0.1258 | 0.1768 | 4272 | -0.3% |

| Microbenchmark | p50 ms | p95 ms | Change |
| --- | ---: | ---: | ---: |
| billboard-nameplate-storm | 0.1540 | 0.1673 | +7.3% |
| collection-mutation | 0.0058 | 0.0079 | -31.3% |
| collection-selection-update | 0.0026 | 0.0029 | +32.1% |
| hud-binding-storm | 0.2924 | 0.3029 | +10.4% |
| motion-declarative | 0.7873 | 1.0291 | +1.1% |
| motion-explicit | 0.4786 | 0.7238 | -42.5% |
| mount-ramp | 158.5316 | 176.2486 | +26.0% |
| mount-ramp-inherited | 191.0591 | 207.7581 | +54.0% |
| mounted-slice-update-storm | 0.2088 | 0.2213 | -1.6% |
| outline-measured-update | 0.7634 | 1.0992 | -42.0% |
| reserved-slot-record-update | 0.5732 | 0.5934 | +21.1% |
| settings-churn | 0.0155 | 0.0167 | +42.7% |
| sparse-update-under-load | 0.0024 | 0.0025 | +8.8% |
| table-mutation | 0.1789 | 0.2209 | -37.5% |
| table-resize-drag | 1.2566 | 1.6411 | +25.8% |
| table-sort-values | 0.9633 | 1.3078 | +27.6% |
| table-source-refresh | 0.2097 | 0.3572 | +8.6% |
| textinput-typing-storm | 0.1364 | 0.3269 | -41.4% |
| timer-readout-storm | 0.1522 | 0.6848 | +29.2% |
| zz-yardstick-cpu-after | 1.2899 | 1.3033 | +4.1% |
| zz-yardstick-cpu-before | 1.2921 | 1.2980 | +12.5% |

## Scene p50 over the last 7 main commits

```mermaid
xychart-beta
    title "adaptive-navigation-images (p50 ms)"
    x-axis 1 --> 7
    line [0.8330, 1.1721, 1.1465, 1.1515, 0.8551, 1.1733, 0.7309]
```

```mermaid
xychart-beta
    title "alert-present-dismiss (p50 ms)"
    x-axis 1 --> 7
    line [2.9632, 2.9538, 2.9589, 2.1244, 2.9396, 2.1232, 3.0157]
```

```mermaid
xychart-beta
    title "animation-interruption (p50 ms)"
    x-axis 1 --> 7
    line [0.0236, 0.0159, 0.0306, 0.0316, 0.0309, 0.0270, 0.0309]
```

```mermaid
xychart-beta
    title "async-image-burst (p50 ms)"
    x-axis 1 --> 7
    line [0.0357, 0.0192, 0.0388, 0.0351, 0.0294, 0.0299, 0.0379]
```

```mermaid
xychart-beta
    title "async-image-grid (p50 ms)"
    x-axis 1 --> 7
    line [1.4898, 1.3778, 2.2419, 2.2404, 2.2280, 2.1194, 2.1310]
```

```mermaid
xychart-beta
    title "collection-mutation (p50 ms)"
    x-axis 1 --> 7
    line [0.3063, 0.3360, 0.3400, 0.2349, 0.3341, 0.2370, 0.3128]
```

```mermaid
xychart-beta
    title "control-motion (p50 ms)"
    x-axis 1 --> 7
    line [0.1272, 0.1810, 0.1801, 0.1813, 0.1326, 0.1801, 0.1085]
```

```mermaid
xychart-beta
    title "dense-hud (p50 ms)"
    x-axis 1 --> 7
    line [0.1428, 0.0755, 0.1379, 0.1416, 0.1070, 0.1087, 0.1342]
```

```mermaid
xychart-beta
    title "dense-motion (p50 ms)"
    x-axis 1 --> 7
    line [0.7269, 0.5529, 0.9128, 0.9089, 0.9130, 0.8166, 0.8911]
```

```mermaid
xychart-beta
    title "hud-binding-storm (p50 ms)"
    x-axis 1 --> 7
    line [0.1859, 0.1272, 0.2142, 0.2163, 0.2139, 0.2076, 0.2091]
```

```mermaid
xychart-beta
    title "lab-collection-churn (p50 ms)"
    x-axis 1 --> 7
    line [0.2870, 0.2054, 0.3706, 0.3769, 0.3702, 0.3267, 0.3462]
```

```mermaid
xychart-beta
    title "lab-dense-scroll (p50 ms)"
    x-axis 1 --> 7
    line [0.1688, 0.1559, 0.1552, 0.1139, 0.1575, 0.1144, 0.1724]
```

```mermaid
xychart-beta
    title "locale-textsize-change (p50 ms)"
    x-axis 1 --> 7
    line [0.0212, 0.0294, 0.0296, 0.0295, 0.0210, 0.0299, 0.0141]
```

```mermaid
xychart-beta
    title "native-scroll-drag (p50 ms)"
    x-axis 1 --> 7
    line [0.0313, 0.0356, 0.0355, 0.0364, 0.0271, 0.0358, 0.0226]
```

```mermaid
xychart-beta
    title "navigation-customization (p50 ms)"
    x-axis 1 --> 7
    line [0.0505, 0.0296, 0.0412, 0.0500, 0.0315, 0.0315, 0.0409]
```

```mermaid
xychart-beta
    title "picker-menu-open-close (p50 ms)"
    x-axis 1 --> 7
    line [4.0174, 3.4024, 5.4017, 5.4631, 5.2994, 5.3502, 5.1493]
```

```mermaid
xychart-beta
    title "picker-segmented-textsize (p50 ms)"
    x-axis 1 --> 7
    line [0.0429, 0.0662, 0.0669, 0.0660, 0.0481, 0.0663, 0.0367]
```

```mermaid
xychart-beta
    title "radial-menu-open-close (p50 ms)"
    x-axis 1 --> 7
    line [3.1112, 1.8589, 2.7809, 3.0636, 2.1657, 2.2270, 2.7740]
```

```mermaid
xychart-beta
    title "screen-lifecycle-churn (p50 ms)"
    x-axis 1 --> 7
    line [10.3266, 13.6779, 13.3474, 13.7228, 11.0919, 14.2328, 9.1106]
```

```mermaid
xychart-beta
    title "scroll-focus-traversal (p50 ms)"
    x-axis 1 --> 7
    line [0.3840, 0.1980, 0.3674, 0.3885, 0.2842, 0.2843, 0.3612]
```

```mermaid
xychart-beta
    title "settings-churn (p50 ms)"
    x-axis 1 --> 7
    line [2.5856, 3.6434, 3.6307, 3.7213, 2.8691, 3.6590, 2.3185]
```

```mermaid
xychart-beta
    title "shadow-storm (p50 ms)"
    x-axis 1 --> 7
    line [0.0005, 0.0005, 0.0005, 0.0005, 0.0005, 0.0005, 0.0005]
```

```mermaid
xychart-beta
    title "stylesheet-state-churn (p50 ms)"
    x-axis 1 --> 7
    line [0.3080, 0.3324, 0.3378, 0.2450, 0.3339, 0.2453, 0.3057]
```

```mermaid
xychart-beta
    title "theme-swap-assets (p50 ms)"
    x-axis 1 --> 7
    line [1.5349, 0.9322, 1.4603, 1.5391, 1.1393, 1.1376, 1.4492]
```

```mermaid
xychart-beta
    title "theme-swap-flat (p50 ms)"
    x-axis 1 --> 7
    line [0.3972, 0.2391, 0.4068, 0.3985, 0.3119, 0.3118, 0.3948]
```

```mermaid
xychart-beta
    title "theme-swap-metrics (p50 ms)"
    x-axis 1 --> 7
    line [1.3783, 1.3845, 1.3991, 1.0991, 1.3897, 1.0599, 1.3071]
```

```mermaid
xychart-beta
    title "virtual-list-scroll (p50 ms)"
    x-axis 1 --> 7
    line [0.0907, 0.0831, 0.1330, 0.1330, 0.1317, 0.1262, 0.1258]
```
