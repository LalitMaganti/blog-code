// DuckDB 1.4+'s in-memory sort of a run (sorted_run.cpp, TemplatedSort): vergesort
// with ska_sort (in-place MSD radix, pdqsort for small partitions) as fallback,
// on 8-byte keys with a row payload. Like DuckDB, not stable.
#include <functional>
#include <vector>
#include "vergesort.h"
#include "ska_sort.hpp"
#include "adapter.h"
struct DuckExtract {
  using result_type = uint64_t;
  const uint64_t & operator()(const Elem & e) const { return e.key; }
  bool ByteIsSkippable(const size_t &) const { return false; }
  bool Interrupted() const { return false; }
  bool requires_next_sort = false;
  size_t ska_sort_width = 8;
};
void DuckDbSort(Elem * begin, Elem * end) {
  DuckExtract extract;
  auto fallback = [extract](Elem * b, Elem * e) { duckdb_ska_sort::ska_sort(b, e, extract); };
  duckdb_vergesort::vergesort(begin, end, [](const Elem & a, const Elem & b) { return a.key < b.key; }, fallback);
}
