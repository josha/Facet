# Facet performance

Latest: `bf45285db96b0ad1fb5d1721bacfa94a008769cd` on 2026-10-26T210624Z, measured on the CI Ubuntu runner by the paired performance shards.
Times are milliseconds per frame or operation: the median over paired rounds of each round's p50 and p95.
Retained heap is the scene's mounted retained Luau heap. Change compares the p50 of the previous main commit.

| Scene | p50 ms | p95 ms | Retained KiB | Change |
| --- | ---: | ---: | ---: | ---: |
| adaptive-navigation-images | 0.8203 | 1.1245 | 7194 | +0.0% |
| alert-present-dismiss | 3.4312 | 5.0046 | 2496 | -6.4% |
| animation-interruption | 0.0364 | 0.0425 | 388 | +19.3% |
| async-image-burst | 0.0458 | 0.0527 | 510 | -11.0% |
| async-image-grid | 2.3646 | 3.6035 | 2149 | -0.7% |
| collection-mutation | 0.4054 | 0.5850 | 3915 | -1.8% |
| control-motion | 0.1572 | 0.5387 | 1637 | +5.7% |
| dense-hud | 0.1825 | 0.1962 | 830 | -4.2% |
| dense-motion | 1.4201 | 2.6059 | 2954 | -6.5% |
| hud-binding-storm | 0.2827 | 0.2988 | 478 | +20.7% |
| lab-collection-churn | 0.4216 | 0.6859 | 4587 | +13.2% |
| lab-dense-scroll | 0.8310 | 5.0698 | 7673 | -9.3% |
| locale-textsize-change | 0.0194 | 0.0238 | 496 | -0.6% |
| native-scroll-drag | 0.0417 | 0.0530 | 2049 | -1.3% |
| navigation-customization | 0.0616 | 0.0698 | 4680 | +3.4% |
| picker-menu-open-close | 5.8829 | 9.3057 | 1483 | -2.9% |
| picker-segmented-textsize | 0.0483 | 0.0559 | 1013 | +0.5% |
| radial-menu-open-close | 12.8509 | 18.9042 | 1213 | +2.6% |
| screen-lifecycle-churn | 10.2078 | 18.2980 | 1396 | +5.8% |
| scroll-focus-traversal | 0.3175 | 0.5214 | 1399 | -18.1% |
| settings-churn | 2.3824 | 3.8439 | 1949 | -1.8% |
| shadow-storm | 0.0005 | 0.0017 | 1999 | +1.5% |
| stylesheet-state-churn | 0.3681 | 0.6985 | 3196 | -4.4% |
| theme-swap-assets | 2.1562 | 2.7240 | 4933 | -0.4% |
| theme-swap-flat | 0.4539 | 0.5653 | 4432 | -14.0% |
| theme-swap-metrics | 1.6201 | 1.9421 | 4952 | -3.4% |
| virtual-list-scroll | 0.1917 | 0.4089 | 5584 | +8.2% |

| Microbenchmark | p50 ms | p95 ms | Change |
| --- | ---: | ---: | ---: |
| billboard-nameplate-storm | 0.1850 | 0.2163 | +25.3% |
| collection-mutation | 0.0057 | 0.0076 | +2.1% |
| collection-selection-update | 0.0029 | 0.0045 | -11.9% |
| hud-binding-storm | 0.3224 | 0.3338 | +2.3% |
| motion-declarative | 1.2415 | 1.8705 | -1.3% |
| motion-explicit | 0.7854 | 1.3699 | -1.1% |
| mount-ramp | 145.2715 | 156.9728 | -10.1% |
| mount-ramp-inherited | 147.4821 | 157.1372 | -1.2% |
| mounted-slice-update-storm | 0.2670 | 0.3223 | +20.4% |
| outline-measured-update | 1.2494 | 2.1695 | +0.4% |
| reserved-slot-record-update | 0.7332 | 1.2886 | -16.6% |
| settings-churn | 0.0144 | 0.0155 | +23.2% |
| sparse-update-under-load | 0.0026 | 0.0028 | +21.7% |
| table-mutation | 0.2630 | 0.3659 | +1.0% |
| table-resize-drag | 3.1256 | 5.0721 | -1.8% |
| table-sort-values | 1.3056 | 2.2481 | -0.8% |
| table-source-refresh | 0.2351 | 0.4178 | -10.2% |
| textinput-typing-storm | 0.1566 | 0.2895 | -4.3% |
| timer-readout-storm | 0.1477 | 2.8000 | -15.2% |
| zz-yardstick-cpu-after | 1.2880 | 1.2977 | +0.6% |
| zz-yardstick-cpu-before | 1.2852 | 1.2934 | -0.5% |

