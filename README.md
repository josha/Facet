# Facet performance

Latest: `f52e4b365b5a79d91631839a8a59de1dba9e25c7` on 2026-10-26T122929Z, measured on the CI Ubuntu runner by the paired performance shards.
Times are milliseconds per frame or operation: the median over paired rounds of each round's p50 and p95.
Retained heap is the scene's mounted retained Luau heap. Change compares the p50 of the previous main commit.

| Scene | p50 ms | p95 ms | Retained KiB | Change |
| --- | ---: | ---: | ---: | ---: |
| adaptive-navigation-images | 1.3609 | 1.7399 | 9153 | +48.6% |
| alert-present-dismiss | 2.5432 | 4.2744 | 6079 | +9.2% |
| animation-interruption | 0.0301 | 0.0366 | 4807 | +24.5% |
| async-image-burst | 0.0459 | 0.0562 | 4978 | +59.7% |
| async-image-grid | 2.7184 | 4.1454 | 7089 | +60.3% |
| collection-mutation | 0.4681 | 0.6239 | 8320 | +40.5% |
| control-motion | 0.1565 | 0.4871 | 6333 | +11.3% |
| dense-hud | 0.1574 | 0.1794 | 5260 | +12.3% |
| dense-motion | 1.3144 | 2.2331 | 8181 | +16.9% |
| hud-binding-storm | 0.2630 | 0.2834 | 4925 | +41.6% |
| lab-collection-churn | 0.2475 | 0.6025 | 9082 | +3.3% |
| lab-dense-scroll | 0.8751 | 4.5708 | 12132 | +17.5% |
| locale-textsize-change | 0.0201 | 0.0237 | 4930 | +32.5% |
| native-scroll-drag | 0.0583 | 0.0755 | 6365 | +25.7% |
| navigation-customization | 0.0504 | 0.0596 | 9149 | +44.8% |
| picker-menu-open-close | 6.6154 | 9.2934 | 5722 | +29.7% |
| picker-segmented-textsize | 0.0616 | 0.0734 | 5451 | +7.0% |
| radial-menu-open-close | 9.6461 | 16.9453 | 5898 | +5.1% |
| screen-lifecycle-churn | 13.3303 | 23.2051 | 5776 | +14.6% |
| scroll-focus-traversal | 0.1954 | 0.4104 | 5858 | +3.2% |
| settings-churn | 3.3595 | 5.1480 | 6529 | +35.3% |
| shadow-storm | 0.0005 | 0.0019 | 6415 | -4.0% |
| stylesheet-state-churn | 0.2752 | 0.5735 | 7652 | +29.6% |
| theme-swap-assets | 2.1494 | 2.7166 | 9569 | +35.0% |
| theme-swap-flat | 0.3183 | 0.4149 | 8878 | -7.7% |
| theme-swap-metrics | 1.6733 | 1.9290 | 9439 | +33.7% |
| virtual-list-scroll | 0.1363 | 0.3506 | 10216 | +7.9% |

| Microbenchmark | p50 ms | p95 ms | Change |
| --- | ---: | ---: | ---: |
| billboard-nameplate-storm | 0.1705 | 0.1996 | +58.7% |
| collection-mutation | 0.0084 | 0.0111 | -1.4% |
| collection-selection-update | 0.0018 | 0.0031 | -3.4% |
| hud-binding-storm | 0.3618 | 0.3758 | +27.2% |
| motion-declarative | 1.2269 | 2.0051 | +31.6% |
| motion-explicit | 0.8496 | 1.5603 | +21.9% |
| mount-ramp | 155.8405 | 175.8204 | +53.1% |
| mount-ramp-inherited | 151.1662 | 177.3057 | +31.9% |
| mounted-slice-update-storm | 0.1466 | 0.1579 | +12.1% |
| outline-measured-update | 1.9987 | 3.1895 | +34.0% |
| reserved-slot-record-update | 0.8256 | 1.3362 | +5.2% |
| settings-churn | 0.0075 | 0.0105 | -48.3% |
| sparse-update-under-load | 0.0024 | 0.0025 | +20.3% |
| table-mutation | 0.3434 | 0.4167 | +7.1% |
| table-resize-drag | 2.1795 | 3.6561 | +17.1% |
| table-sort-values | 1.4065 | 2.1167 | +38.9% |
| table-source-refresh | 0.2201 | 0.3679 | +15.9% |
| textinput-typing-storm | 0.1621 | 0.3084 | +1.7% |
| timer-readout-storm | 0.1695 | 2.5816 | +21.0% |
| zz-yardstick-cpu-after | 1.2882 | 1.3002 | +14.3% |
| zz-yardstick-cpu-before | 1.1391 | 1.2188 | +10.5% |

