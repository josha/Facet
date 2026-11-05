# Facet performance

Latest: `2cdde50ee828e0aba8de3cb460303015f50d8d35` on 2026-11-05T170553Z, measured on the CI Ubuntu runner by the paired performance shards.
Times are milliseconds per frame or operation: the median over paired rounds of each round's p50 and p95.
Retained heap is the scene's mounted retained Luau heap. Change compares the p50 of the previous main commit.

| Scene | p50 ms | p95 ms | Retained KiB | Change |
| --- | ---: | ---: | ---: | ---: |
| adaptive-navigation-images | 0.8330 | 0.9181 | 3914 | — |
| alert-present-dismiss | 2.9632 | 4.6052 | 9392 | — |
| animation-interruption | 0.0236 | 0.0245 | 388 | — |
| async-image-burst | 0.0357 | 0.0418 | 480 | — |
| async-image-grid | 1.4898 | 2.7995 | 2727 | — |
| collection-mutation | 0.3063 | 0.3392 | 2976 | — |
| control-motion | 0.1272 | 0.4271 | 1751 | — |
| dense-hud | 0.1428 | 0.1626 | 744 | — |
| dense-motion | 0.7269 | 1.0640 | 1659 | — |
| hud-binding-storm | 0.1859 | 0.1956 | 475 | — |
| lab-collection-churn | 0.2870 | 0.4468 | 4882 | — |
| lab-dense-scroll | 0.1688 | 0.2302 | 5915 | — |
| locale-textsize-change | 0.0212 | 0.0238 | 538 | — |
| native-scroll-drag | 0.0313 | 0.0448 | 1903 | — |
| navigation-customization | 0.0505 | 0.0606 | 3763 | — |
| picker-menu-open-close | 4.0174 | 6.9066 | 15436 | — |
| picker-segmented-textsize | 0.0429 | 0.0499 | 918 | — |
| radial-menu-open-close | 3.1112 | 4.0083 | 6665 | — |
| screen-lifecycle-churn | 10.3266 | 15.6336 | 26934 | — |
| scroll-focus-traversal | 0.3840 | 0.5876 | 1244 | — |
| settings-churn | 2.5856 | 4.4902 | 9367 | — |
| shadow-storm | 0.0005 | 0.0006 | 1965 | — |
| stylesheet-state-churn | 0.3080 | 0.3489 | 2582 | — |
| theme-swap-assets | 1.5349 | 1.8578 | 7059 | — |
| theme-swap-flat | 0.3972 | 0.4457 | 4462 | — |
| theme-swap-metrics | 1.3783 | 1.6894 | 6109 | — |
| virtual-list-scroll | 0.0907 | 0.1302 | 4270 | — |

| Microbenchmark | p50 ms | p95 ms | Change |
| --- | ---: | ---: | ---: |
| billboard-nameplate-storm | 0.1302 | 0.1402 | — |
| collection-mutation | 0.0074 | 0.0101 | — |
| collection-selection-update | 0.0024 | 0.0030 | — |
| hud-binding-storm | 0.2922 | 0.3074 | — |
| motion-declarative | 0.6836 | 0.9618 | — |
| motion-explicit | 0.6692 | 0.9681 | — |
| mount-ramp | 174.8834 | 196.5471 | — |
| mount-ramp-inherited | 187.3346 | 203.3663 | — |
| mounted-slice-update-storm | 0.1831 | 0.1932 | — |
| outline-measured-update | 1.0204 | 1.3845 | — |
| reserved-slot-record-update | 0.6057 | 0.7152 | — |
| settings-churn | 0.0154 | 0.0166 | — |
| sparse-update-under-load | 0.0020 | 0.0022 | — |
| table-mutation | 0.1949 | 0.2382 | — |
| table-resize-drag | 1.4727 | 2.0301 | — |
| table-sort-values | 0.9697 | 1.4809 | — |
| table-source-refresh | 0.1503 | 0.3215 | — |
| textinput-typing-storm | 0.1925 | 0.3237 | — |
| timer-readout-storm | 0.1381 | 0.6606 | — |
| zz-yardstick-cpu-after | 1.2867 | 1.2957 | — |
| zz-yardstick-cpu-before | 1.2878 | 1.2977 | — |
