# Facet performance

Latest: `43b6f3e4c3e76c4a00b6cb15a07e03f25c17e5a2` on 2026-10-26T040407Z, measured on the CI Ubuntu runner by the paired performance shards.
Times are milliseconds per frame or operation: the median over paired rounds of each round's p50 and p95.
Retained heap is the scene's mounted retained Luau heap. Change compares the p50 of the previous main commit.

| Scene | p50 ms | p95 ms | Retained KiB | Change |
| --- | ---: | ---: | ---: | ---: |
| adaptive-navigation-images | 0.9159 | 1.2365 | 10037 | — |
| alert-present-dismiss | 2.3284 | 4.1464 | 5479 | — |
| animation-interruption | 0.0242 | 0.0291 | 4897 | — |
| async-image-burst | 0.0288 | 0.0335 | 5063 | — |
| async-image-grid | 1.6953 | 2.6374 | 5430 | — |
| collection-mutation | 0.3332 | 0.4857 | 9042 | — |
| control-motion | 0.1407 | 0.4580 | 6569 | — |
| dense-hud | 0.1402 | 0.1593 | 5431 | — |
| dense-motion | 1.1243 | 1.7846 | 6905 | — |
| hud-binding-storm | 0.1858 | 0.1974 | 4996 | — |
| lab-collection-churn | 0.2396 | 0.5186 | 9712 | — |
| lab-dense-scroll | 0.7446 | 4.2191 | 13177 | — |
| locale-textsize-change | 0.0152 | 0.0192 | 5040 | — |
| native-scroll-drag | 0.0464 | 0.0571 | 7119 | — |
| navigation-customization | 0.0348 | 0.0410 | 9901 | — |
| picker-menu-open-close | 5.1020 | 9.2164 | 5460 | — |
| picker-segmented-textsize | 0.0576 | 0.0652 | 5701 | — |
| radial-menu-open-close | 9.1824 | 16.6509 | 5582 | — |
| screen-lifecycle-churn | 11.6362 | 22.7124 | 5433 | — |
| scroll-focus-traversal | 0.1893 | 0.3192 | 6150 | — |
| settings-churn | 2.4831 | 4.5704 | 5053 | — |
| shadow-storm | 0.0005 | 0.0006 | 6884 | — |
| stylesheet-state-churn | 0.2123 | 0.3715 | 7986 | — |
| theme-swap-assets | 1.5921 | 2.0709 | 11272 | — |
| theme-swap-flat | 0.3449 | 0.4246 | 10143 | — |
| theme-swap-metrics | 1.2519 | 1.4481 | 10740 | — |
| virtual-list-scroll | 0.1263 | 0.2976 | 10729 | — |

| Microbenchmark | p50 ms | p95 ms | Change |
| --- | ---: | ---: | ---: |
| billboard-nameplate-storm | 0.1074 | 0.1168 | — |
| collection-mutation | 0.0085 | 0.0128 | — |
| collection-selection-update | 0.0019 | 0.0033 | — |
| hud-binding-storm | 0.2844 | 0.3194 | — |
| motion-declarative | 0.9326 | 1.4109 | — |
| motion-explicit | 0.6970 | 1.2115 | — |
| mount-ramp | 101.7728 | 114.1136 | — |
| mount-ramp-inherited | 114.5673 | 132.5785 | — |
| mounted-slice-update-storm | 0.1308 | 0.1448 | — |
| outline-measured-update | 1.4916 | 2.2375 | — |
| reserved-slot-record-update | 0.7851 | 1.6437 | — |
| settings-churn | 0.0145 | 0.0346 | — |
| sparse-update-under-load | 0.0020 | 0.0022 | — |
| table-mutation | 0.3206 | 0.4502 | — |
| table-resize-drag | 1.8614 | 3.1669 | — |
| table-sort-values | 1.0128 | 1.5056 | — |
| table-source-refresh | 0.1899 | 0.5517 | — |
| textinput-typing-storm | 0.1594 | 0.3057 | — |
| timer-readout-storm | 0.1401 | 2.8411 | — |
| zz-yardstick-cpu-after | 1.1266 | 1.1585 | — |
| zz-yardstick-cpu-before | 1.0310 | 1.0397 | — |
