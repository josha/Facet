# Facet performance

Latest: `b7b5da08e2e8f57ac293c6388a5c56610866c9d9` on 2026-11-06T053831Z, measured on the CI Ubuntu runner by the paired performance shards.
Times are milliseconds per frame or operation: the median over paired rounds of each round's p50 and p95.
Retained heap is the scene's mounted retained Luau heap. Change compares the p50 with the previous main commit measured in the same paired shard, on the same runner.

| Scene | p50 ms | p95 ms | Retained KiB | Change |
| --- | ---: | ---: | ---: | ---: |
| adaptive-navigation-images | 0.8224 | 0.9156 | 3951 | -0.8% |
| alert-present-dismiss | 2.6974 | 4.2063 | 9377 | +1.3% |
| animation-interruption | 0.0325 | 0.0351 | 392 | +5.3% |
| async-image-burst | 0.0306 | 0.0357 | 491 | +2.2% |
| async-image-grid | 2.2886 | 3.7671 | 2722 | +2.5% |
| collection-mutation | 0.3018 | 0.3291 | 2981 | -0.0% |
| control-motion | 0.1234 | 0.4260 | 1800 | -3.0% |
| dense-hud | 0.1129 | 0.1248 | 748 | +7.4% |
| dense-motion | 0.9177 | 1.3484 | 1627 | -0.8% |
| hud-binding-storm | 0.2143 | 0.2289 | 471 | -0.9% |
| lab-collection-churn | 0.3819 | 0.5547 | 5055 | +4.5% |
| lab-dense-scroll | 0.1526 | 0.2211 | 6092 | +5.2% |
| locale-textsize-change | 0.0210 | 0.0238 | 542 | +0.1% |
| native-scroll-drag | 0.0311 | 0.0463 | 1899 | +0.6% |
| navigation-customization | 0.0331 | 0.0383 | 3809 | +0.4% |
| picker-menu-open-close | 6.1012 | 8.8796 | 16083 | +3.0% |
| picker-segmented-textsize | 0.0427 | 0.0503 | 930 | -11.5% |
| radial-menu-open-close | 2.2244 | 3.0500 | 6741 | +1.4% |
| screen-lifecycle-churn | 9.7896 | 15.1552 | 27160 | -1.4% |
| scroll-focus-traversal | 0.2861 | 0.4569 | 1247 | +0.6% |
| settings-churn | 2.5629 | 4.0811 | 9378 | +3.7% |
| shadow-storm | 0.0006 | 0.0007 | 1969 | +3.2% |
| stylesheet-state-churn | 0.3098 | 0.3392 | 2592 | -0.3% |
| theme-swap-assets | 1.1609 | 1.5063 | 7108 | -0.5% |
| theme-swap-flat | 0.3142 | 0.3429 | 4496 | +0.0% |
| theme-swap-metrics | 1.4187 | 1.6796 | 6151 | +0.4% |
| virtual-list-scroll | 0.1325 | 0.1937 | 4275 | +0.1% |

| Microbenchmark | p50 ms | p95 ms | Change |
| --- | ---: | ---: | ---: |
| billboard-nameplate-storm | 0.1550 | 0.1699 | +0.1% |
| collection-mutation | 0.0074 | 0.0101 | +0.8% |
| collection-selection-update | 0.0020 | 0.0023 | -1.0% |
| hud-binding-storm | 0.3390 | 0.3532 | -0.8% |
| motion-declarative | 0.8542 | 1.1316 | +1.4% |
| motion-explicit | 0.6560 | 0.9393 | -1.4% |
| mount-ramp | 135.7286 | 156.6694 | -1.2% |
| mount-ramp-inherited | 156.9780 | 176.3436 | +0.4% |
| mounted-slice-update-storm | 0.2155 | 0.2293 | +0.5% |
| outline-measured-update | 1.0202 | 1.3750 | +1.2% |
| reserved-slot-record-update | 0.4617 | 0.4820 | +3.6% |
| settings-churn | 0.0133 | 0.0172 | +1.1% |
| sparse-update-under-load | 0.0024 | 0.0026 | +0.8% |
| table-mutation | 0.1943 | 0.2366 | -1.4% |
| table-resize-drag | 1.0146 | 1.3763 | +0.1% |
| table-sort-values | 0.9630 | 1.2346 | -1.4% |
| table-source-refresh | 0.2163 | 0.4079 | +1.0% |
| textinput-typing-storm | 0.1914 | 0.3277 | +2.0% |
| timer-readout-storm | 0.1185 | 0.5380 | +0.7% |
| zz-yardstick-cpu-after | 1.2635 | 1.2707 | -0.6% |
| zz-yardstick-cpu-before | 1.1696 | 1.2028 | +0.3% |

