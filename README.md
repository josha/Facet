# Facet performance

Latest: `320b23e68d251a0e33f2e3ef170a1dd11a91a46e` on 2026-11-06T072735Z, measured on the CI Ubuntu runner by the paired performance shards.
Times are milliseconds per frame or operation: the median over paired rounds of each round's p50 and p95.
Retained heap is the scene's mounted retained Luau heap. Change compares the p50 with the previous main commit measured in the same paired shard, on the same runner.

| Scene | p50 ms | p95 ms | Retained KiB | Change |
| --- | ---: | ---: | ---: | ---: |
| adaptive-navigation-images | 0.8328 | 0.9506 | 3931 | +0.6% |
| alert-present-dismiss | 2.9085 | 3.9934 | 9394 | +2.0% |
| animation-interruption | 0.0323 | 0.0354 | 384 | +4.2% |
| async-image-burst | 0.0354 | 0.0408 | 483 | -2.1% |
| async-image-grid | 2.2404 | 3.6925 | 2722 | +0.8% |
| collection-mutation | 0.3298 | 0.3700 | 2978 | -1.1% |
| control-motion | 0.1274 | 0.4464 | 1799 | +2.0% |
| dense-hud | 0.1424 | 0.1583 | 755 | -0.1% |
| dense-motion | 0.9196 | 1.2292 | 1647 | -0.3% |
| hud-binding-storm | 0.2141 | 0.2372 | 479 | +0.8% |
| lab-collection-churn | 0.3673 | 0.5289 | 5044 | +0.3% |
| lab-dense-scroll | 0.1567 | 0.2431 | 6079 | -0.5% |
| locale-textsize-change | 0.0209 | 0.0236 | 534 | -0.8% |
| native-scroll-drag | 0.0311 | 0.0494 | 1891 | -0.9% |
| navigation-customization | 0.0503 | 0.0609 | 3780 | -1.6% |
| picker-menu-open-close | 5.7919 | 8.4149 | 16075 | -2.1% |
| picker-segmented-textsize | 0.0436 | 0.0506 | 913 | +1.4% |
| radial-menu-open-close | 3.1048 | 4.0728 | 6741 | +1.9% |
| screen-lifecycle-churn | 10.1460 | 16.0509 | 27147 | -1.5% |
| scroll-focus-traversal | 0.3899 | 0.5805 | 1247 | -0.2% |
| settings-churn | 2.5694 | 4.1369 | 9298 | +1.4% |
| shadow-storm | 0.0006 | 0.0007 | 1961 | +2.0% |
| stylesheet-state-churn | 0.3260 | 0.3706 | 2593 | -0.7% |
| theme-swap-assets | 1.5404 | 1.8732 | 7107 | -0.0% |
| theme-swap-flat | 0.4005 | 0.4355 | 4511 | -0.7% |
| theme-swap-metrics | 1.3846 | 1.6076 | 6149 | +2.3% |
| virtual-list-scroll | 0.1328 | 0.1857 | 4267 | -0.0% |

| Microbenchmark | p50 ms | p95 ms | Change |
| --- | ---: | ---: | ---: |
| billboard-nameplate-storm | 0.1541 | 0.1693 | -1.2% |
| collection-mutation | 0.0074 | 0.0099 | +0.1% |
| collection-selection-update | 0.0024 | 0.0028 | +1.3% |
| hud-binding-storm | 0.3153 | 0.3312 | +3.0% |
| motion-declarative | 0.8426 | 1.1501 | +1.2% |
| motion-explicit | 0.6702 | 0.9519 | +0.4% |
| mount-ramp | 172.7962 | 188.5364 | +0.6% |
| mount-ramp-inherited | 160.2586 | 179.1198 | -0.2% |
| mounted-slice-update-storm | 0.2136 | 0.2271 | +0.2% |
| outline-measured-update | 1.0502 | 1.4075 | +2.9% |
| reserved-slot-record-update | 0.6098 | 0.6437 | +2.8% |
| settings-churn | 0.0165 | 0.0180 | -2.0% |
| sparse-update-under-load | 0.0024 | 0.0025 | +0.8% |
| table-mutation | 0.1947 | 0.2437 | +0.2% |
| table-resize-drag | 1.4695 | 2.0170 | -0.3% |
| table-sort-values | 1.0481 | 1.2534 | +1.0% |
| table-source-refresh | 0.2155 | 0.3990 | +2.0% |
| textinput-typing-storm | 0.1888 | 0.3333 | -2.1% |
| timer-readout-storm | 0.1440 | 0.6646 | +4.4% |
| zz-yardstick-cpu-after | 1.3125 | 1.3291 | -3.0% |
| zz-yardstick-cpu-before | 1.2898 | 1.2984 | -0.4% |

## Scene p50 over the last 15 main commits

