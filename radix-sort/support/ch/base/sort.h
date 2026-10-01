#pragma once
// Stand-in for ClickHouse base/sort.h: the same pdqsort fork, without the
// debug-build shuffling and comparator wrapper.
#include <pdqsort.h>
template <typename RandomIt, typename Compare>
void sort(RandomIt first, RandomIt last, Compare compare) { ::pdqsort(first, last, compare); }
template <typename RandomIt, typename Compare>
bool trySort(RandomIt first, RandomIt last, Compare compare) { return ::pdqsort_try_sort(first, last, compare); }
