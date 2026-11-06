# Facet performance

Latest: `a6779489f1395e0a6743650dbf7ba5acdce3ab81` on 2026-11-06T033839Z, measured on the CI Ubuntu runner by the paired performance shards.
Times are milliseconds per frame or operation: the median over paired rounds of each round's p50 and p95.
Retained heap is the scene's mounted retained Luau heap. Change compares the p50 with the previous main commit measured in the same paired shard, on the same runner.

| Scene | p50 ms | p95 ms | Retained KiB | Change |
| --- | ---: | ---: | ---: | ---: |
| adaptive-navigation-images | 1.1462 | 1.2207 | 3948 | -2.7% |
| alert-present-dismiss | 3.1043 | 4.4273 | 9393 | +3.4% |
| animation-interruption | 0.0157 | 0.0163 | 383 | -3.2% |
| async-image-burst | 0.0356 | 0.0427 | 483 | -0.2% |
| async-image-grid | 1.2964 | 2.2057 | 2722 | -3.4% |
| collection-mutation | 0.3392 | 0.3837 | 2980 | -1.1% |
| control-motion | 0.1815 | 0.5660 | 1764 | -1.0% |
| dense-hud | 0.1426 | 0.1585 | 752 | +0.1% |
| dense-motion | 0.5534 | 0.7991 | 1619 | -0.5% |
| hud-binding-storm | 0.1190 | 0.1269 | 471 | -1.5% |
| lab-collection-churn | 0.2173 | 0.3381 | 4889 | +6.2% |
| lab-dense-scroll | 0.1580 | 0.2521 | 5932 | +1.2% |
| locale-textsize-change | 0.0297 | 0.0328 | 534 | +0.6% |
| native-scroll-drag | 0.0353 | 0.0496 | 1906 | -1.3% |
| navigation-customization | 0.0505 | 0.0605 | 3790 | -1.8% |
| picker-menu-open-close | 3.4388 | 5.4702 | 15434 | -1.6% |
| picker-segmented-textsize | 0.0664 | 0.0804 | 913 | -0.9% |
| radial-menu-open-close | 3.0986 | 4.1396 | 6669 | +1.8% |
| screen-lifecycle-churn | 13.8748 | 19.8208 | 27022 | +1.3% |
| scroll-focus-traversal | 0.3936 | 0.5882 | 1247 | +0.5% |
| settings-churn | 3.6309 | 5.1823 | 9377 | +1.5% |
| shadow-storm | 0.0006 | 0.0006 | 1961 | +1.8% |
| stylesheet-state-churn | 0.3329 | 0.3703 | 2592 | +0.5% |
| theme-swap-assets | 1.5323 | 1.9014 | 7081 | -1.0% |
| theme-swap-flat | 0.3978 | 0.4430 | 4477 | -1.6% |
| theme-swap-metrics | 1.3567 | 1.6483 | 6123 | -2.6% |
| virtual-list-scroll | 0.0828 | 0.1157 | 4281 | -0.0% |

| Microbenchmark | p50 ms | p95 ms | Change |
| --- | ---: | ---: | ---: |
| billboard-nameplate-storm | 0.0853 | 0.0945 | -2.1% |
| collection-mutation | 0.0084 | 0.0115 | +0.2% |
| collection-selection-update | 0.0024 | 0.0033 | +1.7% |
| hud-binding-storm | 0.3210 | 0.3347 | +1.3% |
| motion-declarative | 0.4687 | 0.6945 | +4.9% |
| motion-explicit | 0.8309 | 1.1323 | +3.1% |
| mount-ramp | 170.5265 | 186.8802 | +0.3% |
| mount-ramp-inherited | 171.2735 | 187.3431 | +0.1% |
| mounted-slice-update-storm | 0.1166 | 0.1241 | +1.9% |
| outline-measured-update | 1.2938 | 1.6444 | -0.1% |
| reserved-slot-record-update | 0.6137 | 0.6466 | +2.2% |
| settings-churn | 0.0173 | 0.0206 | +4.2% |
| sparse-update-under-load | 0.0013 | 0.0014 | -1.5% |
| table-mutation | 0.2816 | 0.3301 | -0.3% |
| table-resize-drag | 1.4667 | 1.9486 | +0.1% |
| table-sort-values | 1.0371 | 1.2816 | -0.9% |
| table-source-refresh | 0.1195 | 0.2525 | +1.3% |
| textinput-typing-storm | 0.2260 | 0.3715 | -2.0% |
| timer-readout-storm | 0.1382 | 0.6526 | -0.2% |
| zz-yardstick-cpu-after | 1.3245 | 1.3430 | +0.3% |
| zz-yardstick-cpu-before | 1.2977 | 1.3142 | +0.5% |