```mermaid
xychart-beta
    title "adaptive-navigation-images (p50 ms)"
    x-axis 1 --> 15
    line [0.8330, 1.1721, 1.1465, 1.1515, 0.8551, 1.1733, 0.7309, 0.8622, 1.1462, 1.1328, 1.0062, 0.8224, 1.1973, 1.1845, 0.8328]
```

```mermaid
xychart-beta
    title "alert-present-dismiss (p50 ms)"
    x-axis 1 --> 15
    line [2.9632, 2.9538, 2.9589, 2.1244, 2.9396, 2.1232, 3.0157, 1.8028, 3.1043, 2.8834, 2.1588, 2.6974, 2.1643, 2.9862, 2.9085]
```

```mermaid
xychart-beta
    title "animation-interruption (p50 ms)"
    x-axis 1 --> 15
    line [0.0236, 0.0159, 0.0306, 0.0316, 0.0309, 0.0270, 0.0309, 0.0158, 0.0157, 0.0311, 0.0236, 0.0325, 0.0205, 0.0231, 0.0323]
```

```mermaid
xychart-beta
    title "async-image-burst (p50 ms)"
    x-axis 1 --> 15
    line [0.0357, 0.0192, 0.0388, 0.0351, 0.0294, 0.0299, 0.0379, 0.0352, 0.0356, 0.0344, 0.0313, 0.0306, 0.0329, 0.0356, 0.0354]
```

```mermaid
xychart-beta
    title "async-image-grid (p50 ms)"
    x-axis 1 --> 15
    line [1.4898, 1.3778, 2.2419, 2.2404, 2.2280, 2.1194, 2.1310, 1.3834, 1.2964, 2.2208, 1.5015, 2.2886, 1.5200, 1.4868, 2.2404]
```

```mermaid
xychart-beta
    title "collection-mutation (p50 ms)"
    x-axis 1 --> 15
    line [0.3063, 0.3360, 0.3400, 0.2349, 0.3341, 0.2370, 0.3128, 0.1996, 0.3392, 0.3005, 0.2394, 0.3018, 0.2393, 0.3345, 0.3298]
```

```mermaid
xychart-beta
    title "control-motion (p50 ms)"
    x-axis 1 --> 15
    line [0.1272, 0.1810, 0.1801, 0.1813, 0.1326, 0.1801, 0.1085, 0.1359, 0.1815, 0.1779, 0.1572, 0.1234, 0.1820, 0.1818, 0.1274]
```

```mermaid
xychart-beta
    title "dense-hud (p50 ms)"
    x-axis 1 --> 15
    line [0.1428, 0.0755, 0.1379, 0.1416, 0.1070, 0.1087, 0.1342, 0.1394, 0.1426, 0.1422, 0.1125, 0.1129, 0.1278, 0.1414, 0.1424]
```

```mermaid
xychart-beta
    title "dense-motion (p50 ms)"
    x-axis 1 --> 15
    line [0.7269, 0.5529, 0.9128, 0.9089, 0.9130, 0.8166, 0.8911, 0.5818, 0.5534, 0.9168, 0.7211, 0.9177, 0.6090, 0.7219, 0.9196]
```

```mermaid
xychart-beta
    title "hud-binding-storm (p50 ms)"
    x-axis 1 --> 15
    line [0.1859, 0.1272, 0.2142, 0.2163, 0.2139, 0.2076, 0.2091, 0.1199, 0.1190, 0.2144, 0.1859, 0.2143, 0.1532, 0.1829, 0.2141]
```

```mermaid
xychart-beta
    title "lab-collection-churn (p50 ms)"
    x-axis 1 --> 15
    line [0.2870, 0.2054, 0.3706, 0.3769, 0.3702, 0.3267, 0.3462, 0.2042, 0.2173, 0.3750, 0.2859, 0.3819, 0.2371, 0.2818, 0.3673]
```

```mermaid
xychart-beta
    title "lab-dense-scroll (p50 ms)"
    x-axis 1 --> 15
    line [0.1688, 0.1559, 0.1552, 0.1139, 0.1575, 0.1144, 0.1724, 0.0890, 0.1580, 0.1640, 0.1204, 0.1526, 0.1206, 0.1619, 0.1567]
```

```mermaid
xychart-beta
    title "locale-textsize-change (p50 ms)"
    x-axis 1 --> 15
    line [0.0212, 0.0294, 0.0296, 0.0295, 0.0210, 0.0299, 0.0141, 0.0208, 0.0297, 0.0299, 0.0245, 0.0210, 0.0297, 0.0302, 0.0209]
```

```mermaid
xychart-beta
    title "native-scroll-drag (p50 ms)"
    x-axis 1 --> 15
    line [0.0313, 0.0356, 0.0355, 0.0364, 0.0271, 0.0358, 0.0226, 0.0274, 0.0353, 0.0363, 0.0460, 0.0311, 0.0402, 0.0369, 0.0311]
```

