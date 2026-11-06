# Facet performance

Latest: `6b61d6dd998681deac24ebbe7a0c18b47ccc0ba2` on 2026-11-06T004451Z, measured on the CI Ubuntu runner by the paired performance shards.
Times are milliseconds per frame or operation: the median over paired rounds of each round's p50 and p95.
Retained heap is the scene's mounted retained Luau heap. Change compares the p50 of the previous main commit.

| Scene | p50 ms | p95 ms | Retained KiB | Change |
| --- | ---: | ---: | ---: | ---: |
| adaptive-navigation-images | 1.1515 | 1.2273 | 3914 | +0.4% |
| alert-present-dismiss | 2.1244 | 3.2679 | 9378 | -28.2% |
| animation-interruption | 0.0316 | 0.0345 | 388 | +3.4% |
| async-image-burst | 0.0351 | 0.0413 | 488 | -9.5% |
| async-image-grid | 2.2404 | 3.6560 | 2711 | -0.1% |
| collection-mutation | 0.2349 | 0.2595 | 2977 | -30.9% |
| control-motion | 0.1813 | 0.5826 | 1752 | +0.6% |
| dense-hud | 0.1416 | 0.1605 | 744 | +2.7% |
| dense-motion | 0.9089 | 1.2355 | 1628 | -0.4% |
| hud-binding-storm | 0.2163 | 0.2304 | 468 | +1.0% |
| lab-collection-churn | 0.3769 | 0.5368 | 4883 | +1.7% |
| lab-dense-scroll | 0.1139 | 0.1706 | 5917 | -26.6% |
| locale-textsize-change | 0.0295 | 0.0335 | 530 | -0.2% |
| native-scroll-drag | 0.0364 | 0.0572 | 1903 | +2.3% |
| navigation-customization | 0.0500 | 0.0613 | 3764 | +21.4% |
| picker-menu-open-close | 5.4631 | 8.1572 | 15940 | +1.1% |
| picker-segmented-textsize | 0.0660 | 0.0796 | 910 | -1.5% |
| radial-menu-open-close | 3.0636 | 4.1040 | 6664 | +10.2% |
| screen-lifecycle-churn | 13.7228 | 19.7431 | 26832 | +2.8% |
| scroll-focus-traversal | 0.3885 | 0.5747 | 1244 | +5.8% |
| settings-churn | 3.7213 | 5.5081 | 9375 | +2.5% |
| shadow-storm | 0.0005 | 0.0005 | 1957 | -14.8% |
| stylesheet-state-churn | 0.2450 | 0.2721 | 2581 | -27.5% |
| theme-swap-assets | 1.5391 | 1.8755 | 7066 | +5.4% |
| theme-swap-flat | 0.3985 | 0.4392 | 4462 | -2.0% |
| theme-swap-metrics | 1.0991 | 1.3252 | 6101 | -21.4% |
| virtual-list-scroll | 0.1330 | 0.1918 | 4270 | +0.0% |

| Microbenchmark | p50 ms | p95 ms | Change |
| --- | ---: | ---: | ---: |
| billboard-nameplate-storm | 0.1546 | 0.1694 | +0.2% |
| collection-mutation | 0.0084 | 0.0115 | -0.1% |
| collection-selection-update | 0.0023 | 0.0035 | -11.3% |
| hud-binding-storm | 0.2652 | 0.2763 | -14.7% |
| motion-declarative | 0.8345 | 1.1174 | -0.5% |
| motion-explicit | 0.8193 | 1.1314 | +1.3% |
| mount-ramp | 170.1873 | 188.8868 | -0.7% |
| mount-ramp-inherited | 127.6791 | 146.8226 | -24.0% |
| mounted-slice-update-storm | 0.2143 | 0.2283 | +1.2% |
| outline-measured-update | 1.2879 | 1.6446 | +0.4% |
| reserved-slot-record-update | 0.6145 | 0.6498 | +4.3% |
| settings-churn | 0.0103 | 0.0113 | -36.5% |
| sparse-update-under-load | 0.0024 | 0.0025 | +0.0% |
| table-mutation | 0.2835 | 0.3359 | -0.8% |
| table-resize-drag | 1.4696 | 1.8690 | +14.5% |
| table-sort-values | 0.7561 | 1.1868 | -27.2% |
| table-source-refresh | 0.2155 | 0.3785 | +1.9% |
| textinput-typing-storm | 0.2328 | 0.3781 | +0.9% |
| timer-readout-storm | 0.1372 | 0.6516 | -8.9% |
| zz-yardstick-cpu-after | 1.3048 | 1.3314 | -1.4% |
| zz-yardstick-cpu-before | 1.2929 | 1.3004 | -1.6% |

## Scene p50 over the last 4 main commits

```mermaid
xychart-beta
    title "adaptive-navigation-images (p50 ms)"
    x-axis 1 --> 4
    line [0.8330, 1.1721, 1.1465, 1.1515]
```