## Scene p50 over the last 2 main commits

```mermaid
xychart-beta
    title "adaptive-navigation-images (p50 ms)"
    x-axis 1 --> 2
    line [0.9159, 1.3609]
```

```mermaid
xychart-beta
    title "alert-present-dismiss (p50 ms)"
    x-axis 1 --> 2
    line [2.3284, 2.5432]
```

```mermaid
xychart-beta
    title "animation-interruption (p50 ms)"
    x-axis 1 --> 2
    line [0.0242, 0.0301]
```

```mermaid
xychart-beta
    title "async-image-burst (p50 ms)"
    x-axis 1 --> 2
    line [0.0288, 0.0459]
```

```mermaid
xychart-beta
    title "async-image-grid (p50 ms)"
    x-axis 1 --> 2
    line [1.6953, 2.7184]
```

```mermaid
xychart-beta
    title "collection-mutation (p50 ms)"
    x-axis 1 --> 2
    line [0.3332, 0.4681]
```

```mermaid
xychart-beta
    title "control-motion (p50 ms)"
    x-axis 1 --> 2
    line [0.1407, 0.1565]
```

```mermaid
xychart-beta
    title "dense-hud (p50 ms)"
    x-axis 1 --> 2
    line [0.1402, 0.1574]
```

```mermaid
xychart-beta
    title "dense-motion (p50 ms)"
    x-axis 1 --> 2
    line [1.1243, 1.3144]
```

```mermaid
xychart-beta
    title "hud-binding-storm (p50 ms)"
    x-axis 1 --> 2
    line [0.1858, 0.2630]
```

```mermaid
xychart-beta
    title "lab-collection-churn (p50 ms)"
    x-axis 1 --> 2
    line [0.2396, 0.2475]
```

```mermaid
xychart-beta
    title "lab-dense-scroll (p50 ms)"
    x-axis 1 --> 2
    line [0.7446, 0.8751]
```

```mermaid
xychart-beta
    title "locale-textsize-change (p50 ms)"
    x-axis 1 --> 2
    line [0.0152, 0.0201]
```

```mermaid
xychart-beta
    title "native-scroll-drag (p50 ms)"
    x-axis 1 --> 2
    line [0.0464, 0.0583]
```

```mermaid
xychart-beta
    title "navigation-customization (p50 ms)"
    x-axis 1 --> 2
    line [0.0348, 0.0504]
```

```mermaid
xychart-beta
    title "picker-menu-open-close (p50 ms)"
    x-axis 1 --> 2
    line [5.1020, 6.6154]
```

```mermaid
xychart-beta
    title "picker-segmented-textsize (p50 ms)"
    x-axis 1 --> 2
    line [0.0576, 0.0616]
```

```mermaid
xychart-beta
    title "radial-menu-open-close (p50 ms)"
    x-axis 1 --> 2
    line [9.1824, 9.6461]
```

```mermaid
xychart-beta
    title "screen-lifecycle-churn (p50 ms)"
    x-axis 1 --> 2
    line [11.6362, 13.3303]
```

```mermaid
xychart-beta
    title "scroll-focus-traversal (p50 ms)"
    x-axis 1 --> 2
    line [0.1893, 0.1954]
```

```mermaid
xychart-beta
    title "settings-churn (p50 ms)"
    x-axis 1 --> 2
    line [2.4831, 3.3595]
```

```mermaid
xychart-beta
    title "shadow-storm (p50 ms)"
    x-axis 1 --> 2
    line [0.0005, 0.0005]
```

```mermaid
xychart-beta
    title "stylesheet-state-churn (p50 ms)"
    x-axis 1 --> 2
    line [0.2123, 0.2752]
```

```mermaid
xychart-beta
    title "theme-swap-assets (p50 ms)"
    x-axis 1 --> 2
    line [1.5921, 2.1494]
```

```mermaid
xychart-beta
    title "theme-swap-flat (p50 ms)"
    x-axis 1 --> 2
    line [0.3449, 0.3183]
```

```mermaid
xychart-beta
    title "theme-swap-metrics (p50 ms)"
    x-axis 1 --> 2
    line [1.2519, 1.6733]
```

```mermaid
xychart-beta
    title "virtual-list-scroll (p50 ms)"
    x-axis 1 --> 2
    line [0.1263, 0.1363]
```
