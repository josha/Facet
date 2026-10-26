# Facet performance

Latest: `406b95776da4e3a9eff33acf695bf6cc6e5bfa1c` on 2026-10-26T204100Z, measured on the CI Ubuntu runner by the paired performance shards.
Times are milliseconds per frame or operation: the median over paired rounds of each round's p50 and p95.
Retained heap is the scene's mounted retained Luau heap. Change compares the p50 of the previous main commit.

| Scene | p50 ms | p95 ms | Retained KiB | Change |
| --- | ---: | ---: | ---: | ---: |
| adaptive-navigation-images | 0.8202 | 1.1736 | 9279 | -19.7% |
| alert-present-dismiss | 3.6648 | 5.4326 | 6565 | +31.5% |
| animation-interruption | 0.0305 | 0.0351 | 4815 | -19.4% |
| async-image-burst | 0.0515 | 0.0595 | 4977 | +26.6% |
| async-image-grid | 2.3810 | 3.7610 | 6605 | -12.2% |
| collection-mutation | 0.4129 | 0.6124 | 8226 | +21.9% |
| control-motion | 0.1487 | 0.4094 | 6325 | -26.3% |
| dense-hud | 0.1905 | 0.2114 | 5256 | +25.2% |
| dense-motion | 1.5193 | 2.5459 | 5882 | -1.6% |
| hud-binding-storm | 0.2342 | 0.2517 | 4917 | -11.2% |
| lab-collection-churn | 0.3722 | 0.7353 | 9074 | -10.7% |
| lab-dense-scroll | 0.9164 | 5.6077 | 11908 | +7.9% |
| locale-textsize-change | 0.0195 | 0.0231 | 4926 | -29.3% |
| native-scroll-drag | 0.0422 | 0.0568 | 6365 | -18.7% |
| navigation-customization | 0.0596 | 0.0692 | 9148 | +23.6% |
| picker-menu-open-close | 6.0581 | 8.8739 | 6553 | -11.0% |
| picker-segmented-textsize | 0.0481 | 0.0574 | 5458 | -26.0% |
| radial-menu-open-close | 12.5300 | 22.4947 | 5924 | +19.1% |
| screen-lifecycle-churn | 9.6509 | 17.9523 | 5775 | -27.4% |
| scroll-focus-traversal | 0.3878 | 0.6120 | 5854 | +29.0% |
| settings-churn | 2.4259 | 3.8958 | 6424 | -21.4% |
| shadow-storm | 0.0005 | 0.0015 | 6461 | +11.9% |
| stylesheet-state-churn | 0.3849 | 0.7041 | 7637 | +17.8% |
| theme-swap-assets | 2.1645 | 2.7319 | 9834 | +27.3% |
| theme-swap-flat | 0.5278 | 0.6517 | 8814 | +28.7% |
| theme-swap-metrics | 1.6779 | 1.9973 | 9362 | +22.2% |
| virtual-list-scroll | 0.1771 | 0.4142 | 10211 | -11.6% |

| Microbenchmark | p50 ms | p95 ms | Change |
| --- | ---: | ---: | ---: |
| billboard-nameplate-storm | 0.1476 | 0.1845 | -13.5% |
| collection-mutation | 0.0055 | 0.0075 | -22.4% |
| collection-selection-update | 0.0033 | 0.0052 | +25.1% |
| hud-binding-storm | 0.3151 | 0.3296 | +4.6% |
| motion-declarative | 1.2578 | 2.0768 | -0.5% |
| motion-explicit | 0.7942 | 1.6015 | -26.7% |
| mount-ramp | 161.6311 | 187.3484 | +20.4% |
| mount-ramp-inherited | 149.3295 | 161.9836 | +16.3% |
| mounted-slice-update-storm | 0.2218 | 0.3008 | -8.5% |
| outline-measured-update | 1.2442 | 2.1978 | -31.7% |
| reserved-slot-record-update | 0.8787 | 1.5271 | +24.3% |
| settings-churn | 0.0117 | 0.0130 | +8.0% |
| sparse-update-under-load | 0.0021 | 0.0023 | -9.9% |
| table-mutation | 0.2604 | 0.3455 | -20.4% |
| table-resize-drag | 3.1828 | 5.5481 | +25.3% |
| table-sort-values | 1.3163 | 2.0687 | +21.5% |
| table-source-refresh | 0.2619 | 0.4397 | -13.2% |
| textinput-typing-storm | 0.1636 | 0.3053 | -23.6% |
| timer-readout-storm | 0.1741 | 2.7009 | +29.7% |
| zz-yardstick-cpu-after | 1.2800 | 1.2878 | +11.6% |
| zz-yardstick-cpu-before | 1.2922 | 1.2991 | +22.5% |

## Scene p50 over the last 8 main commits

```mermaid
xychart-beta
    title "adaptive-navigation-images (p50 ms)"
    x-axis 1 --> 8
    line [0.9159, 1.3609, 0.9193, 1.3288, 1.2245, 1.3615, 1.0208, 0.8202]
```

```mermaid
xychart-beta
    title "alert-present-dismiss (p50 ms)"
    x-axis 1 --> 8
    line [2.3284, 2.5432, 2.6957, 3.5058, 3.6611, 2.3918, 2.7865, 3.6648]
```

```mermaid
xychart-beta
    title "animation-interruption (p50 ms)"
    x-axis 1 --> 8
    line [0.0242, 0.0301, 0.0381, 0.0290, 0.0220, 0.0383, 0.0379, 0.0305]
```

```mermaid
xychart-beta
    title "async-image-burst (p50 ms)"
    x-axis 1 --> 8
    line [0.0288, 0.0459, 0.0389, 0.0449, 0.0266, 0.0450, 0.0407, 0.0515]
```