## Scene p50 over the last 9 main commits

```mermaid
xychart-beta
    title "adaptive-navigation-images (p50 ms)"
    x-axis 1 --> 9
    line [0.9159, 1.3609, 0.9193, 1.3288, 1.2245, 1.3615, 1.0208, 0.8202, 0.8203]
```

```mermaid
xychart-beta
    title "alert-present-dismiss (p50 ms)"
    x-axis 1 --> 9
    line [2.3284, 2.5432, 2.6957, 3.5058, 3.6611, 2.3918, 2.7865, 3.6648, 3.4312]
```

```mermaid
xychart-beta
    title "animation-interruption (p50 ms)"
    x-axis 1 --> 9
    line [0.0242, 0.0301, 0.0381, 0.0290, 0.0220, 0.0383, 0.0379, 0.0305, 0.0364]
```

```mermaid
xychart-beta
    title "async-image-burst (p50 ms)"
    x-axis 1 --> 9
    line [0.0288, 0.0459, 0.0389, 0.0449, 0.0266, 0.0450, 0.0407, 0.0515, 0.0458]
```

```mermaid
xychart-beta
    title "async-image-grid (p50 ms)"
    x-axis 1 --> 9
    line [1.6953, 2.7184, 1.8124, 2.6543, 1.7415, 2.7336, 2.7103, 2.3810, 2.3646]
```

```mermaid
xychart-beta
    title "collection-mutation (p50 ms)"
    x-axis 1 --> 9
    line [0.3332, 0.4681, 0.3201, 0.4622, 0.4560, 0.2881, 0.3389, 0.4129, 0.4054]
```

```mermaid
xychart-beta
    title "control-motion (p50 ms)"
    x-axis 1 --> 9
    line [0.1407, 0.1565, 0.1807, 0.2262, 0.2422, 0.2560, 0.2018, 0.1487, 0.1572]
```

```mermaid
xychart-beta
    title "dense-hud (p50 ms)"
    x-axis 1 --> 9
    line [0.1402, 0.1574, 0.1997, 0.1472, 0.1114, 0.1957, 0.1522, 0.1905, 0.1825]
```

```mermaid
xychart-beta
    title "dense-motion (p50 ms)"
    x-axis 1 --> 9
    line [1.1243, 1.3144, 1.5562, 1.2159, 1.0340, 1.5887, 1.5438, 1.5193, 1.4201]
```

```mermaid
xychart-beta
    title "hud-binding-storm (p50 ms)"
    x-axis 1 --> 9
    line [0.1858, 0.2630, 0.2187, 0.2586, 0.1741, 0.2640, 0.2637, 0.2342, 0.2827]
```

```mermaid
xychart-beta
    title "lab-collection-churn (p50 ms)"
    x-axis 1 --> 9
    line [0.2396, 0.2475, 0.3195, 0.3675, 0.2530, 0.4143, 0.4168, 0.3722, 0.4216]
```

```mermaid
xychart-beta
    title "lab-dense-scroll (p50 ms)"
    x-axis 1 --> 9
    line [0.7446, 0.8751, 0.9218, 0.7244, 0.7929, 0.5928, 0.8489, 0.9164, 0.8310]
```

