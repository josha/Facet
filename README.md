# Facet performance

Latest: `ba0600ff62593bb8369c99c831012a709bccd351` on 2026-11-06T010359Z, measured on the CI Ubuntu runner by the paired performance shards.
Times are milliseconds per frame or operation: the median over paired rounds of each round's p50 and p95.
Retained heap is the scene's mounted retained Luau heap. Change compares the p50 of the previous main commit.

| Scene | p50 ms | p95 ms | Retained KiB | Change |
| --- | ---: | ---: | ---: | ---: |
| adaptive-navigation-images | 1.1733 | 1.2855 | 3947 | +37.2% |
| alert-present-dismiss | 2.1232 | 3.2623 | 9368 | -27.8% |
| animation-interruption | 0.0270 | 0.0312 | 391 | -12.6% |
| async-image-burst | 0.0299 | 0.0347 | 490 | +1.7% |
| async-image-grid | 2.1194 | 3.4001 | 2730 | -4.9% |
| collection-mutation | 0.2370 | 0.2663 | 2980 | -29.1% |
| control-motion | 0.1801 | 0.5574 | 1755 | +35.8% |
| dense-hud | 0.1087 | 0.1182 | 747 | +1.6% |
| dense-motion | 0.8166 | 1.3298 | 1630 | -10.6% |
| hud-binding-storm | 0.2076 | 0.2264 | 470 | -2.9% |
| lab-collection-churn | 0.3267 | 0.4956 | 4916 | -11.8% |
| lab-dense-scroll | 0.1144 | 0.1693 | 5932 | -27.3% |
| locale-textsize-change | 0.0299 | 0.0325 | 533 | +42.3% |
| native-scroll-drag | 0.0358 | 0.0583 | 1906 | +32.4% |
| navigation-customization | 0.0315 | 0.0358 | 3789 | -0.0% |
| picker-menu-open-close | 5.3502 | 8.0405 | 15964 | +1.0% |
| picker-segmented-textsize | 0.0663 | 0.0796 | 914 | +37.8% |
| radial-menu-open-close | 2.2270 | 2.9664 | 6661 | +2.8% |
| screen-lifecycle-churn | 14.2328 | 19.9468 | 27073 | +28.3% |
| scroll-focus-traversal | 0.2843 | 0.4425 | 1239 | +0.0% |
| settings-churn | 3.6590 | 5.5063 | 9377 | +27.5% |
| shadow-storm | 0.0005 | 0.0005 | 1960 | -13.3% |
| stylesheet-state-churn | 0.2453 | 0.2693 | 2584 | -26.5% |
| theme-swap-assets | 1.1376 | 1.4377 | 7072 | -0.1% |
| theme-swap-flat | 0.3118 | 0.3511 | 4467 | -0.0% |
| theme-swap-metrics | 1.0599 | 1.3573 | 6106 | -23.7% |
| virtual-list-scroll | 0.1262 | 0.1850 | 4272 | -4.2% |

| Microbenchmark | p50 ms | p95 ms | Change |
| --- | ---: | ---: | ---: |
| billboard-nameplate-storm | 0.1436 | 0.1598 | -6.6% |
| collection-mutation | 0.0085 | 0.0116 | +20.9% |
| collection-selection-update | 0.0019 | 0.0023 | -1.6% |
| hud-binding-storm | 0.2649 | 0.2772 | -16.5% |
| motion-declarative | 0.7789 | 1.0954 | -4.8% |
| motion-explicit | 0.8325 | 1.1598 | +32.4% |
| mount-ramp | 125.8234 | 146.4309 | -0.4% |
| mount-ramp-inherited | 124.0961 | 139.7243 | -25.1% |
| mounted-slice-update-storm | 0.2122 | 0.2283 | +1.3% |
| outline-measured-update | 1.3171 | 1.6805 | +28.5% |
| reserved-slot-record-update | 0.4733 | 0.5022 | +6.1% |
| settings-churn | 0.0108 | 0.0127 | -33.9% |
| sparse-update-under-load | 0.0022 | 0.0024 | -8.6% |
| table-mutation | 0.2862 | 0.3347 | +29.6% |
| table-resize-drag | 0.9987 | 1.3872 | +0.2% |
| table-sort-values | 0.7549 | 0.9710 | -27.7% |
| table-source-refresh | 0.1931 | 0.3873 | -8.2% |
| textinput-typing-storm | 0.2326 | 0.3856 | +32.9% |
| timer-readout-storm | 0.1178 | 0.5479 | +0.5% |
| zz-yardstick-cpu-after | 1.2393 | 1.2453 | -1.3% |
| zz-yardstick-cpu-before | 1.1484 | 1.1593 | -3.2% |

## Scene p50 over the last 6 main commits

```mermaid
xychart-beta
    title "adaptive-navigation-images (p50 ms)"
    x-axis 1 --> 6
    line [0.8330, 1.1721, 1.1465, 1.1515, 0.8551, 1.1733]
```

```mermaid
xychart-beta
    title "alert-present-dismiss (p50 ms)"
    x-axis 1 --> 6
    line [2.9632, 2.9538, 2.9589, 2.1244, 2.9396, 2.1232]
```

```mermaid
xychart-beta
    title "animation-interruption (p50 ms)"
    x-axis 1 --> 6
    line [0.0236, 0.0159, 0.0306, 0.0316, 0.0309, 0.0270]
```

