# Facet performance

Latest: `43cc3d691f6fc93278c169817abf47ea27583256` on 2026-11-06T013251Z, measured on the CI Ubuntu runner by the paired performance shards.
Times are milliseconds per frame or operation: the median over paired rounds of each round's p50 and p95.
Retained heap is the scene's mounted retained Luau heap. Change compares the p50 with the previous main commit measured in the same paired shard, on the same runner.

| Scene | p50 ms | p95 ms | Retained KiB | Change |
| --- | ---: | ---: | ---: | ---: |
| adaptive-navigation-images | 0.8622 | 0.9408 | 3944 | -0.0% |
| alert-present-dismiss | 1.8028 | 2.7431 | 9369 | +0.0% |
| animation-interruption | 0.0158 | 0.0165 | 383 | +1.6% |
| async-image-burst | 0.0352 | 0.0412 | 499 | +1.2% |
| async-image-grid | 1.3834 | 2.5134 | 2726 | +0.1% |
| collection-mutation | 0.1996 | 0.2152 | 2980 | -0.1% |
| control-motion | 0.1359 | 0.4640 | 1760 | +2.0% |
| dense-hud | 0.1394 | 0.1567 | 748 | -2.0% |
| dense-motion | 0.5818 | 0.8978 | 1659 | +3.4% |
| hud-binding-storm | 0.1199 | 0.1322 | 479 | -1.3% |
| lab-collection-churn | 0.2042 | 0.3492 | 4899 | -0.2% |
| lab-dense-scroll | 0.0890 | 0.1375 | 5924 | +1.4% |
| locale-textsize-change | 0.0208 | 0.0231 | 530 | -0.4% |
| native-scroll-drag | 0.0274 | 0.0337 | 1906 | -14.6% |
| navigation-customization | 0.0503 | 0.0578 | 3790 | -0.3% |
| picker-menu-open-close | 3.5447 | 6.0644 | 15685 | -0.3% |
| picker-segmented-textsize | 0.0489 | 0.0569 | 913 | +2.4% |
| radial-menu-open-close | 3.0517 | 3.8394 | 6668 | +2.2% |
| screen-lifecycle-churn | 11.1435 | 16.1264 | 27001 | -0.7% |
| scroll-focus-traversal | 0.3833 | 0.5560 | 1239 | -2.0% |
| settings-churn | 2.8613 | 4.0767 | 9377 | +2.6% |
| shadow-storm | 0.0003 | 0.0003 | 1961 | -3.6% |
| stylesheet-state-churn | 0.1919 | 0.2120 | 2592 | +5.6% |
| theme-swap-assets | 1.5263 | 1.8389 | 7081 | +1.2% |
| theme-swap-flat | 0.3955 | 0.4423 | 4477 | -0.0% |
| theme-swap-metrics | 0.7848 | 0.9248 | 6107 | -1.0% |
| virtual-list-scroll | 0.0822 | 0.1226 | 4273 | -6.0% |

| Microbenchmark | p50 ms | p95 ms | Change |
| --- | ---: | ---: | ---: |
| billboard-nameplate-storm | 0.0837 | 0.0918 | +1.6% |
| collection-mutation | 0.0070 | 0.0091 | +0.5% |
| collection-selection-update | 0.0023 | 0.0027 | -0.0% |
| hud-binding-storm | 0.1645 | 0.1720 | -1.3% |
| motion-declarative | 0.4759 | 0.7232 | +0.4% |
| motion-explicit | 0.6295 | 0.8651 | -0.6% |
| mount-ramp | 164.5490 | 183.2887 | +0.9% |
| mount-ramp-inherited | 94.7749 | 108.0301 | -0.7% |
| mounted-slice-update-storm | 0.1176 | 0.1269 | +0.1% |
| outline-measured-update | 1.0263 | 1.4191 | -0.6% |
| reserved-slot-record-update | 0.6036 | 0.6523 | -1.0% |
| settings-churn | 0.0091 | 0.0110 | +13.1% |
| sparse-update-under-load | 0.0013 | 0.0014 | +0.4% |
| table-mutation | 0.2206 | 0.2624 | +0.4% |
| table-resize-drag | 1.4486 | 1.9286 | +1.2% |
| table-sort-values | 0.6002 | 0.7552 | +1.2% |
| table-source-refresh | 0.1121 | 0.2671 | -6.1% |
| textinput-typing-storm | 0.1761 | 0.2853 | +0.1% |
| timer-readout-storm | 0.1381 | 0.6504 | -0.3% |
| zz-yardstick-cpu-after | 0.9257 | 0.9571 | -0.8% |
| zz-yardstick-cpu-before | 0.9224 | 0.9740 | -0.9% |

## Scene p50 over the last 8 main commits

```mermaid
xychart-beta
    title "adaptive-navigation-images (p50 ms)"
    x-axis 1 --> 8
    line [0.8330, 1.1721, 1.1465, 1.1515, 0.8551, 1.1733, 0.7309, 0.8622]
```

```mermaid
xychart-beta
    title "alert-present-dismiss (p50 ms)"
    x-axis 1 --> 8
    line [2.9632, 2.9538, 2.9589, 2.1244, 2.9396, 2.1232, 3.0157, 1.8028]
```

```mermaid
xychart-beta
    title "animation-interruption (p50 ms)"
    x-axis 1 --> 8
    line [0.0236, 0.0159, 0.0306, 0.0316, 0.0309, 0.0270, 0.0309, 0.0158]
```

```mermaid
xychart-beta
    title "async-image-burst (p50 ms)"
    x-axis 1 --> 8
    line [0.0357, 0.0192, 0.0388, 0.0351, 0.0294, 0.0299, 0.0379, 0.0352]
```