```mermaid
xychart-beta
    title "alert-present-dismiss (p50 ms)"
    x-axis 1 --> 4
    line [2.9632, 2.9538, 2.9589, 2.1244]
```

```mermaid
xychart-beta
    title "animation-interruption (p50 ms)"
    x-axis 1 --> 4
    line [0.0236, 0.0159, 0.0306, 0.0316]
```

```mermaid
xychart-beta
    title "async-image-burst (p50 ms)"
    x-axis 1 --> 4
    line [0.0357, 0.0192, 0.0388, 0.0351]
```

```mermaid
xychart-beta
    title "async-image-grid (p50 ms)"
    x-axis 1 --> 4
    line [1.4898, 1.3778, 2.2419, 2.2404]
```

```mermaid
xychart-beta
    title "collection-mutation (p50 ms)"
    x-axis 1 --> 4
    line [0.3063, 0.3360, 0.3400, 0.2349]
```

```mermaid
xychart-beta
    title "control-motion (p50 ms)"
    x-axis 1 --> 4
    line [0.1272, 0.1810, 0.1801, 0.1813]
```

```mermaid
xychart-beta
    title "dense-hud (p50 ms)"
    x-axis 1 --> 4
    line [0.1428, 0.0755, 0.1379, 0.1416]
```

```mermaid
xychart-beta
    title "dense-motion (p50 ms)"
    x-axis 1 --> 4
    line [0.7269, 0.5529, 0.9128, 0.9089]
```

```mermaid
xychart-beta
    title "hud-binding-storm (p50 ms)"
    x-axis 1 --> 4
    line [0.1859, 0.1272, 0.2142, 0.2163]
```

```mermaid
xychart-beta
    title "lab-collection-churn (p50 ms)"
    x-axis 1 --> 4
    line [0.2870, 0.2054, 0.3706, 0.3769]
```

```mermaid
xychart-beta
    title "lab-dense-scroll (p50 ms)"
    x-axis 1 --> 4
    line [0.1688, 0.1559, 0.1552, 0.1139]
```

```mermaid
xychart-beta
    title "locale-textsize-change (p50 ms)"
    x-axis 1 --> 4
    line [0.0212, 0.0294, 0.0296, 0.0295]
```

```mermaid
xychart-beta
    title "native-scroll-drag (p50 ms)"
    x-axis 1 --> 4
    line [0.0313, 0.0356, 0.0355, 0.0364]
```

```mermaid
xychart-beta
    title "navigation-customization (p50 ms)"
    x-axis 1 --> 4
    line [0.0505, 0.0296, 0.0412, 0.0500]
```

```mermaid
xychart-beta
    title "picker-menu-open-close (p50 ms)"
    x-axis 1 --> 4
    line [4.0174, 3.4024, 5.4017, 5.4631]
```

```mermaid
xychart-beta
    title "picker-segmented-textsize (p50 ms)"
    x-axis 1 --> 4
    line [0.0429, 0.0662, 0.0669, 0.0660]
```

```mermaid
xychart-beta
    title "radial-menu-open-close (p50 ms)"
    x-axis 1 --> 4
    line [3.1112, 1.8589, 2.7809, 3.0636]
```

```mermaid
xychart-beta
    title "screen-lifecycle-churn (p50 ms)"
    x-axis 1 --> 4
    line [10.3266, 13.6779, 13.3474, 13.7228]
```

```mermaid
xychart-beta
    title "scroll-focus-traversal (p50 ms)"
    x-axis 1 --> 4
    line [0.3840, 0.1980, 0.3674, 0.3885]
```

```mermaid
xychart-beta
    title "settings-churn (p50 ms)"
    x-axis 1 --> 4
    line [2.5856, 3.6434, 3.6307, 3.7213]
```

```mermaid
xychart-beta
    title "shadow-storm (p50 ms)"
    x-axis 1 --> 4
    line [0.0005, 0.0005, 0.0005, 0.0005]
```

```mermaid
xychart-beta
    title "stylesheet-state-churn (p50 ms)"
    x-axis 1 --> 4
    line [0.3080, 0.3324, 0.3378, 0.2450]
```

```mermaid
xychart-beta
    title "theme-swap-assets (p50 ms)"
    x-axis 1 --> 4
    line [1.5349, 0.9322, 1.4603, 1.5391]
```

```mermaid
xychart-beta
    title "theme-swap-flat (p50 ms)"
    x-axis 1 --> 4
    line [0.3972, 0.2391, 0.4068, 0.3985]
```

```mermaid
xychart-beta
    title "theme-swap-metrics (p50 ms)"
    x-axis 1 --> 4
    line [1.3783, 1.3845, 1.3991, 1.0991]
```

```mermaid
xychart-beta
    title "virtual-list-scroll (p50 ms)"
    x-axis 1 --> 4
    line [0.0907, 0.0831, 0.1330, 0.1330]
```
