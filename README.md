# Facet performance

Latest: `937a108143576bc9e20c8950089fb674e1777e00` on 2026-10-26T125646Z, measured on the CI Ubuntu runner by the paired performance shards.
Times are milliseconds per frame or operation: the median over paired rounds of each round's p50 and p95.
Retained heap is the scene's mounted retained Luau heap. Change compares the p50 of the previous main commit.

| Scene | p50 ms | p95 ms | Retained KiB | Change |
| --- | ---: | ---: | ---: | ---: |
| adaptive-navigation-images | 0.9193 | 1.2045 | 9158 | -32.4% |
| alert-present-dismiss | 2.6957 | 4.2182 | 6723 | +6.0% |
| animation-interruption | 0.0381 | 0.0460 | 4815 | +26.6% |
| async-image-burst | 0.0389 | 0.0446 | 4970 | -15.4% |
| async-image-grid | 1.8124 | 2.9673 | 6985 | -33.3% |
| collection-mutation | 0.3201 | 0.4445 | 8281 | -31.6% |
| control-motion | 0.1807 | 0.4578 | 6325 | +15.5% |
| dense-hud | 0.1997 | 0.2236 | 5259 | +26.9% |
| dense-motion | 1.5562 | 2.6375 | 5889 | +18.4% |
| hud-binding-storm | 0.2187 | 0.2302 | 4916 | -16.8% |
| lab-collection-churn | 0.3195 | 0.6653 | 9086 | +29.1% |
| lab-dense-scroll | 0.9218 | 5.5892 | 12125 | +5.3% |
| locale-textsize-change | 0.0267 | 0.0319 | 4926 | +32.9% |
| native-scroll-drag | 0.0482 | 0.0596 | 6365 | -17.2% |
| navigation-customization | 0.0668 | 0.0801 | 9145 | +32.7% |
| picker-menu-open-close | 4.6873 | 6.9948 | 6202 | -29.1% |
| picker-segmented-textsize | 0.0841 | 0.1032 | 5463 | +36.5% |
| radial-menu-open-close | 9.8160 | 16.9304 | 6051 | +1.8% |
| screen-lifecycle-churn | 15.6277 | 25.4842 | 5770 | +17.2% |
| scroll-focus-traversal | 0.2948 | 0.4718 | 5854 | +50.9% |
| settings-churn | 3.8546 | 5.7971 | 6909 | +14.7% |
| shadow-storm | 0.0006 | 0.0016 | 6439 | +15.2% |
| stylesheet-state-churn | 0.3220 | 0.6053 | 7679 | +17.0% |
| theme-swap-assets | 1.6336 | 2.0175 | 9579 | -24.0% |
| theme-swap-flat | 0.4072 | 0.5132 | 8877 | +27.9% |
| theme-swap-metrics | 1.3190 | 1.5252 | 9427 | -21.2% |
| virtual-list-scroll | 0.1356 | 0.3306 | 10235 | -0.6% |

| Microbenchmark | p50 ms | p95 ms | Change |
| --- | ---: | ---: | ---: |
| billboard-nameplate-storm | 0.1465 | 0.1705 | -14.0% |
| collection-mutation | 0.0084 | 0.0112 | +0.6% |
| collection-selection-update | 0.0026 | 0.0042 | +40.9% |
| hud-binding-storm | 0.2945 | 0.3045 | -18.6% |
| motion-declarative | 1.2611 | 2.0508 | +2.8% |
| motion-explicit | 1.0303 | 1.8174 | +21.3% |
| mount-ramp | 115.8291 | 133.0482 | -25.7% |
| mount-ramp-inherited | 158.7191 | 176.7957 | +5.0% |
| mounted-slice-update-storm | 0.2054 | 0.2150 | +40.1% |
| outline-measured-update | 1.5900 | 2.3888 | -20.5% |
| reserved-slot-record-update | 0.8670 | 1.9081 | +5.0% |
| settings-churn | 0.0105 | 0.0113 | +40.8% |
| sparse-update-under-load | 0.0020 | 0.0022 | -14.8% |
| table-mutation | 0.4404 | 0.5489 | +28.3% |
| table-resize-drag | 2.4591 | 3.9925 | +12.8% |
| table-sort-values | 1.0402 | 1.6152 | -26.0% |
| table-source-refresh | 0.2664 | 0.5982 | +21.0% |
| textinput-typing-storm | 0.2183 | 0.3426 | +34.7% |
| timer-readout-storm | 0.1365 | 2.0582 | -19.5% |
| zz-yardstick-cpu-after | 1.2376 | 1.2584 | -3.9% |
| zz-yardstick-cpu-before | 1.1624 | 1.1745 | +2.1% |