```mermaid
xychart-beta
    title "navigation-customization (p50 ms)"
    x-axis 1 --> 15
    line [0.0505, 0.0296, 0.0412, 0.0500, 0.0315, 0.0315, 0.0409, 0.0503, 0.0505, 0.0518, 0.0323, 0.0331, 0.0485, 0.0522, 0.0503]
```

```mermaid
xychart-beta
    title "picker-menu-open-close (p50 ms)"
    x-axis 1 --> 15
    line [4.0174, 3.4024, 5.4017, 5.4631, 5.2994, 5.3502, 5.1493, 3.5447, 3.4388, 5.7846, 4.3066, 6.1012, 4.1897, 4.1591, 5.7919]
```

```mermaid
xychart-beta
    title "picker-segmented-textsize (p50 ms)"
    x-axis 1 --> 15
    line [0.0429, 0.0662, 0.0669, 0.0660, 0.0481, 0.0663, 0.0367, 0.0489, 0.0664, 0.0665, 0.0566, 0.0427, 0.0656, 0.0656, 0.0436]
```

```mermaid
xychart-beta
    title "radial-menu-open-close (p50 ms)"
    x-axis 1 --> 15
    line [3.1112, 1.8589, 2.7809, 3.0636, 2.1657, 2.2270, 2.7740, 3.0517, 3.0986, 3.0720, 2.2117, 2.2244, 2.9094, 3.0660, 3.1048]
```

```mermaid
xychart-beta
    title "screen-lifecycle-churn (p50 ms)"
    x-axis 1 --> 15
    line [10.3266, 13.6779, 13.3474, 13.7228, 11.0919, 14.2328, 9.1106, 11.1435, 13.8748, 13.4354, 13.5508, 9.7896, 15.4034, 13.9148, 10.1460]
```

```mermaid
xychart-beta
    title "scroll-focus-traversal (p50 ms)"
    x-axis 1 --> 15
    line [0.3840, 0.1980, 0.3674, 0.3885, 0.2842, 0.2843, 0.3612, 0.3833, 0.3936, 0.3824, 0.2869, 0.2861, 0.3638, 0.3920, 0.3899]
```

```mermaid
xychart-beta
    title "settings-churn (p50 ms)"
    x-axis 1 --> 15
    line [2.5856, 3.6434, 3.6307, 3.7213, 2.8691, 3.6590, 2.3185, 2.8613, 3.6309, 3.5904, 3.4048, 2.5629, 3.7655, 3.6624, 2.5694]
```

```mermaid
xychart-beta
    title "shadow-storm (p50 ms)"
    x-axis 1 --> 15
    line [0.0005, 0.0005, 0.0005, 0.0005, 0.0005, 0.0005, 0.0005, 0.0003, 0.0006, 0.0005, 0.0005, 0.0006, 0.0005, 0.0005, 0.0006]
```

```mermaid
xychart-beta
    title "stylesheet-state-churn (p50 ms)"
    x-axis 1 --> 15
    line [0.3080, 0.3324, 0.3378, 0.2450, 0.3339, 0.2453, 0.3057, 0.1919, 0.3329, 0.3043, 0.2484, 0.3098, 0.2532, 0.3328, 0.3260]
```

```mermaid
xychart-beta
    title "theme-swap-assets (p50 ms)"
    x-axis 1 --> 15
    line [1.5349, 0.9322, 1.4603, 1.5391, 1.1393, 1.1376, 1.4492, 1.5263, 1.5323, 1.5306, 1.1498, 1.1609, 1.5069, 1.5425, 1.5404]
```

```mermaid
xychart-beta
    title "theme-swap-flat (p50 ms)"
    x-axis 1 --> 15
    line [0.3972, 0.2391, 0.4068, 0.3985, 0.3119, 0.3118, 0.3948, 0.3955, 0.3978, 0.4037, 0.3121, 0.3142, 0.3744, 0.3954, 0.4005]
```

```mermaid
xychart-beta
    title "theme-swap-metrics (p50 ms)"
    x-axis 1 --> 15
    line [1.3783, 1.3845, 1.3991, 1.0991, 1.3897, 1.0599, 1.3071, 0.7848, 1.3567, 1.3755, 1.1092, 1.4187, 1.1033, 1.3933, 1.3846]
```

```mermaid
xychart-beta
    title "virtual-list-scroll (p50 ms)"
    x-axis 1 --> 15
    line [0.0907, 0.0831, 0.1330, 0.1330, 0.1317, 0.1262, 0.1258, 0.0822, 0.0828, 0.1312, 0.0923, 0.1325, 0.0915, 0.0905, 0.1328]
```