## Scene p50 over the last 12 main commits

```mermaid
xychart-beta
    title "adaptive-navigation-images (p50 ms)"
    x-axis 1 --> 12
    line [0.8330, 1.1721, 1.1465, 1.1515, 0.8551, 1.1733, 0.7309, 0.8622, 1.1462, 1.1328, 1.0062, 0.8224]
```

```mermaid
xychart-beta
    title "alert-present-dismiss (p50 ms)"
    x-axis 1 --> 12
    line [2.9632, 2.9538, 2.9589, 2.1244, 2.9396, 2.1232, 3.0157, 1.8028, 3.1043, 2.8834, 2.1588, 2.6974]
```

```mermaid
xychart-beta
    title "animation-interruption (p50 ms)"
    x-axis 1 --> 12
    line [0.0236, 0.0159, 0.0306, 0.0316, 0.0309, 0.0270, 0.0309, 0.0158, 0.0157, 0.0311, 0.0236, 0.0325]
```

```mermaid
xychart-beta
    title "async-image-burst (p50 ms)"
    x-axis 1 --> 12
    line [0.0357, 0.0192, 0.0388, 0.0351, 0.0294, 0.0299, 0.0379, 0.0352, 0.0356, 0.0344, 0.0313, 0.0306]
```

```mermaid
xychart-beta
    title "async-image-grid (p50 ms)"
    x-axis 1 --> 12
    line [1.4898, 1.3778, 2.2419, 2.2404, 2.2280, 2.1194, 2.1310, 1.3834, 1.2964, 2.2208, 1.5015, 2.2886]
```

```mermaid
xychart-beta
    title "collection-mutation (p50 ms)"
    x-axis 1 --> 12
    line [0.3063, 0.3360, 0.3400, 0.2349, 0.3341, 0.2370, 0.3128, 0.1996, 0.3392, 0.3005, 0.2394, 0.3018]
```

```mermaid
xychart-beta
    title "control-motion (p50 ms)"
    x-axis 1 --> 12
    line [0.1272, 0.1810, 0.1801, 0.1813, 0.1326, 0.1801, 0.1085, 0.1359, 0.1815, 0.1779, 0.1572, 0.1234]
```

```mermaid
xychart-beta
    title "dense-hud (p50 ms)"
    x-axis 1 --> 12
    line [0.1428, 0.0755, 0.1379, 0.1416, 0.1070, 0.1087, 0.1342, 0.1394, 0.1426, 0.1422, 0.1125, 0.1129]
```

```mermaid
xychart-beta
    title "dense-motion (p50 ms)"
    x-axis 1 --> 12
    line [0.7269, 0.5529, 0.9128, 0.9089, 0.9130, 0.8166, 0.8911, 0.5818, 0.5534, 0.9168, 0.7211, 0.9177]
```

```mermaid
xychart-beta
    title "hud-binding-storm (p50 ms)"
    x-axis 1 --> 12
    line [0.1859, 0.1272, 0.2142, 0.2163, 0.2139, 0.2076, 0.2091, 0.1199, 0.1190, 0.2144, 0.1859, 0.2143]
```

```mermaid
xychart-beta
    title "lab-collection-churn (p50 ms)"
    x-axis 1 --> 12
    line [0.2870, 0.2054, 0.3706, 0.3769, 0.3702, 0.3267, 0.3462, 0.2042, 0.2173, 0.3750, 0.2859, 0.3819]
```

```mermaid
xychart-beta
    title "lab-dense-scroll (p50 ms)"
    x-axis 1 --> 12
    line [0.1688, 0.1559, 0.1552, 0.1139, 0.1575, 0.1144, 0.1724, 0.0890, 0.1580, 0.1640, 0.1204, 0.1526]
```

```mermaid
xychart-beta
    title "locale-textsize-change (p50 ms)"
    x-axis 1 --> 12
    line [0.0212, 0.0294, 0.0296, 0.0295, 0.0210, 0.0299, 0.0141, 0.0208, 0.0297, 0.0299, 0.0245, 0.0210]
```