```mermaid
xychart-beta
    title "async-image-grid (p50 ms)"
    x-axis 1 --> 8
    line [1.6953, 2.7184, 1.8124, 2.6543, 1.7415, 2.7336, 2.7103, 2.3810]
```

```mermaid
xychart-beta
    title "collection-mutation (p50 ms)"
    x-axis 1 --> 8
    line [0.3332, 0.4681, 0.3201, 0.4622, 0.4560, 0.2881, 0.3389, 0.4129]
```

```mermaid
xychart-beta
    title "control-motion (p50 ms)"
    x-axis 1 --> 8
    line [0.1407, 0.1565, 0.1807, 0.2262, 0.2422, 0.2560, 0.2018, 0.1487]
```

```mermaid
xychart-beta
    title "dense-hud (p50 ms)"
    x-axis 1 --> 8
    line [0.1402, 0.1574, 0.1997, 0.1472, 0.1114, 0.1957, 0.1522, 0.1905]
```

```mermaid
xychart-beta
    title "dense-motion (p50 ms)"
    x-axis 1 --> 8
    line [1.1243, 1.3144, 1.5562, 1.2159, 1.0340, 1.5887, 1.5438, 1.5193]
```

```mermaid
xychart-beta
    title "hud-binding-storm (p50 ms)"
    x-axis 1 --> 8
    line [0.1858, 0.2630, 0.2187, 0.2586, 0.1741, 0.2640, 0.2637, 0.2342]
```

```mermaid
xychart-beta
    title "lab-collection-churn (p50 ms)"
    x-axis 1 --> 8
    line [0.2396, 0.2475, 0.3195, 0.3675, 0.2530, 0.4143, 0.4168, 0.3722]
```

```mermaid
xychart-beta
    title "lab-dense-scroll (p50 ms)"
    x-axis 1 --> 8
    line [0.7446, 0.8751, 0.9218, 0.7244, 0.7929, 0.5928, 0.8489, 0.9164]
```

```mermaid
xychart-beta
    title "locale-textsize-change (p50 ms)"
    x-axis 1 --> 8
    line [0.0152, 0.0201, 0.0267, 0.0304, 0.0349, 0.0344, 0.0276, 0.0195]
```

```mermaid
xychart-beta
    title "native-scroll-drag (p50 ms)"
    x-axis 1 --> 8
    line [0.0464, 0.0583, 0.0482, 0.0561, 0.0672, 0.0581, 0.0520, 0.0422]
```

```mermaid
xychart-beta
    title "navigation-customization (p50 ms)"
    x-axis 1 --> 8
    line [0.0348, 0.0504, 0.0668, 0.0455, 0.0376, 0.0661, 0.0482, 0.0596]
```

```mermaid
xychart-beta
    title "picker-menu-open-close (p50 ms)"
    x-axis 1 --> 8
    line [5.1020, 6.6154, 4.6873, 6.5076, 4.5232, 6.6400, 6.8077, 6.0581]
```

```mermaid
xychart-beta
    title "picker-segmented-textsize (p50 ms)"
    x-axis 1 --> 8
    line [0.0576, 0.0616, 0.0841, 0.0581, 0.0762, 0.0847, 0.0649, 0.0481]
```

```mermaid
xychart-beta
    title "radial-menu-open-close (p50 ms)"
    x-axis 1 --> 8
    line [9.1824, 9.6461, 9.8160, 12.9977, 8.2964, 12.9826, 10.5207, 12.5300]
```

```mermaid
xychart-beta
    title "screen-lifecycle-churn (p50 ms)"
    x-axis 1 --> 8
    line [11.6362, 13.3303, 15.6277, 11.4367, 15.2702, 16.3829, 13.2931, 9.6509]
```

```mermaid
xychart-beta
    title "scroll-focus-traversal (p50 ms)"
    x-axis 1 --> 8
    line [0.1893, 0.1954, 0.2948, 0.3595, 0.2060, 0.4169, 0.3006, 0.3878]
```

```mermaid
xychart-beta
    title "settings-churn (p50 ms)"
    x-axis 1 --> 8
    line [2.4831, 3.3595, 3.8546, 2.7052, 3.5707, 4.0222, 3.0879, 2.4259]
```

```mermaid
xychart-beta
    title "shadow-storm (p50 ms)"
    x-axis 1 --> 8
    line [0.0005, 0.0005, 0.0006, 0.0005, 0.0006, 0.0003, 0.0005, 0.0005]
```

```mermaid
xychart-beta
    title "stylesheet-state-churn (p50 ms)"
    x-axis 1 --> 8
    line [0.2123, 0.2752, 0.3220, 0.3838, 0.4071, 0.2450, 0.3266, 0.3849]
```

```mermaid
xychart-beta
    title "theme-swap-assets (p50 ms)"
    x-axis 1 --> 8
    line [1.5921, 2.1494, 1.6336, 2.1480, 1.2452, 2.1218, 1.7008, 2.1645]
```

```mermaid
xychart-beta
    title "theme-swap-flat (p50 ms)"
    x-axis 1 --> 8
    line [0.3449, 0.3183, 0.4072, 0.4900, 0.2916, 0.5121, 0.4100, 0.5278]
```

```mermaid
xychart-beta
    title "theme-swap-metrics (p50 ms)"
    x-axis 1 --> 8
    line [1.2519, 1.6733, 1.3190, 1.6705, 1.6681, 1.0387, 1.3725, 1.6779]
```

```mermaid
xychart-beta
    title "virtual-list-scroll (p50 ms)"
    x-axis 1 --> 8
    line [0.1263, 0.1363, 0.1356, 0.1842, 0.1329, 0.2108, 0.2004, 0.1771]
```
