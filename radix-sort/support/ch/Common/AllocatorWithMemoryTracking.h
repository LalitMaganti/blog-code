#pragma once
#include <cstdlib>
template <typename T>
struct AllocatorWithMemoryTracking {
  using value_type = T;
  T * allocate(size_t n) { return static_cast<T *>(std::malloc(n * sizeof(T))); }
  void deallocate(T * p, size_t) { std::free(p); }
};
