# Facet performance

Latest: `9122f6cb0592bb7e8e4394298ee392ff75cd99ba` on 2026-11-05T195611Z, measured on the CI Ubuntu runner by the paired performance shards.
Times are milliseconds per frame or operation: the median over paired rounds of each round's p50 and p95.
Retained heap is the scene's mounted retained Luau heap. Change compares the p50 of the previous main commit.

| Scene | p50 ms | p95 ms | Retained KiB | Change |
| --- | ---: | ---: | ---: | ---: |
| adaptive-navigation-images | 1.1721 | 1.2550 | 3922 | +40.7% |
| alert-present-dismiss | 2.9538 | 4.1418 | 9380 | -0.3% |
| animation-interruption | 0.0159 | 0.0164 | 380 | -32.7% |
| async-image-burst | 0.0192 | 0.0223 | 480 | -46.2% |
| async-image-grid | 1.3778 | 2.4489 | 2719 | -7.5% |
| collection-mutation | 0.3360 | 0.3729 | 2977 | +9.7% |
| control-motion | 0.1810 | 0.5870 | 1744 | +42.3% |
| dense-hud | 0.0755 | 0.0827 | 744 | -47.1% |
| dense-motion | 0.5529 | 0.8248 | 1632 | -23.9% |
| hud-binding-storm | 0.1272 | 0.1378 | 467 | -31.6% |
| lab-collection-churn | 0.2054 | 0.3434 | 4883 | -28.4% |
| lab-dense-scroll | 0.1559 | 0.2442 | 5916 | -7.6% |
| locale-textsize-change | 0.0294 | 0.0325 | 530 | +38.2% |
| native-scroll-drag | 0.0356 | 0.0535 | 1911 | +13.7% |
| navigation-customization | 0.0296 | 0.0333 | 3764 | -41.4% |
| picker-menu-open-close | 3.4024 | 5.5668 | 15932 | -15.3% |
| picker-segmented-textsize | 0.0662 | 0.0793 | 918 | +54.4% |
| radial-menu-open-close | 1.8589 | 2.5215 | 6665 | -40.3% |
| screen-lifecycle-churn | 13.6779 | 19.9315 | 26838 | +32.5% |
| scroll-focus-traversal | 0.1980 | 0.3627 | 1244 | -48.4% |
| settings-churn | 3.6434 | 5.2591 | 9279 | +40.9% |
| shadow-storm | 0.0005 | 0.0006 | 1957 | +4.8% |
| stylesheet-state-churn | 0.3324 | 0.3633 | 2589 | +7.9% |
| theme-swap-assets | 0.9322 | 1.1737 | 7074 | -39.3% |
| theme-swap-flat | 0.2391 | 0.2687 | 4462 | -39.8% |
| theme-swap-metrics | 1.3845 | 1.6284 | 6101 | +0.4% |
| virtual-list-scroll | 0.0831 | 0.1250 | 4278 | -8.4% |

| Microbenchmark | p50 ms | p95 ms | Change |
| --- | ---: | ---: | ---: |
| billboard-nameplate-storm | 0.0844 | 0.0930 | -35.2% |
| collection-mutation | 0.0084 | 0.0109 | +13.8% |
| collection-selection-update | 0.0013 | 0.0014 | -46.4% |
| hud-binding-storm | 0.3107 | 0.3259 | +6.3% |
| motion-declarative | 0.4718 | 0.7173 | -31.0% |
| motion-explicit | 0.8313 | 1.1365 | +24.2% |
| mount-ramp | 106.9637 | 120.0452 | -38.8% |
| mount-ramp-inherited | 169.8222 | 187.5333 | -9.3% |
| mounted-slice-update-storm | 0.1192 | 0.1285 | -34.9% |
| outline-measured-update | 1.3059 | 1.6569 | +28.0% |
| reserved-slot-record-update | 0.3245 | 0.3536 | -46.4% |
| settings-churn | 0.0170 | 0.0198 | +10.6% |
| sparse-update-under-load | 0.0013 | 0.0014 | -37.1% |
| table-mutation | 0.2843 | 0.3369 | +45.9% |
| table-resize-drag | 0.8502 | 1.1627 | -42.3% |
| table-sort-values | 1.0465 | 1.3480 | +7.9% |
| table-source-refresh | 0.1164 | 0.2599 | -22.6% |
| textinput-typing-storm | 0.2357 | 0.3819 | +22.5% |
| timer-readout-storm | 0.0859 | 0.3872 | -37.8% |
| zz-yardstick-cpu-after | 1.3027 | 1.3110 | +1.2% |
| zz-yardstick-cpu-before | 1.2954 | 1.3031 | +0.6% |