```mermaid
xychart-beta
    title "async-image-grid (p50 ms)"
    x-axis 1 --> 8
    line [1.4898, 1.3778, 2.2419, 2.2404, 2.2280, 2.1194, 2.1310, 1.3834]
```

```mermaid
xychart-beta
    title "collection-mutation (p50 ms)"
    x-axis 1 --> 8
    line [0.3063, 0.3360, 0.3400, 0.2349, 0.3341, 0.2370, 0.3128, 0.1996]
```

```mermaid
xychart-beta
    title "control-motion (p50 ms)"
    x-axis 1 --> 8
    line [0.1272, 0.1810, 0.1801, 0.1813, 0.1326, 0.1801, 0.1085, 0.1359]
```

```mermaid
xychart-beta
    title "dense-hud (p50 ms)"
    x-axis 1 --> 8
    line [0.1428, 0.0755, 0.1379, 0.1416, 0.1070, 0.1087, 0.1342, 0.1394]
```

```mermaid
xychart-beta
    title "dense-motion (p50 ms)"
    x-axis 1 --> 8
    line [0.7269, 0.5529, 0.9128, 0.9089, 0.9130, 0.8166, 0.8911, 0.5818]
```

```mermaid
xychart-beta
    title "hud-binding-storm (p50 ms)"
    x-axis 1 --> 8
    line [0.1859, 0.1272, 0.2142, 0.2163, 0.2139, 0.2076, 0.2091, 0.1199]
```

```mermaid
xychart-beta
    title "lab-collection-churn (p50 ms)"
    x-axis 1 --> 8
    line [0.2870, 0.2054, 0.3706, 0.3769, 0.3702, 0.3267, 0.3462, 0.2042]
```

```mermaid
xychart-beta
    title "lab-dense-scroll (p50 ms)"
    x-axis 1 --> 8
    line [0.1688, 0.1559, 0.1552, 0.1139, 0.1575, 0.1144, 0.1724, 0.0890]
```

```mermaid
xychart-beta
    title "locale-textsize-change (p50 ms)"
    x-axis 1 --> 8
    line [0.0212, 0.0294, 0.0296, 0.0295, 0.0210, 0.0299, 0.0141, 0.0208]
```

```mermaid
xychart-beta
    title "native-scroll-drag (p50 ms)"
    x-axis 1 --> 8
    line [0.0313, 0.0356, 0.0355, 0.0364, 0.0271, 0.0358, 0.0226, 0.0274]
```

```mermaid
xychart-beta
    title "navigation-customization (p50 ms)"
    x-axis 1 --> 8
    line [0.0505, 0.0296, 0.0412, 0.0500, 0.0315, 0.0315, 0.0409, 0.0503]
```

```mermaid
xychart-beta
    title "picker-menu-open-close (p50 ms)"
    x-axis 1 --> 8
    line [4.0174, 3.4024, 5.4017, 5.4631, 5.2994, 5.3502, 5.1493, 3.5447]
```

```mermaid
xychart-beta
    title "picker-segmented-textsize (p50 ms)"
    x-axis 1 --> 8
    line [0.0429, 0.0662, 0.0669, 0.0660, 0.0481, 0.0663, 0.0367, 0.0489]
```

```mermaid
xychart-beta
    title "radial-menu-open-close (p50 ms)"
    x-axis 1 --> 8
    line [3.1112, 1.8589, 2.7809, 3.0636, 2.1657, 2.2270, 2.7740, 3.0517]
```

```mermaid
xychart-beta
    title "screen-lifecycle-churn (p50 ms)"
    x-axis 1 --> 8
    line [10.3266, 13.6779, 13.3474, 13.7228, 11.0919, 14.2328, 9.1106, 11.1435]
```

```mermaid
xychart-beta
    title "scroll-focus-traversal (p50 ms)"
    x-axis 1 --> 8
    line [0.3840, 0.1980, 0.3674, 0.3885, 0.2842, 0.2843, 0.3612, 0.3833]
```

```mermaid
xychart-beta
    title "settings-churn (p50 ms)"
    x-axis 1 --> 8
    line [2.5856, 3.6434, 3.6307, 3.7213, 2.8691, 3.6590, 2.3185, 2.8613]
```

```mermaid
xychart-beta
    title "shadow-storm (p50 ms)"
    x-axis 1 --> 8
    line [0.0005, 0.0005, 0.0005, 0.0005, 0.0005, 0.0005, 0.0005, 0.0003]
```

```mermaid
xychart-beta
    title "stylesheet-state-churn (p50 ms)"
    x-axis 1 --> 8
    line [0.3080, 0.3324, 0.3378, 0.2450, 0.3339, 0.2453, 0.3057, 0.1919]
```

```mermaid
xychart-beta
    title "theme-swap-assets (p50 ms)"
    x-axis 1 --> 8
    line [1.5349, 0.9322, 1.4603, 1.5391, 1.1393, 1.1376, 1.4492, 1.5263]
```

```mermaid
xychart-beta
    title "theme-swap-flat (p50 ms)"
    x-axis 1 --> 8
    line [0.3972, 0.2391, 0.4068, 0.3985, 0.3119, 0.3118, 0.3948, 0.3955]
```

```mermaid
xychart-beta
    title "theme-swap-metrics (p50 ms)"
    x-axis 1 --> 8
    line [1.3783, 1.3845, 1.3991, 1.0991, 1.3897, 1.0599, 1.3071, 0.7848]
```

```mermaid
xychart-beta
    title "virtual-list-scroll (p50 ms)"
    x-axis 1 --> 8
    line [0.0907, 0.0831, 0.1330, 0.1330, 0.1317, 0.1262, 0.1258, 0.0822]
```