## Scene p50 over the last 3 main commits

```mermaid
xychart-beta
    title "adaptive-navigation-images (p50 ms)"
    x-axis 1 --> 3
    line [0.9159, 1.3609, 0.9193]
```

```mermaid
xychart-beta
    title "alert-present-dismiss (p50 ms)"
    x-axis 1 --> 3
    line [2.3284, 2.5432, 2.6957]
```

```mermaid
xychart-beta
    title "animation-interruption (p50 ms)"
    x-axis 1 --> 3
    line [0.0242, 0.0301, 0.0381]
```

```mermaid
xychart-beta
    title "async-image-burst (p50 ms)"
    x-axis 1 --> 3
    line [0.0288, 0.0459, 0.0389]
```

```mermaid
xychart-beta
    title "async-image-grid (p50 ms)"
    x-axis 1 --> 3
    line [1.6953, 2.7184, 1.8124]
```

```mermaid
xychart-beta
    title "collection-mutation (p50 ms)"
    x-axis 1 --> 3
    line [0.3332, 0.4681, 0.3201]
```

```mermaid
xychart-beta
    title "control-motion (p50 ms)"
    x-axis 1 --> 3
    line [0.1407, 0.1565, 0.1807]
```

```mermaid
xychart-beta
    title "dense-hud (p50 ms)"
    x-axis 1 --> 3
    line [0.1402, 0.1574, 0.1997]
```

```mermaid
xychart-beta
    title "dense-motion (p50 ms)"
    x-axis 1 --> 3
    line [1.1243, 1.3144, 1.5562]
```

```mermaid
xychart-beta
    title "hud-binding-storm (p50 ms)"
    x-axis 1 --> 3
    line [0.1858, 0.2630, 0.2187]
```

```mermaid
xychart-beta
    title "lab-collection-churn (p50 ms)"
    x-axis 1 --> 3
    line [0.2396, 0.2475, 0.3195]
```

```mermaid
xychart-beta
    title "lab-dense-scroll (p50 ms)"
    x-axis 1 --> 3
    line [0.7446, 0.8751, 0.9218]
```

```mermaid
xychart-beta
    title "locale-textsize-change (p50 ms)"
    x-axis 1 --> 3
    line [0.0152, 0.0201, 0.0267]
```

```mermaid
xychart-beta
    title "native-scroll-drag (p50 ms)"
    x-axis 1 --> 3
    line [0.0464, 0.0583, 0.0482]
```

```mermaid
xychart-beta
    title "navigation-customization (p50 ms)"
    x-axis 1 --> 3
    line [0.0348, 0.0504, 0.0668]
```

```mermaid
xychart-beta
    title "picker-menu-open-close (p50 ms)"
    x-axis 1 --> 3
    line [5.1020, 6.6154, 4.6873]
```

```mermaid
xychart-beta
    title "picker-segmented-textsize (p50 ms)"
    x-axis 1 --> 3
    line [0.0576, 0.0616, 0.0841]
```

```mermaid
xychart-beta
    title "radial-menu-open-close (p50 ms)"
    x-axis 1 --> 3
    line [9.1824, 9.6461, 9.8160]
```

```mermaid
xychart-beta
    title "screen-lifecycle-churn (p50 ms)"
    x-axis 1 --> 3
    line [11.6362, 13.3303, 15.6277]
```

```mermaid
xychart-beta
    title "scroll-focus-traversal (p50 ms)"
    x-axis 1 --> 3
    line [0.1893, 0.1954, 0.2948]
```

```mermaid
xychart-beta
    title "settings-churn (p50 ms)"
    x-axis 1 --> 3
    line [2.4831, 3.3595, 3.8546]
```

```mermaid
xychart-beta
    title "shadow-storm (p50 ms)"
    x-axis 1 --> 3
    line [0.0005, 0.0005, 0.0006]
```

```mermaid
xychart-beta
    title "stylesheet-state-churn (p50 ms)"
    x-axis 1 --> 3
    line [0.2123, 0.2752, 0.3220]
```

```mermaid
xychart-beta
    title "theme-swap-assets (p50 ms)"
    x-axis 1 --> 3
    line [1.5921, 2.1494, 1.6336]
```

```mermaid
xychart-beta
    title "theme-swap-flat (p50 ms)"
    x-axis 1 --> 3
    line [0.3449, 0.3183, 0.4072]
```

```mermaid
xychart-beta
    title "theme-swap-metrics (p50 ms)"
    x-axis 1 --> 3
    line [1.2519, 1.6733, 1.3190]
```

```mermaid
xychart-beta
    title "virtual-list-scroll (p50 ms)"
    x-axis 1 --> 3
    line [0.1263, 0.1363, 0.1356]
```