## Scene p50 over the last 2 main commits

```mermaid
xychart-beta
    title "adaptive-navigation-images (p50 ms)"
    x-axis 1 --> 2
    line [0.8330, 1.1721]
```

```mermaid
xychart-beta
    title "alert-present-dismiss (p50 ms)"
    x-axis 1 --> 2
    line [2.9632, 2.9538]
```

```mermaid
xychart-beta
    title "animation-interruption (p50 ms)"
    x-axis 1 --> 2
    line [0.0236, 0.0159]
```

```mermaid
xychart-beta
    title "async-image-burst (p50 ms)"
    x-axis 1 --> 2
    line [0.0357, 0.0192]
```

```mermaid
xychart-beta
    title "async-image-grid (p50 ms)"
    x-axis 1 --> 2
    line [1.4898, 1.3778]
```

```mermaid
xychart-beta
    title "collection-mutation (p50 ms)"
    x-axis 1 --> 2
    line [0.3063, 0.3360]
```

```mermaid
xychart-beta
    title "control-motion (p50 ms)"
    x-axis 1 --> 2
    line [0.1272, 0.1810]
```

```mermaid
xychart-beta
    title "dense-hud (p50 ms)"
    x-axis 1 --> 2
    line [0.1428, 0.0755]
```

```mermaid
xychart-beta
    title "dense-motion (p50 ms)"
    x-axis 1 --> 2
    line [0.7269, 0.5529]
```

```mermaid
xychart-beta
    title "hud-binding-storm (p50 ms)"
    x-axis 1 --> 2
    line [0.1859, 0.1272]
```

```mermaid
xychart-beta
    title "lab-collection-churn (p50 ms)"
    x-axis 1 --> 2
    line [0.2870, 0.2054]
```

```mermaid
xychart-beta
    title "lab-dense-scroll (p50 ms)"
    x-axis 1 --> 2
    line [0.1688, 0.1559]
```

```mermaid
xychart-beta
    title "locale-textsize-change (p50 ms)"
    x-axis 1 --> 2
    line [0.0212, 0.0294]
```

```mermaid
xychart-beta
    title "native-scroll-drag (p50 ms)"
    x-axis 1 --> 2
    line [0.0313, 0.0356]
```

```mermaid
xychart-beta
    title "navigation-customization (p50 ms)"
    x-axis 1 --> 2
    line [0.0505, 0.0296]
```

```mermaid
xychart-beta
    title "picker-menu-open-close (p50 ms)"
    x-axis 1 --> 2
    line [4.0174, 3.4024]
```

```mermaid
xychart-beta
    title "picker-segmented-textsize (p50 ms)"
    x-axis 1 --> 2
    line [0.0429, 0.0662]
```

```mermaid
xychart-beta
    title "radial-menu-open-close (p50 ms)"
    x-axis 1 --> 2
    line [3.1112, 1.8589]
```

```mermaid
xychart-beta
    title "screen-lifecycle-churn (p50 ms)"
    x-axis 1 --> 2
    line [10.3266, 13.6779]
```

```mermaid
xychart-beta
    title "scroll-focus-traversal (p50 ms)"
    x-axis 1 --> 2
    line [0.3840, 0.1980]
```

```mermaid
xychart-beta
    title "settings-churn (p50 ms)"
    x-axis 1 --> 2
    line [2.5856, 3.6434]
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
    line [0.3080, 0.3324]
```

```mermaid
xychart-beta
    title "theme-swap-assets (p50 ms)"
    x-axis 1 --> 2
    line [1.5349, 0.9322]
```

```mermaid
xychart-beta
    title "theme-swap-flat (p50 ms)"
    x-axis 1 --> 2
    line [0.3972, 0.2391]
```

```mermaid
xychart-beta
    title "theme-swap-metrics (p50 ms)"
    x-axis 1 --> 2
    line [1.3783, 1.3845]
```

```mermaid
xychart-beta
    title "virtual-list-scroll (p50 ms)"
    x-axis 1 --> 2
    line [0.0907, 0.0831]
```