```mermaid
xychart-beta
    title "locale-textsize-change (p50 ms)"
    x-axis 1 --> 9
    line [0.0152, 0.0201, 0.0267, 0.0304, 0.0349, 0.0344, 0.0276, 0.0195, 0.0194]
```

```mermaid
xychart-beta
    title "native-scroll-drag (p50 ms)"
    x-axis 1 --> 9
    line [0.0464, 0.0583, 0.0482, 0.0561, 0.0672, 0.0581, 0.0520, 0.0422, 0.0417]
```

```mermaid
xychart-beta
    title "navigation-customization (p50 ms)"
    x-axis 1 --> 9
    line [0.0348, 0.0504, 0.0668, 0.0455, 0.0376, 0.0661, 0.0482, 0.0596, 0.0616]
```

```mermaid
xychart-beta
    title "picker-menu-open-close (p50 ms)"
    x-axis 1 --> 9
    line [5.1020, 6.6154, 4.6873, 6.5076, 4.5232, 6.6400, 6.8077, 6.0581, 5.8829]
```

```mermaid
xychart-beta
    title "picker-segmented-textsize (p50 ms)"
    x-axis 1 --> 9
    line [0.0576, 0.0616, 0.0841, 0.0581, 0.0762, 0.0847, 0.0649, 0.0481, 0.0483]
```

```mermaid
xychart-beta
    title "radial-menu-open-close (p50 ms)"
    x-axis 1 --> 9
    line [9.1824, 9.6461, 9.8160, 12.9977, 8.2964, 12.9826, 10.5207, 12.5300, 12.8509]
```

```mermaid
xychart-beta
    title "screen-lifecycle-churn (p50 ms)"
    x-axis 1 --> 9
    line [11.6362, 13.3303, 15.6277, 11.4367, 15.2702, 16.3829, 13.2931, 9.6509, 10.2078]
```

```mermaid
xychart-beta
    title "scroll-focus-traversal (p50 ms)"
    x-axis 1 --> 9
    line [0.1893, 0.1954, 0.2948, 0.3595, 0.2060, 0.4169, 0.3006, 0.3878, 0.3175]
```

```mermaid
xychart-beta
    title "settings-churn (p50 ms)"
    x-axis 1 --> 9
    line [2.4831, 3.3595, 3.8546, 2.7052, 3.5707, 4.0222, 3.0879, 2.4259, 2.3824]
```

```mermaid
xychart-beta
    title "shadow-storm (p50 ms)"
    x-axis 1 --> 9
    line [0.0005, 0.0005, 0.0006, 0.0005, 0.0006, 0.0003, 0.0005, 0.0005, 0.0005]
```

```mermaid
xychart-beta
    title "stylesheet-state-churn (p50 ms)"
    x-axis 1 --> 9
    line [0.2123, 0.2752, 0.3220, 0.3838, 0.4071, 0.2450, 0.3266, 0.3849, 0.3681]
```

```mermaid
xychart-beta
    title "theme-swap-assets (p50 ms)"
    x-axis 1 --> 9
    line [1.5921, 2.1494, 1.6336, 2.1480, 1.2452, 2.1218, 1.7008, 2.1645, 2.1562]
```

```mermaid
xychart-beta
    title "theme-swap-flat (p50 ms)"
    x-axis 1 --> 9
    line [0.3449, 0.3183, 0.4072, 0.4900, 0.2916, 0.5121, 0.4100, 0.5278, 0.4539]
```

```mermaid
xychart-beta
    title "theme-swap-metrics (p50 ms)"
    x-axis 1 --> 9
    line [1.2519, 1.6733, 1.3190, 1.6705, 1.6681, 1.0387, 1.3725, 1.6779, 1.6201]
```

```mermaid
xychart-beta
    title "virtual-list-scroll (p50 ms)"
    x-axis 1 --> 9
    line [0.1263, 0.1363, 0.1356, 0.1842, 0.1329, 0.2108, 0.2004, 0.1771, 0.1917]
```