```mermaid
xychart-beta
    title "async-image-burst (p50 ms)"
    x-axis 1 --> 6
    line [0.0357, 0.0192, 0.0388, 0.0351, 0.0294, 0.0299]
```

```mermaid
xychart-beta
    title "async-image-grid (p50 ms)"
    x-axis 1 --> 6
    line [1.4898, 1.3778, 2.2419, 2.2404, 2.2280, 2.1194]
```

```mermaid
xychart-beta
    title "collection-mutation (p50 ms)"
    x-axis 1 --> 6
    line [0.3063, 0.3360, 0.3400, 0.2349, 0.3341, 0.2370]
```

```mermaid
xychart-beta
    title "control-motion (p50 ms)"
    x-axis 1 --> 6
    line [0.1272, 0.1810, 0.1801, 0.1813, 0.1326, 0.1801]
```

```mermaid
xychart-beta
    title "dense-hud (p50 ms)"
    x-axis 1 --> 6
    line [0.1428, 0.0755, 0.1379, 0.1416, 0.1070, 0.1087]
```

```mermaid
xychart-beta
    title "dense-motion (p50 ms)"
    x-axis 1 --> 6
    line [0.7269, 0.5529, 0.9128, 0.9089, 0.9130, 0.8166]
```

```mermaid
xychart-beta
    title "hud-binding-storm (p50 ms)"
    x-axis 1 --> 6
    line [0.1859, 0.1272, 0.2142, 0.2163, 0.2139, 0.2076]
```

```mermaid
xychart-beta
    title "lab-collection-churn (p50 ms)"
    x-axis 1 --> 6
    line [0.2870, 0.2054, 0.3706, 0.3769, 0.3702, 0.3267]
```

```mermaid
xychart-beta
    title "lab-dense-scroll (p50 ms)"
    x-axis 1 --> 6
    line [0.1688, 0.1559, 0.1552, 0.1139, 0.1575, 0.1144]
```

```mermaid
xychart-beta
    title "locale-textsize-change (p50 ms)"
    x-axis 1 --> 6
    line [0.0212, 0.0294, 0.0296, 0.0295, 0.0210, 0.0299]
```

```mermaid
xychart-beta
    title "native-scroll-drag (p50 ms)"
    x-axis 1 --> 6
    line [0.0313, 0.0356, 0.0355, 0.0364, 0.0271, 0.0358]
```

```mermaid
xychart-beta
    title "navigation-customization (p50 ms)"
    x-axis 1 --> 6
    line [0.0505, 0.0296, 0.0412, 0.0500, 0.0315, 0.0315]
```

```mermaid
xychart-beta
    title "picker-menu-open-close (p50 ms)"
    x-axis 1 --> 6
    line [4.0174, 3.4024, 5.4017, 5.4631, 5.2994, 5.3502]
```

```mermaid
xychart-beta
    title "picker-segmented-textsize (p50 ms)"
    x-axis 1 --> 6
    line [0.0429, 0.0662, 0.0669, 0.0660, 0.0481, 0.0663]
```

```mermaid
xychart-beta
    title "radial-menu-open-close (p50 ms)"
    x-axis 1 --> 6
    line [3.1112, 1.8589, 2.7809, 3.0636, 2.1657, 2.2270]
```

```mermaid
xychart-beta
    title "screen-lifecycle-churn (p50 ms)"
    x-axis 1 --> 6
    line [10.3266, 13.6779, 13.3474, 13.7228, 11.0919, 14.2328]
```

```mermaid
xychart-beta
    title "scroll-focus-traversal (p50 ms)"
    x-axis 1 --> 6
    line [0.3840, 0.1980, 0.3674, 0.3885, 0.2842, 0.2843]
```

```mermaid
xychart-beta
    title "settings-churn (p50 ms)"
    x-axis 1 --> 6
    line [2.5856, 3.6434, 3.6307, 3.7213, 2.8691, 3.6590]
```

```mermaid
xychart-beta
    title "shadow-storm (p50 ms)"
    x-axis 1 --> 6
    line [0.0005, 0.0005, 0.0005, 0.0005, 0.0005, 0.0005]
```

```mermaid
xychart-beta
    title "stylesheet-state-churn (p50 ms)"
    x-axis 1 --> 6
    line [0.3080, 0.3324, 0.3378, 0.2450, 0.3339, 0.2453]
```

```mermaid
xychart-beta
    title "theme-swap-assets (p50 ms)"
    x-axis 1 --> 6
    line [1.5349, 0.9322, 1.4603, 1.5391, 1.1393, 1.1376]
```

```mermaid
xychart-beta
    title "theme-swap-flat (p50 ms)"
    x-axis 1 --> 6
    line [0.3972, 0.2391, 0.4068, 0.3985, 0.3119, 0.3118]
```

```mermaid
xychart-beta
    title "theme-swap-metrics (p50 ms)"
    x-axis 1 --> 6
    line [1.3783, 1.3845, 1.3991, 1.0991, 1.3897, 1.0599]
```

```mermaid
xychart-beta
    title "virtual-list-scroll (p50 ms)"
    x-axis 1 --> 6
    line [0.0907, 0.0831, 0.1330, 0.1330, 0.1317, 0.1262]
```