## Scene p50 over the last 9 main commits

```mermaid
xychart-beta
    title "adaptive-navigation-images (p50 ms)"
    x-axis 1 --> 9
    line [0.8330, 1.1721, 1.1465, 1.1515, 0.8551, 1.1733, 0.7309, 0.8622, 1.1462]
```

```mermaid
xychart-beta
    title "alert-present-dismiss (p50 ms)"
    x-axis 1 --> 9
    line [2.9632, 2.9538, 2.9589, 2.1244, 2.9396, 2.1232, 3.0157, 1.8028, 3.1043]
```

```mermaid
xychart-beta
    title "animation-interruption (p50 ms)"
    x-axis 1 --> 9
    line [0.0236, 0.0159, 0.0306, 0.0316, 0.0309, 0.0270, 0.0309, 0.0158, 0.0157]
```

```mermaid
xychart-beta
    title "async-image-burst (p50 ms)"
    x-axis 1 --> 9
    line [0.0357, 0.0192, 0.0388, 0.0351, 0.0294, 0.0299, 0.0379, 0.0352, 0.0356]
```

```mermaid
xychart-beta
    title "async-image-grid (p50 ms)"
    x-axis 1 --> 9
    line [1.4898, 1.3778, 2.2419, 2.2404, 2.2280, 2.1194, 2.1310, 1.3834, 1.2964]
```

```mermaid
xychart-beta
    title "collection-mutation (p50 ms)"
    x-axis 1 --> 9
    line [0.3063, 0.3360, 0.3400, 0.2349, 0.3341, 0.2370, 0.3128, 0.1996, 0.3392]
```

```mermaid
xychart-beta
    title "control-motion (p50 ms)"
    x-axis 1 --> 9
    line [0.1272, 0.1810, 0.1801, 0.1813, 0.1326, 0.1801, 0.1085, 0.1359, 0.1815]
```

```mermaid
xychart-beta
    title "dense-hud (p50 ms)"
    x-axis 1 --> 9
    line [0.1428, 0.0755, 0.1379, 0.1416, 0.1070, 0.1087, 0.1342, 0.1394, 0.1426]
```

```mermaid
xychart-beta
    title "dense-motion (p50 ms)"
    x-axis 1 --> 9
    line [0.7269, 0.5529, 0.9128, 0.9089, 0.9130, 0.8166, 0.8911, 0.5818, 0.5534]
```

```mermaid
xychart-beta
    title "hud-binding-storm (p50 ms)"
    x-axis 1 --> 9
    line [0.1859, 0.1272, 0.2142, 0.2163, 0.2139, 0.2076, 0.2091, 0.1199, 0.1190]
```

```mermaid
xychart-beta
    title "lab-collection-churn (p50 ms)"
    x-axis 1 --> 9
    line [0.2870, 0.2054, 0.3706, 0.3769, 0.3702, 0.3267, 0.3462, 0.2042, 0.2173]
```

```mermaid
xychart-beta
    title "lab-dense-scroll (p50 ms)"
    x-axis 1 --> 9
    line [0.1688, 0.1559, 0.1552, 0.1139, 0.1575, 0.1144, 0.1724, 0.0890, 0.1580]
```

