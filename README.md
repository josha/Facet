# Facet performance

Latest: `8c32c1f3224b9510adcd0105773376bb54f7d470` on 2026-11-06T005121Z, measured on the CI Ubuntu runner by the paired performance shards.
Times are milliseconds per frame or operation: the median over paired rounds of each round's p50 and p95.
Retained heap is the scene's mounted retained Luau heap. Change compares the p50 of the previous main commit.

| Scene | p50 ms | p95 ms | Retained KiB | Change |
| --- | ---: | ---: | ---: | ---: |
| adaptive-navigation-images | 0.8551 | 0.9831 | 3915 | -25.7% |
| alert-present-dismiss | 2.9396 | 4.2368 | 9383 | +38.4% |
| animation-interruption | 0.0309 | 0.0337 | 389 | -2.2% |
| async-image-burst | 0.0294 | 0.0346 | 489 | -16.3% |
| async-image-grid | 2.2280 | 3.6060 | 2720 | -0.6% |
| collection-mutation | 0.3341 | 0.3633 | 2978 | +42.2% |
| control-motion | 0.1326 | 0.4601 | 1753 | -26.9% |
| dense-hud | 0.1070 | 0.1190 | 752 | -24.4% |
| dense-motion | 0.9130 | 1.2387 | 1629 | +0.5% |
| hud-binding-storm | 0.2139 | 0.2310 | 469 | -1.1% |
| lab-collection-churn | 0.3702 | 0.5185 | 4887 | -1.8% |
| lab-dense-scroll | 0.1575 | 0.2483 | 5918 | +38.3% |
| locale-textsize-change | 0.0210 | 0.0229 | 515 | -28.8% |
| native-scroll-drag | 0.0271 | 0.0342 | 1903 | -25.5% |
| navigation-customization | 0.0315 | 0.0370 | 3757 | -36.9% |
| picker-menu-open-close | 5.2994 | 8.0561 | 15941 | -3.0% |
| picker-segmented-textsize | 0.0481 | 0.0539 | 919 | -27.1% |
| radial-menu-open-close | 2.1657 | 2.7874 | 6666 | -29.3% |
| screen-lifecycle-churn | 11.0919 | 15.2871 | 26840 | -19.2% |
| scroll-focus-traversal | 0.2842 | 0.4294 | 1244 | -26.8% |
| settings-churn | 2.8691 | 4.1216 | 9375 | -22.9% |
| shadow-storm | 0.0005 | 0.0006 | 1966 | +15.4% |
| stylesheet-state-churn | 0.3339 | 0.3673 | 2590 | +36.3% |
| theme-swap-assets | 1.1393 | 1.4115 | 7068 | -26.0% |
| theme-swap-flat | 0.3119 | 0.3416 | 4464 | -21.7% |
| theme-swap-metrics | 1.3897 | 1.6566 | 6102 | +26.4% |
| virtual-list-scroll | 0.1317 | 0.1853 | 4279 | -1.0% |

| Microbenchmark | p50 ms | p95 ms | Change |
| --- | ---: | ---: | ---: |
| billboard-nameplate-storm | 0.1537 | 0.1677 | -0.6% |
| collection-mutation | 0.0070 | 0.0092 | -16.6% |
| collection-selection-update | 0.0020 | 0.0024 | -16.3% |
| hud-binding-storm | 0.3174 | 0.3323 | +19.7% |
| motion-declarative | 0.8181 | 1.0944 | -2.0% |
| motion-explicit | 0.6287 | 0.8641 | -23.3% |
| mount-ramp | 126.3140 | 144.2294 | -25.8% |
| mount-ramp-inherited | 165.7569 | 186.2666 | +29.8% |
| mounted-slice-update-storm | 0.2095 | 0.2222 | -2.3% |
| outline-measured-update | 1.0249 | 1.4341 | -20.4% |
| reserved-slot-record-update | 0.4462 | 0.4648 | -27.4% |
| settings-churn | 0.0164 | 0.0175 | +59.2% |
| sparse-update-under-load | 0.0024 | 0.0025 | +0.4% |
| table-mutation | 0.2208 | 0.2676 | -22.1% |
| table-resize-drag | 0.9969 | 1.3809 | -32.2% |
| table-sort-values | 1.0442 | 1.2526 | +38.1% |
| table-source-refresh | 0.2103 | 0.3661 | -2.4% |
| textinput-typing-storm | 0.1749 | 0.2874 | -24.9% |
| timer-readout-storm | 0.1173 | 0.5346 | -14.5% |
| zz-yardstick-cpu-after | 1.2552 | 1.2668 | -3.8% |
| zz-yardstick-cpu-before | 1.1868 | 1.1973 | -8.2% |

## Scene p50 over the last 5 main commits

```mermaid
xychart-beta
    title "adaptive-navigation-images (p50 ms)"
    x-axis 1 --> 5
    line [0.8330, 1.1721, 1.1465, 1.1515, 0.8551]
```

```mermaid
xychart-beta
    title "alert-present-dismiss (p50 ms)"
    x-axis 1 --> 5
    line [2.9632, 2.9538, 2.9589, 2.1244, 2.9396]
```