```mermaid
xychart-beta
    title "native-scroll-drag (p50 ms)"
    x-axis 1 --> 12
    line [0.0313, 0.0356, 0.0355, 0.0364, 0.0271, 0.0358, 0.0226, 0.0274, 0.0353, 0.0363, 0.0460, 0.0311]
```

```mermaid
xychart-beta
    title "navigation-customization (p50 ms)"
    x-axis 1 --> 12
    line [0.0505, 0.0296, 0.0412, 0.0500, 0.0315, 0.0315, 0.0409, 0.0503, 0.0505, 0.0518, 0.0323, 0.0331]
```

```mermaid
xychart-beta
    title "picker-menu-open-close (p50 ms)"
    x-axis 1 --> 12
    line [4.0174, 3.4024, 5.4017, 5.4631, 5.2994, 5.3502, 5.1493, 3.5447, 3.4388, 5.7846, 4.3066, 6.1012]
```

```mermaid
xychart-beta
    title "picker-segmented-textsize (p50 ms)"
    x-axis 1 --> 12
    line [0.0429, 0.0662, 0.0669, 0.0660, 0.0481, 0.0663, 0.0367, 0.0489, 0.0664, 0.0665, 0.0566, 0.0427]
```

```mermaid
xychart-beta
    title "radial-menu-open-close (p50 ms)"
    x-axis 1 --> 12
    line [3.1112, 1.8589, 2.7809, 3.0636, 2.1657, 2.2270, 2.7740, 3.0517, 3.0986, 3.0720, 2.2117, 2.2244]
```

```mermaid
xychart-beta
    title "screen-lifecycle-churn (p50 ms)"
    x-axis 1 --> 12
    line [10.3266, 13.6779, 13.3474, 13.7228, 11.0919, 14.2328, 9.1106, 11.1435, 13.8748, 13.4354, 13.5508, 9.7896]
```

```mermaid
xychart-beta
    title "scroll-focus-traversal (p50 ms)"
    x-axis 1 --> 12
    line [0.3840, 0.1980, 0.3674, 0.3885, 0.2842, 0.2843, 0.3612, 0.3833, 0.3936, 0.3824, 0.2869, 0.2861]
```

```mermaid
xychart-beta
    title "settings-churn (p50 ms)"
    x-axis 1 --> 12
    line [2.5856, 3.6434, 3.6307, 3.7213, 2.8691, 3.6590, 2.3185, 2.8613, 3.6309, 3.5904, 3.4048, 2.5629]
```

```mermaid
xychart-beta
    title "shadow-storm (p50 ms)"
    x-axis 1 --> 12
    line [0.0005, 0.0005, 0.0005, 0.0005, 0.0005, 0.0005, 0.0005, 0.0003, 0.0006, 0.0005, 0.0005, 0.0006]
```

```mermaid
xychart-beta
    title "stylesheet-state-churn (p50 ms)"
    x-axis 1 --> 12
    line [0.3080, 0.3324, 0.3378, 0.2450, 0.3339, 0.2453, 0.3057, 0.1919, 0.3329, 0.3043, 0.2484, 0.3098]
```

```mermaid
xychart-beta
    title "theme-swap-assets (p50 ms)"
    x-axis 1 --> 12
    line [1.5349, 0.9322, 1.4603, 1.5391, 1.1393, 1.1376, 1.4492, 1.5263, 1.5323, 1.5306, 1.1498, 1.1609]
```

```mermaid
xychart-beta
    title "theme-swap-flat (p50 ms)"
    x-axis 1 --> 12
    line [0.3972, 0.2391, 0.4068, 0.3985, 0.3119, 0.3118, 0.3948, 0.3955, 0.3978, 0.4037, 0.3121, 0.3142]
```

```mermaid
xychart-beta
    title "theme-swap-metrics (p50 ms)"
    x-axis 1 --> 12
    line [1.3783, 1.3845, 1.3991, 1.0991, 1.3897, 1.0599, 1.3071, 0.7848, 1.3567, 1.3755, 1.1092, 1.4187]
```

```mermaid
xychart-beta
    title "virtual-list-scroll (p50 ms)"
    x-axis 1 --> 12
    line [0.0907, 0.0831, 0.1330, 0.1330, 0.1317, 0.1262, 0.1258, 0.0822, 0.0828, 0.1312, 0.0923, 0.1325]
```