```mermaid
xychart-beta
    title "locale-textsize-change (p50 ms)"
    x-axis 1 --> 9
    line [0.0212, 0.0294, 0.0296, 0.0295, 0.0210, 0.0299, 0.0141, 0.0208, 0.0297]
```

```mermaid
xychart-beta
    title "native-scroll-drag (p50 ms)"
    x-axis 1 --> 9
    line [0.0313, 0.0356, 0.0355, 0.0364, 0.0271, 0.0358, 0.0226, 0.0274, 0.0353]
```

```mermaid
xychart-beta
    title "navigation-customization (p50 ms)"
    x-axis 1 --> 9
    line [0.0505, 0.0296, 0.0412, 0.0500, 0.0315, 0.0315, 0.0409, 0.0503, 0.0505]
```

```mermaid
xychart-beta
    title "picker-menu-open-close (p50 ms)"
    x-axis 1 --> 9
    line [4.0174, 3.4024, 5.4017, 5.4631, 5.2994, 5.3502, 5.1493, 3.5447, 3.4388]
```

```mermaid
xychart-beta
    title "picker-segmented-textsize (p50 ms)"
    x-axis 1 --> 9
    line [0.0429, 0.0662, 0.0669, 0.0660, 0.0481, 0.0663, 0.0367, 0.0489, 0.0664]
```

```mermaid
xychart-beta
    title "radial-menu-open-close (p50 ms)"
    x-axis 1 --> 9
    line [3.1112, 1.8589, 2.7809, 3.0636, 2.1657, 2.2270, 2.7740, 3.0517, 3.0986]
```

```mermaid
xychart-beta
    title "screen-lifecycle-churn (p50 ms)"
    x-axis 1 --> 9
    line [10.3266, 13.6779, 13.3474, 13.7228, 11.0919, 14.2328, 9.1106, 11.1435, 13.8748]
```

```mermaid
xychart-beta
    title "scroll-focus-traversal (p50 ms)"
    x-axis 1 --> 9
    line [0.3840, 0.1980, 0.3674, 0.3885, 0.2842, 0.2843, 0.3612, 0.3833, 0.3936]
```

```mermaid
xychart-beta
    title "settings-churn (p50 ms)"
    x-axis 1 --> 9
    line [2.5856, 3.6434, 3.6307, 3.7213, 2.8691, 3.6590, 2.3185, 2.8613, 3.6309]
```

```mermaid
xychart-beta
    title "shadow-storm (p50 ms)"
    x-axis 1 --> 9
    line [0.0005, 0.0005, 0.0005, 0.0005, 0.0005, 0.0005, 0.0005, 0.0003, 0.0006]
```

```mermaid
xychart-beta
    title "stylesheet-state-churn (p50 ms)"
    x-axis 1 --> 9
    line [0.3080, 0.3324, 0.3378, 0.2450, 0.3339, 0.2453, 0.3057, 0.1919, 0.3329]
```

```mermaid
xychart-beta
    title "theme-swap-assets (p50 ms)"
    x-axis 1 --> 9
    line [1.5349, 0.9322, 1.4603, 1.5391, 1.1393, 1.1376, 1.4492, 1.5263, 1.5323]
```

```mermaid
xychart-beta
    title "theme-swap-flat (p50 ms)"
    x-axis 1 --> 9
    line [0.3972, 0.2391, 0.4068, 0.3985, 0.3119, 0.3118, 0.3948, 0.3955, 0.3978]
```

```mermaid
xychart-beta
    title "theme-swap-metrics (p50 ms)"
    x-axis 1 --> 9
    line [1.3783, 1.3845, 1.3991, 1.0991, 1.3897, 1.0599, 1.3071, 0.7848, 1.3567]
```

```mermaid
xychart-beta
    title "virtual-list-scroll (p50 ms)"
    x-axis 1 --> 9
    line [0.0907, 0.0831, 0.1330, 0.1330, 0.1317, 0.1262, 0.1258, 0.0822, 0.0828]
```