```mermaid
xychart-beta
    title "animation-interruption (p50 ms)"
    x-axis 1 --> 5
    line [0.0236, 0.0159, 0.0306, 0.0316, 0.0309]
```

```mermaid
xychart-beta
    title "async-image-burst (p50 ms)"
    x-axis 1 --> 5
    line [0.0357, 0.0192, 0.0388, 0.0351, 0.0294]
```

```mermaid
xychart-beta
    title "async-image-grid (p50 ms)"
    x-axis 1 --> 5
    line [1.4898, 1.3778, 2.2419, 2.2404, 2.2280]
```

```mermaid
xychart-beta
    title "collection-mutation (p50 ms)"
    x-axis 1 --> 5
    line [0.3063, 0.3360, 0.3400, 0.2349, 0.3341]
```

```mermaid
xychart-beta
    title "control-motion (p50 ms)"
    x-axis 1 --> 5
    line [0.1272, 0.1810, 0.1801, 0.1813, 0.1326]
```

```mermaid
xychart-beta
    title "dense-hud (p50 ms)"
    x-axis 1 --> 5
    line [0.1428, 0.0755, 0.1379, 0.1416, 0.1070]
```

```mermaid
xychart-beta
    title "dense-motion (p50 ms)"
    x-axis 1 --> 5
    line [0.7269, 0.5529, 0.9128, 0.9089, 0.9130]
```

```mermaid
xychart-beta
    title "hud-binding-storm (p50 ms)"
    x-axis 1 --> 5
    line [0.1859, 0.1272, 0.2142, 0.2163, 0.2139]
```

```mermaid
xychart-beta
    title "lab-collection-churn (p50 ms)"
    x-axis 1 --> 5
    line [0.2870, 0.2054, 0.3706, 0.3769, 0.3702]
```

```mermaid
xychart-beta
    title "lab-dense-scroll (p50 ms)"
    x-axis 1 --> 5
    line [0.1688, 0.1559, 0.1552, 0.1139, 0.1575]
```

```mermaid
xychart-beta
    title "locale-textsize-change (p50 ms)"
    x-axis 1 --> 5
    line [0.0212, 0.0294, 0.0296, 0.0295, 0.0210]
```

```mermaid
xychart-beta
    title "native-scroll-drag (p50 ms)"
    x-axis 1 --> 5
    line [0.0313, 0.0356, 0.0355, 0.0364, 0.0271]
```

```mermaid
xychart-beta
    title "navigation-customization (p50 ms)"
    x-axis 1 --> 5
    line [0.0505, 0.0296, 0.0412, 0.0500, 0.0315]
```

```mermaid
xychart-beta
    title "picker-menu-open-close (p50 ms)"
    x-axis 1 --> 5
    line [4.0174, 3.4024, 5.4017, 5.4631, 5.2994]
```

```mermaid
xychart-beta
    title "picker-segmented-textsize (p50 ms)"
    x-axis 1 --> 5
    line [0.0429, 0.0662, 0.0669, 0.0660, 0.0481]
```

```mermaid
xychart-beta
    title "radial-menu-open-close (p50 ms)"
    x-axis 1 --> 5
    line [3.1112, 1.8589, 2.7809, 3.0636, 2.1657]
```

```mermaid
xychart-beta
    title "screen-lifecycle-churn (p50 ms)"
    x-axis 1 --> 5
    line [10.3266, 13.6779, 13.3474, 13.7228, 11.0919]
```

```mermaid
xychart-beta
    title "scroll-focus-traversal (p50 ms)"
    x-axis 1 --> 5
    line [0.3840, 0.1980, 0.3674, 0.3885, 0.2842]
```

```mermaid
xychart-beta
    title "settings-churn (p50 ms)"
    x-axis 1 --> 5
    line [2.5856, 3.6434, 3.6307, 3.7213, 2.8691]
```

```mermaid
xychart-beta
    title "shadow-storm (p50 ms)"
    x-axis 1 --> 5
    line [0.0005, 0.0005, 0.0005, 0.0005, 0.0005]
```

```mermaid
xychart-beta
    title "stylesheet-state-churn (p50 ms)"
    x-axis 1 --> 5
    line [0.3080, 0.3324, 0.3378, 0.2450, 0.3339]
```

```mermaid
xychart-beta
    title "theme-swap-assets (p50 ms)"
    x-axis 1 --> 5
    line [1.5349, 0.9322, 1.4603, 1.5391, 1.1393]
```

```mermaid
xychart-beta
    title "theme-swap-flat (p50 ms)"
    x-axis 1 --> 5
    line [0.3972, 0.2391, 0.4068, 0.3985, 0.3119]
```

```mermaid
xychart-beta
    title "theme-swap-metrics (p50 ms)"
    x-axis 1 --> 5
    line [1.3783, 1.3845, 1.3991, 1.0991, 1.3897]
```

```mermaid
xychart-beta
    title "virtual-list-scroll (p50 ms)"
    x-axis 1 --> 5
    line [0.0907, 0.0831, 0.1330, 0.1330, 0.1317]
```
