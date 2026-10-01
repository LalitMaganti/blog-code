// ClickHouse's ORDER BY path for one numeric column (ColumnVector::getPermutation,
// ascending, stable): trySort on the row permutation, else LSD RadixSort on
// (value, index) pairs; pdqsort below 256 rows.
#include <numeric>
#include <vector>
#include <Columns/RadixSortHelper.h>
#include <base/sort.h>
#include "adapter.h"
std::vector<size_t> g_ch_perm;
void ClickHouseSort(const Elem * in, size_t n) {
  std::vector<UInt64> data(n);
  for (size_t i = 0; i < n; ++i) data[i] = in[i].key;
  std::vector<size_t> & res = g_ch_perm;
  res.resize(n);
  std::iota(res.begin(), res.end(), size_t{0});
  auto less_stable = [&](size_t a, size_t b) { return data[a] < data[b] || (data[a] == data[b] && a < b); };
  if (n >= 256) {
    if (trySort(res.begin(), res.end(), less_stable)) return;
    std::vector<DB::ValueWithIndex<UInt64>> pairs(n);
    for (UInt32 i = 0; i < static_cast<UInt32>(n); ++i) pairs[i] = {data[i], i};
    RadixSort<DB::RadixSortTraits<UInt64>>::executeLSD(pairs.data(), n, false, res.data());
    return;
  }
  ::sort(res.begin(), res.end(), less_stable);
}
